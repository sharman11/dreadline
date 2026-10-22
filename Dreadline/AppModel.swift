import SwiftUI
import AppKit
import EventKit
import ServiceManagement

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var db = Database()
    @Published var sources: [SourceSnapshot] = []
    @Published var sourceStatus: [SourceKind: String] = [.calendar: "Not connected", .reminders: "Not connected"]
    @Published var lastRefresh: [SourceKind: Date] = [:]
    @Published var error: String?
    @Published var storageFailed = false
    @Published var refreshing = false
    @Published var requestedSection: String?
    @Published var editor: LocalReminder?
    @Published var showEditor = false
    @Published var notificationStatus = "Not requested"
    private(set) var quitting = false
    @Published var demoActive = false
    @Published var nextAction: Date?
    @Published var loginStatus = "Not registered"
    private var store: (any StateStore)?
    private var scheduler = Scheduler()
    private let adapter: any SourceAdapter
    private let notifications: any NotificationSink
    private var injectedPresenter: (any PresentationSink)?
    private var presenter: any PresentationSink { injectedPresenter ?? overlay }
    lazy var overlay = OverlayCoordinator(model: self)
    private let driver: any DeadlineDriver
    private var recovery: Timer?
    private var refreshTask: Task<Void, Never>?
    private var fallbackTask: Task<Void, Never>?
    private var generation = 0
    private var gates = DeliveryGates()
    private var wasQuiet = false
    private var observers: [NSObjectProtocol] = []
    private var demoTimer: Timer?
    private var demoIDs = Set<UUID>()
    let databaseURL: URL
    init(store suppliedStore: (any StateStore)? = nil, source: (any SourceAdapter)? = nil, notificationSink: (any NotificationSink)? = nil, presentationSink: (any PresentationSink)? = nil, startServices: Bool = true, deadlineDriver: (any DeadlineDriver)? = nil, clock: any Clock = SystemClock()) {
        adapter = source ?? EventKitAdapter()
        notifications = notificationSink ?? NotificationAdapter()
        injectedPresenter = presentationSink
        scheduler = Scheduler(clock: clock)
        driver = deadlineDriver ?? TimerDeadlineDriver()
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Dreadline", isDirectory: true)
        databaseURL = folder.appendingPathComponent("state.sqlite")
        if startServices, let duplicate = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "xyz.dreadline.app").first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            duplicate.activate(options: []); NSApp.terminate(nil); return
        }
        do { let storage: any StateStore = try suppliedStore ?? SQLiteStore(url: databaseURL); db = try storage.load(); store = storage }
        catch { storageFailed = true; self.error = error.localizedDescription }
        guard startServices else { return }
        if let native = notifications as? NotificationAdapter { native.onError = { [weak self] in self?.error = $0 } }
        notifications.onAction = { [weak self] id, action in
            guard let self else { return }
            Task { @MainActor in
                await self.refresh(catchUp: false)
                guard let uuid = UUID(uuidString: id), let item = self.db.occurrences.first(where: { $0.id == uuid }), !item.state.terminal,
                      item.kind == .local || self.gates.validated.contains(item.kind) else { return }
                if action == "ACK" { self.act(.acknowledge, item) }
                else if action == "SNOOZE" { self.act(.snooze(Date().addingTimeInterval(300)), item) }
                else { self.showMain(); self.tick(catchUp: true) }
            }
        }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .EKEventStoreChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.scheduleRefresh() }
        })
        observers.append(center.addObserver(forName: NSNotification.Name.NSSystemClockDidChange, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.scheduleRefresh() } })
        observers.append(center.addObserver(forName: NSNotification.Name.NSSystemTimeZoneDidChange, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.timeZoneChanged() } })
        observers.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.scheduleRefresh() } })
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.gates.activeSession = false; self?.gates.validated = [.local]; self?.presenter.close(); self?.notifications.cancel() }
            })
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.gates.activeSession = true; await self?.refresh(catchUp: true) }
            })
        }
        recovery = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in Task { @MainActor in await self?.refresh(catchUp: false) } }
        updateLoginStatus()
        Task { notificationStatus = await notifications.authorization(); await refresh(catchUp: true) }
    }
    var preferences: Preferences { db.preferences }
    var unresolved: [Occurrence] { db.occurrences.filter { !$0.state.terminal }.sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) } }
    var pending: [Occurrence] { unresolved.filter { $0.state != .scheduled || ($0.due ?? .distantFuture) <= Date() } }
    var upcoming: [Occurrence] { unresolved.filter { !pending.map(\.id).contains($0.id) } }
    var history: [Occurrence] { db.occurrences.filter { $0.state.terminal && ($0.resolvedAt ?? $0.updated) >= Date().addingTimeInterval(-Double(preferences.retentionDays) * 86400) }.sorted { ($0.resolvedAt ?? $0.updated) > ($1.resolvedAt ?? $1.updated) } }
    var menuTitle: String {
        if db.paused { return "Paused" }
        if !preferences.alertsEnabled { return "Dreadline · Alerts off" }
        guard let next = unresolved.first(where: { $0.due != nil && gates.validated.contains($0.kind) }) else { return "Dreadline" }
        let title = preferences.privateTitles ? "Reminder" : String(next.title.prefix(22))
        let minutes = Int((next.due ?? Date()).timeIntervalSinceNow / 60)
        return "\(title) · \(minutes >= 0 ? "\(minutes)m" : "due")"
    }
    @discardableResult
    func transaction(_ change: (inout Database) throws -> Void) -> Bool {
        guard let store else { error = "Storage unavailable. Use recovery before making changes."; return false }
        do {
            var next = db
            try change(&next)
            try store.save(next)
            db = next; return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func tick(catchUp: Bool = false) {
        guard !storageFailed else { presenter.close(); return }
        var engine = scheduler
        var next = db
        next.prunePrivateHistory(now: scheduler.clock.now)
        let resumedPause = db.paused && db.pauseUntil.map { $0 <= scheduler.clock.now } == true
        let quietNow = next.preferences.quiet.contains(scheduler.clock.now)
        let quietEnded = wasQuiet && !quietNow
        wasQuiet = quietNow
        let presentation = engine.evaluate(&next, gates: gates, catchUp: catchUp || resumedPause || quietEnded)
        do {
            if next != db { try store?.save(next); db = next }
            scheduler = engine
            if !demoActive { presenter.present(presentation, demo: false) }
        } catch { self.error = error.localizedDescription; presenter.close() }
        armTimer()
        reconcileNotifications()
    }
    private func armTimer() {
        nextAction = scheduler.nextDeadline(db)
        driver.schedule(at: nextAction) { [weak self] in self?.tick() }
    }
    private func reconcileNotifications() {
        fallbackTask?.cancel()
        var safe = db
        safe.occurrences.removeAll { !gates.validated.contains($0.kind) }
        fallbackTask = Task { await notifications.reconcile(safe, now: Date()) }
    }
    func updatePreferences(_ value: Preferences) {
        guard value.timing.valid, value.grace > 0, value.taskWindow > 0 else { error = "Lead times must be ordered gentle ≥ prominent ≥ fullscreen ≥ 0."; return }
        if transaction({ $0.preferences = value }) { tick(); scheduleRefresh() }
    }
    func pause(until: Date?) {
        guard until == nil || until! > Date() else { error = "Pause must end in the future."; return }
        if transaction({ $0.paused = true; $0.pauseUntil = until; $0.log("delivery.paused", now: Date()) }) {
            endDemo(); presenter.close(); notifications.cancel(); tick()
        }
    }
    func resume() {
        if transaction({ $0.paused = false; $0.pauseUntil = nil }) { Task { await refresh(catchUp: true) } }
    }
    func act(_ command: Command, _ item: Occurrence) {
        if demoIDs.contains(item.id) { endDemo(); return }
        if case .done = command, item.kind == .reminders {
            do { try adapter.complete(item) }
            catch { self.error = error.localizedDescription; return }
        }
        var engine = scheduler
        if transaction({ try engine.apply(command, id: item.id, to: &$0) }) {
            scheduler = engine; tick()
            if item.kind == .reminders { Task { await refresh(catchUp: false) } }
        }
    }
    func escape(_ item: Occurrence) {
        if item.kind == .calendar, (item.expiry(preferences) ?? .distantPast) <= Date().addingTimeInterval(1) { act(.skip, item) }
        else { act(.snooze(Date().addingTimeInterval(300)), item) }
    }
    func escapeAll(_ items: [Occurrence]) {
        if demoActive { endDemo(); return }
        var engine = scheduler
        if transaction({ next in
            for item in items {
                if item.kind == .calendar, (item.expiry(next.preferences) ?? .distantPast) <= Date().addingTimeInterval(1) { try engine.apply(.skip, id: item.id, to: &next) }
                else { try engine.apply(.snooze(Date().addingTimeInterval(300)), id: item.id, to: &next) }
            }
        }) { scheduler = engine; tick() }
    }
    func join(_ url: String, _ item: Occurrence) {
        guard let url = SafeLinks.validate(url) else { error = "This link is not allowed. Only HTTPS, Zoom, and Teams meeting schemes are supported."; return }
        NSWorkspace.shared.open([url], withApplicationAt: NSWorkspace.shared.urlForApplication(toOpen: url) ?? URL(fileURLWithPath: "/nonexistent"), configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, failure in
            Task { @MainActor in
                if failure == nil { self?.act(.linkOpened, item) }
                else { self?.error = "The OS could not hand off the meeting link. Retry or copy the link." }
            }
        }
    }
    func addOrEdit(_ local: LocalReminder) {
        guard !local.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { error = "Enter a title."; return }
        if !local.url.isEmpty && SafeLinks.validate(local.url) == nil { error = "Enter a safe HTTPS, Zoom, or Teams URL."; return }
        let success = transaction { next in
            if let i = next.locals.firstIndex(where: { $0.id == local.id }) {
                next.locals[i] = local
                // Explicit series editor replaces only unresolved instances. History is retained.
                for index in next.occurrences.indices where next.occurrences[index].seriesID == local.id && !next.occurrences[index].state.terminal {
                    next.occurrences[index].state = .cancelled; next.occurrences[index].resolvedAt = Date(); next.occurrences[index].outcome = "Series edited"
                }
            } else { next.locals.append(local) }
            next.occurrences.append(Scheduler.occurrence(local))
        }
        if success { showEditor = false; editor = nil; tick() }
    }
    func deleteSeries(_ id: UUID) {
        if transaction({ next in
            next.locals.removeAll { $0.id == id }
            for i in next.occurrences.indices where next.occurrences[i].seriesID == id && !next.occurrences[i].state.terminal {
                next.occurrences[i].state = .cancelled; next.occurrences[i].resolvedAt = Date(); next.occurrences[i].outcome = "Local series deleted"
            }
        }) { tick() }
    }
    func setOverride(_ id: UUID, timing: Timing?, ceiling: Intensity?) {
        if let timing, !timing.valid { error = "Invalid timing order."; return }
        if transaction({ next in
            guard let i = next.occurrences.firstIndex(where: { $0.id == id }) else { return }
            next.occurrences[i].timing = timing; next.occurrences[i].ceiling = ceiling ?? (next.occurrences[i].kind == .local ? next.locals.first(where: { $0.id == next.occurrences[i].seriesID })?.intensity : nil)
        }) { tick() }
    }
    func authorizationDescription(_ kind: SourceKind) -> String {
        switch adapter.status(kind) {
        case .notDetermined: return "Not requested — choose Connect"
        case .denied: return "Denied — review System Settings → Privacy & Security"
        case .restricted: return "Restricted by system policy"
        case .writeOnly: return "Write only — full access required to read"
        case .fullAccess: return "Full access"
        @unknown default: return "Unknown authorization"
        }
    }
    func connect(_ kind: SourceKind) {
        Task {
            do { _ = try await adapter.request(kind); await refresh(catchUp: false) }
            catch { self.error = error.localizedDescription }
        }
    }
    func scheduleRefresh() {
        generation += 1
        gates.validated = [.local]; presenter.close(); notifications.cancel()
        refreshTask?.cancel()
        refreshTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await refresh(catchUp: false)
        }
    }
    func refresh(catchUp: Bool) async {
        generation += 1; let current = generation
        refreshing = true
        gates.validated = [.local]
        if !demoActive { presenter.close() }
        notifications.cancel()
        tick(catchUp: catchUp)
        for kind in [SourceKind.calendar, .reminders] {
            sourceStatus[kind] = "Loading"
            do {
                let result = try await adapter.fetch(kind: kind, preferences: preferences, now: Date())
                guard current == generation else { return }
                let saved = transaction { next in
                    Reconciler.merge(result, into: &next, now: Date())
                    next.pruneHistory(working: result, now: Date())
                    next.log("source.\(kind.rawValue).refreshed", now: Date())
                }
                if saved {
                    sources.removeAll { $0.kind == kind }; sources += result.sources
                    gates.validated.insert(kind); lastRefresh[kind] = Date()
                    let selected = kind == .calendar ? preferences.selectedCalendars : preferences.selectedLists
                    let missing = selected.subtracting(Set(result.sources.map(\.id)))
                    sourceStatus[kind] = !missing.isEmpty ? "Partially loaded: selected source unavailable" : (selected.isEmpty ? "Select sources to enable delivery" : (result.items.isEmpty ? "Loaded — no matching items" : "Loaded \(result.items.count) items"))
                }
            } catch {
                guard current == generation else { return }
                sourceStatus[kind] = error.localizedDescription
                // Failed fetch preserves snapshots and action states. Gates suppress uncertain delivery.
            }
        }
        guard current == generation else { return }
        refreshing = false; tick(catchUp: catchUp)
    }
    func timeZoneChanged() {
        _ = transaction { next in
            for local in next.locals where local.recurrence.frequency != .none {
                guard let date = local.recurrence.next(after: Date()) else { continue }
                for i in next.occurrences.indices where next.occurrences[i].seriesID == local.id && next.occurrences[i].state == .scheduled {
                    next.occurrences[i].due = date; next.occurrences[i].anchor = date
                }
            }
        }
        scheduleRefresh()
    }
    func requestNotifications() {
        Task {
            do {
                let allowed = try await notifications.request()
                notificationStatus = await notifications.authorization()
                var p = preferences; p.fallback = allowed; updatePreferences(p)
                if !allowed { error = "Notification access denied. Overlays and local reminders remain available." }
            } catch { self.error = error.localizedDescription }
        }
    }
    func setLogin(_ enabled: Bool) {
        do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
        catch { self.error = "Launch at login: \(error.localizedDescription)" }
        updateLoginStatus()
    }
    func updateLoginStatus() {
        switch SMAppService.mainApp.status {
        case .enabled: loginStatus = "Enabled"
        case .notRegistered: loginStatus = "Not registered"
        case .requiresApproval: loginStatus = "Approval required in System Settings → General → Login Items"
        case .notFound: loginStatus = "App service not found; install a signed app first"
        @unknown default: loginStatus = "Unknown"
        }
    }
    func startDemo(_ intensity: Intensity = .prominent) {
        endDemo(); demoActive = true
        let item = Occurrence(kind: .local, sourceID: "demo", sourceName: "Sandbox demo", providerID: "demo", title: "Demo: take a deliberate pause", due: Date(), state: .presenting)
        demoIDs = [item.id]
        presenter.present(Presentation(items: [item], intensity: intensity, catchUp: false), demo: true)
        demoTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { [weak self] _ in Task { @MainActor in self?.endDemo() } }
    }
    func endDemo() {
        demoTimer?.invalidate(); demoTimer = nil; demoActive = false; demoIDs.removeAll(); presenter.close()
    }
    func showMain() {
        NotificationCenter.default.post(name: .showDreadline, object: nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func exportDiagnostics() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Dreadline-diagnostics.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let summary = "Dreadline diagnostics (redacted)\nStorage: \(storageFailed ? "unavailable" : "ready")\nCalendar authorization: \(adapter.status(.calendar).rawValue)\nReminders authorization: \(adapter.status(.reminders).rawValue)\nSelected calendars: \(preferences.selectedCalendars.count); lists: \(preferences.selectedLists.count)\nPaused: \(db.paused)\nNext action: \(nextAction?.description ?? "none")\n" + db.logs.map { "\($0.date.ISO8601Format()) \($0.category)" }.joined(separator: "\n")
        do { try summary.write(to: url, atomically: true, encoding: .utf8) } catch { self.error = "Export failed: \(error.localizedDescription)" }
    }
    func reset() {
        endDemo(); driver.cancel(); notifications.cancel(); generation += 1; refreshTask?.cancel()
        if storageFailed {
            do {
                store = nil
                let backup = databaseURL.deletingLastPathComponent().appendingPathComponent("Recovery-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
                for suffix in ["", "-wal", "-shm"] {
                    let original = URL(fileURLWithPath: databaseURL.path + suffix)
                    if FileManager.default.fileExists(atPath: original.path) { try FileManager.default.moveItem(at: original, to: backup.appendingPathComponent(original.lastPathComponent)) }
                }
                store = try SQLiteStore(url: databaseURL); db = Database(); try store?.save(db); storageFailed = false; error = nil
            } catch { self.error = "Recovery failed. Original retained: \(error.localizedDescription)" }
        } else if transaction({ $0 = Database() }) { sources = []; gates.validated = [.local] }
        tick()
    }
    func prepareToQuit(keepNotifications: Bool) {
        quitting = true
        endDemo(); driver.cancel(); recovery?.invalidate(); refreshTask?.cancel(); fallbackTask?.cancel()
        if !keepNotifications { notifications.cancel() }
    }
    func quit(keepNotifications: Bool) {
        prepareToQuit(keepNotifications: keepNotifications)
        NSApp.terminate(nil)
    }
}
extension Notification.Name { static let showDreadline = Notification.Name("showDreadline") }
