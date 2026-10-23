import XCTest
import SwiftUI
import AppKit
import AVFoundation

/// Renders the Dreadline trailer: the app's real haunting views, driven frame by frame, over a staged
/// desktop, with the trailer music and the app's own scare sounds. Skipped unless DEMO_VIDEO_MUSIC and
/// DEMO_VIDEO_OUT are set; run it with scripts/render-demo-video.sh.
@MainActor
final class DemoVideoTests: XCTestCase {
    func testRenderDemoVideo() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let music = env["DEMO_VIDEO_MUSIC"], let out = env["DEMO_VIDEO_OUT"] else { throw XCTSkip("DEMO_VIDEO_MUSIC / DEMO_VIDEO_OUT not set") }
        let app = Bundle(for: DemoVideoTests.self).bundleURL.deletingLastPathComponent().appendingPathComponent("Dreadline.app")
        let appBundle = try XCTUnwrap(Bundle(url: app), "Build the app first")
        HauntArt.bundle = appBundle
        let assets = try await DemoAssets.make(app: appBundle)
        let silent = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("dreadline-demo-\(UUID().uuidString).mov")
        defer { try? FileManager.default.removeItem(at: silent) }
        try await DemoRenderer.render(assets: assets, to: silent)
        let output = URL(fileURLWithPath: out)
        try? FileManager.default.removeItem(at: output)
        try await DemoAudio.mix(video: silent, music: URL(fileURLWithPath: music), app: appBundle, to: output)
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
    }
}

// MARK: - Timeline

/// Every beat is placed on the music's hits (see the loudness map in the PR notes).
enum DemoTime {
    static let fps: Int32 = 30
    static let length = 36.4
    static let desktop = 4.1, dash = 7.8, prelude = 8.5, crawl = 14.7
    static let tour = 16.6, dread = 23.0, scare = 25.1, linger = 26.5, card = 27.3, dismiss = 29.2
    static let title = 30.9, sting = 33.4, stingHit = 34.75
    static let knocks = [9.4, 10.9]
    static let flashes: [(at: Double, strength: Double)] = [(4.1, 0.25), (14.7, 0.45), (17.8, 0.25), (20.0, 0.25), (21.0, 0.25), (25.1, 0.55), (29.2, 0.4), (34.75, 0.55)]
    static let shakes: [(at: Double, length: Double, amount: Double)] = [(14.7, 0.35, 14), (25.1, 0.6, 26), (29.2, 0.4, 18), (34.75, 0.5, 30)]
    /// RGB-split glitches on the hits and the subliminal glimpses.
    static let glitches: [(at: Double, length: Double, amount: Double)] = [(6.3, 0.14, 0.7), (14.7, 0.2, 1), (21.0, 0.15, 0.6), (24.0, 0.14, 1), (25.1, 0.22, 1.2), (29.2, 0.2, 1), (34.75, 0.25, 1.3)]
    static let snooze = 21.0
}

private func clamp(_ x: Double) -> Double { min(1, max(0, x)) }
private func ramp(_ t: Double, _ a: Double, _ b: Double) -> Double { clamp((t - a) / (b - a)) }
private func easeIn(_ x: Double) -> Double { x * x }
private func easeOut(_ x: Double) -> Double { 1 - (1 - x) * (1 - x) }
private func easeInOut(_ x: Double) -> Double { x < 0.5 ? 2 * x * x : 1 - pow(-2 * x + 2, 2) / 2 }
/// The same curve as SwiftUI's `.spring(response:dampingFraction:)`, from 0 to 1, `dt` seconds in.
private func spring(_ dt: Double, response: Double, damping: Double) -> Double {
    guard dt > 0 else { return 0 }
    let w0 = 2 * Double.pi / response, z = min(damping, 0.999), wd = w0 * sqrt(1 - z * z)
    return 1 - exp(-z * w0 * dt) * (cos(wd * dt) + (z * w0 / wd) * sin(wd * dt))
}
/// Fades in over 0.25 s at `a` and out over 0.25 s before `b`.
private func window(_ t: Double, _ a: Double, _ b: Double) -> Double { ramp(t, a, a + 0.25) * (1 - ramp(t, b - 0.25, b)) }
/// Stable per-frame noise in 0..<1.
private func noise(_ i: Int) -> Double {
    var x = UInt64(truncatingIfNeeded: i) &+ 0x9E37_79B9_7F4A_7C15
    x = (x ^ (x >> 30)) &* 0xBF58_476D_1CE4_E5B9
    x = (x ^ (x >> 27)) &* 0x94D0_49BB_1331_11EB
    x ^= x >> 31
    return Double(x % 100_000) / 100_000
}

// MARK: - Assets

@MainActor
struct DemoAssets {
    let model: AppModel
    let meeting: Occurrence
    let others: [Occurrence]
    let settings: NSImage
    let onboarding: NSImage
    let glyph: NSImage?
    let grain: [NSImage]

