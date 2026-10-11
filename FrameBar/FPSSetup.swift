import Foundation

struct FPSSetupItem: Identifiable, Equatable {
    let id: String
    let passed: Bool
    let detail: String
}

enum FPSSetup {
    static func report(permission: Bool, readerEnabled: Bool, metrics: Metrics,
                       hasWindow: Bool, now: Date = Date(), freshness: Double = 15) -> [FPSSetupItem] {
        let age = metrics.gameStatsTimestamp.map { now.timeIntervalSince($0) }
        let fresh = age.map { $0 >= 0 && $0 <= freshness } ?? false
        let hasFPS = fresh && metrics.gameFPS.map { $0.isFinite && $0 > 0 } == true
        return [
            .init(id: "Screen access", passed: permission, detail: permission ? "Confirmed" : "Not confirmed; check Screen & System Audio Recording, then relaunch"),
            .init(id: "Stats reader", passed: readerEnabled, detail: readerEnabled ? "Enabled" : "Enable the Roblox stats reader or choose Debug"),
            .init(id: "Game window", passed: metrics.robloxActive && hasWindow, detail: metrics.robloxActive && hasWindow ? "Foreground Roblox window found" : "Return to a Roblox game to run the check"),
            .init(id: "FPS reading", passed: hasFPS,
                  detail: hasFPS ? metrics.gameFPSStatus : "Show Shift–F5 or ⌘⇧F5 stats; no recent FPS reading")
        ]
    }
}

struct CPUAuditResult {
    let phase: String
    let samples: Int
    let average: Double
    let peak: Double
    let belowBudget: Int
}

struct CPUAudit {
    private(set) var started: Date?
    private var samples: [(String, Double)] = []
    static func phase(gameActive: Bool, capturelyRecording: Bool, overlayVisible: Bool, panelVisible: Bool) -> String {
        if gameActive {
            if capturelyRecording { return "Roblox + Capturely" }
            return overlayVisible ? "Roblox overlay" : "Roblox · overlay hidden"
        }
        if capturelyRecording { return "Capturely · game background" }
        return panelVisible ? "Live panel" : "Background / settings"
    }
    mutating func start(now: Date = Date()) { started = now; samples.removeAll(keepingCapacity: true) }
    mutating func record(cpu: Double?, phase: String, now: Date = Date()) -> Bool {
        guard let started else { return false }
        if let cpu, cpu.isFinite, cpu >= 0 { samples.append((phase, cpu)) }
        return now.timeIntervalSince(started) >= 30
    }
    mutating func finish() -> [CPUAuditResult] {
        started = nil
        return Set(samples.map(\.0)).sorted().map { phase in
            let values = samples.filter { $0.0 == phase }.map(\.1)
            return CPUAuditResult(phase: phase, samples: values.count,
                average: values.reduce(0, +) / Double(values.count), peak: values.max() ?? 0,
                belowBudget: values.filter { $0 < 1 }.count)
        }
    }
}
