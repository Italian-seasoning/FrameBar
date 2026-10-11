import Foundation
import ScreenCaptureKit
import CoreMedia
import CoreGraphics

/// A ScreenCaptureKit estimate of changed display frames, not a private WindowServer counter.
/// Pixel buffers are discarded immediately; only frame-status counts are retained.
final class ScreenUpdateSampler: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.framebar.screen-updates", qos: .utility)
    private let lock = NSLock()
    private var frames = 0
    private var sampledAt = ProcessInfo.processInfo.systemUptime
    private var running = false
    private var stream: SCStream?
    private var selectedDisplay: CGDirectDisplayID?
    private var lastPTS = CMTime.invalid
    private var configuring = false
    private var status = "Screen recording permission needed"

    @MainActor func configure(display: CGDirectDisplayID, enabled: Bool) async {
        // Caller serializes configuration; the timer never launches concurrent starts/stops.
        guard !configuring else { return }
        configuring = true
        defer { configuring = false }
        if !enabled || !CGPreflightScreenCaptureAccess() {
            if let stream { try? await stream.stopCapture() }
            stream = nil; selectedDisplay = nil
            setState(false, enabled ? "Screen recording permission needed" : "Desktop counter off")
            return
        }
        let alive = isRunning()
        if selectedDisplay == display && stream != nil && alive { return }
        if let stream { try? await stream.stopCapture() }
        stream = nil; selectedDisplay = nil
        setState(false, "Starting desktop counter")
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            guard let selected = content.displays.first(where: { $0.displayID == display }) else {
                setState(false, "Display unavailable"); return
            }
            let ownApp = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
            let filter = SCContentFilter(display: selected, excludingApplications: ownApp, exceptingWindows: [])
            let config = SCStreamConfiguration()
            config.width = 64
            config.height = max(16, Int(64 * Double(selected.height) / Double(selected.width)))
            config.minimumFrameInterval = CMTime(value: 1, timescale: 240)
            config.queueDepth = 3
            config.showsCursor = false
            config.capturesAudio = false
            let candidate = SCStream(filter: filter, configuration: config, delegate: self)
            try candidate.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
            try await candidate.startCapture()
            stream = candidate; selectedDisplay = display
            setState(true, "Changed frames · capture estimate")
        } catch {
            setState(false, "Capture unavailable; check screen access")
        }
    }

    private func setState(_ active: Bool, _ message: String) {
        lock.lock(); defer { lock.unlock() }
        running = active; status = message; frames = 0
        sampledAt = ProcessInfo.processInfo.systemUptime; lastPTS = .invalid
    }

    private func isRunning() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return running
    }

    func sample() -> (Double?, String) {
        lock.lock(); defer { lock.unlock() }
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = now - sampledAt
        let rate = running && elapsed >= 0.2 ? Double(frames) / elapsed : nil
        frames = 0; sampledAt = now
        return (rate, status)
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, buffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: raw) == .complete else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(buffer)
        lock.lock(); defer { lock.unlock() }
        if !lastPTS.isValid || CMTimeCompare(pts, lastPTS) > 0 {
            frames += 1; lastPTS = pts
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        setState(false, "Desktop capture stopped; retrying")
    }
}