    static func make(app: Bundle) async throws -> DemoAssets {
        let now = Date()
        let meeting = Occurrence(kind: .calendar, sourceID: "work", sourceName: "Work", providerID: "1", title: "Design review",
                                 links: ["https://zoom.us/j/1"], due: now + 300, end: now + 2100)
        let others = [
            Occurrence(kind: .calendar, sourceID: "work", sourceName: "Work", providerID: "2", title: "1:1 with Priya", links: ["https://meet.google.com/abc"], due: now + 5400, end: now + 7200),
            Occurrence(kind: .calendar, sourceID: "work", sourceName: "Work", providerID: "3", title: "Quarterly planning", due: now + 9000, end: now + 12600),
        ]
        let model = await makeModel(items: [meeting] + others, setUp: true)
        var p = model.preferences; p.sound = true; p.scareLevel = .high; model.updatePreferences(p)
        model.settingsTab = SettingsView.Tab.haunting.rawValue
        let fresh = await makeModel(items: [], setUp: false)
        let settings = snapshot(SettingsView(model: model, showsTest: false), size: CGSize(width: 560, height: 580))
        let onboarding = snapshot(OnboardingView(model: fresh, onFinish: {}), size: CGSize(width: 520, height: 640))
        let glyph = app.url(forResource: "GhostTemplate", withExtension: "pdf").flatMap(NSImage.init(contentsOf:))
        return DemoAssets(model: model, meeting: meeting, others: others, settings: settings,
                          onboarding: onboarding, glyph: glyph, grain: (0..<6).map(grainImage))
    }

    /// `setUp: false` is a first launch that has granted everything but not pressed Start yet.
    private static func makeModel(items: [Occurrence], setUp: Bool) async -> AppModel {
        let store = MemoryStore()
        store.db.preferences.alertsEnabled = setUp
        store.db.preferences.onboardingComplete = setUp
        store.db.preferences.selectedCalendars = ["work"]
        let source = FakeSource()
        let cals = [SourceSnapshot(id: "work", accountID: "", name: "Work", provider: "Google", kind: .calendar, writable: false),
                    SourceSnapshot(id: "home", accountID: "", name: "Family", provider: "iCloud", kind: .calendar, writable: false)]
        source.results[.calendar] = SourceResult(kind: .calendar, sources: cals, items: items)
        let notifications = FakeNotifications(); notifications.allowed = true
        let model = AppModel(store: store, source: source, notificationSink: notifications, presentationSink: FakePresenter(),
                             startServices: false, clock: SystemClock(), windowAccess: FakeWorkspaceAccess())
        await model.refreshNotificationStatus()
        await model.refresh(catchUp: false)
        return model
    }

    /// Renders a real app view at 2× so it stays sharp when the camera moves in.
    private static func snapshot<V: View>(_ view: V, size: CGSize?) -> NSImage {
        let host = NSHostingView(rootView: view.frame(width: size?.width, height: size?.height))
        let size = size ?? host.fittingSize
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -20000, y: -20000), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        let rep = capture(host, scale: 2)
        let image = NSImage(size: size); image.addRepresentation(rep)
        return image
    }

    private static func grainImage(_ seed: Int) -> NSImage {
        let w = 640, h = 360
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: w * 4, bitsPerPixel: 32)!
        let data = rep.bitmapData!
        for i in 0..<(w * h) {
            let v = UInt8(noise(seed * 1_000_003 + i) * 255)
            data[i * 4] = v; data[i * 4 + 1] = v; data[i * 4 + 2] = v; data[i * 4 + 3] = 255
        }
        let image = NSImage(size: CGSize(width: w, height: h)); image.addRepresentation(rep)
        return image
    }
}

@MainActor
private func capture(_ view: NSView, scale: CGFloat) -> NSBitmapImageRep {
    let size = view.bounds.size
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    view.cacheDisplay(in: view.bounds, to: rep)
    return rep
}

// MARK: - Video

@MainActor
enum DemoRenderer {
    static let size = CGSize(width: 1920, height: 1080)

    static func render(assets: DemoAssets, to url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width), AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 20_000_000, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel],
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width), kCVPixelBufferHeightKey as String: Int(size.height),
        ])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? DomainError.invalid("writer failed") }
        writer.startSession(atSourceTime: .zero)

        let host = NSHostingView(rootView: AnyView(EmptyView()))
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -20000, y: -20000), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        host.frame = CGRect(origin: .zero, size: size)

        let count = Int(DemoTime.length * Double(DemoTime.fps))
        for frame in 0..<count {
            let t = Double(frame) / Double(DemoTime.fps)
            host.rootView = AnyView(DemoFrame(t: t, frame: frame, assets: assets))
            host.layoutSubtreeIfNeeded()
            let rep = capture(host, scale: 1)
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            guard let pool = adaptor.pixelBufferPool, let image = rep.cgImage else { throw DomainError.invalid("no pixel buffer") }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer else { throw DomainError.invalid("no pixel buffer") }
            CVPixelBufferLockBaseAddress(buffer, [])
            let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: Int(size.width), height: Int(size.height),
                                    bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
            context?.draw(image, in: CGRect(origin: .zero, size: size))
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: DemoTime.fps))
        }
        input.markAsFinished()
        await writer.finishWriting()
        if writer.status != .completed { throw writer.error ?? DomainError.invalid("writer did not complete") }
    }
}

// MARK: - Audio

@MainActor
enum DemoAudio {
    /// `lead` is how far into the clip its peak sits; the clip starts that much early so the peak lands on the hit.
    struct Cue { let resource: String; let hit: Double; let lead: Double; let volume: Float; var fadeOut: (Double, Double)? = nil }
    static let cues: [Cue] = [
        Cue(resource: "haunt-basement", hit: DemoTime.knocks[0], lead: 0.38, volume: 0.85),   // knock
        Cue(resource: "haunt-basement", hit: DemoTime.knocks[1], lead: 0.38, volume: 0.85),
        Cue(resource: "haunt-basement", hit: DemoTime.crawl, lead: 0.38, volume: 0.9),
        Cue(resource: "haunt-deep", hit: DemoTime.scare, lead: 0.3, volume: 1.0),              // the High scare
        Cue(resource: "haunt-basement", hit: DemoTime.snooze, lead: 0.38, volume: 0.85),       // Snooze
        Cue(resource: "haunt-shatter", hit: DemoTime.dismiss, lead: 0.18, volume: 0.9),        // Dismiss
        Cue(resource: "haunt-scream", hit: DemoTime.stingHit, lead: 0, volume: 1.0, fadeOut: (35.7, 36.3)),
    ]

