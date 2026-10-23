import SwiftUI
import AppKit

enum AppStyle {
    // Cold ice-blue horror on pitch black.
    static let canvas = Color(red: 0, green: 0, blue: 0)
    static let card = Color(red: 0.03, green: 0.045, blue: 0.06)
    static let ink = Color(red: 0.88, green: 0.95, blue: 0.99)
    static let muted = Color(red: 0.50, green: 0.61, blue: 0.68)
    /// Primary: ice blue.
    static let accent = Color(red: 0.55, green: 0.86, blue: 1.0)
    /// Secondary glow: pale frost.
    static let poison = Color(red: 0.74, green: 0.94, blue: 1.0)
    static let midnight = Color(red: 0, green: 0, blue: 0)
    static let border = Color(red: 0.11, green: 0.19, blue: 0.25)
    static let blood = Color(red: 0.86, green: 0.16, blue: 0.12)
    static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .bold, design: .serif) }
    static func signal(_ size: CGFloat = 10) -> Font { .system(size: size, weight: .medium, design: .monospaced) }
}
struct HauntedPrimaryStyle: ButtonStyle {
    /// Smaller padding for tight spots like the menu bar popover.
    var compact = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: compact ? 12 : 13, weight: .semibold))
            .padding(.horizontal, compact ? 12 : 18).padding(.vertical, compact ? 7 : 11).foregroundStyle(AppStyle.midnight)
            .background(AppStyle.accent.opacity(configuration.isPressed ? 0.75 : 1), in: RoundedRectangle(cornerRadius: 7))
            .shadow(color: AppStyle.accent.opacity(0.15), radius: 14, y: 3)
            .opacity(enabled ? 1 : 0.45)
    }
}
struct HauntedSecondaryStyle: ButtonStyle {
    var compact = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: compact ? 12 : 13, weight: .medium))
            .padding(.horizontal, compact ? 10 : 14).padding(.vertical, compact ? 7 : 10).foregroundStyle(AppStyle.ink)
            .background(AppStyle.ink.opacity(configuration.isPressed ? 0.12 : 0.045), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(AppStyle.border, lineWidth: 1))
            .opacity(enabled ? 1 : 0.45)
    }
}
struct HauntedRoot: ViewModifier {
    func body(content: Content) -> some View {
        content.preferredColorScheme(.dark).tint(AppStyle.accent)
            .foregroundStyle(AppStyle.ink).background(AppStyle.canvas)
    }
}
extension View { func haunted() -> some View { modifier(HauntedRoot()) } }
struct CrookedBorder: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 2, y: 1)); p.addLine(to: CGPoint(x: rect.width * 0.43, y: 2))
        p.addLine(to: CGPoint(x: rect.width - 1, y: 0)); p.addLine(to: CGPoint(x: rect.width - 2, y: rect.height * 0.55))
        p.addLine(to: CGPoint(x: rect.width, y: rect.height - 2)); p.addLine(to: CGPoint(x: rect.width * 0.4, y: rect.height))
        p.addLine(to: CGPoint(x: 1, y: rect.height - 1)); p.closeSubpath(); return p
    }
}
/// A small portrait of the standing ghost, for the popover header and side reminders.
struct WatcherMark: View {
    var size: CGFloat = 32
    var body: some View {
        StandingGhost().frame(width: size, height: size * 1.5)
    }
}
/// The standing ghost in a faint glow, for empty states. Fills the height it is given.
struct GhostGathering: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Fades to nothing inside its own frame, so no edge ever shows.
                RadialGradient(colors: [AppStyle.accent.opacity(0.14), .clear], center: .center,
                               startRadius: 0, endRadius: min(geo.size.width, geo.size.height) / 2)
                StandingGhost().shadow(color: AppStyle.poison.opacity(0.12), radius: 18)
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}
struct SignalTexture: View {
    var body: some View {
        Canvas { context, size in
            for i in 0..<180 {
                let x = CGFloat((i * 137 + 29) % 1009) / 1009 * size.width
                let y = CGFloat((i * 239 + 73) % 1013) / 1013 * size.height
                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 0.8, height: 0.8)), with: .color(AppStyle.ink.opacity(0.07)))
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}
struct HauntedBackdrop: View {
    var body: some View {
        ZStack {
            AppStyle.canvas
            RadialGradient(colors: [AppStyle.accent.opacity(0.045), .clear], center: .topTrailing, startRadius: 0, endRadius: 650)
            SignalTexture()
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}
