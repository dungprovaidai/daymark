import SwiftUI
import UIKit

enum Palette {
    static let accent = Color("AccentColor")
    static let background = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let names = ["lavender", "mint", "blue", "amber", "rose"]
    static func color(_ name: String) -> Color {
        switch name {
        case "mint": return Color(red: 0.16, green: 0.57, blue: 0.44)
        case "blue": return Color(red: 0.23, green: 0.48, blue: 0.78)
        case "amber": return Color(red: 0.78, green: 0.45, blue: 0.13)
        case "rose": return Color(red: 0.76, green: 0.32, blue: 0.46)
        default: return accent
        }
    }
}

struct Surface<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.primary.opacity(0.035)))
    }
}

struct SymbolTile: View {
    let symbol: String
    var color: Color = Palette.accent
    var body: some View {
        Image(systemName: symbol).font(.body.weight(.semibold))
            .foregroundStyle(color).frame(width: 40, height: 40)
            .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 13))
            .accessibilityHidden(true)
    }
}

struct SectionHeading: View {
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.title3.weight(.semibold))
            if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(.secondary) }
        }.accessibilityElement(children: .combine)
    }
}

struct EmptyCard: View {
    let symbol: String
    let title: String
    let message: String
    var body: some View {
        Surface {
            VStack(spacing: 12) {
                SymbolTile(symbol: symbol)
                Text(title).font(.headline)
                Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }.frame(maxWidth: .infinity).padding(.vertical, 18)
        }
    }
}

struct PressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.65 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

enum Feedback {
    @MainActor static func tap() {
        guard UserDefaults.standard.object(forKey: "haptics") as? Bool ?? true else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }
    @MainActor static func success() {
        guard UserDefaults.standard.object(forKey: "haptics") as? Bool ?? true else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

struct ColorPickerRow: View {
    @Binding var selection: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Color")
            HStack(spacing: 4) {
                ForEach(Palette.names, id: \.self) { name in
                    Button { selection = name; Feedback.tap() } label: {
                        Circle().fill(Palette.color(name)).frame(width: 26, height: 26)
                            .overlay { if selection == name { Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white) } }
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }.buttonStyle(.plain).accessibilityLabel(name.capitalized)
                        .accessibilityAddTraits(selection == name ? .isSelected : [])
                }
            }
        }
    }
}

struct IconPicker: View {
    @Binding var selection: String
    static let icons = ["book.closed", "sparkles", "heart", "graduationcap", "briefcase", "leaf", "sun.max", "moon", "figure.walk", "cup.and.saucer", "pencil", "gift", "number", "checkmark.circle", "star", "text.alignleft"]
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 48))], spacing: 8) {
            ForEach(Self.icons, id: \.self) { icon in
                Button { selection = icon; Feedback.tap() } label: {
                    Image(systemName: icon).frame(width: 44, height: 44)
                        .background(selection == icon ? Palette.accent.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain).foregroundStyle(selection == icon ? Palette.accent : .secondary)
                    .accessibilityLabel(icon.replacingOccurrences(of: ".", with: " "))
                    .accessibilityAddTraits(selection == icon ? .isSelected : [])
            }
        }
    }
}

extension Double {
    var compact: String { formatted(.number.precision(.fractionLength(0...2))) }
}

extension View {
    func pageBackground() -> some View { background(Palette.background).scrollContentBackground(.hidden) }
}