    static func mix(video: URL, music: URL, app: Bundle, to output: URL) async throws {
        let composition = AVMutableComposition()
        let videoAsset = AVURLAsset(url: video)
        let duration = try await videoAsset.load(.duration)
        guard let source = try await videoAsset.loadTracks(withMediaType: .video).first,
              let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw DomainError.invalid("no video track")
        }
        try videoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: source, at: .zero)

        var parameters: [AVMutableAudioMixInputParameters] = []
        func add(_ url: URL, at seconds: Double, volume: Float, shape: (AVMutableAudioMixInputParameters) -> Void = { _ in }) async throws {
            let asset = AVURLAsset(url: url)
            guard let audio = try await asset.loadTracks(withMediaType: .audio).first,
                  let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { return }
            let start = CMTime(seconds: seconds, preferredTimescale: 600)
            let natural = try await asset.load(.duration)
            let length = CMTimeMinimum(natural, duration - start)
            try track.insertTimeRange(CMTimeRange(start: .zero, duration: length), of: audio, at: start)
            let mix = AVMutableAudioMixInputParameters(track: track)
            mix.setVolume(volume, at: .zero)
            shape(mix)
            parameters.append(mix)
        }
        func range(_ a: Double, _ b: Double) -> CMTimeRange {
            CMTimeRange(start: CMTime(seconds: a, preferredTimescale: 600), end: CMTime(seconds: b, preferredTimescale: 600))
        }
        // The music ducks under the meeting scare so it punches through, then comes back.
        try await add(music, at: 0, volume: 0.95) { mix in
            mix.setVolumeRamp(fromStartVolume: 0.95, toEndVolume: 0.55, timeRange: range(DemoTime.scare + 0.1, DemoTime.scare + 0.3))
            mix.setVolumeRamp(fromStartVolume: 0.5, toEndVolume: 0.9, timeRange: range(DemoTime.scare + 1.2, DemoTime.scare + 2.4))
        }
        for cue in cues {
            guard let url = app.url(forResource: cue.resource, withExtension: "m4a") else { throw DomainError.invalid("missing \(cue.resource)") }
            try await add(url, at: cue.hit - cue.lead, volume: cue.volume) { mix in
                if let fade = cue.fadeOut { mix.setVolumeRamp(fromStartVolume: cue.volume, toEndVolume: 0, timeRange: range(fade.0, fade.1)) }
            }
        }
        let audioMix = AVMutableAudioMix(); audioMix.inputParameters = parameters
        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else { throw DomainError.invalid("no export session") }
        export.audioMix = audioMix
        guard #available(macOS 15, *) else { throw XCTSkip("Rendering the demo needs macOS 15") }
        try await export.export(to: output, as: .mp4)
    }
}

// MARK: - One frame

struct DemoFrame: View {
    let t: Double
    let frame: Int
    let assets: DemoAssets

    var body: some View {
        ZStack {
            Color.black
            if glitch > 0 {
                // A torn signal: horizontal bands of the picture jump sideways.
                ZStack {
                    ForEach(0..<12, id: \.self) { band in
                        stage.offset(shake).offset(x: tear(band))
                            .mask(Rectangle().frame(width: DemoRenderer.size.width, height: 90).position(x: 960, y: 45 + 90 * CGFloat(band)))
                    }
                }
            } else {
                stage.offset(shake)
            }
            Image(nsImage: assets.grain[frame % assets.grain.count]).resizable().interpolation(.none)
                .blendMode(.overlay).opacity(0.10)
            RadialGradient(colors: [.clear, .black.opacity(0.6)], center: .center, startRadius: 520, endRadius: 1250)
            AppStyle.poison.opacity(flash)
        }
        .frame(width: DemoRenderer.size.width, height: DemoRenderer.size.height)
        .clipped()
        .environment(\.colorScheme, .dark)
        .transaction { $0.disablesAnimations = true; $0.animation = nil }
    }

    @ViewBuilder private var stage: some View {
        if t < DemoTime.desktop { ColdOpen(t: t, frame: frame) }
        else if t < DemoTime.tour { DesktopAct(t: t, assets: assets) }
        else if t < DemoTime.dread { Tour(t: t, assets: assets) }
        else if t < DemoTime.scare { Dread(t: t, assets: assets) }
        else if t < DemoTime.title { Arrival(t: t, assets: assets) }
        else if t < DemoTime.sting { TitleCard(t: t, frame: frame) }
        else { Sting(t: t) }
    }
    private var flash: Double {
        DemoTime.flashes.map { t >= $0.at && t < $0.at + 0.07 ? $0.strength * (1 - (t - $0.at) / 0.07) : 0 }.max() ?? 0
    }
    /// How far a torn band jumps; about half the bands stay put.
    private func tear(_ band: Int) -> CGFloat {
        let pick = noise(frame * 31 + band)
        return pick < 0.45 ? 0 : CGFloat((noise(frame * 17 + band * 3) - 0.5) * 2 * 90 * glitch)
    }
    private var glitch: Double {
        var amount = DemoTime.glitches.map { t >= $0.at && t < $0.at + $0.length ? $0.amount * (1 - (t - $0.at) / $0.length) : 0 }.max() ?? 0
        // The lights fail while the meeting closes in.
        if t >= 23.4 && t < 24.9 && noise(frame * 5) > 0.84 { amount = max(amount, 0.6) }
        return amount
    }
    private var shake: CGSize {
        let amount = DemoTime.shakes.map { t >= $0.at && t < $0.at + $0.length ? $0.amount * (1 - (t - $0.at) / $0.length) : 0 }.max() ?? 0
        return CGSize(width: (noise(frame * 2) - 0.5) * 2 * amount, height: (noise(frame * 2 + 1) - 0.5) * 2 * amount)
    }
}

