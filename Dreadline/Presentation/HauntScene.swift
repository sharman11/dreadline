import SwiftUI
import AppKit

// One scene owns one haunting. Source refreshes update its text, never its choreography.
//
// Dash (10 s before the early warning): the ghost streaks across the screen once. Nothing else.
// Early warning: windows minimize → ghost peeks from above (upside down) or below, with a knock → windows return.
// Meeting alert: windows minimize → black screen, the ghost pops up → it lingers → the meeting card slides down.
// Exits:  Join    → the ghost vanishes, windows return, then the link opens.
//         Snooze  → the black overlay flickers with a warning, then windows return.
//         Dismiss → the face lunges back with a scary warning, then windows return.
@MainActor
final class HauntScene: ObservableObject {
    /// Where the early-warning ghost appears. The dash direction alternates with it.
    enum Entrance: Int, CaseIterable { case above, below }
    enum Stage: Equatable { case gathering, dash, peek, shock, lingering, manifest, warning, vanishing, gone }
    enum Warning: Equatable { case dismiss, snooze }
    static let dismissLines = [
        "You can't dismiss me.",
        "Dismissed. But not forgotten.",
        "The ghost has noted your absence.",
        "Close the door if you like. I'm already inside.",
        "Fine. Leave. I'll be waiting at the next one."
    ]
    static let snoozeLines = [
        "Five more minutes. Then I come back.",
        "Snooze all you like. I don't sleep.",
        "I'll be right here. Waiting.",
        "Run the clock. I'll keep count."
    ]
    @Published var stage: Stage = .gathering
    /// Paper tear-away exit, 0 → 1.
    @Published var reveal: CGFloat = 0
    @Published var darkness = 0.0
    @Published var knockCount = 0
    @Published var scratchProgress: [CGFloat] = [0, 0, 0]
    /// Dash: 0 off one edge → 1 off the other.
    @Published var dashProgress: CGFloat = 0
    /// Early warning: 0 hidden past the screen edge, 1 peeking in.
    @Published var peek: CGFloat = 0
    /// Meeting alert: the face that pops up.
    @Published var closeupOpacity = 0.0
    @Published var closeupScale: CGFloat = 1
    @Published var shake: CGFloat = 0
    /// Meeting alert: the full ghost. `ghostRest` 0 = centered and large, 1 = hovering behind the card.
    @Published var ghostOpacity = 0.0
    @Published var ghostRest: CGFloat = 0
    @Published var bob = false
    /// Meeting card: 0 above the top edge, 1 settled in the center.
    @Published var cardDrop: CGFloat = 0
    /// Snooze warning: 1 while the black overlay is lit (ghost visible), 0 between flickers.
    @Published var flicker = 0.0
    /// Whole-scene fade used by the Join exit.
    @Published var fade = 0.0
    @Published var warning: String?
    @Published var warningKind: Warning?
    let entrance: Entrance
    /// Dash direction.
    let fromLeft: Bool
    let still: Bool
    private var choreography: Task<Void, Never>?
    init(entrance: Entrance = .above, fromLeft: Bool = true, still: Bool = false) {
        self.entrance = entrance; self.fromLeft = fromLeft; self.still = still
    }
    var interactive: Bool { stage == .manifest && reveal == 0 }

    private func run(_ body: @escaping @MainActor (_ wait: (Int) async throws -> Void) async throws -> Void) {
        choreography?.cancel()
        choreography = Task { [weak self] in
            guard self != nil, !Task.isCancelled else { return }
            let start = ContinuousClock.now
            func wait(_ milliseconds: Int) async throws {
                try await Task.sleep(until: start.advanced(by: .milliseconds(milliseconds)), clock: .continuous)
                try Task.checkCancellation()
            }
            do { try await body(wait) } catch { }
        }
    }

    /// The ghost streaks across the screen once. No windows move and nothing is clickable.
    func dash(finished: @escaping @MainActor () -> Void = {}) {
        stage = .dash; dashProgress = 0; reveal = 0; fade = 0
        run { [weak self] wait in
            guard let self else { return }
            if self.still { try await wait(1200); finished(); return }
            try await wait(60)
            withAnimation(.easeIn(duration: 0.55)) { self.dashProgress = 1 }
            try await wait(800)
            self.stage = .gone
            finished()
        }
    }

