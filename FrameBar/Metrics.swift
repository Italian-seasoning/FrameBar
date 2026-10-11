import Foundation
import AppKit

struct Metrics: Codable {
    var timestamp = Date()
    var cpu: Double?
    var memoryUsed: Double?
    var memoryTotal = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
    var memoryPressure = "Unknown"
    var gpu: Double?
    var quartzFPS: Double?
    var desktopFPS: Double?
    var desktopFPSStatus = "Screen recording permission needed"
    var refreshHz: Double?
    var refreshAdaptive = false
    var refreshSource = "Unavailable"
    var displayName = "Display"
    var robloxCPU: Double?
    var robloxMemory: Double?
    var gameFPS: Double?
    var gameFPSStatus = "Stats reader off"
    var gameStatsTimestamp: Date?
    var pingMS: Double?
    var gameCPUMS: Double?
    var gameGPUMS: Double?
    var monitorCPU: Double?
    var monitorMemory: Double?
    var thermalState = "Nominal"
    var robloxRunning = false
    var robloxActive = false
    var capturelyRecording = false
    var frameMS: Double? { gameFPS.flatMap { $0 > 0 ? 1000 / $0 : nil } }

    mutating func clearGameStats(status: String) {
        gameFPS = nil; pingMS = nil; gameCPUMS = nil; gameGPUMS = nil
        gameStatsTimestamp = nil; gameFPSStatus = status
    }
}

enum OverlayCorner: String, CaseIterable, Identifiable {
    case topRight = "Top right", topLeft = "Top left"
    case bottomRight = "Bottom right", bottomLeft = "Bottom left"
    var id: String { rawValue }
}

enum MenuBarLayout: String, CaseIterable, Identifiable {
    case singleRow = "Single row", stacked = "Stacked"
    var id: String { rawValue }
}

enum MonitorProfile: String, CaseIterable, Identifiable {
    case custom = "Custom", quiet = "Quiet", debug = "Debug", recording = "Recording"
    var id: String { rawValue }
}

/// Profiles change only sampling and overlay readings; placement and menu choices stay personal.
private struct ProfileSettings: Codable, Equatable {
    var interval: Double
    var readGameFPS: Bool
    var readDesktopFPS: Bool
    var lowPower: Bool
    var compact: Bool
    var readings: [String]

    static func preset(_ profile: MonitorProfile) -> Self? {
        let metrics: [OverlayMetric]
        switch profile {
        case .custom: return nil
        case .quiet: metrics = [.cpu, .ram]
        case .debug: metrics = [.fps, .ping, .cpuTime, .gpuTime, .gameCPU, .gameRAM, .gpu, .thermal]
        case .recording: metrics = [.fps, .cpu, .ram, .recording]
        }
        return Self(interval: profile == .debug ? 1 : 2, readGameFPS: profile != .quiet,
                    readDesktopFPS: profile != .quiet, lowPower: true, compact: true, readings: metrics.map(\.rawValue))
    }
}

struct RecordingReadiness: Equatable {
    let text: String
    let needsAction: Bool

    static func status(metrics: Metrics, readerEnabled: Bool, permission: Bool) -> Self? {
        guard metrics.robloxActive else { return nil }
        if !readerEnabled {
            return metrics.capturelyRecording ? Self(text: "Recording · FPS reader off", needsAction: true) : nil
        }
        if !permission { return Self(text: "Enable FPS screen access", needsAction: true) }
        if metrics.gameFPS == nil {
            return Self(text: metrics.capturelyRecording ? "Recording · FPS unavailable" : "Show Roblox stats for FPS", needsAction: true)
        }
        return metrics.capturelyRecording ? Self(text: "Capturely recording", needsAction: false) : nil
    }
}

