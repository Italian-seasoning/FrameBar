import XCTest
import AppKit
@testable import FrameBar

final class MenuBarTests: XCTestCase {
    @MainActor func testRenderedTextAndIconHaveTheSameVisibleCenter() throws {
        for layout in MenuBarLayout.allCases {
          for selected: [MenuBarMetric] in [[.cpu, .ram], [.cpu, .ram, .gpu, .refresh]] {
            let view = MenuBarReadoutView(frame: NSRect(x: 0, y: 0, width: 120, height: 24))
            view.appearance = NSAppearance(named: .darkAqua)
            var metrics = Metrics(); metrics.cpu = 44; metrics.memoryUsed = 12.6
            metrics.gpu = 14; metrics.refreshHz = 120
            view.configure(metrics: metrics, selected: selected, layout: layout, labels: false, showIcon: true)
            let window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = view
            defer { window.close() }
            view.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let scale = Double(bitmap.pixelsWide) / view.bounds.width
            func center(from: Int, to: Int) throws -> Double {
                var inkRows: [Int] = []
                for y in 0..<bitmap.pixelsHigh {
                    if (from..<to).contains(where: { (bitmap.colorAt(x: $0, y: y)?.alphaComponent ?? 0) > 0.25 }) {
                        inkRows.append(y)
                    }
                }
                let first = try XCTUnwrap(inkRows.first)
                let last = try XCTUnwrap(inkRows.last)
                return Double(first + last) / 2 / scale
            }
            let iconCenter = try center(from: Int(4 * scale), to: Int(20 * scale))
            let textCenter = try center(from: Int(25 * scale), to: Int(view.requiredWidth * scale))
            XCTAssertEqual(textCenter, iconCenter, accuracy: 0.5, "\(layout) visible glyph centers must align")
            let path = ProcessInfo.processInfo.environment["FRAMEBAR_RENDER_MENU"]
                ?? FileManager.default.temporaryDirectory.appendingPathComponent("FrameBar-menu").path
            let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            let selectionSuffix = selected.count == 2 ? "" : "-four-metrics"
            try data.write(to: URL(fileURLWithPath: path + "-" + layout.rawValue + selectionSuffix + ".png"))
          }
        }
    }
    func testLowPowerAdaptivePanelDoesNotClaimNominalRefresh() {
        XCTAssertTrue(DisplayRatePolicy.isAdaptive(lowPower: true, minimumInterval: 1 / 120, maximumInterval: 1 / 24))
        XCTAssertFalse(DisplayRatePolicy.isAdaptive(lowPower: false, minimumInterval: 1 / 120, maximumInterval: 1 / 24))
        XCTAssertFalse(DisplayRatePolicy.isAdaptive(lowPower: true, minimumInterval: 1 / 165, maximumInterval: 1 / 165))
        var metrics = Metrics(); metrics.refreshAdaptive = true; metrics.refreshHz = 120
        XCTAssertEqual(MenuBarMetric.refresh.reading(metrics, labels: false), "—Hz")
    }

    @MainActor func testExpandedCompactOverlayWrapsWithinSmallWidth() {
        let suite = "FrameBarTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let prefs = Preferences(defaults: defaults)
        prefs.compact = true; prefs.overlayMetrics = OverlayMetric.allCases
        XCTAssertLessThan(GameOverlayView.width(preferences: prefs), 400)
        XCTAssertGreaterThan(GameOverlayView.height(preferences: prefs, missingFPS: false), 45)
        XCTAssertTrue(GameOverlayView.rows(prefs.overlayMetrics).allSatisfy { $0.count <= 4 })
    }
    @MainActor func testStatusWidthDoesNotChangeWithDigitsMissingValuesOrActiveGame() {
        let view = MenuBarReadoutView(frame: .zero)
        for layout in MenuBarLayout.allCases {
            for labels in [false, true] {
                var metrics = Metrics()
                view.configure(metrics: metrics, selected: MenuBarMetric.allCases, layout: layout, labels: labels, showIcon: true)
                let width = view.requiredWidth
                let columns = view.columnWidths
                for value in [1.0, 9, 10, 99, 100] {
                    metrics.cpu = value; metrics.gpu = value
                    metrics.memoryUsed = value / 10
                    metrics.refreshHz = value * 10
                    metrics.robloxActive = true; metrics.gameFPS = value * 10
                    view.configure(metrics: metrics, selected: MenuBarMetric.allCases, layout: layout, labels: labels, showIcon: true)
                    XCTAssertEqual(view.requiredWidth, width)
                    XCTAssertEqual(view.columnWidths, columns)
                }
            }
        }
    }

    func testDisplayTimingDiscardsStaleRateAndTracksNewIntervals() {
        var timing = DisplayTimingWindow()
        for _ in 0..<9 { timing.append(1 / 120) }
        XCTAssertEqual(timing.hz!, 120, accuracy: 0.01)
        timing.reset()
        XCTAssertNil(timing.hz)
        timing.append(.nan); timing.append(0); timing.append(-1)
        XCTAssertNil(timing.hz)
        for _ in 0..<9 { timing.append(1 / 60) }
        XCTAssertEqual(timing.hz!, 60, accuracy: 0.01)
    }
    func testStackedSelectionKeepsReadingsInTwoRows() {
        var metrics = Metrics()
        metrics.cpu = 45; metrics.memoryUsed = 12.7; metrics.gpu = 80; metrics.refreshHz = 165
        XCTAssertEqual(MenuBarText.rows(metrics: metrics, selected: [.cpu, .ram], layout: .singleRow, labels: false), ["45%  12.7G"])
        XCTAssertEqual(MenuBarText.rows(metrics: metrics, selected: [.cpu, .ram, .gpu, .refresh], layout: .stacked, labels: true),
                       ["CPU 45%  RAM 12.7G", "GPU 80%  Hz 165"])
        XCTAssertEqual(MenuBarText.rows(metrics: metrics, selected: [.gpu], layout: .stacked, labels: true), ["GPU 80%"])
        XCTAssertEqual(MenuBarText.rows(metrics: metrics, selected: [], layout: .stacked, labels: false), [])
    }

    func testInactiveRobloxDoesNotShowStaleGameFPS() {
        var metrics = Metrics()
        metrics.gameFPS = 144
        XCTAssertEqual(MenuBarMetric.gameFPS.reading(metrics, labels: false), "—fps")
        metrics.robloxActive = true
        XCTAssertEqual(MenuBarMetric.gameFPS.reading(metrics, labels: false), "144fps")
    }

    @MainActor func testPreferencesPersistSelectionAndIconOnly() {
        let suite = "FrameBarTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let prefs = Preferences(defaults: defaults)
        prefs.menuLayout = .stacked
        prefs.setMenuMetric(.gpu, enabled: true)
        prefs.setMenuMetric(.cpu, enabled: false)
        prefs.menuLabels = true
        prefs.menuIcon = false
        let reloaded = Preferences(defaults: defaults)
        XCTAssertEqual(reloaded.menuLayout, .stacked)
        XCTAssertEqual(reloaded.menuMetrics, [.ram, .gpu])
        XCTAssertTrue(reloaded.menuLabels)
        XCTAssertFalse(reloaded.menuIcon)
        reloaded.setMenuMetric(.ram, enabled: false)
        reloaded.setMenuMetric(.gpu, enabled: false)
        XCTAssertEqual(Preferences(defaults: defaults).menuMetrics, [])
    }
}
