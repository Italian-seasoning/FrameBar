import AppKit
import QuartzCore

struct DisplayTimingWindow {
    private var intervals: [Double] = []
    var hz: Double? {
        guard intervals.count >= 4 else { return nil }
        let sorted = intervals.sorted()
        return 1 / sorted[sorted.count / 2]
    }
    mutating func append(_ interval: Double) {
        guard interval.isFinite, interval >= 0.001, interval <= 1 else { return }
        intervals.append(interval)
        if intervals.count > 9 { intervals.removeFirst() }
    }
    mutating func reset() { intervals.removeAll(keepingCapacity: true) }
}

enum DisplayRatePolicy {
    static func isAdaptive(lowPower: Bool, minimumInterval: Double, maximumInterval: Double) -> Bool {
        lowPower && minimumInterval > 0 && maximumInterval - minimumInterval > 0.0001
    }
}

/// Estimates system display scheduling, not physical scanout or game render FPS.
@MainActor final class DisplaySampler: NSObject {
    private var link: CADisplayLink?
    private var timing = DisplayTimingWindow()
    private var frames = 0
    private var lastSample = ProcessInfo.processInfo.systemUptime
    private var lastProbe = -Double.infinity
    private var continuous = false
    private var probeRemaining = 0
    private var previousTarget: CFTimeInterval?
    private var adaptive = false
    private(set) var displayID: CGDirectDisplayID = 0

    func select(_ id: CGDirectDisplayID, force: Bool = false, active: Bool = false, enabled: Bool = true) {
        let changed = id != displayID || force
        let wasContinuous = continuous
        if changed {
            stop()
            timing.reset()
            lastProbe = -Double.infinity
            displayID = id
        }
        guard enabled else { continuous = false; stop(); return }
        continuous = active
        if active {
            probeRemaining = 0
            if link == nil { start() }
        } else {
            if wasContinuous { stop() }
            if link == nil && ProcessInfo.processInfo.systemUptime - lastProbe >= 30 {
                probeRemaining = 10
                lastProbe = ProcessInfo.processInfo.systemUptime
                start()
            }
        }
    }

    private func start() {
        guard let screen = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
        }) else { return }
        frames = 0; previousTarget = nil; timing.reset(); lastSample = ProcessInfo.processInfo.systemUptime
        adaptive = DisplayRatePolicy.isAdaptive(lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled,
            minimumInterval: screen.minimumRefreshInterval, maximumInterval: screen.maximumRefreshInterval)
        let candidate = screen.displayLink(target: self, selector: #selector(displayTick(_:)))
        let maximum = Float(max(1, screen.maximumFramesPerSecond))
        candidate.preferredFrameRateRange = CAFrameRateRange(minimum: min(30, maximum), maximum: maximum, preferred: maximum)
        candidate.add(to: .main, forMode: .common)
        link = candidate
    }

    private func stop() { link?.invalidate(); link = nil; frames = 0 }

    @objc private func displayTick(_ link: CADisplayLink) {
        if let previousTarget { timing.append(link.targetTimestamp - previousTarget) }
        previousTarget = link.targetTimestamp
        frames += 1
        if !continuous {
            probeRemaining -= 1
            if probeRemaining <= 0 { stop() }
        }
    }

    func sample() -> (fps: Double?, hz: Double?, source: String, adaptive: Bool) {
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = now - lastSample
        let fps = continuous && frames > 0 && elapsed >= 0.2 ? Double(frames) / elapsed : nil
        frames = 0; lastSample = now
        let power = ProcessInfo.processInfo.isLowPowerModeEnabled ? " · Low Power Mode" : ""
        if adaptive { return (fps, nil, "Low Power Mode · adaptive panel refresh unavailable; display callbacks are not physical scanout", true) }
        if let hz = timing.hz { return (fps, hz, "Core Animation display timing" + power, false) }
        return (fps, nil, "Updating display timing" + power, false)
    }
}
