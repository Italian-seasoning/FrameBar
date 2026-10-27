import XCTest
@testable import FrameBar

final class ProfileTests: XCTestCase {
    @MainActor func testProfilesRestoreCustomAndPreservePlacementAndMenu() {
        let name = "FrameBarProfiles-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = Preferences(defaults: defaults)
        preferences.overlayPosition = CGPoint(x: 0.3, y: 0.7)
        preferences.menuMetrics = [.gpu]
        preferences.opacity = 0.8
        preferences.overlayMetrics = [.fps, .gpu]
        preferences.applyProfile(.quiet)
        XCTAssertEqual(preferences.profile, .quiet)
        XCTAssertFalse(preferences.readGameFPS)
        XCTAssertFalse(preferences.readDesktopFPS)
        XCTAssertEqual(preferences.interval, 2)
        preferences.applyProfile(.debug)
        XCTAssertEqual(preferences.profile, .debug)
        XCTAssertTrue(preferences.lowPower)
        XCTAssertTrue(preferences.overlayMetrics.contains(.cpuTime))
        preferences.applyProfile(.recording)
        XCTAssertEqual(preferences.profile, .recording)
        XCTAssertTrue(preferences.overlayMetrics.contains(.recording))
        preferences.applyProfile(.custom)
        XCTAssertEqual(preferences.overlayMetrics, [.fps, .gpu])
        XCTAssertEqual(preferences.interval, 1)
        XCTAssertTrue(preferences.readDesktopFPS)
        XCTAssertEqual(preferences.profile, .custom)
        XCTAssertEqual(preferences.overlayPosition, CGPoint(x: 0.3, y: 0.7))
        XCTAssertEqual(preferences.menuMetrics, [.gpu])
        XCTAssertEqual(preferences.opacity, 0.8)
        preferences.applyProfile(.quiet)
        let reloaded = Preferences(defaults: defaults)
        XCTAssertEqual(reloaded.profile, .quiet)
        reloaded.applyProfile(.custom)
        XCTAssertEqual(reloaded.overlayMetrics, [.fps, .gpu])
    }

    func testReadinessAppearsOnlyInForegroundGameAndReportsMissingStats() {
        var metrics = Metrics()
        metrics.capturelyRecording = true
        XCTAssertNil(RecordingReadiness.status(metrics: metrics, readerEnabled: true, permission: false))
        metrics.robloxActive = true
        XCTAssertEqual(RecordingReadiness.status(metrics: metrics, readerEnabled: true, permission: false)?.text,
                       "Enable FPS screen access")
        XCTAssertEqual(RecordingReadiness.status(metrics: metrics, readerEnabled: true, permission: true)?.text,
                       "Recording · FPS unavailable")
        metrics.gameFPS = 120
        XCTAssertEqual(RecordingReadiness.status(metrics: metrics, readerEnabled: true, permission: true)?.needsAction, false)
        metrics.capturelyRecording = false
        XCTAssertNil(RecordingReadiness.status(metrics: metrics, readerEnabled: true, permission: true))
        XCTAssertNil(RecordingReadiness.status(metrics: metrics, readerEnabled: false, permission: false))
    }

    @MainActor func testPanelReservesSpaceForReadiness() {
        var metrics = Metrics()
        XCTAssertEqual(MonitorView.panelHeight(metrics: metrics, readerEnabled: true, permission: false), 198)
        metrics.robloxRunning = true
        metrics.robloxActive = true
        XCTAssertEqual(MonitorView.panelHeight(metrics: metrics, readerEnabled: true, permission: false), 238)
        metrics.gameFPS = 120
        XCTAssertEqual(MonitorView.panelHeight(metrics: metrics, readerEnabled: true, permission: true), 218)
    }
}
