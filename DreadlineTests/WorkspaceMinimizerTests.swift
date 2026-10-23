import XCTest

@MainActor
final class FakeWorkspaceAccess: WorkspaceWindowAccess {
    var trusted = true
    var requests = 0
    var entries: [any MinimizableWindow] = []
    func requestPermission() { requests += 1 }
    func windows() -> [any MinimizableWindow] { entries }
}
@MainActor
final class FakeMinimizableWindow: MinimizableWindow {
    var minimized: Bool? = false
    var canMinimize = true
    var failMinimize = false
    var failRestore = false
    var gone = false
    var changes: [Bool] = []
    func setMinimized(_ value: Bool) -> WindowChangeResult {
        changes.append(value)
        if gone { return .gone }
        if value ? failMinimize : failRestore { return .failed }
        minimized = value; return .success
    }
}
@MainActor
final class WorkspaceMinimizerTests: XCTestCase {
    func testOnlyWindowsWeMinimizedAreRestored() {
        let access = FakeWorkspaceAccess(), open = FakeMinimizableWindow(), already = FakeMinimizableWindow()
        already.minimized = true; access.entries = [open, already]
        let manager = WorkspaceMinimizer(access: access)
        manager.minimize(); XCTAssertEqual(open.minimized, true)
        manager.restore(); XCTAssertEqual(open.minimized, false)
        XCTAssertEqual(already.minimized, true); XCTAssertTrue(already.changes.isEmpty)
        XCTAssertEqual(open.changes, [true, false])
    }
    func testPermissionDeniedDoesNotClaimMinimizationOrModifyAnything() {
        let access = FakeWorkspaceAccess(), window = FakeMinimizableWindow()
        access.trusted = false; access.entries = [window]
        let manager = WorkspaceMinimizer(access: access); manager.minimize()
        XCTAssertTrue(window.changes.isEmpty); XCTAssertTrue(manager.status.contains("not minimized"))
    }
    func testUnsupportedAndFailedWindowsAreNotRestored() {
        let access = FakeWorkspaceAccess(), unsupported = FakeMinimizableWindow(), failed = FakeMinimizableWindow()
        unsupported.canMinimize = false; failed.failMinimize = true; access.entries = [unsupported, failed]
        let manager = WorkspaceMinimizer(access: access); manager.minimize(); manager.restore()
        XCTAssertTrue(unsupported.changes.isEmpty); XCTAssertEqual(failed.changes, [true])
        XCTAssertEqual(manager.pendingRestorations, 0)
    }
    func testClosedWindowsDoNotBlockRestoration() {
        let access = FakeWorkspaceAccess(), window = FakeMinimizableWindow(); access.entries = [window]
        let manager = WorkspaceMinimizer(access: access); manager.minimize(); window.gone = true
        manager.restore(); XCTAssertEqual(manager.pendingRestorations, 0)
    }
    func testFailedRestoreCanBeRetriedAndCannotBeOverwrittenByNewMinimize() {
        let access = FakeWorkspaceAccess(), window = FakeMinimizableWindow(); access.entries = [window]
        let manager = WorkspaceMinimizer(access: access); manager.minimize(); window.failRestore = true
        manager.restore(); XCTAssertEqual(manager.pendingRestorations, 1)
        manager.minimize(); XCTAssertEqual(window.changes.filter { $0 }.count, 1)
        window.failRestore = false; manager.restore()
        XCTAssertEqual(manager.pendingRestorations, 0); XCTAssertEqual(window.minimized, false)
    }
    func testPermissionRevocationKeepsRestorationRecordsForRetry() {
        let access = FakeWorkspaceAccess(), window = FakeMinimizableWindow(); access.entries = [window]
        let manager = WorkspaceMinimizer(access: access); manager.minimize(); access.trusted = false
        manager.restore(); XCTAssertEqual(manager.pendingRestorations, 1)
        access.trusted = true; manager.restore(); XCTAssertEqual(window.minimized, false)
    }
    func testRepeatedRestoreIsIdempotent() {
        let access = FakeWorkspaceAccess(), window = FakeMinimizableWindow(); access.entries = [window]
        let manager = WorkspaceMinimizer(access: access); manager.minimize(); manager.restore(); manager.restore()
        XCTAssertEqual(window.changes, [true, false])
    }
}

extension WorkspaceMinimizerTests {
    func testKnockWavesMinimizeWindowsInThreeGroups() {
        let access = FakeWorkspaceAccess()
        let windows = (0..<6).map { _ in FakeMinimizableWindow() }; access.entries = windows
        let manager = WorkspaceMinimizer(access: access)
        XCTAssertTrue(manager.prepareMinimize())
        XCTAssertTrue(windows.allSatisfy { $0.minimized == false })
        manager.minimizeNextWave(); XCTAssertEqual(windows.filter { $0.minimized == true }.count, 2)
        manager.minimizeNextWave(); XCTAssertEqual(windows.filter { $0.minimized == true }.count, 4)
        manager.minimizeNextWave(); XCTAssertEqual(windows.filter { $0.minimized == true }.count, 6)
        manager.restore(); XCTAssertTrue(windows.allSatisfy { $0.minimized == false })
    }
    func testEscapeBetweenKnocksCancelsUnstartedMinimizations() {
        let access = FakeWorkspaceAccess()
        let windows = (0..<6).map { _ in FakeMinimizableWindow() }; access.entries = windows
        let manager = WorkspaceMinimizer(access: access)
        manager.prepareMinimize(); manager.minimizeNextWave(); manager.restore()
        manager.minimizeNextWave(); manager.minimizeNextWave()
        XCTAssertTrue(windows.allSatisfy { $0.minimized == false })
        XCTAssertTrue(windows.suffix(4).allSatisfy { $0.changes.isEmpty })
    }
}
