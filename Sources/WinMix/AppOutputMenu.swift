import SwiftUI

struct AppOutputMenu: View {
    @ObservedObject var model: MixerModel
    let row: AppGroup
    var appearance: MixerAppearance? = nil

    private var labelColor: Color {
        switch appearance {
        case .ceramic: return Ceramic.secondary
        case .retro: return .white.opacity(0.65)
        case .stickerCase: return StickerCase.ink
        case nil: return Color(nsColor: .secondaryLabelColor)
        }
    }

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
            .foregroundStyle(labelColor)
        }
        .menuStyle(.borderlessButton)
        .controlSize(.mini)
        .padding(.horizontal, appearance == .stickerCase ? 5 : 0)
        .padding(.vertical, appearance == .stickerCase ? 3 : 0)
        .background {
            if appearance == .stickerCase {
                RoundedRectangle(cornerRadius: 4).fill(StickerCase.cream)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(StickerCase.ink, lineWidth: 1.2))
            }
        }
        .help(model.outputHelp(for: row))
        .accessibilityLabel("\(row.identity.name) output device")
        .accessibilityValue(model.outputLabel(for: row))
    }
}
