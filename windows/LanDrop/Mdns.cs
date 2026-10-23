using System.Diagnostics;
using System.Runtime.InteropServices;

namespace LanDrop;

/// 用 Windows 自带的 DNS-SD（dnsapi.dll，Win10 1809+）广播 Bonjour 服务，iOS 的 NWBrowser 能发现
static class Mdns
{
    [StructLayout(LayoutKind.Sequential)]
    struct RegisterRequest
    {
        public uint Version;
        public uint InterfaceIndex;
        public IntPtr ServiceInstance;
        public IntPtr Callback;
        public IntPtr Context;
        public IntPtr Credentials;
        public int UnicastEnabled;
    }

    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    delegate void RegisterComplete(uint status, IntPtr context, IntPtr instance);

    [DllImport("dnsapi.dll", CharSet = CharSet.Unicode)]
    static extern IntPtr DnsServiceConstructInstance(string serviceName, string hostName, IntPtr ip4, IntPtr ip6,
        ushort port, ushort priority, ushort weight, uint propertiesCount, IntPtr keys, IntPtr values);

    [DllImport("dnsapi.dll")]
    static extern uint DnsServiceRegister(IntPtr request, IntPtr cancel);

    [DllImport("dnsapi.dll")]
    static extern uint DnsServiceDeRegister(IntPtr request, IntPtr cancel);

    const uint Pending = 9506; // DNS_REQUEST_PENDING：已提交，结果走回调

    // 回调委托和请求内存要一直活着：注册是异步的，原生代码之后还会用到
    static readonly RegisterComplete callback = (status, _, _) => Debug.WriteLine($"mDNS: {status}");
    static IntPtr request;

    public static void Register(string name, int port)
    {
        var req = new RegisterRequest
        {
            Version = 1, // DNS_QUERY_REQUEST_VERSION1
            ServiceInstance = DnsServiceConstructInstance($"{name}._landrop._tcp.local", $"{name}.local",
                IntPtr.Zero, IntPtr.Zero, (ushort)port, 0, 0, 0, IntPtr.Zero, IntPtr.Zero),
            Callback = Marshal.GetFunctionPointerForDelegate(callback),
        };
        request = Marshal.AllocHGlobal(Marshal.SizeOf<RegisterRequest>());
        Marshal.StructureToPtr(req, request, false);
        var r = DnsServiceRegister(request, IntPtr.Zero);
        if (r != Pending) Debug.WriteLine($"DnsServiceRegister failed: {r}");
    }

    public static void Unregister()
    {
        if (request != IntPtr.Zero) DnsServiceDeRegister(request, IntPtr.Zero);
    }
}
