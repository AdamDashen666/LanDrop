import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var link = Link(receives: true)
    @State private var text = ""
    @State private var importing = false
    @State private var photos: [PhotosPickerItem] = []
    @Environment(\.scenePhase) private var phase

    var body: some View {
        NavigationStack {
            Form {
                PCPicker(link: link)
                Section("发送到电脑") {
                    TextEditor(text: $text)
                        .frame(minHeight: 100)
                        .accessibilityIdentifier("textInput")
                    Button("发送文本") {
                        link.run {
                            try await link.send(text: text)
                            text = ""
                        }
                    }
                    .disabled(text.isEmpty || link.busy)
                    .accessibilityIdentifier("sendText")
                    Button("选择文件") { importing = true }
                        .disabled(link.busy)
                    PhotosPicker("从相册选择", selection: $photos, matching: .any(of: [.images, .videos]))
                        .disabled(link.busy)
                    if let p = link.progress { ProgressView(p) }
                    if !link.status.isEmpty {
                        Text(link.status)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("status")
                    }
                }
                if !link.received.isEmpty {
                    Section("从电脑收到") {
                        ForEach(link.received) { ReceivedRow(item: $0) }
                    }
                }
            }
            .navigationTitle("局域网互传")
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            link.run {
                for url in urls {
                    let ok = url.startAccessingSecurityScopedResource()
                    defer { if ok { url.stopAccessingSecurityScopedResource() } }
                    try await link.send(file: url)
                }
            }
        }
        .onChange(of: photos) { items in
            guard !items.isEmpty else { return }
            photos = []
            link.run {
                for item in items {
                    guard let picked = try await item.loadTransferable(type: PickedFile.self) else { continue }
                    defer { try? FileManager.default.removeItem(at: picked.url.deletingLastPathComponent()) }
                    try await link.send(file: picked.url)
                }
            }
        }
        .task(id: phase) {
            if phase == .active { await link.pollLoop() }
        }
        .onAppear { link.startBrowsing() }
    }
}

/// 相册里的原文件（照片 / 视频）：系统给的临时文件只在回调里有效，先复制出来
struct PickedFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .data) { received in
            PickedFile(url: try Proto.tempCopy(of: received.file, name: received.file.lastPathComponent))
        }
    }
}

struct ReceivedRow: View {
    let item: Received

    var body: some View {
        if let text = item.text {
            HStack {
                Text(text).lineLimit(3)
                Spacer()
                Button("复制") { UIPasteboard.general.string = text }
                    .buttonStyle(.borderless)
            }
        } else if let file = item.file {
            // 文件存在 Documents，“文件”App →“我的 iPhone”→“局域网互传”里也能找到
            ShareLink(item: file) { Label(item.name, systemImage: "doc") }
        }
    }
}
