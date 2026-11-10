import SwiftUI

enum StickerCase {
    static let paper = Color(red: 0.937, green: 0.929, blue: 0.910)
    static let cream = Color(red: 1, green: 0.985, blue: 0.947)
    static let ink = Color(red: 0.098, green: 0.098, blue: 0.098)
    static let secondary = Color(red: 0.31, green: 0.30, blue: 0.28)
    static let teal = Color(red: 0.157, green: 0.722, blue: 0.686)
    static let pink = Color(red: 0.937, green: 0.145, blue: 0.553)
    static let mint = Color(red: 0.76, green: 0.93, blue: 0.90)
    static let rose = Color(red: 0.98, green: 0.72, blue: 0.84)
}

/// Static, deterministic print grain. Decorative only; never participates in hit testing.
struct StickerPaper: View {
    var tint: Color = StickerCase.paper

    var body: some View {
        tint.overlay {
            Canvas { context, size in
                for index in 0..<1600 {
                    let x = CGFloat((index * 73) % 1601) / 1601 * size.width
                    let y = CGFloat((index * 193) % 1607) / 1607 * size.height
                    let length: CGFloat = index.isMultiple(of: 5) ? 2.5 : 0.7
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: length, height: 0.6)),
                                 with: .color(StickerCase.ink.opacity(0.055)))
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// Die-cut corners keep the sticker silhouette distinct from ordinary rounded cards.
struct StickerOutline: Shape {
    var cut: CGFloat = 10

    func path(in rect: CGRect) -> Path {
        let corner = min(cut, min(rect.width, rect.height) / 2)
        return Path { path in
            path.move(to: CGPoint(x: rect.minX + corner, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - corner, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + corner))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - corner))
            path.addLine(to: CGPoint(x: rect.maxX - corner, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + corner, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - corner))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + corner))
            path.closeSubpath()
        }
    }
}

struct StickerWordmark: View {
    var body: some View {
        Text("WinMix")
            .font(.system(size: 32, weight: .black).width(.condensed).italic())
            .tracking(-1)
            .foregroundStyle(StickerCase.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 2)
            .background {
                ZStack {
                    Rectangle().fill(StickerCase.teal).frame(width: 74, height: 17)
                        .rotationEffect(.degrees(-9)).offset(x: -61, y: 1)
                    Rectangle().fill(StickerCase.pink).frame(width: 74, height: 17)
                        .rotationEffect(.degrees(-9)).offset(x: 61, y: 1)
                    StickerOutline(cut: 7).fill(.white)
                        .shadow(color: StickerCase.ink.opacity(0.18), radius: 0, x: 1, y: 2)
                    StickerOutline(cut: 7).stroke(StickerCase.ink, lineWidth: 1.8)
                }
            }
            .rotationEffect(.degrees(-2))
            .accessibilityAddTraits(.isHeader)
    }
}

struct StickerButtonStyle: ButtonStyle {
    var selected = false

    func makeBody(configuration: Configuration) -> some View {
        StickerButtonBody(configuration: configuration, selected: selected)
    }
}

/// Read enabled state inside the rendered view, after the caller's disabled modifier.
private struct StickerButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let selected: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(StickerCase.ink)
            .symbolRenderingMode(.monochrome)
            .frame(width: 30, height: 30)
            .background(configuration.isPressed ? StickerCase.teal.opacity(0.35)
                        : selected ? StickerCase.rose : StickerCase.cream,
                        in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(StickerCase.ink, lineWidth: 1.7))
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(RoundedRectangle(cornerRadius: 5))
    }
}

struct StickerBoostToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 8) {
                configuration.label
                Capsule().fill(configuration.isOn ? StickerCase.pink : StickerCase.secondary.opacity(0.2))
                    .overlay(Capsule().strokeBorder(StickerCase.ink, lineWidth: 1.5))
                    .overlay {
                        Circle().fill(StickerCase.cream)
                            .overlay(Circle().strokeBorder(StickerCase.ink, lineWidth: 1))
                            .frame(width: 16, height: 16)
                            .offset(x: configuration.isOn ? 7 : -7)
                    }
                    .frame(width: 36, height: 22)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }.toggleStyle(.switch)
        }
    }
}

/// Matches the existing fader's interaction and native accessibility representation.
struct StickerVolumeSlider: View {
    @Binding var value: Double
    let maximum: Double
    let isMuted: Bool
    let label: String
    var accent: Color = StickerCase.teal
    @Environment(\.isEnabled) private var isEnabled
    @FocusState private var isFocused: Bool

    var body: some View {
        GeometryReader { geometry in
            let travel = max(geometry.size.width - 14, 1)
            let progress = CGFloat(min(max(value / maximum, 0), 1))
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 5).fill(StickerCase.cream).frame(height: 10)
                Rectangle().fill(isMuted ? StickerCase.secondary.opacity(0.35) : accent)
                    .frame(width: 7 + progress * travel, height: 10)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 5, bottomLeadingRadius: 5))
                RoundedRectangle(cornerRadius: 5).strokeBorder(StickerCase.ink, lineWidth: 1.8).frame(height: 10)
                RoundedRectangle(cornerRadius: 3).fill(StickerCase.ink)
                    .overlay(Rectangle().fill(StickerCase.cream).frame(width: 2, height: 13))
                    .frame(width: 14, height: 24)
                    .offset(x: progress * travel)
            }
            .frame(height: 32)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                guard isEnabled else { return }
                value = min(max((drag.location.x - 7) / travel, 0), 1) * maximum
            })
        }
        .frame(minWidth: 60, minHeight: 32, maxHeight: 32)
        .opacity(isEnabled ? 1 : 0.4)
        .focusable(isEnabled)
        .focusEffectDisabled()
        .focused($isFocused)
        .overlay {
            if isFocused {
                RoundedRectangle(cornerRadius: 5).strokeBorder(StickerCase.ink, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
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
