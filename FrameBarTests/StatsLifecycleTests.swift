import XCTest
@testable import FrameBar

final class StatsLifecycleTests: XCTestCase {
    func testTurningStatsOffClearsEveryOCRReadingWithoutClearingHardware() {
        var metrics = Metrics()
        metrics.cpu = 42; metrics.gpu = 20
        metrics.gameFPS = 120; metrics.pingMS = 40; metrics.gameCPUMS = 8; metrics.gameGPUMS = 6
        metrics.gameStatsTimestamp = Date()
        metrics.clearGameStats(status: "Stats reader off")
        XCTAssertNil(metrics.gameFPS); XCTAssertNil(metrics.pingMS)
        XCTAssertNil(metrics.gameCPUMS); XCTAssertNil(metrics.gameGPUMS)
        XCTAssertNil(metrics.gameStatsTimestamp)
        XCTAssertEqual(metrics.cpu, 42); XCTAssertEqual(metrics.gpu, 20)
        XCTAssertEqual(metrics.gameFPSStatus, "Stats reader off")
    }
}
