// 局域网互传 Windows 端：托盘程序 + HTTP 服务（端口 47380）+ Bonjour 广播 _landrop._tcp。
// 协议（iOS 端见 App/Shared/Link.swift），请求头里的文本都做了百分号编码：
//   POST /pair       头 X-Device-Name X-Device-Id X-Receive → 弹“允许/拒绝”通知，允许返回 {name, token}，否则 403
//   POST /send       头 X-Token X-Kind(file|text) X-File-Name，body 为内容 → 存到接收目录并通知
//   GET  /inbox      头 X-Token → 待发往该设备的 [{id, kind, name, text}]
//   GET  /item/{id}  下载文件；POST /ack/{id} 确认收到后出队
//   POST /local/send {device, paths, text} → 只接受本机回环，给资源管理器“发送到”启动的第二个进程用
using System.Collections.Specialized;
using System.Diagnostics;
using System.Drawing.Imaging;
using System.Net;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text.Json;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Logging;
using Microsoft.Toolkit.Uwp.Notifications;

namespace LanDrop;

record Device(string Name, string Id, bool Receive);
record OutItem(string Id, string Kind, string Name, string? Text, string? Path);
record LocalSend(string Device, string[]? Paths, string? Text);

/// 一次接收的进度，ProgressForm 每 100ms 读一次
class Transfer(string name, long? total)
{
    public string Name { get; } = name;
    public long? Total { get; } = total;
    public long Received;
    public bool? Ok; // null = 还在传
}

