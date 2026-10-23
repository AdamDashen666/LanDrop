import Foundation
import Network
import UIKit

/// 与电脑端（windows/LanDrop/Program.cs）约定的协议细节，都是纯函数，方便单元测试。
enum Proto {
    static let port: UInt16 = 47380
    static let service = "_landrop._tcp"

    /// 不走手机上设置的 HTTP 代理，局域网直连
    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.connectionProxyDictionary = [:]
        return URLSession(configuration: config)
    }()

    /// 请求头只能放 ASCII：文件名、设备名用百分号编码，电脑端用 Uri.UnescapeDataString 还原
    static func encode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
    }

    /// 手动输入的 IP 没写端口时补上默认端口
    static func address(fromInput s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespaces)
        return t.contains(":") ? t : "\(t):\(port)"
    }

    static func request(address: String, path: String, method: String = "GET", token: String,
                        headers: [String: String] = [:], timeout: TimeInterval = 15) throws -> URLRequest {
        guard let url = URL(string: "http://\(address)\(path)") else { throw LinkError.resolve }
        var r = URLRequest(url: url, timeoutInterval: timeout)
        r.httpMethod = method
        r.setValue(token, forHTTPHeaderField: "X-Token")
        for (k, v) in headers { r.setValue(v, forHTTPHeaderField: k) }
        return r
    }

    /// 电脑发来的文件名只取最后一段，防止写到 Documents 外面
    static func safeName(_ name: String) -> String {
        let n = (name as NSString).lastPathComponent.replacingOccurrences(of: "/", with: "_")
        return ["", ".", ".."].contains(n) ? "file" : n
    }

    /// 分享扩展给的 suggestedName 常常没有扩展名，从临时文件名补上
    static func fileName(suggested: String?, fallback: URL) -> String {
        guard let s = suggested, !s.isEmpty else { return fallback.lastPathComponent }
        return (s as NSString).pathExtension.isEmpty && !fallback.pathExtension.isEmpty ? "\(s).\(fallback.pathExtension)" : s
    }

    /// 不覆盖已有文件：a.txt → a (1).txt
    static func uniqueURL(in dir: URL, name: String) -> URL {
        let base = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension
        var url = dir.appendingPathComponent(name)
        var i = 1
        while FileManager.default.fileExists(atPath: url.path) {
            url = dir.appendingPathComponent(ext.isEmpty ? "\(base) (\(i))" : "\(base) (\(i)).\(ext)")
            i += 1
        }
        return url
    }

    /// 复制到独立的临时子目录，保留原文件名；用完删 url.deletingLastPathComponent()
    static func tempCopy(of src: URL, name: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(safeName(name))
        try FileManager.default.copyItem(at: src, to: dest)
        return dest
    }
}

enum LinkError: LocalizedError {
    case notPaired, denied, unauthorized, resolve, http(Int)

    var errorDescription: String? {
        switch self {
        case .notPaired: return "请先配对电脑"
        case .denied: return "电脑拒绝了配对（或 60 秒内没点允许）"
        case .unauthorized: return "电脑已取消配对，请重新配对"
        case .resolve: return "连不上这台电脑"
        case .http(let code): return "电脑返回错误 \(code)"
        }
    }
}

struct InboxItem: Decodable {
    let id: String
    let kind: String // "file" | "text"
    let name: String
    let text: String?
}

struct Received: Identifiable {
    let id = UUID()
    let name: String
    let text: String?
    let file: URL?
}

/// continuation 只能 resume 一次；只在主队列上调用
private final class Once<T>: @unchecked Sendable {
    private var cont: CheckedContinuation<T, Error>?
    init(_ cont: CheckedContinuation<T, Error>) { self.cont = cont }
    func finish(_ result: Result<T, Error>) { cont?.resume(with: result); cont = nil }
}

/// 发现、配对、收发。App 和分享扩展各有一份配对（不共用存储，见 important.md）。
@MainActor
final class Link: ObservableObject {
    /// App 会接收电脑发来的东西；分享扩展只发送
    let receives: Bool
    @Published private(set) var pcName = UserDefaults.standard.string(forKey: "pcName") ?? ""
    @Published private var token = UserDefaults.standard.string(forKey: "token") ?? ""
    @Published var found: [String: NWEndpoint] = [:] // Bonjour 发现的电脑名 → 端点
    @Published var progress: Progress?
    @Published var status = ""
    @Published var busy = false
    @Published var received: [Received] = []
    // shortcut: 只记一台电脑，要同时配多台时改成字典
    private var address = UserDefaults.standard.string(forKey: "pcAddress") ?? ""
    private var browser: NWBrowser?