private struct Caption: View {
    let label: String
    let line: String
    let alpha: Double
    var top = false
    var body: some View {
        ZStack(alignment: top ? .topLeading : .bottomLeading) {
            LinearGradient(colors: [.black.opacity(0.75), .clear], startPoint: top ? .top : .bottom, endPoint: top ? .bottom : .top)
                .frame(height: 460).frame(maxHeight: .infinity, alignment: top ? .top : .bottom)
            VStack(alignment: .leading, spacing: 12) {
                Text(label).font(AppStyle.signal(17)).tracking(5).foregroundStyle(AppStyle.accent)
                Text(line).font(AppStyle.display(52)).foregroundStyle(AppStyle.ink).fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 660, alignment: .leading)
            .shadow(color: .black.opacity(0.9), radius: 18)
            .offset(y: (1 - alpha) * (top ? -14 : 14))
            .padding(.horizontal, 110).padding(.vertical, top ? 100 : 92)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: top ? .topLeading : .bottomLeading)
        .opacity(alpha)
    }
}

// MARK: Act 1: cold open

private struct ColdOpen: View {
    let t: Double
    let frame: Int
    private var lines: [(at: Double, until: Double, text: String)] {
        [(0.05, 1.05, "You have a meeting."), (1.1, 2.05, "You forgot."), (2.1, 3.95, "She didn’t.")]
    }
    var body: some View {
        ZStack {
            Color.black
            // A glimpse of her in the dark as the last line lands.
            StandingGhost().frame(height: 900).offset(x: 560, y: 60)
                .opacity(t >= 2.1 && t < 2.75 ? (noise(frame) > 0.35 ? 0.28 : 0.05) : 0)
            // One subliminal frame of the face.
            CloseupGhost().frame(width: 1100, height: 1100).opacity(t >= 3.6 && t < 3.67 ? 0.3 : 0)
            ForEach(lines.indices, id: \.self) { i in
                let line = lines[i]
                let on = t >= line.at && t < line.until
                let settle = t - line.at
                Text(line.text).font(AppStyle.display(96)).foregroundStyle(AppStyle.ink)
                    .scaleEffect(1 + 0.03 * ramp(t, line.at, line.until))
                    .opacity(on ? (settle < 0.18 ? (noise(frame + i * 7) > 0.4 ? 1 : 0.2) : 1) * (1 - ramp(t, line.until - 0.15, line.until)) : 0)
            }
        }
    }
}

// MARK: Act 2: the desktop, the dash, the early warning

private struct DesktopAct: View {
    let t: Double
    let assets: DemoAssets
    private var minimized: Double {
        if t >= DemoTime.crawl { return 1 }
        if t >= 14.15 { return 1 - easeOut(ramp(t, 14.15, 14.6)) }
        return easeIn(ramp(t, DemoTime.prelude, DemoTime.prelude + 0.45))
    }
    var body: some View {
        ZStack {
            FakeDesktop(minimized: minimized, menuTitle: "Design review · 5m", alarm: 0, assets: assets,
                        glimpse: t >= 6.3 && t < 6.42 ? 0.5 : 0)
            overlay
            Caption(label: "DREADLINE", line: "It lives in your menu bar.", alpha: window(t, 4.3, 5.15))
            Caption(label: "IT WATCHES", line: "Every meeting on your calendar.", alpha: window(t, 5.25, 7.55))
            Caption(label: "10 SECONDS BEFORE", line: "Something passes by.", alpha: window(t, 7.7, 8.95))
            Caption(label: "5 MINUTES BEFORE", line: "The early warning. Your windows vanish.", alpha: window(t, 9.0, 13.7))
            Caption(label: "OR FROM BELOW", line: "She always finds a way in.", alpha: window(t, 14.8, 16.45), top: true)
        }
    }

    @ViewBuilder private var overlay: some View {
        let due = Date().addingTimeInterval(300 - max(0, t - DemoTime.prelude))
        let item = { var m = assets.meeting; m.due = due; return m }()
        if t >= DemoTime.dash && t < DemoTime.prelude {
            OverlayView(model: assets.model, presentation: Presentation(items: [item], intensity: .gentle, catchUp: false, phase: .dash),
                        demo: false, redact: true, scene: Self.dash(t))
        } else if t >= DemoTime.prelude && t < 14.15 {
            OverlayView(model: assets.model, presentation: Presentation(items: [item], intensity: .gentle, catchUp: false, phase: .prelude),
                        demo: false, redact: true, scene: Self.above(t))
        } else if t >= DemoTime.crawl {
            OverlayView(model: assets.model, presentation: Presentation(items: [item], intensity: .gentle, catchUp: false, phase: .prelude),
                        demo: false, redact: true, scene: Self.below(t))
        }
    }

