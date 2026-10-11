import XCTest
import AppKit
@testable import FrameBar

final class PerformanceStatsTests: XCTestCase {
    @MainActor func testShortcutOnlyMatchesItsExactChord() {
        func event(_ flags: NSEvent.ModifierFlags, key: UInt16 = 31) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                             windowNumber: 0, context: nil, characters: "o", charactersIgnoringModifiers: "o",
                             isARepeat: false, keyCode: key)!
        }
        XCTAssertTrue(OverlayShortcut.matches(event([.command, .option, .control])))
        XCTAssertFalse(OverlayShortcut.matches(event([.command, .option])))
        XCTAssertFalse(OverlayShortcut.matches(event([.command, .option, .control, .shift])))
        XCTAssertFalse(OverlayShortcut.matches(event([.command, .option, .control], key: 0)))
    }
    func testLowsUseSlowestFrameDurationsAndDoNotInventSmallSampleLows() {
        let frames = Array(repeating: 10.0, count: 990) + Array(repeating: 20.0, count: 9) + [100.0]
        let report = FrameTimingReport(milliseconds: frames, name: "client")!
        XCTAssertEqual(report.averageFPS, 1000 / 10.18, accuracy: 0.0001)
        XCTAssertEqual(report.onePercentLow!, 1000 / 28, accuracy: 0.0001)
        XCTAssertEqual(report.pointOnePercentLow, 10)
        XCTAssertEqual(report.p99MS, 10)
        XCTAssertEqual(report.worstMS, 100)
        XCTAssertEqual(report.over33MS, 1)
        let short = FrameTimingReport(milliseconds: [8, 16], name: "short")!
        XCTAssertNil(short.onePercentLow)
        XCTAssertNil(short.pointOnePercentLow)
        XCTAssertNil(FrameTimingReport(milliseconds: [10, .nan], name: "invalid"))
        XCTAssertNil(FrameTimingReport(milliseconds: [10, 0], name: "invalid"))
    }

    func testImporterAcceptsLiteralContiguousFramesAndRejectsSampledFPS() {
        let dump = "Frames[0] = MakeFrame(0, 100.0, 108.0, ts0, tt0, ti0);\nFrames[1] = MakeFrame(0, 108.0, 124.0, ts1, tt1, ti1);"
        XCTAssertEqual(FrameTimingImport.parse(dump, name: "dump")?.count, 2)
        XCTAssertEqual(FrameTimingImport.parse(dump, name: "dump")?.worstMS, 16)
        XCTAssertNil(FrameTimingImport.parse(dump.replacingOccurrences(of: "Frames[1]", with: "Frames[0]"), name: "duplicate"))
        XCTAssertNil(FrameTimingImport.parse(dump.replacingOccurrences(of: "108.0, 124.0", with: "110.0, 124.0"), name: "gap"))
        XCTAssertEqual(FrameTimingImport.parse("frame,frame_ms\n0,8.0\n1,12.0\n", name: "csv")?.averageFPS, 100)
        XCTAssertNil(FrameTimingImport.parse("timestamp,roblox_stats_fps\n0,120\n1,60", name: "samples"))
        XCTAssertNil(FrameTimingImport.parse("frame_ms\n8\nwrong", name: "bad"))
    }

    func testSessionCountsIndependentReadsOnly() {
        var session = SessionSummary()
        var metrics = Metrics(); metrics.gameFPS = 60; metrics.robloxMemory = 2
        for _ in 0..<10 { session.recordHardware(metrics) }
        session.recordFPS(60); session.recordFPS(nil); session.recordFPS(120)
        XCTAssertEqual(session.hardwareSamples, 10)
        XCTAssertEqual(session.fpsSamples, 2)
        XCTAssertEqual(session.averageFPS, 90)
        XCTAssertEqual(session.peakMemory, 2)
    }

    func testMixedRowsAndRenderRatesDoNotReadPhysicsAsFPS() {
        XCTAssertEqual(FPSParser.parse(["Render: 143.2/s Physics: 60/s Network: 30/s"]), 143.2)
        XCTAssertEqual(FPSParser.parse(["Render: 120 FPS Physics: 60 FPS"]), 120)
        XCTAssertNil(FPSParser.parse(["Physics: 60/s", "Network: 120/s"]))
        XCTAssertEqual(FPSParser.milliseconds(label: "Ping", lines: ["CPU 4.1 ms GPU 5.2 ms Ping 42 ms"]), 42)
        XCTAssertNil(FPSParser.milliseconds(label: "Ping", lines: ["CPU 42 ms"]))
    }

    @MainActor func testOverlaySelectionPersistsAndCannotBecomeEmpty() {
        let suite = "FrameBarTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let prefs = Preferences(defaults: defaults)
        prefs.overlayMetrics = [.fps]
        prefs.setOverlayMetric(.fps, enabled: false)
        XCTAssertEqual(prefs.overlayMetrics, [.fps])
        prefs.setOverlayMetric(.ping, enabled: true)
        prefs.shortcutEnabled = false
        XCTAssertEqual(Preferences(defaults: defaults).overlayMetrics, [.fps, .ping])
        XCTAssertFalse(Preferences(defaults: defaults).shortcutEnabled)
        XCTAssertLessThan(GameOverlayView.width(preferences: prefs), 266)
    }
}
