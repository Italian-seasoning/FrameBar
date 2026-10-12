import AppKit
import SwiftUI
import Combine
import os
import Sparkle

@main struct FrameBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        Settings { EmptyView() }
            .commands {
                CommandGroup(replacing: .appSettings) {
                    Button("Settings…") { delegate.showSettings() }.keyboardShortcut(",")
                }
                CommandGroup(after: .appInfo) { FrameBarUpdateButton() }
            }
    }
}

@MainActor final class FrameBarUpdater: ObservableObject {
    static let shared = FrameBarUpdater()
    @Published private(set) var canCheckForUpdates = false
    private let controller: SPUStandardUpdaterController

    private init() {
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheckForUpdates)
    }
    func checkForUpdates() { controller.checkForUpdates(nil) }
}

struct FrameBarUpdateButton: View {
    @ObservedObject private var updater = FrameBarUpdater.shared
    var body: some View {
        Button("Check for Updates…") { updater.checkForUpdates() }.disabled(!updater.canCheckForUpdates)
    }
}

final class MonitorPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var store: MonitorStore!
    private var overlay: OverlayController!
    private var statusItem: NSStatusItem!
    private var menuReadout: MenuBarReadoutView!
    private var menuPanel: MonitorPanel!
    private var settingsWindow: NSWindow?
    private let settingsNavigation = SettingsNavigation()
    private var outsideClick: Any?
    private var escapeKey: Any?
    private var subscriptions = Set<AnyCancellable>()
    private var lastMenuSignature = ""
    private let shortcut = OverlayShortcut()
    private let logger = Logger(subsystem: "app.italianseasoning.FrameBar", category: "App")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        store = MonitorStore()
        if let index = CommandLine.arguments.firstIndex(of: "--diagnostics"), CommandLine.arguments.count > index + 1 {
            let path = CommandLine.arguments[index + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                guard let self else { return }
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
                if let data = try? encoder.encode(self.store.history) { try? data.write(to: URL(fileURLWithPath: path), options: .atomic) }
                NSApp.terminate(nil)
            }
            return
        }
        _ = FrameBarUpdater.shared
        overlay = OverlayController(store: store)
        shortcut.action = { [weak self] in self?.store.overlayHidden.toggle() }
        store.preferences.$shortcutEnabled.sink { [weak self] enabled in
            guard let self else { return }
            self.shortcut.setEnabled(enabled)
            self.store.shortcutAvailable = !enabled || self.shortcut.registered
        }.store(in: &subscriptions)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self; button.action = #selector(togglePanel)
            menuReadout = MenuBarReadoutView(frame: button.bounds)
            menuReadout.autoresizingMask = [.width, .height]
            button.addSubview(menuReadout)
        }
        // A clear borderless host lets native glass sample the desktop without the
        // heavier NSPopover material underneath it.
        menuPanel = MonitorPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        menuPanel.title = "FrameBar"
        menuPanel.level = .statusBar
        menuPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        menuPanel.isOpaque = false; menuPanel.backgroundColor = .clear; menuPanel.hasShadow = false
        menuPanel.hidesOnDeactivate = false; menuPanel.isReleasedWhenClosed = false
        menuPanel.animationBehavior = .none
        store.$metrics.sink { [weak self] metrics in
            guard let self else { return }
            self.updateStatusItem(metrics: metrics)
            DispatchQueue.main.async { self.positionPanel() }
        }.store(in: &subscriptions)
        Publishers.CombineLatest4(store.preferences.$menuLayout, store.preferences.$menuMetrics,
                                  store.preferences.$menuLabels, store.preferences.$menuIcon)
            .dropFirst().sink { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.updateStatusItem(metrics: self.store.metrics)
                    self.positionPanel()
                }
            }.store(in: &subscriptions)
        outsideClick = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hidePanel()
        }
        escapeKey = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.store.preferences.shortcutEnabled == true && OverlayShortcut.matches(event) {
                self?.store.overlayHidden.toggle()
                return nil
            }
            if event.keyCode == 53 && self?.menuPanel.isVisible == true { self?.hidePanel(); return nil }
            return event
        }
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification).sink { [weak self] notification in
            if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
               app.processIdentifier == ProcessInfo.processInfo.processIdentifier { return }
            self?.hidePanel()
        }.store(in: &subscriptions)
        logger.info("FrameBar launched; compact glass panel ready")
        if CommandLine.arguments.contains("--show") { DispatchQueue.main.async { [weak self] in self?.togglePanel() } }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if menuPanel != nil && !menuPanel.isVisible { togglePanel() }
        return false
    }

    private func updateStatusItem(metrics: Metrics) {
        guard let button = statusItem.button else { return }
        let prefs = store.preferences
        let rows = MenuBarText.rows(metrics: metrics, selected: prefs.menuMetrics, layout: prefs.menuLayout, labels: prefs.menuLabels)
        let showIcon = prefs.menuIcon || rows.isEmpty
        let text = rows.joined(separator: "\n")
        let signature = "\(showIcon):\(prefs.menuLayout.rawValue):\(text)"
        guard signature != lastMenuSignature else { return }
        lastMenuSignature = signature
        menuReadout.configure(metrics: metrics, selected: prefs.menuMetrics, layout: prefs.menuLayout,
                              labels: prefs.menuLabels, showIcon: showIcon)
        if statusItem.length != menuReadout.requiredWidth { statusItem.length = menuReadout.requiredWidth }
        menuReadout.frame = button.bounds
        let description = prefs.menuMetrics.map { "\($0.rawValue): \($0.reading(metrics, labels: false))" }.joined(separator: ", ")
        button.setAccessibilityLabel(description.isEmpty ? "FrameBar" : "FrameBar, " + description)
        button.toolTip = "FrameBar · " + (description.isEmpty ? "Click to open" : description)
        if prefs.menuMetrics.contains(.refresh), metrics.refreshAdaptive {
            button.toolTip? += "\n—Hz: current panel refresh is unavailable in Low Power Mode."
        }
    }

    private func positionPanel() {
        guard menuPanel.isVisible, let button = statusItem.button, let window = button.window,
              let screen = window.screen else { return }
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        let height = MonitorView.panelHeight(metrics: store.metrics, readerEnabled: store.preferences.readGameFPS,
                                            permission: store.permissionGranted)
        let width: CGFloat = 256
        let x = min(screen.visibleFrame.maxX - width - 6, max(screen.visibleFrame.minX + 6, anchor.midX - width / 2))
        let y = min(anchor.minY - height - 3, screen.visibleFrame.maxY - height - 3)
        let frame = NSRect(x: x, y: y, width: width, height: height)
        if menuPanel.frame != frame { menuPanel.setFrame(frame, display: true) }
    }

    private func hidePanel() {
        menuPanel.orderOut(nil)
        menuPanel.contentView = nil
        store.setPanelVisible(false)
    }

    @objc private func togglePanel() {
        if menuPanel.isVisible { hidePanel() }
        else {
            let host = NSHostingView(rootView: MonitorView(store: store, preferences: store.preferences,
                openSettings: { [weak self] capture in self?.showSettings(capture: capture) }))
            host.focusRingType = .none
            menuPanel.contentView = host
            store.setPanelVisible(true)
            menuPanel.orderFrontRegardless()
            positionPanel()
            menuPanel.makeKey()
        }
    }

    func showSettings(capture: Bool = false) {
        guard store != nil else { return }
        hidePanel()
        if capture { settingsNavigation.pane = .capture }
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 600),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
            window.title = "FrameBar Settings"
            window.contentMinSize = NSSize(width: 480, height: 500)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.setFrameAutosaveName("FrameBarSettings")
            if !window.setFrameUsingName("FrameBarSettings") { window.center() }
            window.contentView = nil
            settingsWindow = window
        }
        // Drop the settings view when closed so a hidden window has no live subscriptions.
        if settingsWindow?.contentView == nil {
            settingsWindow?.contentView = NSHostingView(rootView: SettingsView(store: store,
                preferences: store.preferences, navigation: settingsNavigation))
        }
        store.settingsVisible = true
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === settingsWindow else { return }
        store.settingsVisible = false
        window.contentView = nil
    }
}