    @MainActor static func dash(_ t: Double) -> HauntScene {
        let scene = HauntScene(entrance: .below, fromLeft: true)
        scene.stage = .dash
        scene.dashProgress = easeIn(ramp(t, DemoTime.dash + 0.06, DemoTime.dash + 0.61))
        return scene
    }
    /// The real prelude choreography (HauntScene.prelude), retimed so the knocks land on the music.
    @MainActor static func above(_ t: Double) -> HauntScene {
        let scene = HauntScene(entrance: .above, fromLeft: true)
        let k1 = DemoTime.knocks[0], k2 = DemoTime.knocks[1], jolt = 12.6, out = 13.7
        var peek = spring(t - k1, response: 0.75, damping: 0.68)
        if t >= k2 { peek = 1 - 0.14 * easeInOut(ramp(t, k2, k2 + 0.18)) }
        if t >= jolt { peek = 0.86 + 0.18 * spring(t - jolt, response: 0.3, damping: 0.6) }
        let leave = easeIn(ramp(t, out, out + 0.45))
        var dark = 0.45 * easeOut(ramp(t, k1, k1 + 0.4))
        if t >= k2 { dark = 0.45 + 0.1 * easeOut(ramp(t, k2, k2 + 0.3)) }
        scene.stage = .peek
        scene.peek = peek * (1 - leave)
        scene.darkness = dark * (1 - leave)
        scene.scratchProgress = [easeOut(ramp(t, k1, k1 + 0.4)) * (1 - leave), easeOut(ramp(t, k2, k2 + 0.3)) * (1 - leave), 0]
        scene.knockCount = leave > 0.6 ? 0 : (t >= k2 ? 2 : (t >= k1 ? 1 : 0))
        return scene
    }
    @MainActor static func below(_ t: Double) -> HauntScene {
        let scene = HauntScene(entrance: .below, fromLeft: false)
        let a = DemoTime.crawl, out = 16.0
        let leave = easeIn(ramp(t, out, out + 0.45))
        scene.stage = .peek
        scene.peek = spring(t - a, response: 0.45, damping: 0.55) * (1 - leave)
        scene.darkness = 0.6 * (1 - leave)
        scene.scratchProgress = [0, 0, easeOut(ramp(t, a, a + 0.35)) * (1 - leave)]
        scene.knockCount = leave > 0.6 ? 0 : (t >= a + 0.7 ? 2 : 1)
        return scene
    }
}

// MARK: Act 3: the feature tour

private struct Tour: View {
    let t: Double
    let assets: DemoAssets
    private struct Beat { let start: Double; let end: Double; let label: String; let line: String }
    private let beats = [
        Beat(start: DemoTime.tour, end: 17.8, label: "FULL SCREEN", line: "She takes over everything."),
        Beat(start: 17.8, end: 20.0, label: "SCARE LEVEL", line: "Low. Medium. High.\nHigh is not a joke."),
        Beat(start: 20.0, end: 21.0, label: "FOUR PERMISSIONS", line: "Nothing leaves your Mac."),
        Beat(start: DemoTime.snooze, end: DemoTime.dread, label: "SNOOZE", line: "She always comes back."),
    ]
    var body: some View {
        let index = beats.lastIndex { t >= $0.start } ?? 0
        let beat = beats[index]
        let progress = ramp(t, beat.start, beat.end)
        if index == beats.count - 1 { SnoozeBeat(t: t, assets: assets, label: beat.label, line: beat.line) }
        else { ZStack {
            Color.black
            RadialGradient(colors: [AppStyle.accent.opacity(0.10), .clear], center: UnitPoint(x: 0.33, y: 0.5), startRadius: 0, endRadius: 900)
            StandingGhost().frame(height: 980).offset(x: 700, y: 120).opacity(0.10)
            card(index)
                .scaleEffect(1.04 - 0.04 * progress)
                .opacity(ramp(t, beat.start, beat.start + 0.1) * (index == beats.count - 1 ? 1 - ramp(t, 22.7, DemoTime.dread) : 1))
                .position(x: 660, y: 540)
            VStack(alignment: .leading, spacing: 14) {
                Text(beat.label).font(AppStyle.signal(18)).tracking(5).foregroundStyle(AppStyle.accent)
                Text(beat.line).font(AppStyle.display(58)).foregroundStyle(AppStyle.ink).fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 640, alignment: .leading)
            .opacity(ramp(t, beat.start + 0.05, beat.start + 0.3) * (index == beats.count - 1 ? 1 - ramp(t, 22.7, DemoTime.dread) : 1))
            .offset(y: (1 - ramp(t, beat.start + 0.05, beat.start + 0.3)) * 16)
            .position(x: 1490, y: 540)
        } }
    }
    @ViewBuilder private func card(_ index: Int) -> some View {
        switch index {
        case 0: framed(Image(nsImage: assets.settings).resizable().frame(width: 560 * 1.32, height: 580 * 1.32))
        // The camera moves in on the Sound card, where the scare level lives.
        case 1:
            // Moves in on the scare level row, keeping the High segment in view, and rings it.
            let w = 560 * 1.32, h = 580 * 1.32, row = 0.712
            framed(ZStack {
                Image(nsImage: assets.settings).resizable().frame(width: w, height: h)
                    .scaleEffect(1.45, anchor: UnitPoint(x: 0.95, y: row))
                RoundedRectangle(cornerRadius: 12).stroke(AppStyle.accent, lineWidth: 3)
                    .frame(width: w - 36, height: 104)
                    .shadow(color: AppStyle.accent.opacity(0.8), radius: 14)
                    .position(x: w / 2, y: h * row)
                    .opacity(ramp(t, 18.1, 18.35))
            }.frame(width: w, height: h).clipped())
        default: framed(Image(nsImage: assets.onboarding).resizable().frame(width: 520 * 1.2, height: 640 * 1.2))
        }
    }
    private func framed<V: View>(_ view: V) -> some View {
        view.clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppStyle.border, lineWidth: 1.5))
            .shadow(color: AppStyle.accent.opacity(0.18), radius: 60)
    }
}

