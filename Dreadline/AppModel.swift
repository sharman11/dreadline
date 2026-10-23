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
    @Published var settingsTab = "General"
    @Published var editor: LocalReminder?
    @Published var showEditor = false
    @Published var notificationStatus = "Not requested"
    private(set) var quitting = false
    @Published var demoActive = false
    @Published var nextAction: Date?
    let windowMinimizer: WorkspaceMinimizer
    @Published var windowControlStatus = "Accessibility permission required to minimize windows."
    @Published var overlayStatus = "Idle"
    @Published var loginStatus = "Not registered"
    /// Live permission state for onboarding and Settings. Refreshed by `refreshPermissions()`.
    @Published private(set) var calendarAccessGranted = false
    @Published private(set) var accessibilityTrusted = false
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
    /// Remaining stages of a full-sequence preview.
    private var demoFlow: [HauntPhase] = []
    private var soundPreview: NSSound?
    private var demoIDs = Set<UUID>()
    /// Items whose meeting link is being handed to the browser; kept off screen until the handoff settles.
    private var handoff = Set<UUID>()
    let databaseURL: URL
    init(store suppliedStore: (any StateStore)? = nil, source: (any SourceAdapter)? = nil, notificationSink: (any NotificationSink)? = nil, presentationSink: (any PresentationSink)? = nil, startServices: Bool = true, deadlineDriver: (any DeadlineDriver)? = nil, clock: any Clock = SystemClock(), windowAccess: (any WorkspaceWindowAccess)? = nil) {
        windowMinimizer = WorkspaceMinimizer(access: windowAccess ?? AXWorkspaceWindowAccess())
        adapter = source ?? EventKitAdapter()
        notifications = notificationSink ?? NotificationAdapter()
        injectedPresenter = presentationSink
        scheduler = Scheduler(clock: clock)
        driver = deadlineDriver ?? TimerDeadlineDriver()
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Dreadline", isDirectory: true)
        let legacy = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Containers/xyz.dreadline.app/Data/Library/Application Support/Dreadline/state.sqlite")
        databaseURL = FileManager.default.fileExists(atPath: legacy.path) ? legacy : folder.appendingPathComponent("state.sqlite")
        do { let storage: any StateStore = try suppliedStore ?? SQLiteStore(url: databaseURL); db = try storage.load(); store = storage }
        catch { storageFailed = true; self.error = error.localizedDescription }
        refreshPermissions()
        guard startServices else { return }
        if let native = notifications as? NotificationAdapter { native.onError = { [weak self] in self?.error = $0 } }
        notifications.onAction = { [weak self] id, action in
            guard let self else { return }
            Task { @MainActor in
                await self.refresh(catchUp: false)
                guard let uuid = UUID(uuidString: id), let item = self.db.occurrences.first(where: { $0.id == uuid }), !item.state.terminal,
                      item.kind == .local || self.gates.validated.contains(item.kind) else { return }
                if action == "ACK" { self.act(.acknowledge, item) }
                else if action == "SNOOZE" { self.act(.snooze(Date().addingTimeInterval(self.snoozeInterval(item))), item) }
                else { self.showMain(); self.tick(catchUp: true) }
            }
        }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .EKEventStoreChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.scheduleRefresh() }
        })
        observers.append(center.addObserver(forName: NSNotification.Name.NSSystemClockDidChange, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.scheduleRefresh() } })
        observers.append(center.addObserver(forName: NSNotification.Name.NSSystemTimeZoneDidChange, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.timeZoneChanged() } })
        observers.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.refreshPermissions(); self?.scheduleRefresh() } })
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
        refreshPermissions()
        _ = transaction { $0.log(windowMinimizer.trusted ? "window.control.trusted" : "window.control.untrusted", now: Date()) }
        Task { notificationStatus = await notifications.authorization(); await refresh(catchUp: true) }
    }
    var preferences: Preferences { db.preferences }
    var unresolved: [Occurrence] { db.occurrences.filter { !$0.state.terminal }.sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) } }
    var pending: [Occurrence] { unresolved.filter { $0.state != .scheduled || ($0.due ?? .distantFuture) <= Date() } }
    var upcoming: [Occurrence] { let shown = Set(pending.map(\.id)); return unresolved.filter { !shown.contains($0.id) } }
    var activeLocalReminders: [LocalReminder] {
        let activeSeries = Set(unresolved.compactMap(\.seriesID))
        return db.locals.filter { activeSeries.contains($0.id) || $0.recurrence.frequency != .none }
    }
    var history: [Occurrence] { db.occurrences.filter { $0.state.terminal && ($0.resolvedAt ?? $0.updated) >= Date().addingTimeInterval(-Double(preferences.retentionDays) * 86400) }.sorted { ($0.resolvedAt ?? $0.updated) > ($1.resolvedAt ?? $1.updated) } }
    var ghostWatching: Bool {
        !db.paused && unresolved.contains { item in
            guard let due = item.due else { return false }
            return due.timeIntervalSinceNow <= (item.timing ?? preferences.timing).gentle
        }
    }
    var menuTitle: String {
        if !setupComplete { return "Finish setup" }
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
            if !demoActive { presenter.present(Self.excluding(handoff, from: presentation), demo: false) }
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
        if demoIDs.contains(item.id) { endDemo(animated: true); return }
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
    /// Snooze length: the local reminder's own preference, otherwise the app-wide one.
    func snoozeInterval(_ item: Occurrence) -> TimeInterval {
        let minutes = item.kind == .local ? db.locals.first(where: { $0.id == item.seriesID })?.snoozeMinutes : nil
        return Double(max(1, minutes ?? preferences.snoozeMinutes)) * 60
    }
    func snoozeLabel(_ item: Occurrence) -> String { "Snooze \(Int(snoozeInterval(item) / 60)) min" }
    func escape(_ item: Occurrence) {
        if item.kind == .calendar, (item.expiry(preferences) ?? .distantPast) <= Date().addingTimeInterval(1) { act(.skip, item) }
        else { act(.snooze(Date().addingTimeInterval(snoozeInterval(item))), item) }
    }
    func escapeAll(_ items: [Occurrence]) {
        if demoActive { endDemo(); return }
        var engine = scheduler
        if transaction({ next in
            for item in items {
                if item.kind == .calendar, (item.expiry(next.preferences) ?? .distantPast) <= Date().addingTimeInterval(1) { try engine.apply(.skip, id: item.id, to: &next) }
                else { try engine.apply(.snooze(Date().addingTimeInterval(snoozeInterval(item))), id: item.id, to: &next) }
            }
        }) { scheduler = engine; tick() }
    }
    static func excluding(_ ids: Set<UUID>, from presentation: Presentation?) -> Presentation? {
        guard var shown = presentation, !ids.isEmpty else { return presentation }
        shown.items.removeAll { ids.contains($0.id) }
        return shown.items.isEmpty ? nil : shown
    }
    func join(_ url: String, _ item: Occurrence) {
        guard let url = SafeLinks.validate(url) else { error = "This link is not allowed. Only HTTPS, Zoom, and Teams meeting schemes are supported."; handoff.remove(item.id); tick(); return }
        guard let app = NSWorkspace.shared.urlForApplication(toOpen: url) else {
            handoff.remove(item.id); error = "No app on this Mac can open this meeting link."; settleArrival([item.id]); return
        }
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, failure in
            Task { @MainActor in
                guard let self else { return }
                self.handoff.remove(item.id)
                if failure == nil { self.act(.linkOpened, item) }
                else { self.error = "The OS could not hand off the meeting link. Retry or copy the link."; self.settleArrival([item.id]) }
            }
        }
    }
    /// Join from the haunting: the ghost vanishes, windows return, then the link opens in front of them.
    func joinFromOverlay(_ link: String, _ item: Occurrence) {
        if demoIDs.contains(item.id) { presenter.farewell(.join) { [weak self] in self?.endDemo() }; return }
        guard SafeLinks.validate(link) != nil else { error = "This link is not allowed. Only HTTPS, Zoom, and Teams meeting schemes are supported."; return }
        handoff.insert(item.id)
        presenter.farewell(.join) { [weak self] in self?.join(link, item) }
    }
    /// Snooze from the haunting (button or Escape): the overlay flickers a warning before the snooze applies.
    func snoozeFromOverlay(_ items: [Occurrence]) {
        presenter.farewell(.snooze) { [weak self] in
            guard let self else { return }
            if items.contains(where: { self.demoIDs.contains($0.id) }) { self.endDemo() } else { self.escapeAll(items) }
        }
    }
    /// Dismiss from the haunting: a parting warning plays before the occurrence is silenced.
    func dismissFromOverlay(_ item: Occurrence) {
        presenter.farewell(.dismiss) { [weak self] in
            guard let self else { return }
            if self.demoIDs.contains(item.id) { self.endDemo() } else { self.act(.acknowledge, item) }
        }
    }
    /// After a failed handoff the item comes back as a side reminder, never as a second scare.
    private func settleArrival(_ ids: Set<UUID>) {
        if !transaction({ db in
            for i in db.occurrences.indices where ids.contains(db.occurrences[i].id) && db.occurrences[i].arrivalShownFor == db.occurrences[i].due {
                db.occurrences[i].arrivalUntil = scheduler.clock.now
            }
        }) { return }
        tick()
    }
    func addOrEdit(_ local: LocalReminder) {
        guard !local.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { error = "Enter a title."; return }
        if !local.url.isEmpty && SafeLinks.validate(local.url) == nil { error = "Enter a safe HTTPS, Zoom, or Teams URL."; return }
        let now = scheduler.clock.now
        let success = transaction { next in
            var needsOccurrence = true
            if let i = next.locals.firstIndex(where: { $0.id == local.id }) {
                let old = next.locals[i]
                next.locals[i] = local
                let scheduleChanged = old.due != local.due || old.recurrence != local.recurrence
                let fresh = Scheduler.occurrence(local)
                // Explicit series editor replaces only unresolved instances. History is retained.
                for index in next.occurrences.indices where next.occurrences[index].seriesID == local.id && !next.occurrences[index].state.terminal {
                    if scheduleChanged {
                        next.occurrences[index].state = .cancelled; next.occurrences[index].resolvedAt = now; next.occurrences[index].outcome = "Series edited"
                    } else {
                        // Same schedule: update the pending occurrence in place so it keeps its due time.
                        next.occurrences[index].title = fresh.title; next.occurrences[index].links = fresh.links
                        next.occurrences[index].ceiling = fresh.ceiling; next.occurrences[index].recurring = fresh.recurring
                        next.occurrences[index].updated = now
                        needsOccurrence = false
                    }
                }
            } else { next.locals.append(local) }
            if needsOccurrence { next.occurrences.append(Scheduler.occurrence(local, due: Self.firstDue(local, now: now))) }
        }
        if success { showEditor = false; editor = nil; tick() }
    }
    /// A repeating reminder whose chosen start has passed begins at its next future date.
    static func firstDue(_ local: LocalReminder, now: Date) -> Date {
        guard local.recurrence.frequency != .none, local.due <= now else { return local.due }
        return local.recurrence.next(after: now) ?? local.due
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
        // Sources stay validated from their last successful fetch, so a routine refresh
        // (menu click, timer, calendar sync) never tears down an alert that is on screen.
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
                gates.validated.remove(kind); notifications.cancel()
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
            // Once answered, macOS won't ask again; the switch lives in System Settings.
            if notificationStatus == "Denied" { openNotificationSettings(); return }
            do {
                let allowed = try await notifications.request()
                notificationStatus = await notifications.authorization()
                var p = preferences; p.fallback = allowed; updatePreferences(p)
                if !allowed { openNotificationSettings() }
            } catch { self.error = error.localizedDescription }
        }
    }
    func openNotificationSettings() {
        let id = Bundle.main.bundleIdentifier ?? "xyz.dreadline.app"
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.notifications?id=\(id)")!)
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
    /// Previews one stage: `.gentle` is the early warning, `.fullscreen` the meeting alert, `.prominent` the side reminder.
    func startDemo(_ intensity: Intensity = .fullscreen) {
        endDemo(resumeDelivery: false); demoActive = true
        if intensity == .gentle { showDemo(.prelude) } else { showDemo(.reminder, intensity: intensity) }
    }
    /// Settings → Haunting → Test haunting: plays whatever the chosen style would do at a real meeting.
    func testHaunting() {
        if preferences.fullscreenEnabled && preferences.poltergeistEnabled == true { startFlowPreview() }
        else { startDemo(.prominent) }
    }
    /// Previews the whole haunting, compressed: dash → early warning → meeting alert.
    func startFlowPreview() {
        endDemo(resumeDelivery: false); demoActive = true
        demoFlow = [.prelude, .reminder]
        showDemo(.dash)
    }
    private func showDemo(_ phase: HauntPhase, intensity: Intensity = .fullscreen) {
        let due: Date
        switch phase {
        case .dash: due = Date().addingTimeInterval(300 + Haunt.dashLead)
        case .prelude: due = Date().addingTimeInterval(300)
        case .reminder: due = Date().addingTimeInterval(Haunt.arrivalLead)
        }
        let item = Occurrence(kind: .calendar, sourceID: "demo", sourceName: "Sample calendar", providerID: "demo", title: "A quick catch-up", links: ["https://example.com/meeting"], due: due, state: .presenting)
        demoIDs.insert(item.id)
        presenter.present(Presentation(items: [item], intensity: phase == .reminder ? intensity : .gentle, catchUp: false, phase: phase), demo: true)
        let limit: TimeInterval = phase == .dash ? Haunt.dashSeconds + 2 : (phase == .prelude ? Haunt.preludeSeconds + 1 : Haunt.arrivalSeconds)
        demoTimer?.invalidate()
        demoTimer = Timer.scheduledTimer(withTimeInterval: limit, repeats: false) { [weak self] _ in Task { @MainActor in self?.demoStageFinished() } }
    }
    /// A preview stage played out: continue a full-sequence preview after a short gap, or end it.
    func demoStageFinished() {
        guard demoActive else { return }
        guard !demoFlow.isEmpty else { endDemo(); return }
        let next = demoFlow.removeFirst()
        presenter.close()
        demoTimer?.invalidate()
        demoTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            Task { @MainActor in guard let self, self.demoActive else { return }; self.showDemo(next) }
        }
    }
    // MARK: Setup and permissions

    /// What Dreadline needs before it can haunt anything: calendar access, at least one calendar,
    /// window control, and notifications.
    var requiredSetupDone: Bool {
        calendarAccessGranted && !preferences.selectedCalendars.isEmpty && accessibilityTrusted && notificationsGranted
    }
    /// False once the calendar prompt was answered; after that the switch lives in System Settings.
    var remindersAccessGranted: Bool { adapter.status(.reminders) == .fullAccess }
    var calendarAccessUndetermined: Bool { adapter.status(.calendar) == .notDetermined }
    var notificationsGranted: Bool { notificationStatus == "Authorized" || notificationStatus == "Provisional" }
    /// The app is usable only once setup was completed and every requirement still holds.
    var setupComplete: Bool { preferences.onboardingComplete && requiredSetupDone }
    func refreshPermissions() {
        let calendar = adapter.status(.calendar) == .fullAccess
        if calendar != calendarAccessGranted { calendarAccessGranted = calendar }
        let trusted = windowMinimizer.trusted
        if trusted != accessibilityTrusted { accessibilityTrusted = trusted }
        refreshWindowControl()
        Task { await refreshNotificationStatus() }
    }
    /// Notification permission can change in System Settings at any time, so it is re-read with the others.
    func refreshNotificationStatus() async {
        let status = await notifications.authorization()
        if status != notificationStatus { notificationStatus = status }
    }
    func requestCalendarAccess() {
        Task {
            do { _ = try await adapter.request(.calendar) } catch { self.error = error.localizedDescription }
            refreshPermissions()
            // A denied request needs System Settings; opening it saves a hunt.
            if !calendarAccessGranted, adapter.status(.calendar) != .notDetermined {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
            }
            await refresh(catchUp: false)
        }
    }
    /// Shows the system prompt and opens the Accessibility pane where the switch lives.
    func openAccessibilitySettings() {
        windowMinimizer.requestPermission()
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    /// Finishes onboarding: alerts turn on and the app unlocks.
    func completeSetup() {
        refreshPermissions()
        guard requiredSetupDone else { return }
        var p = preferences; p.onboardingComplete = true; p.alertsEnabled = true
        updatePreferences(p)
    }
    func setCalendar(_ id: String, selected: Bool) {
        var p = preferences
        if selected { p.selectedCalendars.insert(id) } else { p.selectedCalendars.remove(id) }
        updatePreferences(p)
    }
    func requestWindowControl() {
        windowMinimizer.requestPermission()
        refreshWindowControl()
    }
    func refreshWindowControl() {
        windowControlStatus = windowMinimizer.trusted ? "Accessibility enabled. Hauntings will minimize open windows." : "Accessibility permission required — windows cannot be minimized."
    }
    /// Records the outcome of a haunting's minimize step (counts only, never window names).
    func recordWindowControl() {
        windowControlStatus = windowMinimizer.status
        let m = windowMinimizer
        let category = m.trusted ? "window.control.minimized.\(m.pendingRestorations).found.\(m.found).skipped.\(m.skipped)\(m.enumerationIncomplete ? ".incomplete" : "")" : "window.control.untrusted"
        _ = transaction { $0.log(category, now: Date()) }
    }
    func restoreWorkspace() {
        windowMinimizer.restore(); windowControlStatus = windowMinimizer.status
    }
    func previewHauntSound(_ effect: HauntSound) {
        soundPreview?.stop()
        guard let url = effect.url else { return }
        let sound = NSSound(contentsOf: url, byReference: true)
        sound?.volume = Float(preferences.volume); sound?.loops = false; sound?.play(); soundPreview = sound
    }
    func finishArrival(_ presentation: Presentation) {
        presenter.close()
        let ids = Set(presentation.items.map(\.id))
        if transaction({ db in
            for i in db.occurrences.indices where ids.contains(db.occurrences[i].id) {
                db.occurrences[i].arrivalShownFor = db.occurrences[i].due
                db.occurrences[i].arrivalUntil = scheduler.clock.now
            }
        }) { tick() }
    }
    func stopPresentation(_ presentation: Presentation) {
        if demoActive { endDemo(); return }
        presenter.close()
        if presentation.phase != .reminder {
            presenter.close()
            let ids = Set(presentation.items.map(\.id))
            if transaction({ db in
                for i in db.occurrences.indices where ids.contains(db.occurrences[i].id) {
                    db.occurrences[i].preludeUntil = nil; db.occurrences[i].dashUntil = nil
                }
            }) { presenter.close(); tick() }
        } else { escapeAll(presentation.items) }
    }
    func endDemo(resumeDelivery: Bool = true, animated: Bool = false) {
        let wasActive = demoActive
        soundPreview?.stop(); soundPreview = nil
        demoTimer?.invalidate(); demoTimer = nil; demoActive = false; demoIDs.removeAll(); demoFlow.removeAll(); if animated { presenter.release() } else { presenter.close() }
        if wasActive && resumeDelivery && !quitting { tick(catchUp: true) }
    }
    func showMain() {
        NotificationCenter.default.post(name: .showDreadline, object: nil)
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
