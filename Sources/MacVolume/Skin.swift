import SwiftUI

/// The retro hardware look: gunmetal panels, black LED displays and a dot-matrix font.
enum Skin {
    static let chrome = Color(red: 0.17, green: 0.18, blue: 0.22)
    static let chromeLight = Color(red: 0.25, green: 0.26, blue: 0.31)
    static let bevelHighlight = Color(red: 0.42, green: 0.44, blue: 0.51)
    static let bevelShadow = Color(red: 0.06, green: 0.06, blue: 0.08)
    static let display = Color(red: 0.015, green: 0.03, blue: 0.025)
    static let green = Color(red: 0.25, green: 1.0, blue: 0.42)
    static let greenDim = Color(red: 0.05, green: 0.17, blue: 0.09)
    static let amber = Color(red: 1.0, green: 0.76, blue: 0.2)
    static let red = Color(red: 1.0, green: 0.27, blue: 0.2)
    static let unlit = Color(red: 0.09, green: 0.1, blue: 0.11)

    static func label(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold, design: .monospaced) }
}

/// A raised or sunken edge, like the moulded plastic on old hi-fi gear.
struct Bevel: ViewModifier {
    var raised = true

    func body(content: Content) -> some View {
        content.overlay {
            Canvas { context, size in
                let light = raised ? Skin.bevelHighlight : Skin.bevelShadow
                let dark = raised ? Skin.bevelShadow : Skin.bevelHighlight
                let (w, h) = (size.width, size.height)
                context.fill(Path(CGRect(x: 0, y: 0, width: w, height: 1)), with: .color(light))
                context.fill(Path(CGRect(x: 0, y: 0, width: 1, height: h)), with: .color(light))
                context.fill(Path(CGRect(x: 0, y: h - 1, width: w, height: 1)), with: .color(dark))
                context.fill(Path(CGRect(x: w - 1, y: 0, width: 1, height: h)), with: .color(dark))
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

extension View {
    func bevel(raised: Bool = true) -> some View { modifier(Bevel(raised: raised)) }
}

struct SkinButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 7)
            .frame(minHeight: 22)
            .background(configuration.isPressed ? Skin.chrome : Skin.chromeLight)
            .bevel(raised: !configuration.isPressed)
            .contentShape(Rectangle())
    }
}

/// A small round lamp.
struct Lamp: View {
    let isOn: Bool
    var color = Skin.green

    var body: some View {
        Circle()
            .fill(isOn ? color : Skin.unlit)
            .frame(width: 7, height: 7)
            .shadow(color: isOn ? color.opacity(0.9) : .clear, radius: 3)
            .overlay(Circle().stroke(Skin.bevelShadow, lineWidth: 1))
            .accessibilityHidden(true)
    }
}

/// The logo's rising LED wedge, small enough for the title strip.
struct LogoMark: View {
    var body: some View {
        Canvas { context, size in
            let heights = [2, 3, 4, 5, 6]
            let cell = size.height / 6
            for (column, height) in heights.enumerated() {
                for row in 0..<height {
                    let color = row >= 5 ? Skin.red : row >= 3 ? Skin.amber : Skin.green
                    let rect = CGRect(x: CGFloat(column) * cell * 1.3, y: size.height - CGFloat(row + 1) * cell,
                                      width: cell, height: cell - 1)
                    context.fill(Path(rect), with: .color(color))
                }
            }
        }
        .frame(width: 21, height: 16)
        .accessibilityHidden(true)
    }
}

/// Fine horizontal grooves, as on a title bar's grip.
struct Grooves: View {
    var body: some View {
        Canvas { context, size in
            var y: CGFloat = 0
            while y < size.height {
                context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(Skin.bevelHighlight.opacity(0.7)))
                context.fill(Path(CGRect(x: 0, y: y + 1, width: size.width, height: 1)), with: .color(Skin.bevelShadow))
                y += 4
            }
        }
        .frame(height: 11)
        .accessibilityHidden(true)
    }
}

/// A 5×7 dot-matrix font, for the display and readouts. Text outside it stays blank, so
/// free-form names are shown with a regular font instead wherever they matter.
enum DotFont {
    static let columns = 6  // 5 dots plus a gap
    static let rows = 7

    static func normalized(_ text: String) -> [Character] {
        Array(text.replacingOccurrences(of: "’", with: "'")
            .folding(options: .diacriticInsensitive, locale: nil)
            .uppercased())
    }

