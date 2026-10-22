import SwiftUI
import AppKit

@MainActor
protocol PresentationSink { func present(_ presentation: Presentation?, demo: Bool); func close() }
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
    init(model: AppModel) {
        self.model = model
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, let presentation = self.current else { return }
                let demo = self.demo; self.close(); self.present(presentation, demo: demo)
            }
        }
    }
    func present(_ presentation: Presentation?, demo: Bool = false) {
        guard let presentation, let model else { close(); return }
        if current == presentation && self.demo == demo { return }
        if let current, current.intensity == presentation.intensity, self.demo == demo,
           let panel = windows.compactMap({ $0 as? ReminderPanel }).first,
           let host = panel.contentView as? NSHostingView<OverlayView> {
            sound?.stop(); sound = nil
            self.current = presentation
            host.rootView = OverlayView(model: model, presentation: presentation, demo: demo, redact: model.preferences.privateTitles || !demo)
            panel.escapeHandler = { [weak model] in model?.escapeAll(presentation.items) }
            return
        }
        let wasVisible = current != nil
        let prior = previousApp
        close(restoreFocus: false)
        current = presentation; self.demo = demo
        let prefs = model.preferences
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? NSScreen.main
        guard let screen else { return }
        let fullscreen = presentation.intensity == .fullscreen
        if fullscreen && prefs.dimAllDisplays {
            for other in NSScreen.screens where other != screen {
                let dim = NSWindow(contentRect: other.frame, styleMask: .borderless, backing: .buffered, defer: false)
                dim.backgroundColor = NSColor.black.withAlphaComponent(0.45)
                dim.isOpaque = false; dim.ignoresMouseEvents = true
                configure(dim); dim.orderFrontRegardless(); windows.append(dim)
            }
        }
        let rect: NSRect
        if fullscreen { rect = screen.frame }
        else {
            let visible = screen.visibleFrame
            let width: CGFloat = presentation.intensity == .gentle ? 360 : 430
            let height: CGFloat = presentation.intensity == .gentle ? 280 : 370
            rect = NSRect(x: visible.maxX - width - 20, y: visible.maxY - height - 20, width: width, height: height)
        }
        let panel = ReminderPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Dreadline reminder"
        panel.setAccessibilityLabel("Dreadline reminder")
        configure(panel)
        panel.isFloatingPanel = true; panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear; panel.isOpaque = false
        panel.hasShadow = !fullscreen
        // Public session-active signals cannot reliably detect a locked screen. Real overlays
        // remain nonactivating and redact details. Full detail is available in the app window.
        let redact = prefs.privateTitles || !demo
        panel.contentView = NSHostingView(rootView: OverlayView(model: model, presentation: presentation, demo: demo, redact: redact))
        panel.escapeHandler = { [weak model] in model?.escapeAll(presentation.items) }
        panel.orderFrontRegardless(); windows.append(panel)
        if demo && fullscreen {
            previousApp = prior ?? NSWorkspace.shared.frontmostApplication
            NSApp.activate(ignoringOtherApps: true); panel.makeKeyAndOrderFront(nil)
        }
        if !wasVisible && prefs.sound && presentation.items.contains(where: { item in item.kind != .local || model.db.locals.first(where: { $0.id == item.seriesID })?.sound == true }) && !demo && !prefs.quiet.contains(Date()) {
            let s = NSSound(named: "Glass"); s?.volume = Float(prefs.volume); s?.loops = false; s?.play(); sound = s
        }
    }
    private func configure(_ window: NSWindow) {
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isReleasedWhenClosed = false
    }
    func close() { close(restoreFocus: true) }
    private func close(restoreFocus: Bool) {
        sound?.stop(); sound = nil
        for window in windows { window.orderOut(nil); window.close() }
        windows.removeAll(); current = nil
        if restoreFocus, let previousApp, !previousApp.isTerminated, NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            previousApp.activate(options: [])
        }
        if restoreFocus { previousApp = nil }
    }
}
struct OverlayView: View {
    @ObservedObject var model: AppModel
    let presentation: Presentation
    let demo: Bool
    let redact: Bool
    @State private var armed = false
    var body: some View {
        ZStack {
            if presentation.intensity == .fullscreen { Color.black.opacity(0.6).ignoresSafeArea() }
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label(demo ? "Sandbox preview" : (presentation.catchUp ? "Catch up" : "Commitment reminder"), systemImage: "bell.badge")
                    Spacer()
                    Text("\(presentation.items.count) pending").foregroundStyle(.secondary)
                }.font(.headline)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(presentation.items) { item in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(redact ? "A commitment needs your attention" : item.title).font(.title3).bold().lineLimit(4)
                                if let due = item.due { Text(due, style: .time).foregroundStyle(.secondary) }
                                if !redact { Text(item.sourceName).font(.caption) }
                                HStack {
                                    Button(item.kind == .local ? "Done" : "Acknowledge") { model.act(item.kind == .local ? .done : .acknowledge, item) }
                                    Button("Snooze 5m") { model.escape(item) }
                                    Button("Skip") { model.act(.skip, item) }
                                }.disabled(!armed)
                            }.accessibilityElement(children: .contain)
                        }
                    }
                }.frame(maxHeight: presentation.intensity == .fullscreen ? 500 : (presentation.intensity == .gentle ? 110 : 220))
                HStack {
                    Button("Pause all") { if demo { model.endDemo() } else { model.pause(until: nil) } }
                    Spacer()
                    Button(demo ? "End preview" : "Stop for now (Esc)") { model.escapeAll(presentation.items) }
                }
                Text(demo ? "Demo is isolated. No source data or delivery state is changed." : "Escape snoozes this queue for 5 minutes, capped at event expiry. Open Dreadline for details.")
                    .font(.caption).foregroundStyle(.secondary)
                if let error = model.error { Text(error).font(.caption).foregroundStyle(.red) }
            }
            .padding(24).frame(maxWidth: presentation.intensity == .fullscreen ? 620 : (presentation.intensity == .gentle ? 360 : 430))
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            .padding(presentation.intensity == .fullscreen ? 48 : 0)
        }
        .task { try? await Task.sleep(for: .milliseconds(600)); armed = true }
        .onExitCommand { model.escapeAll(presentation.items) }
    }
}
