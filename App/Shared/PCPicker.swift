import SwiftUI

/// “电脑”一栏：配对状态、发现的电脑（点一下配对）、手动输入 IP 兜底
struct PCPicker: View {
    @ObservedObject var link: Link
    @State private var manual = ""

    var body: some View {
        Section {
            if link.paired {
                Label("已配对：\(link.pcName)", systemImage: "checkmark.circle.fill")
                    .accessibilityIdentifier("pairedPC")
            }
            ForEach(link.found.keys.sorted(), id: \.self) { name in
                Button {
                    link.run { try await link.pair(name: name) }
                } label: {
                    HStack {
                        Label(name, systemImage: "desktopcomputer")
                        Spacer()
                        Text(link.paired && name == link.pcName ? "重新配对" : "配对").foregroundStyle(.secondary)
                    }
                }
                .disabled(link.busy)
            }
            HStack {
                TextField("或输入电脑 IP", text: $manual)
                    .keyboardType(.numbersAndPunctuation)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("配对") {
                    link.run { try await link.pair(address: Proto.address(fromInput: manual)) }
                }
                .disabled(manual.isEmpty || link.busy)
            }
        } header: {
            Text("电脑")
        } footer: {
            if link.found.isEmpty {
                Text("没发现电脑：确认电脑上的“局域网互传”在运行，并且和手机连着同一个 Wi-Fi。")
            }
        }
    }
}
