import Foundation

@MainActor
protocol DeadlineDriver: AnyObject {
    func schedule(at date: Date?, action: @escaping @MainActor () -> Void)
    func cancel()
}
@MainActor
final class TimerDeadlineDriver: DeadlineDriver {
    private var timer: Timer?
    func schedule(at date: Date?, action: @escaping @MainActor () -> Void) {
        cancel()
        guard let date else { return }
        let timer = Timer(fire: date, interval: 0, repeats: false) { _ in Task { @MainActor in action() } }
        timer.tolerance = 0.25
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
    func cancel() { timer?.invalidate(); timer = nil }
}
