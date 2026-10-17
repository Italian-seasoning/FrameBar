import AppKit
import Combine
import ServiceManagement

@MainActor final class MonitorStore: ObservableObject {
    @Published var metrics = Metrics()
    private(set) var history: [Metrics] = []
    @Published var permissionGranted = CGPreflightScreenCaptureAccess()
    @Published var loginEnabled = SMAppService.mainApp.status == .enabled
    @Published var errorMessage: String?
    @Published var settingsVisible = false
    @Published var overlayHidden = false
    @Published var currentSession: SessionSummary?
    @Published var recentSessions: [SessionSummary] = []
    @Published var frameReport: FrameTimingReport?
    @Published var importingFrames = false
    @Published var lastFPSStatus = "Open Roblox and show debug stats to read FPS"
    @Published var shortcutAvailable = true
    @Published var fpsSetupItems: [FPSSetupItem] = []
    @Published var fpsSetupPending = false
    @Published var auditRunning = false
    @Published var auditResults: [CPUAuditResult] = []
    @Published var nativeFPSHUDEnabled = UserDefaults(suiteName: "com.roblox.RobloxPlayer")?.bool(forKey: "MetalHUDForceEnabled") ?? false
    private var cpuAudit = CPUAudit()
    private(set) var panelVisible = false
    let preferences = Preferences()
    private let sampler = SystemSampler()
    private let display = DisplaySampler()
    private let desktop = ScreenUpdateSampler()
    private let game = GameFPSReader()
    private let queue = DispatchQueue(label: "app.framebar.metrics", qos: .utility)
    private var timer: Timer?
    private var subscriptions = Set<AnyCancellable>()
    private var sampling = false
    private var readingFPS = false
    private var configuringDesktop = false
    private var lastOCR = Date.distantPast
    private var missingFPS = 0
    private var cpuBudgetInterval = 4.0
    private var lastDesktopRequest = ""
    private var lastDesktopConfig = Date.distantPast
    private var lastPermissionCheck = Date.distantPast
    private var gameEpoch = 0
    private var gamePID: pid_t?
    private var gameActive = false
    private(set) var gameRect: CGRect?
    private(set) var screen: NSScreen?

