import XCTest

@MainActor
final class HauntSceneTests: XCTestCase {
    func testPreludeMinimizesFirstThenGhostKnocksThenWindowsReturn() async throws {
        let scene = HauntScene()
        var cues: [String] = []
        scene.start(prelude: true,
                    minimize: { XCTAssertEqual(scene.peek, 0); cues.append("minimize") },
                    knock: { cues.append("knock\($0)") },
                    restore: { XCTAssertEqual(scene.peek, 0); cues.append("restore") },
                    finished: { cues.append("finished") })
        defer { scene.cancel() }
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(cues, ["minimize"])
        XCTAssertEqual(scene.stage, .gathering)
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(scene.stage, .peek)
        try await Task.sleep(for: .milliseconds(3000))
        XCTAssertEqual(cues, ["minimize", "knock0", "knock1", "restore", "finished"])
    }
    func testCancelStopsLaterKnocksAndWindowCallbacks() async throws {
        let scene = HauntScene()
        var cues: [String] = []
        scene.start(prelude: true, minimize: { cues.append("minimize") }, knock: { cues.append("knock\($0)") }, restore: { cues.append("restore") })
        try await Task.sleep(for: .milliseconds(100))
        scene.cancel()
        try await Task.sleep(for: .milliseconds(3600))
        XCTAssertEqual(cues, ["minimize"])
    }
    func testArrivalPopsThenGhostLingersThenCardSlidesDown() async throws {
        let scene = HauntScene()
        var cues: [String] = []
        scene.start(prelude: false, minimize: { cues.append("minimize") }, arrival: { cues.append("sting") })
        defer { scene.cancel() }
        try await Task.sleep(for: .milliseconds(450))
        XCTAssertEqual(scene.stage, .shock)
        XCTAssertEqual(cues, ["minimize", "sting"])
        XCTAssertEqual(scene.darkness, 1, "The scare is on a black screen")
        XCTAssertEqual(scene.closeupOpacity, 1, "The face pops in without fading")
        XCTAssertFalse(scene.interactive)
        try await Task.sleep(for: .milliseconds(1100))
        XCTAssertEqual(scene.stage, .lingering)
        XCTAssertEqual(scene.ghostOpacity, 1)
        XCTAssertEqual(scene.cardDrop, 0, "The ghost lingers before the card arrives")
        try await Task.sleep(for: .milliseconds(1500))
        XCTAssertEqual(scene.cardDrop, 1)
        XCTAssertEqual(scene.ghostRest, 1)
        XCTAssertGreaterThan(scene.ghostOpacity, 0, "The ghost stays on screen behind the card")
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(scene.stage, .manifest)
        XCTAssertTrue(scene.interactive)
    }
    func testReducedMotionSkipsTheScareAndShowsTheCard() async throws {
        let scene = HauntScene(still: true)
        scene.start(prelude: false)
        defer { scene.cancel() }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(scene.stage, .manifest)
        XCTAssertEqual(scene.closeupOpacity, 0)
        XCTAssertEqual(scene.cardDrop, 1)
    }
    func testDashCrossesOnceWithoutTouchingWindows() async throws {
        let scene = HauntScene(fromLeft: false)
        var finished = 0
        scene.dash { finished += 1 }
        defer { scene.cancel() }
        XCTAssertEqual(scene.stage, .dash)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(scene.dashProgress, 1)
        XCTAssertFalse(scene.interactive)
        try await Task.sleep(for: .milliseconds(800))
        XCTAssertEqual(finished, 1)
        XCTAssertEqual(scene.darkness, 0, "The dash never darkens the screen")
    }
    func testDismissWarningShowsTheFaceBeforeWorkspaceReturns() async throws {
        let scene = HauntScene(still: true)
        scene.start(prelude: false)
        try await Task.sleep(for: .milliseconds(50))
        var cues: [String] = []
        scene.warn(.dismiss, line: "You can't dismiss me.", restore: { cues.append("restore") }, done: { cues.append("done") })
        defer { scene.cancel() }
        XCTAssertEqual(scene.stage, .warning)
        XCTAssertEqual(scene.warningKind, .dismiss)
        XCTAssertEqual(scene.closeupOpacity, 1)
        XCTAssertEqual(scene.cardDrop, 0)
        XCTAssertFalse(scene.interactive)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(cues, [])
        try await Task.sleep(for: .milliseconds(3600))
        XCTAssertEqual(cues, ["restore", "done"])
        XCTAssertEqual(scene.reveal, 1)
    }
    func testSnoozeWarningFlickersTheBlackOverlaySafely() async throws {
        let scene = HauntScene()
        var samples: [Double] = []
        var cues: [String] = []
        scene.warn(.snooze, line: "I'll be right here. Waiting.", restore: { cues.append("restore") }, done: { cues.append("done") })
        defer { scene.cancel() }
        for _ in 0..<14 { try await Task.sleep(for: .milliseconds(200)); samples.append(scene.darkness) }
        let changes = zip(samples, samples.dropFirst()).filter { abs($0 - $1) > 0.5 }.count
        XCTAssertGreaterThanOrEqual(changes, 4, "The overlay visibly flickers")
        XCTAssertLessThanOrEqual(changes, 9, "Under 3 flashes per second")
        try await Task.sleep(for: .milliseconds(1000))
        XCTAssertEqual(cues, ["restore", "done"])
    }
    func testJoinVanishesThenRestoresBeforeTheLinkOpens() async throws {
        let scene = HauntScene()
        var cues: [String] = []
        scene.vanish(restore: { XCTAssertEqual(scene.fade, 1); cues.append("restore") }, done: { cues.append("open link") })
        defer { scene.cancel() }
        XCTAssertEqual(scene.stage, .vanishing)
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual(cues, ["restore", "open link"])
    }
}