/// The real Snooze warning (HauntScene.warn(.snooze)): the room flickers like a failing light and she flickers with it.
private struct SnoozeBeat: View {
    let t: Double
    let assets: DemoAssets
    let label: String
    let line: String
    var body: some View {
        ZStack {
            Color.black
            OverlayView(model: assets.model, presentation: Presentation(items: [assets.meeting], intensity: .fullscreen, catchUp: false, phase: .reminder),
                        demo: false, redact: true, scene: Self.scene(t))
            Caption(label: label, line: line, alpha: window(t, DemoTime.snooze + 0.3, DemoTime.dread - 0.1), top: true)
        }
        .opacity(1 - ramp(t, DemoTime.dread - 0.3, DemoTime.dread))
    }
    @MainActor static func scene(_ t: Double) -> HauntScene {
        let s = HauntScene(entrance: .above, fromLeft: true)
        let dt = t - DemoTime.snooze
        s.stage = .warning
        s.warning = HauntScene.snoozeLines[1]
        s.warningKind = .snooze
        s.ghostRest = 0
        s.ghostOpacity = 0.9 * easeOut(ramp(dt, 0, 0.3))
        // The same failing-light pattern as the app: changes at least 330 ms apart.
        let pattern: [(Double, Double)] = [(0, 1), (0.15, 1), (0.5, 0), (0.85, 0.92), (1.2, 0.1), (1.55, 1), (1.9, 0)]
        let lit = pattern.last { dt >= $0.0 }?.1 ?? 1
        s.darkness = lit; s.flicker = lit
        return s
    }
}

// MARK: Act 4: the dread, the scare, the dismiss

private struct Dread: View {
    let t: Double
    let assets: DemoAssets
    /// The room's light gives out for a frame here and there.
    private var lightsOut: Double {
        let frame = Int(t * Double(DemoTime.fps))
        return t >= 23.4 && noise(frame * 7 + 3) > 0.82 ? 0.7 : 0
    }
    var body: some View {
        let pulse = 0.5 + 0.5 * sin(t * 9)
        let time = (assets.meeting.due ?? Date()).formatted(date: .omitted, time: .shortened).uppercased()
        ZStack {
            FakeDesktop(minimized: easeIn(ramp(t, 24.3, 24.75)), menuTitle: "Design review · now", alarm: pulse, assets: assets,
                        glimpse: t >= 24.0 && t < 24.12 ? 0.75 : 0)
                .scaleEffect(1 + 0.05 * ramp(t, DemoTime.dread, DemoTime.scare), anchor: UnitPoint(x: 0.66, y: 0.52))
            Color.black.opacity(0.3 * ramp(t, DemoTime.dread, 24.3) + easeIn(ramp(t, 24.55, 24.95)) + lightsOut)
            Caption(label: time, line: "Your meeting is starting.", alpha: window(t, 23.25, 24.45))
        }
    }
}

private struct Arrival: View {
    let t: Double
    let assets: DemoAssets
    var body: some View {
        ZStack {
            Color.black
            OverlayView(model: assets.model, presentation: Presentation(items: [assets.meeting], intensity: .fullscreen, catchUp: false, phase: .reminder),
                        demo: false, redact: true, scene: Self.scene(t))
            Caption(label: "AT MEETING TIME", line: "Join, snooze, or dismiss. Choose wisely.", alpha: window(t, 27.75, DemoTime.dismiss - 0.05))
            Color.black.opacity(easeIn(ramp(t, 30.55, DemoTime.title)))
        }
    }

    /// The real arrival and Dismiss choreography (HauntScene.arrival / warn), retimed to the music.
    @MainActor static func scene(_ t: Double) -> HauntScene {
        let s = HauntScene(entrance: .above, fromLeft: true)
        let a = DemoTime.scare, linger = DemoTime.linger, card = DemoTime.card, dismiss = DemoTime.dismiss
        s.darkness = 1
        s.ghostRest = 0
        if t < dismiss {
            s.stage = t < linger ? .shock : (t < card + 1 ? .lingering : .manifest)
            let pop = spring(t - a, response: 0.14, damping: 0.35)
            s.shake = t < a + 0.4 ? pop : 1 - spring(t - a - 0.4, response: 0.16, damping: 0.3)
            let fade = easeOut(ramp(t, linger, linger + 0.4))
            s.closeupOpacity = 1 - fade
            s.closeupScale = 1.12 - 0.12 * pop - 0.1 * fade
            let rest = easeInOut(ramp(t, card, card + 0.9))
            s.cardDrop = spring(t - card, response: 0.7, damping: 0.74)
            s.ghostRest = rest
            s.ghostOpacity = fade * (1 - 0.45 * rest)
        } else {
            s.stage = .warning
            s.warning = HauntScene.dismissLines[0]
            s.warningKind = .dismiss
            s.cardDrop = 1 - easeIn(ramp(t, dismiss, dismiss + 0.3))
            s.ghostRest = 1
            s.ghostOpacity = 0
            s.closeupOpacity = 1
            let pop = spring(t - dismiss, response: 0.18, damping: 0.4)
            s.closeupScale = 0.7 + 0.35 * pop
            s.shake = t < dismiss + 0.38 ? pop : 1 - spring(t - dismiss - 0.38, response: 0.16, damping: 0.3)
        }
        return s
    }
}

// MARK: Act 5: title and the last scare

