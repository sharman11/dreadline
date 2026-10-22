import Foundation
import UserNotifications

@MainActor
protocol NotificationSink: AnyObject {
    var onAction: ((String, String) -> Void)? { get set }
    func request() async throws -> Bool
    func authorization() async -> String
    func cancel()
    func reconcile(_ db: Database, now: Date) async
}
@MainActor
final class NotificationAdapter: NSObject, NotificationSink, UNUserNotificationCenterDelegate {
    private var generation = 0
    private var activeTask: Task<Void, Never>?
    var onError: ((String) -> Void)?
    private let center = UNUserNotificationCenter.current()
    var onAction: ((String, String) -> Void)?
    override init() {
        super.init()
        center.delegate = self
        let category = UNNotificationCategory(identifier: "REMINDER", actions: [
            UNNotificationAction(identifier: "ACK", title: "Acknowledge", options: .foreground),
            UNNotificationAction(identifier: "SNOOZE", title: "Snooze 5 minutes", options: .foreground)
        ], intentIdentifiers: [], options: [])
        center.setNotificationCategories([category])
    }
    func request() async throws -> Bool { try await center.requestAuthorization(options: [.alert, .sound]) }
    func authorization() async -> String {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized: return "Authorized"
        case .denied: return "Denied"
        case .notDetermined: return "Not requested"
        case .provisional: return "Provisional"
        @unknown default: return "Unknown"
        }
    }
    func cancel() { generation += 1; activeTask?.cancel(); center.removeAllPendingNotificationRequests(); center.removeAllDeliveredNotifications() }
    func reconcile(_ db: Database, now: Date) async {
        let previous = activeTask
        cancel()
        let current = generation
        let work = Task { [weak self] in
            await previous?.value
            guard let self, !Task.isCancelled, current == self.generation else { return }
            self.center.removeAllPendingNotificationRequests()
            await self.schedule(db, now: now, generation: current)
        }
        activeTask = work
        await work.value
        if current == generation { activeTask = nil }
    }
    private func schedule(_ db: Database, now: Date, generation current: Int) async {
        guard db.preferences.fallback, db.preferences.alertsEnabled, !db.paused else { return }
        var requests: [(Occurrence, Date)] = []
        for item in db.occurrences where !item.state.terminal && item.outcome != "Identity ambiguous; delivery suppressed" {
            guard let due = item.due else { continue }
            let date = max(item.firstAlert(db.preferences) ?? due, item.snoozeUntil ?? .distantPast)
            guard date > now, !db.preferences.quiet.contains(date), item.expiry(db.preferences).map({ date < $0 }) ?? true else { continue }
            requests.append((item, date))
        }
        // Conservative app bound; do not depend on an undocumented macOS queue capacity.
        for (item, date) in requests.sorted(by: { $0.1 < $1.1 }).prefix(32) {
            let content = UNMutableNotificationContent()
            content.title = db.preferences.privateTitles ? "Commitment reminder" : item.title
            content.body = "Open Dreadline to review. Source changes while quit may make this alert stale."
            content.categoryIdentifier = "REMINDER"
            content.userInfo = ["occurrence": item.id.uuidString]
            if db.preferences.sound && (item.kind != .local || db.locals.first(where: { $0.id == item.seriesID })?.sound == true) { content.sound = .default }
            let request = UNNotificationRequest(identifier: "\(item.id.uuidString).fallback", content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSinceNow), repeats: false))
            guard !Task.isCancelled, current == generation else { return }
            do { try await center.add(request) }
            catch { onError?("Notification scheduling failed. Custom reminders remain available.") }
            guard !Task.isCancelled, current == generation else {
                center.removePendingNotificationRequests(withIdentifiers: [request.identifier]); return
            }
        }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Custom delivery owns the foreground ledger. Never duplicate with a system banner.
        completionHandler([])
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let id = response.notification.request.content.userInfo["occurrence"] as? String ?? ""
        let action = response.actionIdentifier
        Task { @MainActor in self.onAction?(id, action) }
        completionHandler()
    }
}