    /// Runs the early warning (prelude) or the meeting alert. `minimize` runs first and may block while
    /// windows animate away; the timeline starts once it returns. `finished` fires when a prelude is over.
    func start(prelude: Bool,
               minimize: @escaping @MainActor () -> Void = {},
               knock: @escaping @MainActor (Int) -> Void = { _ in },
               arrival: @escaping @MainActor () -> Void = {},
               restore: @escaping @MainActor () -> Void = {},
               finished: @escaping @MainActor () -> Void = {}) {
        stage = .gathering; reveal = 0; darkness = 0; knockCount = 0; scratchProgress = [0, 0, 0]
        peek = 0; closeupOpacity = 0; closeupScale = 1; shake = 0
        ghostOpacity = 0; ghostRest = 0; bob = false; cardDrop = 0; flicker = 0; fade = 0; warning = nil; warningKind = nil
        choreography?.cancel()
        choreography = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }
            minimize()
            let start = ContinuousClock.now
            func wait(_ milliseconds: Int) async throws {
                try await Task.sleep(until: start.advanced(by: .milliseconds(milliseconds)), clock: .continuous)
                try Task.checkCancellation()
            }
            do {
                if prelude { try await self.prelude(wait, knock: knock, restore: restore) }
                else { try await self.arrival(wait, arrival: arrival) }
                finished()
            } catch { }
        }
    }

    private func prelude(_ wait: (Int) async throws -> Void, knock: @MainActor (Int) -> Void, restore: @MainActor () -> Void) async throws {
        if still {
            stage = .peek; peek = 1; darkness = 0.4; knockCount = 1; knock(0)
            try await wait(2600)
            peek = 0; darkness = 0; stage = .gone
            restore()
            return
        }
        // Let the minimize animation finish before anything appears.
        try await wait(450)
        stage = .peek
        knockCount = 1; knock(0)
        withAnimation(.spring(response: 0.75, dampingFraction: 0.68)) { peek = 1 }
        withAnimation(.easeOut(duration: 0.4)) { darkness = 0.45; scratchProgress[0] = 1 }
        try await wait(1500)
        knockCount = 2; knock(1)
        withAnimation(.easeOut(duration: 0.3)) { darkness = 0.55; scratchProgress[1] = 1 }
        withAnimation(.easeInOut(duration: 0.18)) { peek = 0.86 }
        try await wait(1700)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { peek = 1.04 }
        try await wait(2650)
        withAnimation(.easeIn(duration: 0.45)) { peek = 0; darkness = 0; scratchProgress = [0, 0, 0] }
        try await wait(3150)
        stage = .gone
        restore()
        try await wait(3500)
    }

    private func arrival(_ wait: (Int) async throws -> Void, arrival: @MainActor () -> Void) async throws {
        if still {
            // Reduced motion: no pop, no movement. The ghost and card are simply there.
            arrival()
            darkness = 1; ghostOpacity = 0.5; ghostRest = 1; cardDrop = 1; stage = .manifest
            return
        }
        try await wait(250)
        // The scare: the room is black and the face is suddenly there. No fade-in.
        stage = .shock
        arrival()
        darkness = 1; closeupOpacity = 1; closeupScale = 1.12
        withAnimation(.spring(response: 0.14, dampingFraction: 0.35)) { closeupScale = 1; shake = 1 }
        try await wait(400)
        withAnimation(.spring(response: 0.16, dampingFraction: 0.3)) { shake = 0 }
        try await wait(1250)
        // The face withdraws into the whole ghost, which lingers in the room.
        stage = .lingering
        withAnimation(.easeOut(duration: 0.4)) { closeupOpacity = 0; closeupScale = 0.9; ghostOpacity = 1 }
        withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { bob = true }
        try await wait(2900)
        // The meeting slides down from the top; the ghost drifts back to hover behind it.
        withAnimation(.spring(response: 0.7, dampingFraction: 0.74)) { cardDrop = 1 }
        withAnimation(.easeInOut(duration: 0.9)) { ghostRest = 1; ghostOpacity = 0.55 }
        try await wait(3300)
        stage = .manifest
    }

    /// Dismiss: the face lunges back with a scary warning. Snooze: the black overlay flickers with a warning.
    /// Then the windows return and the screen tears away.
    func warn(_ kind: Warning, line: String, restore: @escaping @MainActor () -> Void, done: @escaping @MainActor () -> Void) {
        // Controls lock the moment the button is pressed.
        stage = .warning; warning = line; warningKind = kind
        withAnimation(still ? nil : .easeIn(duration: 0.3)) { cardDrop = 0 }
        switch kind {
        case .dismiss:
            darkness = 1; ghostOpacity = 0
            closeupOpacity = 1; closeupScale = still ? 1 : 0.7
            if !still { withAnimation(.spring(response: 0.18, dampingFraction: 0.4)) { closeupScale = 1.05; shake = 1 } }
        case .snooze:
            darkness = 1; flicker = 1
            withAnimation(still ? nil : .easeOut(duration: 0.3)) { ghostRest = 0; ghostOpacity = 0.9 }
        }
        run { [weak self] wait in
            guard let self else { return }
            if kind == .dismiss, !self.still {
                try await wait(380)
                withAnimation(.spring(response: 0.16, dampingFraction: 0.3)) { self.shake = 0 }
            }
            if kind == .snooze, !self.still {
                // A failing light: on/off changes at least 330 ms apart (under 3 flashes per second).
                for (time, value) in [(150, 1.0), (500, 0.0), (850, 0.92), (1200, 0.1), (1550, 1.0), (1900, 0.0), (2250, 0.85), (2600, 0.0)] {
                    try await wait(time)
                    self.darkness = value; self.flicker = value
                }
            }
            try await wait(2900)
            restore()
            withAnimation(self.still ? nil : .easeInOut(duration: 0.65)) { self.reveal = 1 }
            try await wait(3600)
            done()
        }
    }

    /// Join: everything fades out, then the windows return.
    func vanish(restore: @escaping @MainActor () -> Void, done: @escaping @MainActor () -> Void) {
        stage = .vanishing
        withAnimation(still ? nil : .easeIn(duration: 0.35)) { fade = 1 }
        run { [weak self] wait in
            guard let self else { return }
            try await wait(self.still ? 0 : 380)
            restore()
            done()
        }
    }

    func depart(duration: Double = 0.42) {
        choreography?.cancel()
        withAnimation(still ? nil : .easeInOut(duration: duration)) { reveal = 1; peek = 0 }
    }
    func cancel() { choreography?.cancel(); choreography = nil }
}

