import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// 系统分享菜单里的“局域网互传”：已配对就直接发，发完自动关闭
final class ShareViewController: UIViewController {
    private let link = Link(receives: false)

    override func viewDidLoad() {
        super.viewDidLoad()
        let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        let host = UIHostingController(rootView: ShareView(link: link, providers: items.flatMap { $0.attachments ?? [] }) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        })
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
        link.startBrowsing()
    }
}

struct ShareView: View {
    @ObservedObject var link: Link
    let providers: [NSItemProvider]
    let close: () -> Void
    @State private var sent = false

    var body: some View {
        NavigationStack {
            Form {
                PCPicker(link: link)
                Section("发送 \(providers.count) 项") {
                    if let p = link.progress { ProgressView(p) }
                    if !link.status.isEmpty { Text(link.status).foregroundStyle(.secondary) }
                    Button("发送", action: send)
                        .disabled(!link.paired || link.busy || sent)
                }
            }
            .navigationTitle("发送到电脑")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("关闭", action: close) }
        }
        // 打开时已配对、或在这里刚配对完，就自动发送
        .task(id: link.paired) { if link.paired && !sent { send() } }
    }

    private func send() {
        link.run {
            for p in providers { try await Self.send(p, via: link) }
            sent = true
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            close()
        }
    }

    /// 网址、纯文本按文本发；其余（照片、视频、文件）取原文件发
    @MainActor
    private static func send(_ p: NSItemProvider, via link: Link) async throws {
        if !p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            if p.hasItemConformingToTypeIdentifier(UTType.url.identifier),
               let url = try await p.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL, !url.isFileURL {
                return try await link.send(text: url.absoluteString)
            }
            if p.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
               let text = try await p.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                return try await link.send(text: text)
            }
        }
        // 文件 App 分享来的是原文件地址：能直接读就直接发，大文件不必先复制一份
        if p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
           let url = await Self.fileURL(from: p) {
            let ok = url.startAccessingSecurityScopedResource()
            defer { if ok { url.stopAccessingSecurityScopedResource() } }
            if FileManager.default.isReadableFile(atPath: url.path) { return try await link.send(file: url) }
        }
        guard let type = Proto.contentType(in: p.registeredTypeIdentifiers) else { throw CocoaError(.fileReadUnknown) }
        let suggested = p.suggestedName
        let file: URL = try await withCheckedThrowingContinuation { cont in
            _ = p.loadFileRepresentation(forTypeIdentifier: type) { url, err in
                // 系统给的临时文件只在回调里有效
                do {
                    guard let url else { throw err ?? CocoaError(.fileReadUnknown) }
                    cont.resume(returning: try Proto.tempCopy(of: url, name: Proto.fileName(suggested: suggested, fallback: url)))
                } catch { cont.resume(throwing: error) }
            }
        }
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        try await link.send(file: file)
    }

    /// public.file-url 有时给 URL，有时给它的 bplist 数据
    private static func fileURL(from p: NSItemProvider) async -> URL? {
        switch try? await p.loadItem(forTypeIdentifier: UTType.fileURL.identifier) {
        case let url as URL: return url.isFileURL ? url : nil
        case let data as Data: return URL(dataRepresentation: data, relativeTo: nil).flatMap { $0.isFileURL ? $0 : nil }
        default: return nil
        }
    }
}
