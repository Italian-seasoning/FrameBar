import Foundation

struct SessionSummary: Codable, Equatable {
    var started = Date()
    var ended: Date?
    var hardwareSamples = 0
    var fpsSamples = 0
    var fpsSum = 0.0
    var minimumFPS: Double?
    var maximumFPS: Double?
    var peakMemory = 0.0
    var peakGPU = 0.0
    var peakCPU = 0.0
    var averageFPS: Double? { fpsSamples > 0 ? fpsSum / Double(fpsSamples) : nil }
    mutating func recordHardware(_ metrics: Metrics) {
        hardwareSamples += 1
        peakMemory = max(peakMemory, metrics.robloxMemory ?? 0)
        peakGPU = max(peakGPU, metrics.gpu ?? 0)
        peakCPU = max(peakCPU, metrics.robloxCPU ?? 0)
    }
    mutating func recordFPS(_ fps: Double?) {
        guard let fps, fps.isFinite, fps > 0 else { return }
        fpsSamples += 1; fpsSum += fps
        minimumFPS = min(minimumFPS ?? fps, fps)
        maximumFPS = max(maximumFPS ?? fps, fps)
    }
}

struct FrameTimingReport {
    let name: String
    let count: Int
    let averageFPS: Double
    let onePercentLow: Double?
    let pointOnePercentLow: Double?
    let medianMS: Double
    let p95MS: Double
    let p99MS: Double
    let worstMS: Double
    let over33MS: Int

    init?(milliseconds: [Double], name: String) {
        guard milliseconds.count >= 2, milliseconds.count <= 1_000_000,
              milliseconds.allSatisfy({ $0.isFinite && $0 > 0 && $0 <= 60000 }) else { return nil }
        let sorted = milliseconds.sorted()
        self.name = name; count = sorted.count
        averageFPS = 1000 / (sorted.reduce(0, +) / Double(count))
        func percentile(_ value: Double) -> Double {
            sorted[max(0, min(sorted.count - 1, Int(ceil(Double(sorted.count) * value)) - 1))]
        }
        func low(_ proportion: Double, minimum: Int) -> Double? {
            guard sorted.count >= minimum else { return nil }
            let tail = sorted.suffix(max(1, Int(ceil(Double(sorted.count) * proportion))))
            return 1000 / (tail.reduce(0, +) / Double(tail.count))
        }
        onePercentLow = low(0.01, minimum: 100)
        pointOnePercentLow = low(0.001, minimum: 1000)
        medianMS = percentile(0.5); p95MS = percentile(0.95); p99MS = percentile(0.99)
        worstMS = sorted.last!; over33MS = sorted.filter { $0 > 33.333333 }.count
    }
}

enum FrameTimingImport {
    /// Extract literal frame boundaries without evaluating any HTML or JavaScript.
    static func parse(_ source: String, name: String) -> FrameTimingReport? {
        let number = #"([-+]?[0-9]+(?:\.[0-9]+)?(?:[eE][-+]?[0-9]+)?)"#
        let pattern = #"(?:\bS\.)?\bFrames\[(\d+)\]\s*=\s*MakeFrame\(\s*\d+\s*,\s*"# + number + #"\s*,\s*"# + number + #"\s*,"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let text = source as NSString
        let matches = regex.matches(in: source, range: NSRange(location: 0, length: text.length))
        if !matches.isEmpty {
            var durations: [Double] = []
            var previousIndex: Int?
            var previousEnd: Double?
            for match in matches {
                guard let index = Int(text.substring(with: match.range(at: 1))),
                      let start = Double(text.substring(with: match.range(at: 2))),
                      let end = Double(text.substring(with: match.range(at: 3))),
                      start.isFinite, end.isFinite, end > start,
                      previousIndex == nil || index == previousIndex! + 1,
                      previousEnd == nil || abs(start - previousEnd!) < 0.1 else { return nil }
                durations.append(end - start)
                previousIndex = index; previousEnd = end
            }
            return FrameTimingReport(milliseconds: durations, name: name)
        }
        // Explicit per-frame CSV only; sampled FPS exports are deliberately rejected.
        let lines = source.split(whereSeparator: \.isNewline)
        guard let header = lines.first else { return nil }
        let columns = header.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        guard let index = columns.firstIndex(of: "frame_ms") else { return nil }
        var durations: [Double] = []
        for line in lines.dropFirst() {
            let cells = line.split(separator: ",", omittingEmptySubsequences: false)
            guard cells.indices.contains(index), let value = Double(cells[index].trimmingCharacters(in: .whitespaces)) else { return nil }
            durations.append(value)
        }
        return FrameTimingReport(milliseconds: durations, name: name)
    }
}