// Removing an irregular strip reveals the real workspace; no screenshot is taken.
struct PaperRevealMask: Shape {
    var progress: CGFloat
    var animatableData: CGFloat { get { progress } set { progress = newValue } }
    func path(in rect: CGRect) -> Path {
        let edge = -20 + progress * (rect.width + 40)
        var path = Path()
        path.move(to: CGPoint(x: rect.width + 36, y: -1))
        path.addLine(to: CGPoint(x: edge, y: -1))
        for i in 0...64 {
            let t = Double(i) / 64
            let tooth = CGFloat(sin(t * 39) * 5 + sin(t * 91) * 2)
            path.addLine(to: CGPoint(x: edge + tooth, y: rect.height * CGFloat(t)))
        }
        path.addLine(to: CGPoint(x: rect.width + 36, y: rect.height + 1))
        path.closeSubpath(); return path
    }
}
struct HauntCurtain: View {
    @ObservedObject var scene: HauntScene
    var body: some View {
        AppStyle.midnight.opacity(scene.darkness * (1 - scene.fade))
            .mask(PaperRevealMask(progress: scene.reveal)).ignoresSafeArea()
    }
}

struct PoltergeistScratches: View {
    @ObservedObject var scene: HauntScene
    var body: some View {
        GeometryReader { geo in
            ZStack {
                RadialGradient(colors: [.clear, .black.opacity(0.85)], center: .center,
                               startRadius: geo.size.height * 0.2, endRadius: geo.size.width * 0.65)
                    .opacity(Double(scene.knockCount) * 0.25)
                ForEach(0..<3) { beat in
                    ScratchMark(beat: beat).trim(from: 0, to: scene.scratchProgress[beat])
                        .stroke(.black.opacity(0.7), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .overlay {
                            ScratchMark(beat: beat).trim(from: 0, to: scene.scratchProgress[beat])
                                .stroke(AppStyle.ink.opacity(0.38), lineWidth: 0.7)
                        }
                }
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}
private struct ScratchMark: Shape {
    let beat: Int
    func path(in rect: CGRect) -> Path {
        let x = rect.width * (beat == 1 ? 0.90 : 0.08)
        let y = rect.height * (beat == 2 ? 0.65 : 0.16)
        var path = Path()
        for finger in 0..<4 {
            let offset = CGFloat(finger) * 11
            path.move(to: CGPoint(x: x + offset, y: y))
            path.addCurve(to: CGPoint(x: x + offset - 25, y: y + rect.height * 0.23),
                          control1: CGPoint(x: x + offset + 22, y: y + rect.height * 0.08),
                          control2: CGPoint(x: x + offset - 10, y: y + rect.height * 0.16))
        }
        return path
    }
}
/// Bundled haunting artwork (WebP, decoded natively on macOS 14+), loaded once.
@MainActor
enum HauntArt {
    /// Tests point this at the built app, whose bundle holds the artwork.
    static var bundle = Bundle.main
    private static var cache: [String: NSImage] = [:]
    static func image(_ name: String) -> NSImage? {
        if let hit = cache[name] { return hit }
        let image = bundle.url(forResource: name, withExtension: "webp").flatMap(NSImage.init(contentsOf:))
        cache[name] = image
        return image
    }
}
/// The face for the jump scare (grinning) or the Dismiss warning (screaming). Both are squares on black
/// whose hands run off the edges, so every edge fades into the dark instead of cutting off on a wide screen.
struct CloseupGhost: View {
    var screaming = false
    var body: some View {
        Group {
            if let art = HauntArt.image(screaming ? "ghost-scream" : "ghost-grin") {
                Image(nsImage: art).resizable().scaledToFit()
                    .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.16),
                                                 .init(color: .black, location: 0.84), .init(color: .clear, location: 1)],
                                         startPoint: .leading, endPoint: .trailing))
                    .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.8),
                                                 .init(color: .clear, location: 1)],
                                         startPoint: .top, endPoint: .bottom))
            }
            else { Color.clear }
        }.accessibilityHidden(true).allowsHitTesting(false)
    }
}
/// Early warning from above: the ghost hangs upside down from the top edge, hair falling with gravity.
struct HangingGhost: View {
    var body: some View {
        Group {
            if let art = HauntArt.image("ghost-hanging") { Image(nsImage: art).resizable().scaledToFit() }
            else { Color.clear }
        }.accessibilityHidden(true).allowsHitTesting(false)
    }
}
/// The dash: the ghost lunging sideways, hair and dress streaming behind. Drawn facing right.
struct DashingGhost: View {
    /// Width ÷ height of the art.
    static let aspect: CGFloat = 3
    var body: some View {
        Group {
            if let art = HauntArt.image("ghost-dash") { Image(nsImage: art).resizable().scaledToFit() }
            else { Color.clear }
        }.accessibilityHidden(true).allowsHitTesting(false)
    }
}
/// Early warning from below: the ghost's eyes and claws rise over the bottom edge of the screen.
struct CrawlingGhost: View {
    /// Where her ledge line sits in the art (fraction of its height); the claws hang below it.
    static let ledge: CGFloat = 0.86
    var body: some View {
        Group {
            if let art = HauntArt.image("ghost-crawling") { Image(nsImage: art).resizable().scaledToFit() }
            else { Color.clear }
        }.accessibilityHidden(true).allowsHitTesting(false)
    }
}
/// The full-length ghost that lingers at the meeting alert.
struct StandingGhost: View {
    var body: some View {
        Group {
            if let art = HauntArt.image("ghost-standing") { Image(nsImage: art).resizable().scaledToFit() }
            else { Color.clear }
        }.accessibilityHidden(true).allowsHitTesting(false)
    }
}