    init() {
        if let data = UserDefaults.standard.data(forKey: "recentSessions"),
           let sessions = try? JSONDecoder().decode([SessionSummary].self, from: data) { recentSessions = Array(sessions.prefix(5)) }
        preferences.$interval.removeDuplicates().sink { [weak self] interval in
            self?.startTimer(interval)
        }.store(in: &subscriptions)
        preferences.$readGameFPS.dropFirst().sink { [weak self] enabled in
            guard let self else { return }
            self.gameEpoch += 1
            var next = self.metrics
            next.clearGameStats(status: enabled ? "Waiting for stats" : "Stats reader off")
            self.metrics = next
            self.lastOCR = .distantPast
            if !enabled { self.fpsSetupPending = false }
        }.store(in: &subscriptions)
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification] {
            NSWorkspace.shared.notificationCenter.publisher(for: name).sink { [weak self] _ in
                self?.updateGame()
            }.store(in: &subscriptions)
        }
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification).sink { [weak self] _ in
            guard let self else { return }
            self.display.select(self.displayID, force: true, active: self.continuousDisplayTiming, enabled: self.needsDisplayTiming)
        }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange).sink { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.display.select(self.displayID, force: true, active: self.continuousDisplayTiming, enabled: self.needsDisplayTiming)
                self.metrics.refreshHz = nil
                self.metrics.refreshSource = "Updating display timing after power change"
                self.tick()
            }
        }.store(in: &subscriptions)
        updateGame()
        display.select(displayID, enabled: needsDisplayTiming)
        tick()
        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification).sink { [weak self] _ in
            guard let self, var session = self.currentSession else { return }
            session.ended = Date()
            let summaries = Array(([session] + self.recentSessions).prefix(5))
            if let data = try? JSONEncoder().encode(summaries) { UserDefaults.standard.set(data, forKey: "recentSessions") }
        }.store(in: &subscriptions)
    }

    var displayID: CGDirectDisplayID {
        (screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? CGMainDisplayID()
    }
    private var continuousDisplayTiming: Bool { panelVisible && !settingsVisible && !gameActive }
    private var needsDisplayTiming: Bool { (panelVisible && !settingsVisible) || preferences.menuMetrics.contains(.refresh) }

    private func startTimer(_ interval: Double) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: max(0.5, interval), repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
        timer?.tolerance = max(0.1, interval * 0.2)
    }

    func setPanelVisible(_ visible: Bool) {
        guard visible != panelVisible else { return }
        panelVisible = visible
        if visible {
            let granted = CGPreflightScreenCaptureAccess()
            if permissionGranted != granted { permissionGranted = granted }
            lastPermissionCheck = Date()
        }
        display.select(displayID, active: continuousDisplayTiming, enabled: needsDisplayTiming)
        tick()
    }

    private func updateGame(rescan: Bool = true) {
        let pid: pid_t?
        let active: Bool
        if rescan {
            let app = NSWorkspace.shared.runningApplications.first {
                $0.bundleIdentifier == "com.roblox.RobloxPlayer" || $0.bundleURL?.lastPathComponent == "Roblox.app"
            }
            pid = app?.processIdentifier
            active = pid != nil && NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
        } else {
            pid = gamePID
            active = gameActive
        }
        if pid != gamePID {
            if var session = currentSession {
                session.ended = Date()
                recentSessions.insert(session, at: 0)
                recentSessions = Array(recentSessions.prefix(5))
                if let data = try? JSONEncoder().encode(recentSessions) { UserDefaults.standard.set(data, forKey: "recentSessions") }
            }
            currentSession = pid == nil ? nil : SessionSummary()
        }
        if pid != gamePID || active != gameActive {
            gameEpoch += 1
            var next = metrics
            next.clearGameStats(status: active ? "Waiting for stats" : "Roblox is in the background")
            metrics = next
            gamePID = pid; gameActive = active
            lastOCR = .distantPast
            missingFPS = 0
        }
        if metrics.robloxRunning != (pid != nil) { metrics.robloxRunning = pid != nil }
        if metrics.robloxActive != active { metrics.robloxActive = active }
        let needsGeometry = (preferences.overlayEnabled && !overlayHidden) || panelVisible || preferences.menuMetrics.contains(.refresh) || fpsSetupPending
        if active, needsGeometry, let pid,
           let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
            gameRect = windows.filter {
                ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid
                    && ($0[kCGWindowLayer as String] as? Int) == 0
            }.compactMap {
                ($0[kCGWindowBounds as String] as? NSDictionary).flatMap { CGRect(dictionaryRepresentation: $0) }
            }.filter { $0.width > 250 && $0.height > 200 }.max { $0.width * $0.height < $1.width * $1.height }
        } else { gameRect = nil }
        if let rect = gameRect {
            screen = NSScreen.screens.max {
                let a = CGDisplayBounds(($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0).intersection(rect)
                let b = CGDisplayBounds(($1.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0).intersection(rect)
                return a.width * a.height < b.width * b.height
            }
        } else { screen = NSScreen.main ?? NSScreen.screens.first }
    }

    private func tick() {
        guard !sampling else { return }
        sampling = true
        updateGame(rescan: false)
        if (panelVisible || gameActive) && Date().timeIntervalSince(lastPermissionCheck) >= 10 {
            let granted = CGPreflightScreenCaptureAccess()
            if permissionGranted != granted { permissionGranted = granted }
            lastPermissionCheck = Date()
        }
        display.select(displayID, active: continuousDisplayTiming, enabled: needsDisplayTiming)
        // Desktop counter pauses during Roblox: neither a desktop FPS badge nor capture overhead in games.
        let desktopEnabled = preferences.readDesktopFPS && panelVisible && !settingsVisible && !gameActive
        let request = "\(displayID):\(desktopEnabled):\(permissionGranted)"
        if !configuringDesktop && (request != lastDesktopRequest || (desktopEnabled && permissionGranted && Date().timeIntervalSince(lastDesktopConfig) > 15)) {
            configuringDesktop = true
            lastDesktopRequest = request
            lastDesktopConfig = Date()
            let id = displayID
            Task { [weak self] in
                guard let self else { return }
                await self.desktop.configure(display: id, enabled: desktopEnabled)
                self.configuringDesktop = false
            }
        }
        let pid = gamePID
        queue.async { [weak self, sampler] in
            let sample = sampler.sample(pid: pid)
            Task { @MainActor in
                guard let self else { return }
                var next = sample
                let timing = self.display.sample()
                let desktop = self.desktop.sample()
                next.quartzFPS = timing.fps; next.refreshHz = timing.hz; next.refreshSource = timing.source
                next.refreshAdaptive = timing.adaptive
                next.displayName = self.screen?.localizedName ?? "Display"
                next.desktopFPS = self.gameActive ? nil : desktop.0
                next.desktopFPSStatus = self.gameActive ? "Paused during Roblox" : desktop.1
                next.robloxRunning = self.gamePID != nil; next.robloxActive = self.gameActive
                if pid != self.gamePID { next.robloxCPU = nil; next.robloxMemory = nil }
                next.gameFPS = self.metrics.gameFPS
                next.gameFPSStatus = self.metrics.gameFPSStatus
                next.gameStatsTimestamp = self.metrics.gameStatsTimestamp
                next.capturelyRecording = CapturelyTelemetry.recordingNeedsFPS(pid: self.gamePID)
                if self.gameActive {
                    next.pingMS = self.metrics.pingMS
                    next.gameCPUMS = self.metrics.gameCPUMS
                    next.gameGPUMS = self.metrics.gameGPUMS
                }
                if !self.preferences.readGameFPS {
                    next.clearGameStats(status: "Stats reader off")
                }
                else if !self.gameActive { next.clearGameStats(status: self.gamePID == nil ? "Open Roblox to read game FPS" : "Roblox is in the background") }
                else if !self.permissionGranted { next.clearGameStats(status: "Allow screen access for game FPS") }
                self.metrics = next
                CapturelyTelemetry.publish(next, pid: self.gamePID)
                if next.robloxActive { self.currentSession?.recordHardware(next) }
                if self.preferences.lowPower {
                    if (next.monitorCPU ?? 0) > 0.8 { self.cpuBudgetInterval = min(30, self.cpuBudgetInterval * 1.5) }
                    else if (next.monitorCPU ?? 0) < 0.3 { self.cpuBudgetInterval = max(4, self.cpuBudgetInterval - 0.5) }
                } else { self.cpuBudgetInterval = 2 }
                self.history.append(next)
                self.history.removeAll { Date().timeIntervalSince($0.timestamp) > 300 }
                if self.auditRunning {
                    let phase = CPUAudit.phase(gameActive: next.robloxActive, capturelyRecording: next.capturelyRecording,
                        overlayVisible: self.preferences.overlayEnabled && !self.overlayHidden, panelVisible: self.panelVisible)
                    if self.cpuAudit.record(cpu: next.monitorCPU, phase: phase) {
                        self.auditResults = self.cpuAudit.finish()
                        self.auditRunning = false
                    }
                }
                self.sampling = false
                self.readFPSIfNeeded(manual: self.fpsSetupPending)
            }
        }
    }

    var fpsReadInterval: Double {
        let thermal = ProcessInfo.processInfo.thermalState
        let powerInterval: Double = preferences.lowPower && (thermal == .serious || thermal == .critical || ProcessInfo.processInfo.isLowPowerModeEnabled) ? 10 : 0
        return max(powerInterval, cpuBudgetInterval, missingFPS == 0 ? 0 : min(30, 4 * pow(2, Double(min(missingFPS, 3)))))
    }

    func retryFPS() {
        missingFPS = 0; lastOCR = .distantPast
        readFPSIfNeeded(manual: true)
    }

    func checkFPSSetup() {
        permissionGranted = CGPreflightScreenCaptureAccess()
        fpsSetupItems = FPSSetup.report(permission: permissionGranted, readerEnabled: preferences.readGameFPS,
            metrics: metrics, hasWindow: gameRect != nil, freshness: fpsReadInterval + 5)
        fpsSetupPending = preferences.readGameFPS
        missingFPS = 0; lastOCR = .distantPast
        readFPSIfNeeded(manual: true)
    }

    func startCPUAudit() {
        auditResults = []
        cpuAudit.start()
        auditRunning = true
    }

    private func readFPSIfNeeded(manual: Bool = false) {
        let overlayNeedsStats = preferences.overlayEnabled && !overlayHidden && preferences.overlayMetrics.contains {
            $0 == .fps || $0 == .frameMS || $0 == .ping || $0 == .cpuTime || $0 == .gpuTime
        }
        guard preferences.readGameFPS, permissionGranted || manual, gameActive,
              (manual || overlayNeedsStats || panelVisible || preferences.menuMetrics.contains(.gameFPS) || metrics.capturelyRecording), let pid = gamePID,
              !readingFPS, Date().timeIntervalSince(lastOCR) >= fpsReadInterval else { return }
        readingFPS = true; lastOCR = Date()
        let epoch = gameEpoch
        Task { [weak self] in
            guard let self else { return }
            let result = await self.game.read(pid: pid, accurate: manual || self.missingFPS % 3 == 1)
            self.readingFPS = false
            guard epoch == self.gameEpoch, self.gameActive, self.preferences.readGameFPS else { return }
            var next = self.metrics
            next.gameFPS = result.fps
            next.gameStatsTimestamp = Date()
            next.gameFPSStatus = result.status
            self.lastFPSStatus = result.status
            next.pingMS = result.ping
            next.gameCPUMS = result.cpuMS
            next.gameGPUMS = result.gpuMS
            self.metrics = next
            self.missingFPS = result.fps == nil ? self.missingFPS + 1 : 0
            self.currentSession?.recordFPS(result.fps)
            if result.captured { self.permissionGranted = true }
            if self.fpsSetupPending {
                self.fpsSetupItems = FPSSetup.report(permission: self.permissionGranted,
                    readerEnabled: self.preferences.readGameFPS, metrics: next, hasWindow: self.gameRect != nil,
                    freshness: self.fpsReadInterval + 5)
                self.fpsSetupPending = false
            }
        }
    }

    func resetSession() { currentSession = gamePID == nil ? nil : SessionSummary() }

    func setNativeFPSHUD(_ enabled: Bool) {
        guard let defaults = UserDefaults(suiteName: "com.roblox.RobloxPlayer") else { return }
        // Apple's app-scoped HUD preference also applies to Froststrap's client,
        // which uses the same bundle identifier. No game files are modified.
        defaults.set(enabled, forKey: "MetalHUDForceEnabled")
        nativeFPSHUDEnabled = enabled
        if enabled { preferences.readGameFPS = false }
    }

    func importFrameTimings() {
        guard !importingFrames else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.html, .commaSeparatedText]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a Roblox MicroProfiler HTML dump or per-frame CSV with a frame_ms column."
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importingFrames = true
        Task {
            let report = await Task.detached(priority: .utility) { () -> FrameTimingReport? in
                guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 32 * 1024 * 1024,
                      let data = try? Data(contentsOf: url), let source = String(data: data, encoding: .utf8) else { return nil }
                return FrameTimingImport.parse(source, name: url.lastPathComponent)
            }.value
            importingFrames = false
            if let report { frameReport = report }
            else { errorMessage = "No valid contiguous frame timings found. Use a client MicroProfiler dump (up to 32 MB), or CSV with one frame_ms value per rendered frame. Sampled FPS exports cannot produce 1% lows." }
        }
    }

    func requestScreenAccess() {
        permissionGranted = CGRequestScreenCaptureAccess()
        if !permissionGranted {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
        }
    }

    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginEnabled = SMAppService.mainApp.status == .enabled
            if enabled && !loginEnabled { errorMessage = "Approve FrameBar in System Settings → General → Login Items." }
        } catch { errorMessage = error.localizedDescription }
    }

    func exportCSV() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "FrameBar-\(Date().formatted(.iso8601).replacingOccurrences(of: ":", with: "-" )).csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try csv().write(to: url, atomically: true, encoding: .utf8) }
        catch { errorMessage = error.localizedDescription }
    }

    func csv() -> String {
        let header = "timestamp,cpu_percent,memory_gib,memory_total_gib,gpu_percent,desktop_updates_per_second,display_callback_hz,display_refresh_hz,roblox_cpu_percent_one_core,roblox_memory_gib,roblox_stats_fps,roblox_active,memory_pressure,ping_ms,game_cpu_ms,game_gpu_ms,monitor_cpu_percent_one_core,monitor_memory_mb,thermal_state"
        let formatter = ISO8601DateFormatter()
        func value(_ number: Double?) -> String { number.map { String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), $0) } ?? "" }
        return ([header] + history.map { sample in
            [formatter.string(from: sample.timestamp), value(sample.cpu), value(sample.memoryUsed), value(sample.memoryTotal),
             value(sample.gpu), value(sample.desktopFPS), value(sample.quartzFPS), value(sample.refreshHz),
             value(sample.robloxCPU), value(sample.robloxMemory), value(sample.gameFPS), sample.robloxActive ? "true" : "false", sample.memoryPressure,
             value(sample.pingMS), value(sample.gameCPUMS), value(sample.gameGPUMS), value(sample.monitorCPU), value(sample.monitorMemory), sample.thermalState].joined(separator: ",")
        }).joined(separator: "\n") + "\n"
    }
}