private struct TitleCard: View {
    let t: Double
    let frame: Int
    var body: some View {
        let a = DemoTime.title
        let flicker = t < a + 0.4 ? (noise(frame * 3) > 0.45 ? 1.0 : 0.15) : 1.0
        ZStack {
            Color.black
            RadialGradient(colors: [AppStyle.accent.opacity(0.12), .clear], center: .center, startRadius: 0, endRadius: 700)
            StandingGhost().frame(height: 980).offset(y: 70).opacity(0.16 * ramp(t, a, a + 0.6))
            VStack(spacing: 26) {
                Text("DREADLINE").font(AppStyle.display(150)).tracking(10).foregroundStyle(AppStyle.ink)
                    .shadow(color: AppStyle.accent.opacity(0.35), radius: 30).opacity(flicker)
                Text("The calendar that haunts you.").font(AppStyle.display(44)).foregroundStyle(AppStyle.muted)
                    .opacity(ramp(t, a + 0.7, a + 1.0))
                Text("NEVER MISS A MEETING AGAIN").font(AppStyle.signal(22)).tracking(9).foregroundStyle(AppStyle.accent)
                    .opacity(ramp(t, a + 1.4, a + 1.7))
            }
        }
        .opacity(1 - ramp(t, DemoTime.sting - 0.3, DemoTime.sting))
    }
}

private struct Sting: View {
    let t: Double
    var body: some View {
        let hit = DemoTime.stingHit
        ZStack {
            Color.black
            Text("See you at your next meeting.").font(AppStyle.display(46)).foregroundStyle(AppStyle.ink.opacity(0.85))
                .opacity(t < hit ? ramp(t, 33.8, 34.3) : 0)
            if t >= hit && t < hit + 1.0 {
                CloseupGhost(screaming: true).frame(width: 1150, height: 1150)
                    .scaleEffect(1.3 - 0.3 * spring(t - hit, response: 0.14, damping: 0.35))
            }
        }
    }
}

// MARK: - The staged desktop

private struct FakeDesktop: View {
    let minimized: Double
    let menuTitle: String
    /// 0…1 glow on the meeting in the calendar window.
    let alarm: Double
    let assets: DemoAssets
    /// Opacity of her, standing between the windows for a few frames.
    var glimpse: Double = 0
    private let dock = CGPoint(x: 1240, y: 1030)
    var body: some View {
        ZStack(alignment: .topLeading) {
            Wallpaper()
            minimizing(DesktopWindow(title: "Q4 Roadmap") { NotesContent() }, size: CGSize(width: 900, height: 620),
                       center: CGPoint(x: 640, y: 470), progress: minimized)
            minimizing(DesktopWindow(title: "Calendar") { CalendarContent(assets: assets, alarm: alarm) }, size: CGSize(width: 760, height: 600),
                       center: CGPoint(x: 1260, y: 560), progress: clamp((minimized - 0.12) / 0.88))
            if glimpse > 0 {
                StandingGhost().frame(height: 980).position(x: 1180, y: 600).opacity(glimpse)
                    .shadow(color: AppStyle.poison.opacity(0.3), radius: 30)
            }
            Dock().position(x: 960, y: 1080 - 58)
            MenuBar(title: menuTitle, glyph: assets.glyph)
        }
        .frame(width: 1920, height: 1080)
    }
    /// A quick genie: the window shrinks into the dock.
    private func minimizing<V: View>(_ view: V, size: CGSize, center: CGPoint, progress: Double) -> some View {
        let e = easeIn(progress)
        return view.frame(width: size.width, height: size.height)
            .scaleEffect(1 - 0.93 * e)
            .opacity(1 - ramp(e, 0.75, 1))
            .position(x: center.x + (dock.x - center.x) * e, y: center.y + (dock.y - center.y) * e)
    }
}

private struct Wallpaper: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.03, green: 0.05, blue: 0.09), Color(red: 0.01, green: 0.015, blue: 0.03)], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color(red: 0.12, green: 0.26, blue: 0.36).opacity(0.55), .clear], center: UnitPoint(x: 0.2, y: 0.85), startRadius: 0, endRadius: 950)
            RadialGradient(colors: [Color(red: 0.26, green: 0.16, blue: 0.36).opacity(0.35), .clear], center: UnitPoint(x: 0.85, y: 0.18), startRadius: 0, endRadius: 820)
            Ridge(seed: 1, base: 0.70, height: 0.12).fill(Color(red: 0.02, green: 0.03, blue: 0.05).opacity(0.85))
            Ridge(seed: 2, base: 0.80, height: 0.09).fill(Color.black.opacity(0.9))
        }
    }
}
private struct Ridge: Shape {
    let seed: Double
    let base: Double
    let height: Double
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.height))
        for i in 0...96 {
            let x = Double(i) / 96
            let y = base - height * (0.55 * sin(x * 7 + seed) + 0.3 * sin(x * 17 + seed * 3) + 0.15 * sin(x * 41 + seed * 5) + 0.5) / 1.5
            path.addLine(to: CGPoint(x: rect.width * x, y: rect.height * y))
        }
        path.addLine(to: CGPoint(x: rect.width, y: rect.height))
        path.closeSubpath()
        return path
    }
}

private struct MenuBar: View {
    let title: String
    let glyph: NSImage?
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.45).frame(height: 34)
            HStack(spacing: 24) {
                Text("Notes").fontWeight(.bold)
                Text("File"); Text("Edit"); Text("Format"); Text("View"); Text("Window")
            }
            .padding(.leading, 26).frame(height: 34)
            HStack(spacing: 7) {
                if let glyph { Image(nsImage: glyph).renderingMode(.template).resizable().frame(width: 19, height: 19) }
                Text(title)
            }
            .frame(width: 250, height: 34, alignment: .leading).offset(x: 1460)
            Text(Date().formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()))
                .frame(width: 220, height: 34, alignment: .trailing).offset(x: 1920 - 22 - 220)
        }
        .font(.system(size: 14, weight: .medium)).foregroundStyle(.white.opacity(0.92))
        .frame(width: 1920, height: 34, alignment: .topLeading)
    }
}

