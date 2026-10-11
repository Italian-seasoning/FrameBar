import SwiftUI

struct PerformanceDetailsView: View {
    @ObservedObject var store: MonitorStore
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DataRow(label: "FrameBar CPU", value: store.metrics.monitorCPU.map { String(format: "%.2f%%", $0) } ?? "—")
            DataRow(label: "FrameBar RAM", value: Format.number(store.metrics.monitorMemory) + " MB")
            DataRow(label: "Thermal state", value: store.metrics.thermalState)
            DataRow(label: "Stats read interval", value: "\(Int(store.fpsReadInterval))s")
            DisclosureGroup("Game technical stats") {
                VStack(spacing: 8) {
                    DataRow(label: "Roblox CPU · one core", value: Format.percent(store.metrics.robloxCPU))
                    DataRow(label: "Roblox RAM", value: Format.memory(store.metrics.robloxMemory) + "G")
                    DataRow(label: "Frame period · derived", value: milliseconds(store.metrics.frameMS))
                    DataRow(label: "CPU · visible stats", value: milliseconds(store.metrics.gameCPUMS))
                    DataRow(label: "GPU · visible stats", value: milliseconds(store.metrics.gameGPUMS))
                    DataRow(label: "Ping · visible stats", value: milliseconds(store.metrics.pingMS))
                }.padding(.top, 8)
            }
            DisclosureGroup("Session summary") {
                VStack(alignment: .leading, spacing: 8) {
                    if let session = store.currentSession ?? store.recentSessions.first {
                        Text(store.currentSession == nil ? "LAST SESSION" : "CURRENT SESSION")
                            .font(.caption).foregroundStyle(.secondary)
                        summary(session)
                        if store.currentSession != nil {
                            Button("Reset session") { store.resetSession() }.buttonStyle(.bordered)
                        }
                    } else { Text("Open Roblox to start a session.").font(.callout).foregroundStyle(.secondary) }
                    Text("FPS summary uses independent OCR samples, not every rendered frame. Five completed summaries stay on this Mac.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.padding(.top, 8)
            }
            DisclosureGroup("Frame timings · 1% lows") {
                VStack(alignment: .leading, spacing: 8) {
                    Button(store.importingFrames ? "Importing…" : "Import frame capture…") { store.importFrameTimings() }
                        .buttonStyle(.bordered).disabled(store.importingFrames)
                    Text("Import a client MicroProfiler HTML dump or per-frame CSV (frame_ms). These are capture results, not live overlay readings.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if let report = store.frameReport {
                        Text(report.name).font(.callout).lineLimit(2).foregroundStyle(.secondary)
                        DataRow(label: "Captured frames", value: "\(report.count)")
                        DataRow(label: "Average FPS", value: Format.number(report.averageFPS))
                        DataRow(label: "1% low FPS", value: Format.number(report.onePercentLow))
                        DataRow(label: "0.1% low FPS", value: Format.number(report.pointOnePercentLow))
                        DataRow(label: "Median frame", value: milliseconds(report.medianMS))
                        DataRow(label: "P95 / P99", value: "\(decimal(report.p95MS)) / \(decimal(report.p99MS))ms")
                        DataRow(label: "Worst frame", value: milliseconds(report.worstMS))
                        DataRow(label: "Frames >33.3ms", value: "\(report.over33MS)")
                        Text("Lows = 1000 ÷ mean duration of the slowest 1% / 0.1% of frames. Minimum 100 / 1000 frames respectively.")
                            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }.padding(.top, 8)
            }
        }
    }

    private func summary(_ session: SessionSummary) -> some View {
        VStack(spacing: 8) {
            DataRow(label: "FPS samples", value: "\(session.fpsSamples)")
            DataRow(label: "Sample average FPS", value: Format.number(session.averageFPS))
            DataRow(label: "Sample min / max", value: "\(Format.number(session.minimumFPS)) / \(Format.number(session.maximumFPS))")
            DataRow(label: "Peak Roblox RAM", value: Format.memory(session.peakMemory) + "G")
            DataRow(label: "Peak Roblox CPU", value: Format.percent(session.peakCPU))
            DataRow(label: "Peak system GPU", value: Format.percent(session.peakGPU))
        }
    }
    private func decimal(_ value: Double) -> String { String(format: "%.1f", value) }
    private func milliseconds(_ value: Double?) -> String { value.map { decimal($0) + "ms" } ?? "—" }
}
