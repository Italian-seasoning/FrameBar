import Foundation
import ScreenCaptureKit
import Vision
import CoreGraphics

actor GameFPSReader {
    struct Reading {
        var fps: Double?
        var status: String
        var ping: Double?
        var cpuMS: Double?
        var gpuMS: Double?
        var captured = false
    }
    private var cachedWindow: SCWindow?
    private var cachedAt = Date.distantPast
    private var cachedPID: pid_t?

    func read(pid: pid_t, accurate: Bool = false) async -> Reading {
        do {
            if cachedPID != pid || Date().timeIntervalSince(cachedAt) > 10 || cachedWindow == nil {
                let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
                cachedWindow = content.windows.filter {
                    $0.owningApplication?.processID == pid && $0.windowLayer == 0 && $0.frame.width > 250 && $0.frame.height > 200
                }.max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
                cachedPID = pid
                cachedAt = Date()
            }
            guard let window = cachedWindow else { return Reading(status: "Waiting for a Roblox game window") }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let config = SCStreamConfiguration()
            // Preserve text resolution, capped at 1920 pixels; caller limits captures to one every two seconds.
            let scale = min(2, 1600 / max(1, window.frame.width))
            config.width = Int(window.frame.width * scale)
            config.height = Int(window.frame.height * scale)
            config.showsCursor = false
            config.ignoreShadowsSingleWindow = true
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            let crop = CGRect(x: 0, y: 0, width: image.width, height: Int(Double(image.height) * 0.4)).integral
            guard let statsImage = image.cropping(to: crop) else { return Reading(status: "Stats image unavailable") }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = accurate ? .accurate : .fast
            request.usesLanguageCorrection = false
            request.recognitionLanguages = ["en-US"]
            // Roblox debug stats are in the top-left. No full desktop or other app is read.
            try VNImageRequestHandler(cgImage: statsImage).perform([request])
            let observations = (request.results ?? []).filter { ($0.topCandidates(1).first?.confidence ?? 0) >= 0.4 }
            var rows: [(Double, [(Double, String)])] = []
            for observation in observations.sorted(by: { $0.boundingBox.midY > $1.boundingBox.midY }) {
                guard let text = observation.topCandidates(1).first?.string else { continue }
                if let index = rows.indices.first(where: { abs(rows[$0].0 - observation.boundingBox.midY) < 0.008 }) {
                    rows[index].1.append((observation.boundingBox.minX, text))
                } else { rows.append((observation.boundingBox.midY, [(observation.boundingBox.minX, text)])) }
            }
            let lines = observations.compactMap { $0.topCandidates(1).first?.string } + rows.map { $0.1.sorted { $0.0 < $1.0 }.map(\.1).joined(separator: " ") }
            let fps = FPSParser.parse(lines)
            return Reading(fps: fps, status: fps != nil ? "Reading visible Roblox stats" : "No FPS label found · try Shift–F5 or ⌘⇧F5 (Fn may be needed)",
                           ping: FPSParser.milliseconds(label: "Ping", lines: lines),
                           cpuMS: FPSParser.milliseconds(label: "CPU", lines: lines),
                           gpuMS: FPSParser.milliseconds(label: "GPU", lines: lines), captured: true)
        } catch {
            cachedWindow = nil
            let detail = error as NSError
            return Reading(status: "Capture failed (\(detail.domain) \(detail.code)) · check access, then relaunch FrameBar")
        }
    }
}