    static let glyphs: [Character: [UInt8]] = [
        "A": [0x0E, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11], "B": [0x1E, 0x11, 0x11, 0x1E, 0x11, 0x11, 0x1E],
        "C": [0x0E, 0x11, 0x10, 0x10, 0x10, 0x11, 0x0E], "D": [0x1E, 0x11, 0x11, 0x11, 0x11, 0x11, 0x1E],
        "E": [0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x1F], "F": [0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x10],
        "G": [0x0E, 0x11, 0x10, 0x17, 0x11, 0x11, 0x0F], "H": [0x11, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11],
        "I": [0x0E, 0x04, 0x04, 0x04, 0x04, 0x04, 0x0E], "J": [0x07, 0x02, 0x02, 0x02, 0x02, 0x12, 0x0C],
        "K": [0x11, 0x12, 0x14, 0x18, 0x14, 0x12, 0x11], "L": [0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x1F],
        "M": [0x11, 0x1B, 0x15, 0x15, 0x11, 0x11, 0x11], "N": [0x11, 0x19, 0x15, 0x13, 0x11, 0x11, 0x11],
        "O": [0x0E, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E], "P": [0x1E, 0x11, 0x11, 0x1E, 0x10, 0x10, 0x10],
        "Q": [0x0E, 0x11, 0x11, 0x11, 0x15, 0x12, 0x0D], "R": [0x1E, 0x11, 0x11, 0x1E, 0x14, 0x12, 0x11],
        "S": [0x0F, 0x10, 0x10, 0x0E, 0x01, 0x01, 0x1E], "T": [0x1F, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04],
        "U": [0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E], "V": [0x11, 0x11, 0x11, 0x11, 0x11, 0x0A, 0x04],
        "W": [0x11, 0x11, 0x11, 0x15, 0x15, 0x1B, 0x11], "X": [0x11, 0x11, 0x0A, 0x04, 0x0A, 0x11, 0x11],
        "Y": [0x11, 0x11, 0x0A, 0x04, 0x04, 0x04, 0x04], "Z": [0x1F, 0x01, 0x02, 0x04, 0x08, 0x10, 0x1F],
        "0": [0x0E, 0x11, 0x13, 0x15, 0x19, 0x11, 0x0E], "1": [0x04, 0x0C, 0x04, 0x04, 0x04, 0x04, 0x0E],
        "2": [0x0E, 0x11, 0x01, 0x02, 0x04, 0x08, 0x1F], "3": [0x1F, 0x02, 0x04, 0x02, 0x01, 0x11, 0x0E],
        "4": [0x02, 0x06, 0x0A, 0x12, 0x1F, 0x02, 0x02], "5": [0x1F, 0x10, 0x1E, 0x01, 0x01, 0x11, 0x0E],
        "6": [0x06, 0x08, 0x10, 0x1E, 0x11, 0x11, 0x0E], "7": [0x1F, 0x01, 0x02, 0x04, 0x08, 0x08, 0x08],
        "8": [0x0E, 0x11, 0x11, 0x0E, 0x11, 0x11, 0x0E], "9": [0x0E, 0x11, 0x11, 0x0F, 0x01, 0x02, 0x0C],
        "%": [0x18, 0x19, 0x02, 0x04, 0x08, 0x13, 0x03], "*": [0x00, 0x04, 0x15, 0x0E, 0x15, 0x04, 0x00],
        "-": [0x00, 0x00, 0x00, 0x1F, 0x00, 0x00, 0x00], ":": [0x00, 0x0C, 0x0C, 0x00, 0x0C, 0x0C, 0x00],
        ".": [0x00, 0x00, 0x00, 0x00, 0x00, 0x0C, 0x0C], "'": [0x0C, 0x04, 0x08, 0x00, 0x00, 0x00, 0x00],
        "#": [0x0A, 0x0A, 0x1F, 0x0A, 0x1F, 0x0A, 0x0A], "+": [0x00, 0x04, 0x04, 0x1F, 0x04, 0x04, 0x00],
        "/": [0x00, 0x01, 0x02, 0x04, 0x08, 0x10, 0x00], "(": [0x02, 0x04, 0x08, 0x08, 0x08, 0x04, 0x02],
        ")": [0x08, 0x04, 0x02, 0x02, 0x02, 0x04, 0x08], "&": [0x0C, 0x12, 0x14, 0x08, 0x15, 0x12, 0x0D],
        "!": [0x04, 0x04, 0x04, 0x04, 0x04, 0x00, 0x04],
    ]