    var paired: Bool { !token.isEmpty }

    nonisolated init(receives: Bool) { self.receives = receives }

    func startBrowsing() {
        guard browser == nil else { return }
        let b = NWBrowser(for: .bonjour(type: Proto.service, domain: nil), using: .tcp)
        b.browseResultsChangedHandler = { [weak self] results, _ in
            var map: [String: NWEndpoint] = [:]
            for r in results {
                if case .service(let name, _, _, _) = r.endpoint { map[name] = r.endpoint }
            }
            print("[LanDrop] found \(map.keys.sorted())")
            guard let self else { return }
            Task { @MainActor in self.found = map }
        }
        b.start(queue: .main)
        browser = b
    }

    /// 按钮统一走这里：显示忙碌，把错误写到状态栏；电脑不认 token 时清除配对
    func run(_ work: @escaping @MainActor () async throws -> Void) {
        Task {
            busy = true
            defer { busy = false; progress = nil }
            do { try await work() } catch { report(error) }
        }
    }

    func pair(name: String) async throws {
        guard let ep = found[name] else { throw LinkError.resolve }
        try await pair(address: try await Self.resolve(ep))
    }

    func pair(address: String) async throws {
        status = "请在电脑上点“允许”…"
        let device = UIDevice.current
        let r = try Proto.request(address: address, path: "/pair", method: "POST", token: "", headers: [
            "X-Device-Name": Proto.encode(device.name),
            "X-Device-Id": device.identifierForVendor?.uuidString ?? UUID().uuidString,
            "X-Receive": receives ? "1" : "0",
        ], timeout: 90)
        let (data, resp) = try await Proto.session.data(for: r)
        try Self.check(resp)
        struct Reply: Decodable { let name: String; let token: String }
        let reply = try JSONDecoder().decode(Reply.self, from: data)
        save(name: reply.name, address: address, token: reply.token)
        status = "已配对 \(reply.name)"
        print("[LanDrop] paired \(reply.name) at \(address)")
    }

    func unpair() { save(name: pcName, address: address, token: "") }

    func send(text: String) async throws {
        try await upload(kind: "text", name: "text.txt", file: nil, data: Data(text.utf8))
    }

    func send(file: URL) async throws {
        try await upload(kind: "file", name: file.lastPathComponent, file: file, data: nil)
    }

