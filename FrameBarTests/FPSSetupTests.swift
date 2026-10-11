import XCTest
@testable import FrameBar

final class FPSSetupTests: XCTestCase {
    func testSetupDoesNotTreatStaleOrFutureFPSAsWorking() {
        let now = Date(timeIntervalSince1970: 100)
        var metrics = Metrics()
        metrics.robloxActive = true; metrics.gameFPS = 120
        metrics.gameStatsTimestamp = Date(timeIntervalSince1970: 80)
        XCTAssertFalse(FPSSetup.report(permission: true, readerEnabled: true, metrics: metrics, hasWindow: true, now: now).last!.passed)
        metrics.gameStatsTimestamp = Date(timeIntervalSince1970: 101)
        XCTAssertFalse(FPSSetup.report(permission: true, readerEnabled: true, metrics: metrics, hasWindow: true, now: now).last!.passed)
        metrics.gameStatsTimestamp = Date(timeIntervalSince1970: 99)
        XCTAssertTrue(FPSSetup.report(permission: true, readerEnabled: true, metrics: metrics, hasWindow: true, now: now).allSatisfy(\.passed))
    }
    func testAuditKeepsPhasesSeparateAndIgnoresInvalidSamples() {
        var audit = CPUAudit()
        audit.start(now: Date(timeIntervalSince1970: 100))
        XCTAssertFalse(audit.record(cpu: 0.2, phase: "Idle", now: Date(timeIntervalSince1970: 102)))
        _ = audit.record(cpu: .nan, phase: "Idle", now: Date(timeIntervalSince1970: 104))
        _ = audit.record(cpu: 1.5, phase: "Game", now: Date(timeIntervalSince1970: 110))
        XCTAssertTrue(audit.record(cpu: 0.5, phase: "Game", now: Date(timeIntervalSince1970: 130)))
        let results = audit.finish()
        XCTAssertEqual(results.first { $0.phase == "Game" }?.average, 1)
        XCTAssertEqual(results.first { $0.phase == "Game" }?.belowBudget, 1)
        XCTAssertEqual(results.first { $0.phase == "Idle" }?.samples, 1)
    }
    func testAuditDistinguishesForegroundGameplayFromBackgroundRecording() {
        XCTAssertEqual(CPUAudit.phase(gameActive: false, capturelyRecording: true, overlayVisible: true, panelVisible: false), "Capturely · game background")
        XCTAssertEqual(CPUAudit.phase(gameActive: true, capturelyRecording: true, overlayVisible: true, panelVisible: false), "Roblox + Capturely")
        XCTAssertEqual(CPUAudit.phase(gameActive: true, capturelyRecording: false, overlayVisible: false, panelVisible: false), "Roblox · overlay hidden")
    }
}