    /// Adds the lit dots of `characters`, starting `column` dots from the left, skipping
    /// anything outside `visibleColumns`.
    static func addDots(of characters: [Character], from column: Int, pitch: CGFloat, dot: CGFloat,
                        visibleColumns: Int, to path: inout Path) {
        for (index, character) in characters.enumerated() {
            let start = column + index * columns
            guard start < visibleColumns, start + columns > 0, let glyph = glyphs[character] else { continue }
            for (row, bits) in glyph.enumerated() {
                for bit in 0..<5 where bits & (0x10 >> UInt8(bit)) != 0 {
                    let x = start + bit
                    guard x >= 0, x < visibleColumns else { continue }
                    path.addRect(CGRect(x: CGFloat(x) * pitch, y: CGFloat(row) * pitch, width: dot, height: dot))
                }
            }
        }
    }
}

/// Fixed-size dot-matrix text.
struct DotText: View {
    let text: String
    var color = Skin.green
    var dot: CGFloat = 1.5
    var gap: CGFloat = 0.5

    var body: some View {
        let characters = DotFont.normalized(text)
        let pitch = dot + gap
        let columns = characters.count * DotFont.columns
        Canvas { context, _ in
            var path = Path()
            DotFont.addDots(of: characters, from: 0, pitch: pitch, dot: dot, visibleColumns: columns, to: &path)
            context.fill(path, with: .color(color))
        }
        .frame(width: CGFloat(columns) * pitch, height: CGFloat(DotFont.rows) * pitch)
        .accessibilityElement()
        .accessibilityLabel(text)
    }
}

/// A dot-matrix display that scrolls text too long to fit, and holds still when its window
/// is in the background.
struct Marquee: View {
    let text: String
    var color = Skin.green

    private static let dot: CGFloat = 2
    private static let pitch: CGFloat = 2.5

    @Environment(\.controlActiveState) private var activeState

    var body: some View {
        GeometryReader { geometry in
            let visibleColumns = Int(geometry.size.width / Self.pitch)
            let characters = DotFont.normalized(text)
            let fits = characters.count * DotFont.columns <= visibleColumns
            ZStack(alignment: .topLeading) {
                unlitDots(columns: visibleColumns)
                if fits || activeState == .inactive {
                    dots(characters, offset: 0, columns: visibleColumns)
                } else {
                    let loop = characters + DotFont.normalized("   ***   ")
                    TimelineView(.periodic(from: .now, by: 0.1)) { timeline in
                        let step = Int(timeline.date.timeIntervalSinceReferenceDate * 10)
                        let offset = -(step % (loop.count * DotFont.columns))
                        dots(loop + loop, offset: offset, columns: visibleColumns)
                    }
                }
            }
        }
        .frame(height: CGFloat(DotFont.rows) * Self.pitch)
        .accessibilityElement()
        .accessibilityLabel(text)
    }

    private func dots(_ characters: [Character], offset: Int, columns: Int) -> some View {
        Canvas { context, _ in
            var path = Path()
            DotFont.addDots(of: characters, from: offset, pitch: Self.pitch, dot: Self.dot, visibleColumns: columns, to: &path)
            context.fill(path, with: .color(color))
        }
    }

    /// The faint grid of switched-off LEDs behind the text.
    private func unlitDots(columns: Int) -> some View {
        Canvas { context, _ in
            var path = Path()
            for x in 0..<columns {
                for y in 0..<DotFont.rows {
                    path.addRect(CGRect(x: CGFloat(x) * Self.pitch, y: CGFloat(y) * Self.pitch, width: Self.dot, height: Self.dot))
                }
            }
            context.fill(path, with: .color(Skin.greenDim.opacity(0.55)))
        }
    }
}

/// A volume slider drawn as a row of LED segments: green, then yellow, red only when boosted.
struct LEDSlider: View {
    @Binding var value: Double
    let maximum: Double
    let isMuted: Bool
    let label: String

    private static let segments = 30

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                let width = size.width / CGFloat(Self.segments)
                for index in 0..<Self.segments {
                    let level = Double(index + 1) / Double(Self.segments) * maximum
                    let isLit = level <= value + maximum / Double(Self.segments) / 2 && value > 0
                    let rect = CGRect(x: CGFloat(index) * width, y: 0, width: width - 1.5, height: size.height)
                    context.fill(Path(rect), with: .color(color(for: level, isLit: isLit)))
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                value = min(max(drag.location.x / geometry.size.width, 0), 1) * maximum
            })
        }
        .padding(3)
        .frame(height: 20)
        .background(Skin.display)
        .bevel(raised: false)
        .accessibilityRepresentation {
            Slider(value: $value, in: 0...maximum) { Text(label) }
        }
    }

    private func color(for level: Double, isLit: Bool) -> Color {
        guard isLit else { return Skin.unlit }
        if isMuted { return Skin.bevelHighlight.opacity(0.85) }
        return level > 1.0001 ? Skin.red : level > 0.75 ? Skin.amber : Skin.green
    }
}
