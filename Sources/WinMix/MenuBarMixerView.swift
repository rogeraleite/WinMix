import AppKit
import SwiftUI

/// A second control surface for the app-owned mixer; no independent audio state.
struct MenuBarMixerView: View {
    @ObservedObject var model: MixerModel
    let permissionStatus: AudioCaptureAccess.Status
    let openMixer: () -> Void
    let openChromeSetup: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if permissionStatus == .denied {
                Label("Allow System Audio Recording in Settings to control app audio.", systemImage: "lock")
                    .font(.callout).padding(16)
            } else if model.rows.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "speaker.wave.2").font(.title2).foregroundStyle(.secondary)
                    Text("Apps appear here when they play audio.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity).padding(24)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.rows) { row in
                            appRow(row)
                            if row.id != model.rows.last?.id { Divider().padding(.horizontal, 12) }
                        }
                    }
                }
                .frame(height: min(CGFloat(model.rows.count) * 108, 300))
            }
            if let error = model.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption).lineLimit(2).help(error)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.vertical, 8)
            }
            Divider()
            footer
        }
        .frame(width: 360)
        .frame(maxHeight: 520)
        .background(.background)
        .accessibilityIdentifier("menu-bar-mixer")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("WinMix").font(.headline)
                Spacer()
                Toggle("Boost", isOn: $model.boostEnabled)
                    .toggleStyle(.switch).controlSize(.mini).fixedSize()
                    .help(MixerControlHelp.boost(model.boostEnabled))
                    .disabled(permissionStatus == .denied)
            }
            Text(model.outputName.isEmpty ? "System output" : model.outputName)
                .font(.caption).foregroundStyle(.secondary)
                .lineLimit(1).help(model.outputName)
        }
        .padding(12)
    }

    private func appRow(_ row: AppGroup) -> some View {
        let setting = model.setting(for: row)
        let state = setting.isMuted ? "Muted" : row.isPlaying ? "Playing" : "Paused"
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(nsImage: row.identity.icon).resizable()
                    .frame(width: 22, height: 22).accessibilityHidden(true)
                Text(row.identity.name).font(.callout.weight(.medium))
                    .lineLimit(1).help(row.identity.name)
                Spacer(minLength: 4)
                Text(state).font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Button { model.toggleMute(row) } label: {
                    Image(systemName: setting.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .frame(width: 22, height: 24)
                }
                .buttonStyle(.borderless)
                .help(MixerControlHelp.mute(setting.isMuted))
                .accessibilityLabel(setting.isMuted ? "Unmute \(row.identity.name)" : "Mute \(row.identity.name)")
                .accessibilityValue(setting.isMuted ? "Muted" : "Not muted")
                Slider(value: Binding(
                    get: { min(model.setting(for: row).volume, model.maximumVolume) },
                    set: { model.setVolume($0, for: row) }
                ), in: 0...model.maximumVolume) {
                    Text("\(row.identity.name) volume")
                }
                .labelsHidden()
                .help(MixerControlHelp.volume(setting.volume, maximum: model.maximumVolume, muted: setting.isMuted))
                .accessibilityValue("\(Int((setting.volume * 100).rounded())) percent")
                Text("\(Int((setting.volume * 100).rounded()))%")
                    .font(.caption.monospacedDigit()).frame(width: 38, alignment: .trailing)
            }
            AppOutputMenu(model: model, row: row)
        }
        .padding(12)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button("Open Mixer", action: openMixer)
                Spacer()
                SettingsLink { Text("Settings…") }
            }
            HStack {
                Button("Chrome Setup…", action: openChromeSetup)
                Spacer()
                Button("Quit WinMix") { NSApplication.shared.terminate(nil) }
            }
        }
        .buttonStyle(.borderless)
        .padding(12)
    }
}
