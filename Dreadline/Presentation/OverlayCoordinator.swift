import SwiftUI
import AppKit

/// How the user is leaving a haunting; each gets its own exit before the action is applied.
enum HauntFarewell { case dismiss, snooze, join }

@MainActor
protocol PresentationSink {
    func present(_ presentation: Presentation?, demo: Bool)
    func close()
    func release()
    /// Plays an exit for the visible haunting, then runs `then` (which applies the user's action).
    func farewell(_ kind: HauntFarewell, then: @escaping @MainActor () -> Void)
}
extension PresentationSink {
    func release() { close() }
    func farewell(_ kind: HauntFarewell, then: @escaping @MainActor () -> Void) { then() }
}
final class ReminderPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    var escapeHandler: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { escapeHandler?() }
}
@MainActor
final class OverlayCoordinator: PresentationSink {
    private weak var model: AppModel?
    private var windows: [NSWindow] = []
    private var current: Presentation?
    private var previousApp: NSRunningApplication?
    private var sound: NSSound?
    private var screenObserver: NSObjectProtocol?
    private var demo = false
    private var watchdog: Timer?
    private var scene = HauntScene()
    private var entranceCount = 0
    private var releaseTask: Task<Void, Never>?
    private var generation = 0
    /// Set while a Dismiss/Join exit plays; the surface ignores scheduler updates until it finishes.
    private var exitCompletion: (@MainActor () -> Void)?
    init(model: AppModel) {
        self.model = model
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.exitCompletion == nil, let presentation = self.current, let model = self.model else { return }
                // A display change never snoozes. Side panels move to the new layout; a fullscreen
                // effect ends (prelude) or settles into its side reminder instead of replaying.
                if self.demo { model.endDemo() }
                else if presentation.intensity != .fullscreen && presentation.phase != .prelude { self.repositionPanel() }
                else if presentation.phase != .reminder { model.stopPresentation(presentation) }
                else { model.finishArrival(presentation) }
            }
        }
    }
    func present(_ presentation: Presentation?, demo: Bool = false) {
        guard exitCompletion == nil else { return }
        guard let presentation, let model else { release(); return }
        if releaseTask != nil { close(restoreFocus: false) }
        if !model.preferences.sound { sound?.stop(); sound = nil }
        if current == presentation && self.demo == demo { return }
        if let current, current.intensity == presentation.intensity, current.phase == presentation.phase, self.demo == demo,
           let panel = windows.compactMap({ $0 as? ReminderPanel }).first,
           let host = panel.contentView as? NSHostingView<OverlayView> {
            self.current = presentation
            host.rootView = OverlayView(model: model, presentation: presentation, demo: demo, redact: model.preferences.privateTitles || !demo, scene: scene)
            panel.escapeHandler = escapeHandler(presentation, demo: demo)
            return
        }
        let wasVisible = current != nil
        let prior = previousApp
        close(restoreFocus: false)
        current = presentation; self.demo = demo
        let prefs = model.preferences
        scene = HauntScene(entrance: HauntScene.Entrance.allCases[entranceCount % 2], fromLeft: entranceCount % 2 == 0,
                           still: prefs.reducedMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        entranceCount += 1
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? NSScreen.main
        guard let screen else { return }
        let prelude = presentation.phase == .prelude
        let dash = presentation.phase == .dash
        let fullscreen = presentation.intensity == .fullscreen || prelude || dash
        if fullscreen && !dash && (prefs.dimAllDisplays || prefs.poltergeistEnabled == true || demo) {
            for other in NSScreen.screens where other != screen {
                let dim = NSWindow(contentRect: other.frame, styleMask: .borderless, backing: .buffered, defer: false)
                dim.backgroundColor = .clear
                dim.isOpaque = false; dim.ignoresMouseEvents = false
                let curtain = NSHostingView(rootView: HauntCurtain(scene: scene))
                curtain.sizingOptions = []; curtain.frame = NSRect(origin: .zero, size: other.frame.size)
                dim.contentView = curtain; dim.setFrame(other.frame, display: false)
                configure(dim); dim.orderFrontRegardless(); windows.append(dim)
            }
        }
        let rect: NSRect
        if fullscreen { rect = screen.frame }
        else {
            let visible = screen.visibleFrame
            let width: CGFloat = presentation.intensity == .gentle ? 420 : 480
            let height: CGFloat = presentation.intensity == .gentle ? 400 : 440
            rect = NSRect(x: visible.maxX - width - 20, y: visible.maxY - height - 20, width: width, height: height)
        }
        let panel = ReminderPanel(contentRect: rect, styleMask: demo ? [.borderless] : [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Dreadline reminder"
        panel.setAccessibilityLabel("Dreadline reminder")
        configure(panel)
        panel.isFloatingPanel = true; panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear; panel.isOpaque = false
        panel.hasShadow = !fullscreen
        // Public session-active signals cannot reliably detect a locked screen. Real overlays
        // remain nonactivating and redact details. Full detail is available in the app window.
        let redact = prefs.privateTitles || !demo
        let host = NSHostingView(rootView: OverlayView(model: model, presentation: presentation, demo: demo, redact: redact, scene: scene))
        // GeometryReader has no useful intrinsic window size. Keep the panel's explicit
        // screen rect authoritative instead of letting NSHostingView shrink the window.
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: rect.size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        panel.setFrame(rect, display: true)
        panel.escapeHandler = escapeHandler(presentation, demo: demo)
        // The dash passes over your work: clicks go through and focus never moves.
        panel.ignoresMouseEvents = dash
        panel.orderFrontRegardless(); windows.append(panel)
        if dash {
            let token = generation
            scene.dash { [weak self] in
                guard let self, self.generation == token, let model = self.model, let latest = self.current else { return }
                if self.demo { model.demoStageFinished() } else { model.stopPresentation(latest) }
            }
        } else if fullscreen {
            let token = generation
            // Windows leave first; the ghost appears once they are gone.
            scene.start(prelude: prelude,
                        minimize: { [weak self, weak model] in
                            guard let self, self.generation == token, let model else { return }
                            model.windowMinimizer.minimize()
                            model.recordWindowControl()
                        },
                        knock: { [weak self] beat in
                            // One clip carries both hits of the early warning.
                            guard beat == 0, let self, self.generation == token, let model = self.model, self.soundAllowed else { return }
                            self.playSound(HauntSounds.earlyWarning, volume: model.preferences.volume)
                        },
                        arrival: { [weak self] in
                            guard let self, self.generation == token else { return }
                            self.playArrivalIfEnabled()
                        },
                        restore: { [weak self, weak model] in
                            guard let self, self.generation == token else { return }
                            model?.restoreWorkspace()
                        },
                        finished: { [weak self, weak model] in
                            // A prelude ends itself once its windows are back.
                            guard let self, self.generation == token, prelude, let model, let latest = self.current else { return }
                            if self.demo { model.demoStageFinished() } else { model.stopPresentation(latest) }
                        })
        } else { scene.stage = .manifest; scene.cardDrop = 1 }
        model.overlayStatus = "\(dash ? "Dash" : prelude ? "Prelude" : "Meeting") · \(Int(panel.frame.width)) × \(Int(panel.frame.height)) · \(panel.isVisible ? "visible" : "hidden") · \(windows.count) display surface(s)"
        if dash {
            let token = generation
            watchdog = Timer.scheduledTimer(withTimeInterval: Haunt.dashSeconds + 1, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.generation == token, let latest = self.current, let model = self.model else { return }
                    if self.demo { model.demoStageFinished() } else { model.stopPresentation(latest) }
                }
            }
        } else if fullscreen {
            previousApp = prior ?? NSWorkspace.shared.frontmostApplication
            if demo { NSApp.activate(ignoringOtherApps: true) }
            panel.makeKeyAndOrderFront(nil)
            // Fallback only: the prelude finishes itself, and the arrival settles into a side reminder.
            let limit: TimeInterval = prelude ? Haunt.preludeSeconds + 1 : Haunt.arrivalSeconds
            let token = generation
            watchdog = Timer.scheduledTimer(withTimeInterval: limit, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.generation == token, self.exitCompletion == nil, let latest = self.current, let model = self.model else { return }
                    if self.demo { latest.phase == .prelude ? model.demoStageFinished() : model.endDemo(animated: true) }
                    else if latest.phase == .prelude { model.stopPresentation(latest) }
                    else if model.preferences.poltergeistEnabled == true { model.finishArrival(latest) }
                    else { model.stopPresentation(latest) }
                }
            }
        }
        if !fullscreen && !wasVisible { playArrivalIfEnabled() }
    }
    private func escapeHandler(_ presentation: Presentation, demo: Bool) -> () -> Void {
        { [weak self, weak model] in
            guard self?.exitCompletion == nil, let model else { return }
            switch presentation.phase {
            case .dash: return
            case .prelude: if demo { model.endDemo() } else { model.stopPresentation(presentation) }
            // Escape on a real meeting alert is Snooze, with its warning; in a preview it just closes.
            case .reminder: if demo { model.endDemo() } else { model.snoozeFromOverlay(presentation.items) }
            }
        }
    }
    func farewell(_ kind: HauntFarewell, then: @escaping @MainActor () -> Void) {
        guard current != nil, exitCompletion == nil, releaseTask == nil else { then(); return }
        exitCompletion = then
        watchdog?.invalidate(); watchdog = nil
        let token = generation
        let restore: @MainActor () -> Void = { [weak self, weak model] in
            guard let self, self.generation == token else { return }
            model?.restoreWorkspace()
        }
        let finish: @MainActor () -> Void = { [weak self] in
            guard let self, self.generation == token else { return }
            let pending = self.exitCompletion; self.exitCompletion = nil
            self.close(); pending?()
        }
        switch kind {
        case .dismiss:
            if soundAllowed, let model { playSound(HauntSounds.dismiss, volume: model.preferences.volume) }
            else { sound?.stop(); sound = nil }
            scene.warn(.dismiss, line: HauntScene.dismissLines.randomElement() ?? "You can't dismiss me.", restore: restore, done: finish)
        case .snooze:
            if soundAllowed, let model { playSound(HauntSounds.snooze, volume: model.preferences.volume) }
            else { sound?.stop(); sound = nil }
            scene.warn(.snooze, line: HauntScene.snoozeLines.randomElement() ?? "Five more minutes. Then I come back.", restore: restore, done: finish)
        case .join:
            sound?.stop(); sound = nil
            scene.vanish(restore: restore, done: finish)
        }
    }
    private func repositionPanel() {
        guard let panel = windows.compactMap({ $0 as? ReminderPanel }).first,
              let screen = panel.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame, size = panel.frame.size
        panel.setFrame(NSRect(x: visible.maxX - size.width - 20, y: visible.maxY - size.height - 20, width: size.width, height: size.height), display: true)
    }
    private var soundAllowed: Bool {
        guard let model, let current else { return false }
        return model.preferences.sound && !model.preferences.quiet.contains(Date()) && current.items.contains { item in
            item.kind != .local || model.db.locals.first(where: { $0.id == item.seriesID })?.sound == true
        }
    }
    /// The fullscreen meeting alert plays the scare level's sound, in tests too;
    /// a side reminder gets the quieter early-warning clip.
    private func playArrivalIfEnabled() {
        guard soundAllowed, let model, let current else { return }
        let effect = current.intensity == .fullscreen
            ? HauntSounds.scare(model.preferences.scareLevel ?? .medium)
            : HauntSounds.sideReminder
        playSound(effect, volume: model.preferences.volume)
    }
    private func playSound(_ effect: HauntSound, volume: Double) {
        sound?.stop()
        let clip = effect.url.flatMap { NSSound(contentsOf: $0, byReference: true) }
        clip?.volume = Float(volume); clip?.loops = false; clip?.play(); sound = clip
    }
    func release() {
        guard current != nil, releaseTask == nil, exitCompletion == nil else { return }
        watchdog?.invalidate(); watchdog = nil
        sound?.stop(); sound = nil
        model?.restoreWorkspace()
        let token = generation
        scene.depart()
        if scene.still { close(); return }
        releaseTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(450))
                try Task.checkCancellation()
                guard let self, generation == token else { return }
                close()
            } catch { }
        }
    }

    private func configure(_ window: NSWindow) {
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isReleasedWhenClosed = false
    }
    func close() { close(restoreFocus: true) }
    private func close(restoreFocus: Bool) {
        // An interrupted exit still applies the user's choice.
        let pending = exitCompletion; exitCompletion = nil
        generation += 1
        releaseTask?.cancel(); releaseTask = nil
        scene.cancel()
        watchdog?.invalidate(); watchdog = nil
        sound?.stop(); sound = nil
        for window in windows { window.orderOut(nil); window.close() }
        windows.removeAll(); current = nil
        model?.overlayStatus = "Idle"
        model?.restoreWorkspace()
        if restoreFocus, let previousApp, !previousApp.isTerminated, NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            previousApp.activate(options: [])
        }
        if restoreFocus { previousApp = nil }
        pending?()
    }
}
struct OverlayView: View {
    @ObservedObject var model: AppModel
    let presentation: Presentation
    let demo: Bool
    let redact: Bool
    @ObservedObject var scene: HauntScene
    private var prelude: Bool { presentation.phase == .prelude }
    private var dash: Bool { presentation.phase == .dash }
    private var fullscreen: Bool { presentation.intensity == .fullscreen || prelude || dash }
    private var meetingsOnly: Bool { presentation.items.allSatisfy { $0.kind == .calendar } }
    var body: some View {
        Group {
            if fullscreen {
                GeometryReader { geo in
                    ZStack {
                        AppStyle.midnight.opacity(scene.darkness).ignoresSafeArea()
                        PoltergeistScratches(scene: scene).ignoresSafeArea()
                        if dash { dashingGhost(geo.size) }
                        else if prelude {
                            peekingGhost(geo.size)
                            // The caption sits opposite the ghost so it never covers her face.
                            preludeCaption
                                .frame(maxHeight: .infinity, alignment: scene.entrance == .below ? .top : .bottom)
                                .padding(scene.entrance == .below ? .top : .bottom, geo.size.height * 0.1)
                        }
                        else { arrival(geo.size) }
                    }
                    .opacity(1 - scene.fade)
                    .scaleEffect(1 - scene.fade * 0.04)
                    .mask(PaperRevealMask(progress: scene.reveal))
                }.preferredColorScheme(.dark)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    HStack { Text("DREADLINE").font(AppStyle.display(22)); Spacer(); WatcherMark(size: 30) }
                    if scene.stage == .warning, let line = scene.warning {
                        Text(line).font(AppStyle.display(24)).foregroundStyle(scene.warningKind == .dismiss ? AppStyle.blood : AppStyle.ink)
                            .frame(maxWidth: .infinity, maxHeight: 245, alignment: .leading)
                    } else {
                        reminders(limit: 245)
                    }
                    footer
                }.padding(24).haunted().overlay(CrookedBorder().stroke(AppStyle.border, lineWidth: 1))
                // The side panel flickers itself for the snooze warning.
                .opacity((1 - scene.fade) * (scene.warningKind == .snooze ? 0.3 + 0.7 * scene.flicker : 1))
                .mask(PaperRevealMask(progress: scene.reveal))
            }
        }
        .allowsHitTesting(scene.interactive)
    }

    // MARK: Dash

    /// Ten seconds before the early warning, the ghost tears across the screen once.
    private func dashingGhost(_ size: CGSize) -> some View {
        let height = size.height * 0.3, width = height * DashingGhost.aspect
        let facing: CGFloat = scene.fromLeft ? 1 : -1
        return ZStack {
            // One faint echo behind her; the art already streams its own trail.
            DashingGhost().frame(width: width, height: height)
                .scaleEffect(x: facing, y: 1)
                .opacity(0.22).blur(radius: 7)
                .modifier(DashMotion(progress: scene.dashProgress, size: size, extent: width, fromLeft: scene.fromLeft, lag: width * 0.18))
            DashingGhost().frame(width: width, height: height)
                .scaleEffect(x: facing, y: 1)
                .modifier(DashMotion(progress: scene.dashProgress, size: size, extent: width, fromLeft: scene.fromLeft, lag: 0))
        }
        .frame(width: size.width, height: size.height)
    }

    // MARK: Early warning

    /// The ghost hangs down from the top edge upside down, or rises from the bottom, then slips away.
    private func peekingGhost(_ size: CGSize) -> some View {
        let height = size.height * 0.82, width = height * 2 / 3
        let shown = scene.peek
        return Group {
            switch scene.entrance {
            case .above:
                // Lowers in from the top edge until her face and clawed hands are in view.
                HangingGhost().frame(width: width, height: height)
                    .offset(x: -size.width * 0.18, y: -(size.height / 2 + height / 2) + shown * height * 0.74)
            case .below:
                // Rises until her ledge line sits on the screen's bottom edge, claws curled over it.
                let wide = min(size.width * 0.62, size.height * 1.05 * 3 / 2), tall = wide * 2 / 3
                CrawlingGhost().frame(width: wide, height: tall)
                    .offset(y: size.height / 2 + tall / 2 - shown * tall * CrawlingGhost.ledge)
            }
        }
        .opacity(Double(min(1, shown * 1.4)))
        .shadow(color: AppStyle.poison.opacity(0.18), radius: 30)
    }
    private var preludeCaption: some View {
        VStack(spacing: 10) {
            if let due = presentation.items.first?.due {
                HStack(spacing: 6) { Text(meetingsOnly ? "Meeting in" : "Due in"); Text(due, style: .relative) }
                    .font(AppStyle.display(30)).foregroundStyle(AppStyle.ink)
            }
            Text("ESC TO LEAVE").font(AppStyle.signal(9)).foregroundStyle(AppStyle.ink.opacity(0.6))
        }
        .shadow(color: .black.opacity(0.8), radius: 12)
        .opacity(Double(min(1, scene.peek)))
    }

    // MARK: Meeting alert

    private func arrival(_ size: CGSize) -> some View {
        let snoozing = scene.warningKind == .snooze
        return ZStack {
            // 1. The scare: the face, suddenly there (and back again for the Dismiss warning).
            CloseupGhost(screaming: scene.warningKind == .dismiss)
                .frame(width: min(size.width, size.height) * 1.05, height: min(size.width, size.height) * 1.05)
                .scaleEffect(scene.closeupScale).opacity(scene.closeupOpacity)
                .offset(x: scene.shake * 22, y: scene.shake * -14)
            // 2. The whole ghost lingers, then drifts back to hover behind the meeting card.
            StandingGhost().frame(height: size.height * 0.92)
                .scaleEffect(1 - scene.ghostRest * 0.22)
                .offset(x: scene.ghostRest * size.width * 0.27,
                        y: scene.ghostRest * -size.height * 0.03 + (scene.bob ? -10 : 10))
                .opacity(scene.ghostOpacity * (snoozing ? scene.flicker : 1))
                .shadow(color: AppStyle.poison.opacity(0.15), radius: 40)
            // 3. The meeting slides down from the top.
            detailsCard(size)
                .offset(y: -(1 - scene.cardDrop) * size.height * 0.85)
                .opacity(scene.cardDrop > 0.01 ? 1 : 0)
            if scene.stage == .warning, let line = scene.warning, let kind = scene.warningKind {
                warningView(line, kind: kind).frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, size.height * 0.1)
            }
        }.frame(width: size.width, height: size.height)
    }
    private func detailsCard(_ size: CGSize) -> some View {
        VStack(alignment: .center, spacing: size.height < 800 ? 14 : 20) {
            Text("DREADLINE").font(AppStyle.signal(12)).tracking(4).foregroundStyle(AppStyle.accent)
            Text("You’re expected.").font(AppStyle.display(min(56, size.height * 0.065))).foregroundStyle(AppStyle.ink)
            reminders(limit: size.height * 0.36)
            footer
        }
        .padding(size.height < 800 ? 26 : 36)
        .frame(width: min(640, size.width * 0.62))
        .background(AppStyle.card.opacity(0.94))
        .overlay(CrookedBorder().stroke(AppStyle.border, lineWidth: 1))
        .overlay(alignment: .top) {
            HStack { thread; Spacer(); thread }.padding(.horizontal, 60)
                .frame(height: size.height).offset(y: -size.height)
        }
        .shadow(color: .black.opacity(0.6), radius: 40, y: 18)
    }
    private var thread: some View {
        Rectangle().fill(AppStyle.ink.opacity(0.35)).frame(width: 1.2).accessibilityHidden(true)
    }
    private func warningView(_ line: String, kind: HauntScene.Warning) -> some View {
        let minutes = presentation.items.first.map { Int(model.snoozeInterval($0) / 60) } ?? 5
        let subject = meetingsOnly ? "This meeting" : "This reminder"
        return VStack(spacing: 12) {
            Text(line).font(AppStyle.display(kind == .dismiss ? 52 : 44)).multilineTextAlignment(.center)
                .foregroundStyle(kind == .dismiss ? AppStyle.blood : AppStyle.ink)
            Text(kind == .dismiss ? "\(subject) is silenced… for now." : "\(subject) returns in \(minutes) minutes.")
                .font(AppStyle.signal(13)).foregroundStyle(AppStyle.accent)
        }
        .padding(.horizontal, 60).padding(.vertical, 28)
        .background(Ellipse().fill(.black.opacity(0.78)).blur(radius: 36))
        .shadow(color: .black, radius: 18)
    }

    // MARK: Shared

    /// Fits its content; a longer queue scrolls within `limit`.
    @ViewBuilder private func reminders(limit: CGFloat) -> some View {
        if presentation.items.count <= 2 { reminderList }
        else { ScrollView { reminderList }.frame(height: limit) }
    }
    private var reminderList: some View {
            VStack(alignment: .leading, spacing: 22) {
                ForEach(presentation.items) { item in
                    VStack(alignment: .leading, spacing: 14) {
                        Text(redact ? (item.kind == .calendar ? "Your next meeting" : "Your reminder") : item.title).font(AppStyle.display(fullscreen ? 28 : 22))
                        if let due = item.due { Text(due, format: .dateTime.hour().minute()).font(AppStyle.signal(16)) }
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 10) { actions(item) }
                            VStack(alignment: .leading, spacing: 10) { actions(item) }
                        }
                    }.padding(fullscreen ? 20 : 0)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(fullscreen ? AppStyle.canvas.opacity(0.6) : .clear)
                        .overlay { if fullscreen { CrookedBorder().stroke(AppStyle.border, lineWidth: 1) } }
                        .foregroundStyle(AppStyle.ink).accessibilityElement(children: .contain)
                }
            }.foregroundStyle(AppStyle.ink)
    }
    @ViewBuilder private func actions(_ item: Occurrence) -> some View {
        JoinButton(model: model, item: item, demo: demo, fromOverlay: true)
        if item.links.isEmpty {
            Button(item.kind == .local ? "Done" : "View meeting") {
                if demo { model.endDemo() }
                else if item.kind == .local { model.act(.done, item) }
                else { model.showMain() }
            }.buttonStyle(HauntedPrimaryStyle())
        }
        Button(model.snoozeLabel(item)) { model.snoozeFromOverlay([item]) }.buttonStyle(HauntedSecondaryStyle())
        Button("Dismiss") { model.dismissFromOverlay(item) }.buttonStyle(.borderless)
            .foregroundStyle(AppStyle.ink)
    }
    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            HStack {
                Button(demo ? "Close preview" : "Pause for 1 hour") {
                    if demo { model.endDemo() } else { model.pause(until: Date().addingTimeInterval(3600)) }
                }.buttonStyle(.borderless)
                Spacer()
                Text(demo ? "ESC TO LEAVE" : "ESC TO SNOOZE").font(AppStyle.signal(9))
            }
            Text(demo ? "Preview only. No calendar changes." : "The workspace returns automatically after 30 seconds.")
                .font(.caption)
            if fullscreen { Text(model.windowControlStatus).font(.caption) }
            if let error = model.error { Text(error).font(.caption) }
        }.foregroundStyle(fullscreen ? AppStyle.ink.opacity(0.8) : AppStyle.muted)
    }
}

/// Moves the dashing ghost along a swooping arc, evaluated every frame. Starts and ends fully off screen
/// (its echo included), so the ghost needs no visibility gate.
private struct DashMotion: ViewModifier, Animatable {
    var progress: CGFloat
    let size: CGSize
    /// Horizontal size of the moving art.
    let extent: CGFloat
    let fromLeft: Bool
    let lag: CGFloat
    nonisolated var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }
    func body(content: Content) -> some View {
        let edge = size.width / 2 + extent / 2 + 20
        let travel = edge * 2 + extent * 0.18
        let direction: CGFloat = fromLeft ? 1 : -1
        let x = direction * (-edge + progress * travel - lag)
        let y = -size.height * 0.08 - CGFloat(sin(Double(progress) * .pi)) * size.height * 0.07
        return content.offset(x: x, y: y)
    }
}