private struct Dock: View {
    private let colors: [Color] = [
        Color(red: 0.25, green: 0.55, blue: 0.95), Color(red: 0.95, green: 0.75, blue: 0.25), Color(red: 0.35, green: 0.8, blue: 0.45),
        Color(red: 0.9, green: 0.35, blue: 0.35), Color(red: 0.6, green: 0.45, blue: 0.95), Color(red: 0.3, green: 0.3, blue: 0.34),
        Color(red: 0.95, green: 0.95, blue: 0.97),
    ]
    var body: some View {
        HStack(spacing: 14) {
            ForEach(colors.indices, id: \.self) { i in
                RoundedRectangle(cornerRadius: 15).fill(LinearGradient(colors: [colors[i], colors[i].opacity(0.7)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 66, height: 66)
            }
            Rectangle().fill(Color.white.opacity(0.2)).frame(width: 1, height: 56)
            RoundedRectangle(cornerRadius: 15).fill(Color.white.opacity(0.08)).frame(width: 66, height: 66)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 24).fill(Color.white.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.white.opacity(0.14), lineWidth: 1))
    }
}

private struct DesktopWindow<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(Color(red: 1, green: 0.37, blue: 0.34)).frame(width: 13, height: 13)
                Circle().fill(Color(red: 1, green: 0.74, blue: 0.18)).frame(width: 13, height: 13)
                Circle().fill(Color(red: 0.16, green: 0.79, blue: 0.25)).frame(width: 13, height: 13)
                Spacer()
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white.opacity(0.7))
                Spacer()
                Color.clear.frame(width: 55, height: 1)
            }
            .padding(.horizontal, 16).frame(height: 42).background(Color(white: 0.17))
            content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(Color(white: 0.105))
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.6), radius: 34, y: 18)
    }
}

private struct NotesContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Q4 Roadmap").font(.system(size: 34, weight: .bold)).foregroundStyle(.white.opacity(0.92))
            Text("Edited just now").font(.system(size: 14)).foregroundStyle(.white.opacity(0.4))
            VStack(alignment: .leading, spacing: 13) {
                ForEach(["Ship the new onboarding flow", "Calendar sync: handle declined invites", "Pricing page copy, round two",
                         "Prep slides for today's design review", "Hire two more engineers"], id: \.self) { item in
                    HStack(alignment: .top, spacing: 12) {
                        Circle().fill(.white.opacity(0.5)).frame(width: 7, height: 7).padding(.top, 8)
                        Text(item).font(.system(size: 19)).foregroundStyle(.white.opacity(0.82))
                    }
                }
            }.padding(.top, 8)
            Text("Notes from Tuesday: the team agreed to keep scope tight and revisit the timeline after the review. Bring the latest mocks and the open questions list.")
                .font(.system(size: 17)).foregroundStyle(.white.opacity(0.5)).lineSpacing(5).padding(.top, 10)
        }.padding(40)
    }
}

private struct CalendarContent: View {
    let assets: DemoAssets
    let alarm: Double
    private let row: CGFloat = 76
    var body: some View {
        let due = assets.meeting.due ?? Date()
        let calendar = Calendar.current
        let first = calendar.date(bySettingHour: max(0, calendar.component(.hour, from: due) - 2), minute: 0, second: 0, of: due) ?? due
        let y: (Date) -> CGFloat = { CGFloat($0.timeIntervalSince(first) / 3600) * row }
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Today").font(.system(size: 26, weight: .bold)).foregroundStyle(.white.opacity(0.92))
                Text(due.formatted(.dateTime.weekday(.wide).day().month(.wide))).font(.system(size: 16)).foregroundStyle(.white.opacity(0.45))
            }.padding(.horizontal, 28).padding(.vertical, 22)
            ZStack(alignment: .topLeading) {
                ForEach(0..<7, id: \.self) { h in
                    let hour = first.addingTimeInterval(Double(h) * 3600)
                    HStack(spacing: 12) {
                        Text(hour.formatted(.dateTime.hour())).font(.system(size: 13)).foregroundStyle(.white.opacity(0.4)).frame(width: 56, alignment: .trailing)
                        Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
                    }.offset(y: CGFloat(h) * row)
                }
                event("Team standup", start: first.addingTimeInterval(1800), minutes: 30, color: Color(red: 0.6, green: 0.45, blue: 0.95), y: y)
                event(assets.meeting.title, start: due, minutes: 30, color: alarm > 0 ? AppStyle.blood : AppStyle.accent, y: y, glow: alarm)
                if let next = assets.others.first, let start = next.due { event(next.title, start: start, minutes: 30, color: Color(red: 0.35, green: 0.8, blue: 0.45), y: y) }
            }.padding(.leading, 20).padding(.trailing, 28).padding(.top, 6)
        }
    }
    private func event(_ title: String, start: Date, minutes: Double, color: Color, y: (Date) -> CGFloat, glow: Double = 0) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white.opacity(0.95))
            Text(start.formatted(date: .omitted, time: .shortened)).font(.system(size: 13)).foregroundStyle(.white.opacity(0.6))
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .frame(width: 560, height: CGFloat(minutes / 60) * row + 14, alignment: .topLeading)
        .background(color.opacity(0.28 + 0.3 * glow), in: RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 4) }
        .shadow(color: color.opacity(0.6 * glow), radius: 22)
        .offset(x: 68, y: y(start))
    }
}
