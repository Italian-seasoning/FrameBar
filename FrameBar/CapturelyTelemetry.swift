import Foundation

/// A small local snapshot, shared without another capture stream or network service.
enum CapturelyTelemetry {
    private static let queue = DispatchQueue(label: "framebar.capturely.telemetry", qos: .utility)
    static func recordingNeedsFPS(pid: pid_t?) -> Bool {
        guard let pid, let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
              let data = try? Data(contentsOf: support.appendingPathComponent("FrameBar/capturely-request.json")), data.count < 1024,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Double],
              object["gamePID"] == Double(pid), let stamp = object["timestamp"] else { return false }
        return abs(Date().timeIntervalSince1970 - stamp) <= 5
    }
    static func publish(_ metrics: Metrics, pid: pid_t?) {
        guard metrics.robloxActive, metrics.capturelyRecording, let pid else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard let payload = try? encoder.encode(metrics),
              var object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] else { return }
        object["schemaVersion"] = 1
        object["gamePID"] = pid
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
        queue.async {
            guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
            let folder = support.appendingPathComponent("FrameBar", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try data.write(to: folder.appendingPathComponent("capturely-telemetry.json"), options: .atomic)
            } catch { /* Recording must never interrupt the monitor. */ }
        }
    }
}
