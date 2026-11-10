import SwiftUI

enum MixerAppearance: String, CaseIterable, Identifiable {
    case ceramic, retro, stickerCase

    var id: String { rawValue }
    var title: String {
        switch self {
        case .ceramic: return "Ceramic"
        case .retro: return "Retro"
        case .stickerCase: return "Sticker Case"
        }
    }

    var headerColor: Color {
        switch self {
        case .ceramic: return Ceramic.secondary
        case .retro: return .white.opacity(0.7)
        case .stickerCase: return StickerCase.ink
        }
    }
}

enum Ceramic {
    static let surface = Color(red: 0.96, green: 0.97, blue: 0.98)
    static let edge = Color(red: 0.86, green: 0.89, blue: 0.93)
    static let blue = Color(red: 0.14, green: 0.31, blue: 0.91)
    static let ink = Color(red: 0.09, green: 0.13, blue: 0.23)
    static let secondary = Color(red: 0.36, green: 0.41, blue: 0.50)
    static let inset = Color(red: 0.92, green: 0.95, blue: 0.99)
}

enum MixerControlHelp {
    static func boost(_ enabled: Bool) -> String {
        enabled
            ? "Boost: On. App sliders allow up to 200%. Click to turn off and cap boosted apps at 100%."
            : "Boost: Off. App sliders are limited to 100%. Click to unlock up to 200%."
    }

    static func mute(_ muted: Bool) -> String {
        muted ? "Mute: On. Click to unmute." : "Mute: Off. Click to mute."
    }

    static func volume(_ value: Double, maximum: Double, muted: Bool) -> String {
        "Volume: \(Int((value * 100).rounded()))%. \(muted ? "Muted. " : "")Range: 0–\(Int(maximum * 100))%. Drag to adjust."
    }
}

/// All themes expose the same keyboard-accessible header actions.
struct MixerHeaderControls: View {
    @Binding var appearance: MixerAppearance
    let showSetup: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            Menu {
                ForEach(MixerAppearance.allCases) { style in
                    Button { appearance = style } label: {
                        if appearance == style {
                            Label(style.title, systemImage: "checkmark")
                        } else {
                            Text(style.title)
                        }
                    }
                }
            } label: {
                headerGlyph("paintpalette")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .frame(width: appearance == .stickerCase ? 28 : nil, height: appearance == .stickerCase ? 28 : nil)
            .background {
                if appearance == .stickerCase {
                    RoundedRectangle(cornerRadius: 5).fill(StickerCase.cream)
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(StickerCase.ink, lineWidth: 1.5))
                }
            }
            .help("Appearance: \(appearance.title). Click to choose \(MixerAppearance.allCases.map(\.title).joined(separator: ", ")).")
            .accessibilityLabel("Change appearance")
            .accessibilityValue(appearance.title)

            Button(action: showSetup) {
                headerGlyph(appearance == .stickerCase ? "questionmark" : "questionmark.circle")
            }
            .buttonStyle(.plain)
            .help("Install browser tab controls")
            .accessibilityLabel("Help installing browser tab controls")
        }
        .font(.system(size: 14))
        .foregroundStyle(appearance.headerColor)
    }

    private func headerGlyph(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .frame(width: 28, height: 28)
            .background {
                if appearance == .stickerCase {
                    RoundedRectangle(cornerRadius: 5).fill(StickerCase.cream)
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(StickerCase.ink, lineWidth: 1.5))
                }
            }
            .contentShape(Rectangle())
    }
}

struct CeramicButtonStyle: ButtonStyle {
    var active = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(active ? Ceramic.blue : Ceramic.secondary)
            .frame(width: 30, height: 30)
            .background {
                Circle().fill(configuration.isPressed ? Ceramic.edge : active ? Ceramic.blue.opacity(0.12) : Color.white.opacity(0.85))
                    .shadow(color: Ceramic.ink.opacity(configuration.isPressed ? 0 : 0.08), radius: 2, y: 1)
            }
            .overlay(Circle().strokeBorder(active ? Ceramic.blue.opacity(0.65) : Ceramic.edge.opacity(0.8), lineWidth: active ? 1.2 : 0.5))
            .contentShape(Circle())
    }
}

struct CeramicVolumeSlider: View {
    @Binding var value: Double
    let maximum: Double
    let isMuted: Bool
    let label: String
    @Environment(\.isEnabled) private var isEnabled
    @FocusState private var isFocused: Bool

    var body: some View {
        GeometryReader { geometry in
            let travel = max(geometry.size.width - 14, 1)
            let progress = CGFloat(min(max(value / maximum, 0), 1))
            ZStack(alignment: .leading) {
                Capsule().fill(Ceramic.edge).frame(height: 6)
                Capsule().fill(isMuted ? Ceramic.secondary.opacity(0.45) : Ceramic.blue)
                    .frame(width: 7 + progress * travel, height: 6)
                RoundedRectangle(cornerRadius: 5)
                    .fill(LinearGradient(colors: [.white, Ceramic.surface], startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Ceramic.edge, lineWidth: 0.5))
                    .shadow(color: Ceramic.ink.opacity(0.13), radius: 2, y: 1)
                    .frame(width: 14, height: 20)
                    .offset(x: progress * travel)
            }
            .frame(height: 28)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                guard isEnabled else { return }
                value = min(max((drag.location.x - 7) / travel, 0), 1) * maximum
            })
        }
        .frame(minWidth: 50, minHeight: 28, maxHeight: 28)
        .opacity(isEnabled ? 1 : 0.45)
        .focusable(isEnabled)
        .focusEffectDisabled()
        .focused($isFocused)
        .overlay {
            if isFocused {
                RoundedRectangle(cornerRadius: 6).strokeBorder(Ceramic.blue.opacity(0.7), lineWidth: 2)
                    .padding(-3).allowsHitTesting(false)
            }
        }
        .onMoveCommand { direction in
            guard isEnabled else { return }
            switch direction {
            case .left, .down: value = max(0, value - 0.01)
            case .right, .up: value = min(maximum, value + 0.01)
            @unknown default: break
            }
        }
        .accessibilityRepresentation {
            Slider(value: $value, in: 0...maximum) { Text(label) }
                .labelsHidden()
                .accessibilityValue("\(Int((value * 100).rounded())) percent")
        }
    }
}
