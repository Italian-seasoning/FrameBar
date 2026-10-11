import XCTest
@testable import FrameBar

final class OverlayPlacementTests: XCTestCase {
    func testCustomPlacementClampsAndScalesWithWindow() {
        let size = CGSize(width: 266, height: 45)
        let bounds = CGRect(x: 200, y: 100, width: 1000, height: 600)
        let topRight = OverlayPlacement.frame(bounds: bounds, size: size, corner: .topRight,
                                             custom: CGPoint(x: 3, y: -2))
        XCTAssertEqual(topRight.maxX, bounds.maxX - 14)
        XCTAssertEqual(topRight.maxY, bounds.maxY - 64)
        let bottomLeft = OverlayPlacement.frame(bounds: bounds, size: size, corner: .topRight,
                                               custom: CGPoint(x: -1, y: 2))
        XCTAssertEqual(bottomLeft.minX, bounds.minX + 14)
        XCTAssertEqual(bottomLeft.minY, bounds.minY + 14)
        let middle = OverlayPlacement.frame(bounds: bounds, size: size, corner: .topRight,
                                           custom: CGPoint(x: 0.5, y: 0.5))
        XCTAssertEqual(middle.midX, bounds.midX)
        let larger = OverlayPlacement.frame(bounds: CGRect(x: 0, y: 0, width: 1600, height: 900),
                                            size: size, corner: .topRight, custom: CGPoint(x: 0.5, y: 0.5))
        XCTAssertEqual(larger.midX, 800)
        XCTAssertEqual(larger.midY, 425)
        let tight = OverlayPlacement.frame(bounds: CGRect(origin: .zero, size: size),
                                           size: size, corner: .bottomRight, custom: nil)
        XCTAssertEqual(tight.origin, .zero)
    }

    @MainActor func testPositionPersistsAndCornerResetsCustomPosition() {
        let suite = "FrameBarTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let prefs = Preferences(defaults: defaults)
        prefs.overlayPosition = CGPoint(x: 0.3, y: 0.7)
        let restored = Preferences(defaults: defaults)
        XCTAssertEqual(restored.overlayPosition, CGPoint(x: 0.3, y: 0.7))
        restored.corner = .bottomLeft
        XCTAssertNil(Preferences(defaults: defaults).overlayPosition)
        XCTAssertEqual(OverlayPlacement.position(corner: restored.corner, custom: nil), CGPoint(x: 0, y: 1))
    }
}
