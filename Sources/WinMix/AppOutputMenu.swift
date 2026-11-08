import SwiftUI

struct AppOutputMenu: View {
    @ObservedObject var model: MixerModel
    let row: AppGroup
    let appearance: MixerAppearance

    private var selection: Binding<String> {
        Binding(get: { model.setting(for: row).outputUID ?? "" },
                set: { model.setOutput($0.isEmpty ? nil : $0, for: row) })
    }

    var body: some View {
        Menu {
            Picker("Output device", selection: selection) {
                Text("System default").tag("")
                ForEach(model.outputDevices) { device in Text(device.name).tag(device.uid) }
                if let uid = model.setting(for: row).outputUID,
                   !model.outputDevices.contains(where: { $0.uid == uid }) {
                    Text("\(model.setting(for: row).outputName ?? "Saved output") — disconnected")
                        .tag(uid).disabled(true)
                }
            }
            if row.key == "com.google.Chrome" {
                Divider()
                Text("All Chrome tabs share this output")
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "hifispeaker")
                Text(model.outputLabel(for: row)).lineLimit(1).truncationMode(.middle)
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(appearance == .ceramic ? Ceramic.secondary : .white.opacity(0.65))
        }
        .menuStyle(.borderlessButton)
        .controlSize(.mini)
        .help(model.outputHelp(for: row))
        .accessibilityLabel("\(row.identity.name) output device")
        .accessibilityValue(model.outputLabel(for: row))
    }
}
