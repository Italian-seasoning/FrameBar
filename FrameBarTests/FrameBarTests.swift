import XCTest
@testable import FrameBar

final class FrameBarTests: XCTestCase {
    func testRAMAndSwapStack() {
        var metrics = Metrics()
        metrics.memoryUsed = 8
        metrics.swapUsed = 1.5
        XCTAssertEqual(MenuBarText.rows(metrics: metrics, selected: [.ram, .swap], layout: .stacked, labels: true),
                       ["RAM 8.0G", "Swap 1.5G"])
        metrics.swapUsed = nil
        XCTAssertEqual(MenuBarMetric.swap.reading(metrics, labels: false), "—G")
        let swap = SystemSampler().sample(pid: nil).swapUsed
        XCTAssertNotNil(swap)
        XCTAssertGreaterThanOrEqual(swap ?? -1, 0)
    }

    func testFPSFormatsAndDecimals() {
        XCTAssertEqual(FPSParser.parse(["Render: 144.8 FPS"]), 144.8)
        XCTAssertEqual(FPSParser.parse(["FPS: 60"]), 60)
        XCTAssertEqual(FPSParser.parse(["Render FPS = 59,95"]), 59.95)
        XCTAssertEqual(FPSParser.parse(["Render", "143.2 FPS"]), 143.2)
    }
    func testRejectsOtherSubsystemsAndAmbiguousCounters() {
        XCTAssertNil(FPSParser.parse(["Physics: 60 FPS", "Heartbeat: 60 FPS", "Network FPS: 30"]))
        XCTAssertNil(FPSParser.parse(["59 FPS", "144 FPS"]))
        XCTAssertEqual(FPSParser.parse(["Render: 144 FPS", "Physics: 60 FPS"]), 144)
        XCTAssertNil(FPSParser.parse(["Render: 0 FPS"]))
        XCTAssertNil(FPSParser.parse(["FPS: 99999"]))
        XCTAssertNil(FPSParser.parse(["CPU 44.6% GPU 60%", "Ping 15 ms"]))
    }
    func testOverlayOnlyVisibleWithActiveRobloxWindow() {
        XCTAssertTrue(OverlayPolicy.visible(enabled: true, running: true, active: true, hasWindow: true))
        XCTAssertFalse(OverlayPolicy.visible(enabled: true, running: false, active: false, hasWindow: false))
        XCTAssertFalse(OverlayPolicy.visible(enabled: true, running: true, active: false, hasWindow: true))
        XCTAssertFalse(OverlayPolicy.visible(enabled: false, running: true, active: true, hasWindow: true))
        XCTAssertFalse(OverlayPolicy.visible(enabled: true, running: true, active: true, hasWindow: false))
    }

    @MainActor func testOverlayCannotTakeFocusOrHitTestMouseInput() {
        let store = MonitorStore()
        let overlay = OverlayController(store: store)
        XCTAssertTrue(overlay.panel.ignoresMouseEvents)
        XCTAssertFalse(overlay.panel.acceptsMouseMovedEvents)
        XCTAssertFalse(overlay.panel.canBecomeKey)
        XCTAssertFalse(overlay.panel.canBecomeMain)
        let host = OverlayHostingView(rootView: GameOverlayView(store: store, preferences: store.preferences))
        XCTAssertNil(host.hitTest(NSPoint(x: 10, y: 10)))
    }
}
