import Foundation

enum FPSParser {
    private static let patterns = [
        #"\bfps\s*[:=]?\s*([0-9]+(?:[.,][0-9]+)?)\b"#,
        #"\b([0-9]+(?:[.,][0-9]+)?)\s*fps\b"#,
        #"\brender\s*[:=]?\s*([0-9]+(?:[.,][0-9]+)?)\s*/\s*s\b"#
    ].compactMap { try? NSRegularExpression(pattern: $0, options: .caseInsensitive) }
    /// Prefer explicitly labelled render/client stats, and reject server/physics rates.
    static func parse(_ lines: [String]) -> Double? {
        let allowed = lines.filter {
            let text = $0.lowercased()
            return !["heartbeat", "physics", "network", "server", "quartz"].contains(where: text.contains)
        }
        let preferred = allowed.filter {
            let text = $0.lowercased()
            return text.contains("render") || text.contains("client")
        }
        func matches(_ input: [String]) -> [Double] {
            input.flatMap { line in
                patterns.flatMap { regex -> [Double] in
                    let text = line as NSString
                    return regex.matches(in: line, range: NSRange(location: 0, length: text.length)).compactMap {
                        Double(text.substring(with: $0.range(at: 1)).replacingOccurrences(of: ",", with: "."))
                    }
                }
            }.filter { $0.isFinite && $0 >= 1 && $0 <= 1000 }
        }
        // A grouped OCR row may contain render, physics and network columns.
        // Extract only an explicitly labelled render value before rejecting that row.
        let renderPattern = try! NSRegularExpression(pattern: #"\brender\s*(?:fps)?\s*[:=]?\s*([0-9]+(?:[.,][0-9]+)?)\s*(?:fps|/\s*s)\b"#, options: .caseInsensitive)
        let render = lines.compactMap { line -> Double? in
            let text = line as NSString
            guard let match = renderPattern.firstMatch(in: line, range: NSRange(location: 0, length: text.length)) else { return nil }
            return Double(text.substring(with: match.range(at: 1)).replacingOccurrences(of: ",", with: "."))
        }.filter { $0 >= 1 && $0 <= 1000 }
        let explicit = render.isEmpty ? matches(preferred) : render
        let values = explicit.isEmpty ? matches(allowed) : explicit
        guard let first = values.first, values.allSatisfy({ abs($0 - first) < 0.5 }) else { return nil }
        return first
    }

    static func milliseconds(label: String, lines: [String]) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: "\\b" + NSRegularExpression.escapedPattern(for: label) + #"\s*[:=]?\s*([0-9]+(?:[.,][0-9]+)?)\s*ms\b"#, options: .caseInsensitive) else { return nil }
        let values = lines.compactMap { line -> Double? in
            let text = line as NSString
            guard let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: text.length)) else { return nil }
            return Double(text.substring(with: match.range(at: 1)).replacingOccurrences(of: ",", with: "."))
        }.filter { $0.isFinite && $0 >= 0 && $0 < 10000 }
        guard let first = values.first, values.allSatisfy({ abs($0 - first) < 0.5 }) else { return nil }
        return first
    }
}