    /// App 在前台时每 2 秒问一次电脑有没有要发过来的东西
    // shortcut: 2 秒轮询，要更快时改成长轮询
    func pollLoop() async {
        while !Task.isCancelled {
            if paired && !address.isEmpty {
                do { try await pollOnce() } catch {
                    if case LinkError.unauthorized = error { report(error) } else { _ = try? await freshAddress() }
                }
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }

    // MARK: - 内部

    private func report(_ error: Error) {
        if case LinkError.unauthorized = error { unpair() }
        status = error.localizedDescription
        print("[LanDrop] error: \(error)")
    }

    private func save(name: String, address: String, token: String) {
        pcName = name
        self.address = address
        self.token = token
        let d = UserDefaults.standard
        d.set(name, forKey: "pcName")
        d.set(address, forKey: "pcAddress")
        d.set(token, forKey: "token")
    }

    /// 发送前重新解析一次（电脑换了 IP 也能连上）；Bonjour 找不到时用上次的地址（手动配对的情况）
    private func freshAddress() async throws -> String {
        guard paired else { throw LinkError.notPaired }
        if let ep = found[pcName], let a = try? await Self.resolve(ep) { save(name: pcName, address: a, token: token) }
        return address
    }

    // shortcut: 用的是前台 URLSession，App 切到后台传输会中断；要后台传时改 background session
    private func upload(kind: String, name: String, file: URL?, data: Data?) async throws {
        let req = try Proto.request(address: try await freshAddress(), path: "/send", method: "POST", token: token,
                                    headers: ["X-Kind": kind, "X-File-Name": Proto.encode(name)])
        status = kind == "text" ? "正在发送文本" : "正在发送 \(name)"
        let resp: URLResponse = try await withCheckedThrowingContinuation { cont in
            let once = Once(cont)
            let done: @Sendable (Data?, URLResponse?, Error?) -> Void = { _, resp, err in
                DispatchQueue.main.async {
                    if let resp { once.finish(.success(resp)) } else { once.finish(.failure(err ?? URLError(.unknown))) }
                }
            }
            let task = file.map { Proto.session.uploadTask(with: req, fromFile: $0, completionHandler: done) }
                ?? Proto.session.uploadTask(with: req, from: data ?? Data(), completionHandler: done)
            progress = task.progress
            task.resume()
        }
        try Self.check(resp)
        status = kind == "text" ? "文本已发送" : "已发送 \(name)"
        print("[LanDrop] sent \(kind) \(name)")
    }

    private func pollOnce() async throws {
        let (data, resp) = try await Proto.session.data(for: try Proto.request(address: address, path: "/inbox", token: token, timeout: 5))
        try Self.check(resp)
        for item in try JSONDecoder().decode([InboxItem].self, from: data) {
            if item.kind == "text" {
                received.insert(Received(name: item.name, text: item.text ?? "", file: nil), at: 0)
            } else {
                let url = try await download(item)
                received.insert(Received(name: url.lastPathComponent, text: nil, file: url), at: 0)
            }
            let (_, ack) = try await Proto.session.data(for: try Proto.request(address: address, path: "/ack/\(item.id)", method: "POST", token: token))
            try Self.check(ack)
            status = "收到 \(item.kind == "text" ? "文本" : item.name)"
            print("[LanDrop] received \(item.kind) \(item.name)")
        }
    }

    private func download(_ item: InboxItem) async throws -> URL {
        let req = try Proto.request(address: address, path: "/item/\(item.id)", token: token)
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let name = Proto.safeName(item.name)
        status = "正在接收 \(name)"
        defer { progress = nil }
        return try await withCheckedThrowingContinuation { cont in
            let task = Proto.session.downloadTask(with: req) { tmp, resp, err in
                // 临时文件只在回调里有效，必须在这里移走
                do {
                    guard let tmp, let resp else { throw err ?? URLError(.unknown) }
                    try Link.check(resp)
                    let dest = Proto.uniqueURL(in: docs, name: name)
                    try FileManager.default.moveItem(at: tmp, to: dest)
                    cont.resume(returning: dest)
                } catch { cont.resume(throwing: error) }
            }
            progress = task.progress
            task.resume()
        }
    }

    nonisolated static func check(_ resp: URLResponse) throws {
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        switch code {
        case 200: return
        case 401: throw LinkError.unauthorized
        case 403: throw LinkError.denied
        default: throw LinkError.http(code)
        }
    }

    /// Bonjour 端点 → "IPv4:端口"：连一下，拿系统解析出的对端地址，之后用普通 URLSession
    nonisolated static func resolve(_ endpoint: NWEndpoint) async throws -> String {
        let params = NWParameters.tcp
        (params.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options)?.version = .v4
        // 电脑也会广播代理软件的假 IP（198.18.x.x），手机上的 fake-ip 代理会“接住”它；不走 VPN 通道就只会连上真实的局域网地址
        params.prohibitedInterfaceTypes = [.other]
        let conn = NWConnection(to: endpoint, using: params)
        defer { conn.stateUpdateHandler = nil; conn.cancel() }
        return try await withCheckedThrowingContinuation { cont in
            let once = Once(cont)
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    // 用原始字节拼 IP：Host 的描述会带 "%en0" 这样的网卡后缀
                    if case .hostPort(.ipv4(let ip), let port) = conn.currentPath?.remoteEndpoint {
                        once.finish(.success("\(ip.rawValue.map { String($0) }.joined(separator: ".")):\(port.rawValue)"))
                    } else {
                        once.finish(.failure(LinkError.resolve))
                    }
                case .failed: once.finish(.failure(LinkError.resolve))
                default: break // .waiting 可能只是在等本地网络权限，交给超时
                }
            }
            conn.start(queue: .main)
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { once.finish(.failure(LinkError.resolve)) }
        }
    }
}
