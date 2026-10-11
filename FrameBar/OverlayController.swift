import AppKit
import SwiftUI
import Combine
import os

enum OverlayPolicy {
    static func visible(enabled: Bool, running: Bool, active: Bool, hasWindow: Bool) -> Bool {
        enabled && running && active && hasWindow
    }
}

/// Coordinates describe the available travel, with (0, 0) at the top left.
enum OverlayPlacement {
    static func clamped(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x.isFinite ? min(1, max(0, point.x)) : 1,
                y: point.y.isFinite ? min(1, max(0, point.y)) : 0)
    }

    static func position(corner: OverlayCorner, custom: CGPoint?) -> CGPoint {
        if let custom { return clamped(custom) }
        return CGPoint(x: corner == .topLeft || corner == .bottomLeft ? 0 : 1,
                       y: corner == .topLeft || corner == .topRight ? 0 : 1)
    }

    static func frame(bounds: CGRect, size: CGSize, corner: OverlayCorner, custom: CGPoint?) -> CGRect {
        let position = position(corner: corner, custom: custom)
        // Leave space for game controls while keeping the whole overlay on screen.
        let horizontalInset = min(14, max(0, (bounds.width - size.width) / 2))
        let verticalRoom = max(0, bounds.height - size.height)
        let bottomInset = min(14, verticalRoom / 2)
        let topInset = min(64, verticalRoom - bottomInset)
        let travelX = max(0, bounds.width - size.width - 2 * horizontalInset)
        let travelY = max(0, verticalRoom - topInset - bottomInset)
        return CGRect(x: bounds.minX + horizontalInset + position.x * travelX,
                      y: bounds.maxY - topInset - size.height - position.y * travelY,
                      width: size.width, height: size.height)
    }
}

final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor final class OverlayController {
    let panel: OverlayPanel
    private let store: MonitorStore
    private var subscriptions = Set<AnyCancellable>()
    private let logger = Logger(subsystem: "app.italianseasoning.FrameBar", category: "Overlay")

    init(store: MonitorStore) {
        self.store = store
        panel = OverlayPanel(contentRect: NSRect(x: 0, y: 0, width: 324, height: 190),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "FrameBar Roblox Overlay"
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        store.$metrics.sink { [weak self] _ in
            DispatchQueue.main.async { self?.update() }
        }.store(in: &subscriptions)
        store.preferences.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.update() }
        }.store(in: &subscriptions)
        store.$overlayHidden.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.update() }
        }.store(in: &subscriptions)
    }

    func update() {
        let visible = OverlayPolicy.visible(enabled: store.preferences.overlayEnabled && !store.overlayHidden, running: store.metrics.robloxRunning,
                                            active: store.metrics.robloxActive, hasWindow: store.gameRect != nil)
        guard visible, let screen = store.screen else {
            if panel.isVisible { panel.orderOut(nil); logger.info("Overlay hidden") }
            if panel.contentView != nil { panel.contentView = nil }
            return
        }
        let height = GameOverlayView.height(preferences: store.preferences, missingFPS: store.metrics.gameFPS == nil)
        let width: CGFloat = GameOverlayView.width(preferences: store.preferences)
        var bounds = screen.visibleFrame
        if let game = store.gameRect {
            let desktopTop = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
            let converted = NSRect(x: game.minX, y: desktopTop - game.maxY, width: game.width, height: game.height)
            let intersection = screen.frame.intersection(converted)
            if intersection.width >= width && intersection.height >= height { bounds = intersection }
        }
        if panel.contentView == nil {
            let host = NSHostingView(rootView: GameOverlayView(store: store, preferences: store.preferences))
            host.focusRingType = .none
            panel.contentView = host
        }
        let frame = OverlayPlacement.frame(bounds: bounds, size: CGSize(width: width, height: height),
                                           corner: store.preferences.corner, custom: store.preferences.overlayPosition)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        if !panel.isVisible { panel.orderFrontRegardless(); logger.info("Roblox overlay visible") }
    }
}