enum OverlayMetric: String, CaseIterable, Identifiable {
    case fps = "FPS", cpu = "CPU", ram = "RAM", gpu = "GPU", frameMS = "Frame period", ping = "Ping"
    case gameCPU = "Game CPU", gameRAM = "Game RAM", cpuTime = "CPU time", gpuTime = "GPU time", thermal = "Thermal"
    case recording = "Recording"
    var id: String { rawValue }
    var shortLabel: String { self == .frameMS ? "ms" : rawValue }
    func reading(_ metrics: Metrics) -> String {
        switch self {
        case .fps: return Format.number(metrics.gameFPS)
        case .cpu: return Format.percent(metrics.cpu)
        case .ram: return Format.memory(metrics.memoryUsed) + "G"
        case .gpu: return Format.percent(metrics.gpu)
        case .frameMS: return metrics.frameMS.map { String(format: "%.1f", $0) } ?? "—"
        case .ping: return Format.number(metrics.pingMS) + "ms"
        case .gameCPU: return Format.percent(metrics.robloxCPU)
        case .gameRAM: return Format.memory(metrics.robloxMemory) + "G"
        case .cpuTime: return Format.number(metrics.gameCPUMS) + "ms"
        case .gpuTime: return Format.number(metrics.gameGPUMS) + "ms"
        case .thermal: return metrics.thermalState
        case .recording: return metrics.capturelyRecording ? "REC" : "Off"
        }
    }
}

enum MenuBarMetric: String, CaseIterable, Identifiable {
    case cpu = "CPU", ram = "RAM", gpu = "GPU", refresh = "Refresh rate", gameFPS = "Game FPS"
    var id: String { rawValue }
    var reservedReading: String {
        switch self {
        case .cpu, .gpu: return "100%"
        case .ram: return Format.memory(ceil(Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824)) + "G"
        case .refresh: return "9999Hz"
        case .gameFPS: return "1000fps"
        }
    }
    func reading(_ metrics: Metrics, labels: Bool) -> String {
        switch self {
        case .cpu: return (labels ? "CPU " : "") + Format.percent(metrics.cpu)
        case .ram: return (labels ? "RAM " : "") + Format.memory(metrics.memoryUsed) + "G"
        case .gpu: return (labels ? "GPU " : "") + Format.percent(metrics.gpu)
        case .refresh: return metrics.refreshAdaptive ? (labels ? "Hz —" : "—Hz") : (labels ? "Hz " : "") + Format.number(metrics.refreshHz) + (labels ? "" : "Hz")
        case .gameFPS: return Format.number(metrics.robloxActive ? metrics.gameFPS : nil) + "fps"
        }
    }
}

enum MenuBarText {
    static func rows(metrics: Metrics, selected: [MenuBarMetric], layout: MenuBarLayout, labels: Bool) -> [String] {
        let values = selected.map { $0.reading(metrics, labels: labels) }
        guard !values.isEmpty else { return [] }
        if layout == .singleRow || values.count == 1 { return [values.joined(separator: "  ")] }
        let split = (values.count + 1) / 2
        return [values.prefix(split).joined(separator: "  "), values.dropFirst(split).joined(separator: "  ")]
    }
}

@MainActor final class Preferences: ObservableObject {
    @Published var overlayEnabled: Bool { didSet { save() } }
    @Published var compact: Bool { didSet { save() } }
    @Published var corner: OverlayCorner { didSet { overlayPosition = nil; save() } }
    @Published var overlayPosition: CGPoint? { didSet { save() } }
    @Published var interval: Double { didSet { save() } }
    @Published var readGameFPS: Bool { didSet { save() } }
    @Published var readDesktopFPS: Bool { didSet { save() } }
    @Published var opacity: Double { didSet { save() } }
    @Published var menuLayout: MenuBarLayout { didSet { save() } }
    @Published var menuMetrics: [MenuBarMetric] { didSet { save() } }
    @Published var menuLabels: Bool { didSet { save() } }
    @Published var menuIcon: Bool { didSet { save() } }
    @Published var overlayMetrics: [OverlayMetric] { didSet { save() } }
    @Published var shortcutEnabled: Bool { didSet { save() } }
    @Published var lowPower: Bool { didSet { save() } }
    private let defaults: UserDefaults

    private var profileSettings: ProfileSettings {
        ProfileSettings(interval: interval, readGameFPS: readGameFPS, readDesktopFPS: readDesktopFPS,
                        lowPower: lowPower, compact: compact, readings: overlayMetrics.map(\.rawValue))
    }

    var profile: MonitorProfile {
        MonitorProfile.allCases.first { ProfileSettings.preset($0) == profileSettings } ?? .custom
    }