static class Program
{
    const int Port = 47380;
    // 设置 LANDROP_HOME 时所有文件都放到它下面，只给 test.ps1 用
    static readonly string? Home = Environment.GetEnvironmentVariable("LANDROP_HOME");
    static readonly string ReceiveDir = Home != null ? Path.Combine(Home, "recv")
        : Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads", "局域网互传");
    static readonly string DataDir = Home ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "LanDrop");
    static readonly string SendToDir = Home != null ? Path.Combine(Home, "SendTo") : Environment.GetFolderPath(Environment.SpecialFolder.SendTo);
    static string DevicesFile => Path.Combine(DataDir, "devices.json");

    static readonly object gate = new(); // 保护 devices 和 outbox
    static Dictionary<string, Device> devices = new(); // token → 设备
    // shortcut: 待发队列只在内存里，电脑程序退出就丢失；要持久化时存到 DataDir
    static readonly Dictionary<string, List<OutItem>> outbox = new(); // 设备 id → 待发
    static readonly Dictionary<string, TaskCompletionSource<bool>> pairing = new();
    static Control ui = null!;

    [STAThread]
    static void Main(string[] args)
    {
        // 资源管理器“发送到”：交给已在运行的主进程；主进程没在运行就自己当主进程
        if (args is ["--send", var target, .. var files] && PostToRunning(new LocalSend(target, files, null))) return;

        Directory.CreateDirectory(ReceiveDir);
        Directory.CreateDirectory(DataDir);
        if (File.Exists(DevicesFile)) devices = JsonSerializer.Deserialize<Dictionary<string, Device>>(File.ReadAllText(DevicesFile)) ?? new();

        // 先启动服务，再创建控件：控件会装上 WinForms 同步上下文，之后同步等待异步方法可能死锁
        var server = BuildServer();
        try { server.StartAsync().GetAwaiter().GetResult(); }
        catch (IOException)
        {
            MessageBox.Show($"端口 {Port} 被占用：局域网互传可能已经在运行。", "局域网互传");
            return;
        }
        Mdns.Register(Environment.MachineName, Port);

        ApplicationConfiguration.Initialize();
        ui = new Control();
        _ = ui.Handle; // 让后台线程能 BeginInvoke 回 UI 线程
        ToastNotificationManagerCompat.OnActivated += OnToast;
        SyncSendTo();
        // 开机自启动：每次启动都写一遍，exe 挪了位置也能跟上；用户可在任务管理器“启动应用”里关掉（那里的开关不受这里影响）
        if (Home == null) Microsoft.Win32.Registry.SetValue(@"HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run", "LanDrop", $"\"{Environment.ProcessPath}\"");

        var menu = new ContextMenuStrip();
        menu.Opening += (_, e) => { BuildMenu(menu); e.Cancel = false; }; // 菜单为空时 Opening 默认是取消的
        using var tray = new NotifyIcon
        {
            Icon = Icon.ExtractAssociatedIcon(Environment.ProcessPath!),
            Text = "局域网互传",
            ContextMenuStrip = menu,
            Visible = true,
        };
        tray.DoubleClick += (_, _) => OpenFolder();
        if (args is ["--send", var id, .. var paths]) Enqueue(id, paths, null);

        Application.Run();
        tray.Visible = false;
        Mdns.Unregister();
        server.StopAsync().Wait(1000);
    }

    static WebApplication BuildServer()
    {
        var builder = WebApplication.CreateSlimBuilder();
        builder.Logging.ClearProviders();
        builder.WebHost.ConfigureKestrel(o =>
        {
            o.ListenAnyIP(Port);
            o.Limits.MaxRequestBodySize = null; // 默认只允许 30MB
        });
        var app = builder.Build();
        app.MapPost("/pair", Pair);
        app.MapPost("/send", Receive);
        app.MapGet("/inbox", Inbox);
        app.MapGet("/item/{id}", Item);
        app.MapPost("/ack/{id}", Ack);
        app.MapPost("/local/send", LocalSendHandler);
        return app;
    }

    // ---------- HTTP 接口 ----------

    static string H(HttpRequest r, string name) => Uri.UnescapeDataString(r.Headers[name].ToString());

    static Device? Auth(HttpRequest r)
    {
        lock (gate) return devices.GetValueOrDefault(r.Headers["X-Token"].ToString());
    }

    static async Task<IResult> Pair(HttpRequest r)
    {
        var name = H(r, "X-Device-Name").Trim();
        var id = H(r, "X-Device-Id");
        var receive = r.Headers["X-Receive"] == "1";
        // id 会写进“发送到”快捷方式的参数，只允许 UUID 字符
        if (name == "" || id == "" || id.Length > 64 || !id.All(c => char.IsAsciiLetterOrDigit(c) || c == '-')) return Results.BadRequest();
        var label = receive ? name : $"{name}（分享菜单）";

        var key = Guid.NewGuid().ToString("N");
        var answer = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
        lock (gate) pairing[key] = answer;
        Toast(b => b.AddArgument("pair", key)
            .AddText($"{label} 请求配对")
            .AddText("允许后它发来的文件和文本会直接接收，不再询问。")
            .AddButton(new ToastButton().SetContent("允许").AddArgument("allow", "1"))
            .AddButton(new ToastButton().SetContent("拒绝").AddArgument("allow", "0")));
        var allowed = await Task.WhenAny(answer.Task, Task.Delay(60_000)) == answer.Task && answer.Task.Result;
        lock (gate) pairing.Remove(key);
        if (!allowed) return Results.StatusCode(403);

        var token = Convert.ToHexString(RandomNumberGenerator.GetBytes(32));
        lock (gate)
        {
            // 同一台设备重新配对：替换旧记录
            foreach (var old in devices.Where(kv => kv.Value.Id == id && kv.Value.Receive == receive).Select(kv => kv.Key).ToList())
                devices.Remove(old);
            var unique = label;
            for (var i = 2; devices.Values.Any(d => d.Name == unique); i++) unique = $"{label} {i}";
            devices[token] = new Device(unique, id, receive);
            SaveDevices();
        }
        if (receive) ui.BeginInvoke(SyncSendTo);
        return Results.Json(new { name = Environment.MachineName, token });
    }

    static async Task<IResult> Receive(HttpRequest r)
    {
        var device = Auth(r);
        if (device == null) return Results.Unauthorized();
        var isText = H(r, "X-Kind") == "text";
        var name = isText ? $"文本 {DateTime.Now:yyyyMMdd-HHmmss}.txt" : SafeName(H(r, "X-File-Name"));

        var t = new Transfer(name, r.ContentLength);
        _ = Task.Delay(3000).ContinueWith(_ => { if (t.Ok == null) ui.BeginInvoke(() => new ProgressForm(t).Show()); });
        var part = Path.Combine(ReceiveDir, $".{Guid.NewGuid():N}.part");
        try
        {
            await using (var f = File.Create(part))
            {
                var buf = new byte[1 << 20];
                int n;
                while ((n = await r.Body.ReadAsync(buf, r.HttpContext.RequestAborted)) > 0)
                {
                    await f.WriteAsync(buf.AsMemory(0, n));
                    t.Received += n;
                }
            }
            var path = MoveUnique(part, name);
            t.Ok = true;
            Notify(device, path, isText);
            return Results.Ok();
        }
        catch (Exception ex)
        {
            // 手机中途断开等：删掉半截文件
            t.Ok = false;
            File.Delete(part);
            Debug.WriteLine($"receive failed: {ex}");
            return Results.StatusCode(500);
        }
    }

    static IResult Inbox(HttpRequest r)
    {
        var d = Auth(r);
        if (d == null) return Results.Unauthorized();
        lock (gate)
            return Results.Json(outbox.GetValueOrDefault(d.Id)?.Select(i => new { i.Id, i.Kind, i.Name, i.Text }).ToList() ?? []);
    }

    static IResult Item(HttpRequest r, string id)
    {
        var d = Auth(r);
        if (d == null) return Results.Unauthorized();
        OutItem? item;
        lock (gate) item = outbox.GetValueOrDefault(d.Id)?.FirstOrDefault(i => i.Id == id);
        if (item?.Path is { } p && File.Exists(p)) return Results.File(p, "application/octet-stream");
        // 文件已被删掉：出队，免得手机一直重试
        lock (gate) outbox.GetValueOrDefault(d.Id)?.RemoveAll(i => i.Id == id);
        return Results.NotFound();
    }

    static IResult Ack(HttpRequest r, string id)
    {
        var d = Auth(r);
        if (d == null) return Results.Unauthorized();
        lock (gate) outbox.GetValueOrDefault(d.Id)?.RemoveAll(i => i.Id == id);
        return Results.Ok();
    }

    static IResult LocalSendHandler(HttpContext ctx, LocalSend body)
    {
        // 能指定任意本地路径，绝不能对局域网开放
        var ip = ctx.Connection.RemoteIpAddress;
        if (ip == null || !IPAddress.IsLoopback(ip.IsIPv4MappedToIPv6 ? ip.MapToIPv4() : ip)) return Results.StatusCode(403);
        Enqueue(body.Device, body.Paths, body.Text);
        return Results.Ok();
    }

    static bool PostToRunning(LocalSend s)
    {
        try
        {
            // 本机回环，不走系统代理
            using var http = new HttpClient(new HttpClientHandler { UseProxy = false }) { Timeout = TimeSpan.FromSeconds(3) };
            return http.PostAsJsonAsync($"http://127.0.0.1:{Port}/local/send", s).GetAwaiter().GetResult().IsSuccessStatusCode;
        }
        catch (Exception) { return false; }
    }

    // ---------- 发往手机 ----------

    static IEnumerable<Device> Receivers()
    {
        lock (gate) return devices.Values.Where(d => d.Receive).ToList();
    }

    static void Enqueue(string deviceId, string[]? paths, string? text)
    {
        var device = Receivers().FirstOrDefault(d => d.Id == deviceId);
        if (device == null)
        {
            Toast(b => b.AddText("这台设备已取消配对").AddText("请在手机上的“局域网互传”里重新配对。"));
            return;
        }
        var items = new List<OutItem>();
        if (!string.IsNullOrEmpty(text)) items.Add(new OutItem(NewId(), "text", "文本", text, null));
        // shortcut: 文件夹会被跳过，要发文件夹时先压缩
        foreach (var p in paths ?? [])
            if (File.Exists(p)) items.Add(new OutItem(NewId(), "file", Path.GetFileName(p), null, Path.GetFullPath(p)));
        if (items.Count == 0) return;
        lock (gate)
        {
            if (!outbox.TryGetValue(deviceId, out var q)) outbox[deviceId] = q = [];
            q.AddRange(items);
        }
        Toast(b => b.AddText($"等待 {device.Name} 接收：{string.Join("、", items.Select(i => i.Name))}")
            .AddText($"在 {device.Name} 上打开“局域网互传”就会收到。"));
    }

    static string NewId() => Guid.NewGuid().ToString("N");

    static void SendClipboard(string deviceId)
    {
        if (Clipboard.ContainsFileDropList()) Enqueue(deviceId, Clipboard.GetFileDropList().Cast<string>().ToArray(), null);
        else if (Clipboard.ContainsText()) Enqueue(deviceId, null, Clipboard.GetText());
        else if (Clipboard.GetImage() is { } img)
        {
            var path = Path.Combine(Path.GetTempPath(), $"截图 {DateTime.Now:yyyyMMdd-HHmmss}.png");
            img.Save(path, ImageFormat.Png);
            Enqueue(deviceId, [path], null);
        }
    }

    // ---------- 托盘、通知、文件 ----------

    static void BuildMenu(ContextMenuStrip menu)
    {
        menu.Items.Clear();
        var send = new ToolStripMenuItem("发送剪贴板到");
        foreach (var d in Receivers()) send.DropDownItems.Add(d.Name, null, (_, _) => SendClipboard(d.Id));
        send.Enabled = send.DropDownItems.Count > 0;
        menu.Items.Add(send);
        menu.Items.Add("打开接收目录", null, (_, _) => OpenFolder());
        menu.Items.Add("清除所有配对", null, (_, _) =>
        {
            lock (gate)
            {
                devices.Clear();
                outbox.Clear();
                SaveDevices();
            }
            SyncSendTo();
        });
        menu.Items.Add("退出", null, (_, _) => Application.Exit());
    }

    static void OpenFolder() => Process.Start("explorer.exe", ReceiveDir);

    static void Notify(Device from, string path, bool isText)
    {
        var text = isText ? File.ReadAllText(path) : "";
        Toast(b => b.AddArgument("path", path).AddArgument("text", isText ? "1" : "0")
            .AddText(isText ? $"收到 {from.Name} 的文本" : $"收到 {from.Name} 的文件")
            // 通知内容有 5KB 上限；截断时不能把表情（两个 char）切开，否则通知会被系统拒收
            .AddText(isText ? (text.Length > 200 ? text[..(char.IsHighSurrogate(text[199]) ? 199 : 200)] + "…" : text) : Path.GetFileName(path))
            .AddButton(new ToastButton().SetContent("复制").AddArgument("do", "copy"))
            .AddButton(new ToastButton().SetContent("打开目录").AddArgument("do", "open")));
    }

    static void Toast(Action<ToastContentBuilder> build)
    {
        try
        {
            var b = new ToastContentBuilder();
            build(b);
            b.Show();
        }
        catch (Exception ex) { Debug.WriteLine($"toast failed: {ex}"); } // 通知被系统关掉时也不能影响收文件
    }

    static void OnToast(ToastNotificationActivatedEventArgsCompat e)
    {
        var a = ToastArguments.Parse(e.Argument);
        if (a.TryGetValue("pair", out var key))
        {
            lock (gate)
                if (a.TryGetValue("allow", out var allow) && pairing.TryGetValue(key, out var answer)) answer.TrySetResult(allow == "1");
            return;
        }
        if (!a.TryGetValue("path", out var path) || !a.TryGetValue("do", out var action)) return;
        ui.BeginInvoke(() =>
        {
            try
            {
                if (action == "open") Process.Start("explorer.exe", $"/select,\"{path}\"");
                else if (a.Get("text") == "1") Clipboard.SetText(File.ReadAllText(path));
                else Clipboard.SetFileDropList(new StringCollection { path });
            }
            catch (Exception ex) { Toast(b => b.AddText("操作失败").AddText(ex.Message)); } // 文件被删、剪贴板被占用等
        });
    }

    static void SaveDevices() => File.WriteAllText(DevicesFile, JsonSerializer.Serialize(devices));

    /// 资源管理器右键“发送到”里每台能接收的设备一个快捷方式；每次全部重建，顺便修正 exe 挪动过的路径
    static void SyncSendTo()
    {
        Directory.CreateDirectory(SendToDir);
        foreach (var f in Directory.GetFiles(SendToDir, "*（局域网互传）.lnk")) File.Delete(f);
        dynamic shell = Activator.CreateInstance(Type.GetTypeFromProgID("WScript.Shell")!)!;
        foreach (var d in Receivers())
        {
            var lnk = shell.CreateShortcut(Path.Combine(SendToDir, $"{SafeName(d.Name)}（局域网互传）.lnk"));
            lnk.TargetPath = Environment.ProcessPath;
            lnk.Arguments = $"--send {d.Id}";
            lnk.Save();
        }
    }

    /// 手机发来的文件名只取最后一段并去掉非法字符，防止写到接收目录外面
    internal static string SafeName(string name)
    {
        var invalid = Path.GetInvalidFileNameChars();
        var n = new string(Path.GetFileName(name).Select(c => invalid.Contains(c) ? '_' : c).ToArray()).Trim().TrimEnd('.');
        return n == "" ? "file" : n;
    }

    /// 不覆盖已有文件：a.txt → a (1).txt
    static string MoveUnique(string src, string name)
    {
        var stem = Path.GetFileNameWithoutExtension(name);
        var ext = Path.GetExtension(name);
        for (var i = 0; ; i++)
        {
            var dest = Path.Combine(ReceiveDir, i == 0 ? name : $"{stem} ({i}){ext}");
            if (File.Exists(dest)) continue;
            try
            {
                File.Move(src, dest);
                return dest;
            }
            catch (IOException) when (File.Exists(dest)) { } // 同名文件同时到达：换下一个名字
        }
    }
}
