# 局域网互传 LanDrop

iPhone / iPad ⇄ Windows 在同一局域网里互传文件和文本，配对一次后不再询问。

## Windows 端（`windows/`）
- 运行 `LanDrop.exe`（需要 .NET 8 桌面运行时和 ASP.NET Core 运行时），常驻托盘。第一次运行 Windows 防火墙会询问，选“允许”（专用网络）。
- 收到的东西放在 `下载\局域网互传`。传输超过 3 秒时左上角显示进度条；传完弹通知，可“复制”或“打开目录”。
- 发往手机：资源管理器右键“发送到 → iPhone（局域网互传）”，或托盘菜单“发送剪贴板到”。手机上打开 App 就会收到（App 在前台时每 2 秒检查一次）。
- 托盘菜单还有：打开接收目录、清除所有配对、退出。开机自启：把 exe 的快捷方式放进 `shell:startup`。
- 构建：`dotnet publish windows/LanDrop -c Release -r win-x64 --self-contained false -p:PublishSingleFile=true -o windows/publish`
- 测试：`pwsh windows/test.ps1`（先退出正在运行的局域网互传）。

## iOS / iPadOS 端
- GitHub Actions 构建，产物 `ios-app/LanDrop-unsigned.ipa`，自己签名安装。
- 打开 App → 点发现的电脑配对（电脑上点“允许”）；发现不了就输入电脑 IP。
- 发送：输入文本、选择文件、从相册选择；也可在别的 App 里用系统“分享” → 局域网互传（第一次用分享菜单要再配对一次）。
- 从电脑收到的文件在 App 里可分享/存相册，也在“文件”App →“我的 iPhone”→“局域网互传”里。

## 已知限制
- 局域网明文 HTTP，同一网络里能抓包的人可以拿到配对 token。
- App 切到后台传输会中断；电脑程序退出后，还没被手机取走的待发队列会丢失。
- 不发文件夹（先压缩）。