    func applyProfile(_ profile: MonitorProfile) {
        let next: ProfileSettings
        if profile == .custom {
            guard let data = defaults.data(forKey: "customProfile"),
                  let saved = try? JSONDecoder().decode(ProfileSettings.self, from: data) else { return }
            next = saved
        } else {
            if self.profile == .custom, let data = try? JSONEncoder().encode(profileSettings) {
                defaults.set(data, forKey: "customProfile")
            }
            guard let preset = ProfileSettings.preset(profile) else { return }
            next = preset
        }
        interval = next.interval
        readGameFPS = next.readGameFPS
        readDesktopFPS = next.readDesktopFPS
        lowPower = next.lowPower
        compact = next.compact
        overlayMetrics = next.readings.compactMap(OverlayMetric.init(rawValue:))
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        overlayEnabled = defaults.object(forKey: "overlayEnabled") as? Bool ?? true
        compact = defaults.object(forKey: "compact") as? Bool ?? true
        corner = OverlayCorner(rawValue: defaults.string(forKey: "corner") ?? "") ?? .topRight
        if let position = defaults.array(forKey: "overlayPosition") as? [Double], position.count == 2 {
            overlayPosition = OverlayPlacement.clamped(CGPoint(x: position[0], y: position[1]))
        } else { overlayPosition = nil }
        interval = defaults.object(forKey: "interval") as? Double ?? 1
        readGameFPS = defaults.object(forKey: "readGameFPS") as? Bool ?? true
        readDesktopFPS = defaults.object(forKey: "readDesktopFPS") as? Bool ?? true
        opacity = defaults.object(forKey: "opacity") as? Double ?? 0.92
        menuLayout = MenuBarLayout(rawValue: defaults.string(forKey: "menuLayout") ?? "") ?? .singleRow
        menuMetrics = defaults.stringArray(forKey: "menuMetrics")?.compactMap(MenuBarMetric.init(rawValue:)) ?? [.cpu, .ram]
        menuLabels = defaults.object(forKey: "menuLabels") as? Bool ?? false
        menuIcon = defaults.object(forKey: "menuIcon") as? Bool ?? true
        overlayMetrics = defaults.stringArray(forKey: "overlayMetrics")?.compactMap(OverlayMetric.init(rawValue:)) ?? [.fps, .cpu, .ram, .gpu]
        shortcutEnabled = defaults.object(forKey: "shortcutEnabled") as? Bool ?? true
        lowPower = defaults.object(forKey: "lowPower") as? Bool ?? true
    }

    func setMenuMetric(_ metric: MenuBarMetric, enabled: Bool) {
        var selected = Set(menuMetrics)
        if enabled { selected.insert(metric) } else { selected.remove(metric) }
        menuMetrics = MenuBarMetric.allCases.filter { selected.contains($0) }
    }

    func setOverlayMetric(_ metric: OverlayMetric, enabled: Bool) {
        var selected = Set(overlayMetrics)
        if enabled { selected.insert(metric) } else { selected.remove(metric) }
        let next = OverlayMetric.allCases.filter { selected.contains($0) }
        if !next.isEmpty { overlayMetrics = next }
    }

    private func save() {
        defaults.set(overlayEnabled, forKey: "overlayEnabled")
        defaults.set(compact, forKey: "compact")
        defaults.set(corner.rawValue, forKey: "corner")
        if let overlayPosition {
            defaults.set([Double(overlayPosition.x), Double(overlayPosition.y)], forKey: "overlayPosition")
        } else { defaults.removeObject(forKey: "overlayPosition") }
        defaults.set(interval, forKey: "interval")
        defaults.set(readGameFPS, forKey: "readGameFPS")
        defaults.set(readDesktopFPS, forKey: "readDesktopFPS")
        defaults.set(opacity, forKey: "opacity")
        defaults.set(menuLayout.rawValue, forKey: "menuLayout")
        defaults.set(menuMetrics.map(\.rawValue), forKey: "menuMetrics")
        defaults.set(menuLabels, forKey: "menuLabels")
        defaults.set(menuIcon, forKey: "menuIcon")
        defaults.set(overlayMetrics.map(\.rawValue), forKey: "overlayMetrics")
        defaults.set(shortcutEnabled, forKey: "shortcutEnabled")
        defaults.set(lowPower, forKey: "lowPower")
    }
}

enum Format {
    static func percent(_ value: Double?) -> String { value.map { String(format: "%.0f%%", $0) } ?? "—" }
    static func number(_ value: Double?) -> String { value.map { String(format: "%.0f", $0) } ?? "—" }
    static func memory(_ value: Double?) -> String { value.map { String(format: "%.1f", $0) } ?? "—" }
}
