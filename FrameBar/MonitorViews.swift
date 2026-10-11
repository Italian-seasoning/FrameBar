import SwiftUI

/// One native glass surface per floating panel, with no extra darkening layer.
struct FloatingGlass: ViewModifier {
    var radius: CGFloat = 20
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        Group {
            if reduceTransparency {
                content.background(Color(nsColor: .windowBackgroundColor), in: shape)
            } else if #available(macOS 26.0, *) {
                content.glassEffect(.regular, in: shape)
            } else {
                content.background(.ultraThinMaterial, in: shape)
            }
        }
        // Native refraction can spill into a borderless window's rectangular host.
        // Keep every floating surface and its effect inside the same rounded edge.
        .clipShape(shape)
    }
}

struct MonitorView: View {
    @ObservedObject var store: MonitorStore
    @ObservedObject var preferences: Preferences
    var openSettings: (Bool) -> Void
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "waveform.path.ecg").font(.system(size: 11, weight: .medium)).foregroundStyle(.mint)
                Text("FrameBar").font(.system(size: 11, weight: .semibold))
                Spacer()
                Button { openSettings(false) } label: {
                    Image(systemName: "gearshape").font(.system(size: 12))
                        .frame(width: 23, height: 23).contentShape(Rectangle())
                }.buttonStyle(.plain).foregroundStyle(.secondary)
                    .help("Open settings window")
                    .accessibilityLabel("Settings")
            }.padding(.horizontal, 14).padding(.top, 9).padding(.bottom, 8)
            live
        }
        .frame(width: 256, height: Self.panelHeight(metrics: store.metrics, readerEnabled: preferences.readGameFPS, permission: store.permissionGranted))
        .modifier(FloatingGlass(radius: 18))
        .alert("FrameBar", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
    }

    private var readiness: RecordingReadiness? {
        RecordingReadiness.status(metrics: store.metrics, readerEnabled: preferences.readGameFPS,
                                  permission: store.permissionGranted)
    }
    static func panelHeight(metrics: Metrics, readerEnabled: Bool, permission: Bool) -> CGFloat {
        184 + (metrics.robloxRunning ? 20 : 0)
            + (RecordingReadiness.status(metrics: metrics, readerEnabled: readerEnabled, permission: permission) == nil ? 0 : 20)
    }
    private var live: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                hardware("CPU", Format.number(store.metrics.cpu), "%")
                Rectangle().fill(.primary.opacity(0.08)).frame(width: 0.5, height: 28)
                hardware("RAM", Format.memory(store.metrics.memoryUsed), "G")
                    .help("\(Format.memory(store.metrics.memoryUsed)) of \(Format.memory(store.metrics.memoryTotal)) GiB")
                Rectangle().fill(.primary.opacity(0.08)).frame(width: 0.5, height: 28)
                hardware("GPU", Format.number(store.metrics.gpu), "%")
            }
            Divider().padding(.vertical, 12)
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.metrics.robloxActive ? "GAME FPS" : "DESKTOP FPS").font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(Format.number(store.metrics.robloxActive ? store.metrics.gameFPS : store.metrics.desktopFPS))
                            .font(.system(size: 19, weight: .medium, design: .rounded)).monospacedDigit()
                        if !store.permissionGranted {
                            Button { store.requestScreenAccess() } label: {
                                Image(systemName: "slider.horizontal.3").font(.system(size: 10))
                                    .frame(width: 20, height: 20).contentShape(Rectangle())
                            }.buttonStyle(.plain).foregroundStyle(.secondary)
                                .accessibilityLabel("Set up FPS screen access")
                                .help("Allow screen recording access to measure FPS")
                        } else { Text("fps").font(.system(size: 9)).foregroundStyle(.secondary) }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                    .help(store.metrics.robloxActive ? store.metrics.gameFPSStatus : "Changed screen frames; measured only while this panel is open")
                VStack(alignment: .trailing, spacing: 4) {
                    Text("DISPLAY").font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(store.metrics.refreshAdaptive ? "Adaptive" : Format.number(store.metrics.refreshHz))
                            .font(.system(size: store.metrics.refreshAdaptive ? 13 : 19, weight: .medium, design: .rounded)).monospacedDigit()
                        if !store.metrics.refreshAdaptive { Text("Hz").font(.system(size: 9)).foregroundStyle(.secondary) }
                    }
                }.help("\(store.metrics.displayName) · \(store.metrics.refreshSource)")
            }
            if store.metrics.robloxRunning {
                DataRow(label: "Roblox", value: "\(Format.percent(store.metrics.robloxCPU)) · \(Format.memory(store.metrics.robloxMemory))G", compact: true)
                    .padding(.top, 7).help("Roblox CPU: 100% = one core. Memory is process resident memory.")
            }
            if let readiness {
                HStack(spacing: 5) {
                    if readiness.needsAction {
                        Button {
                            openSettings(true)
                        } label: {
                            Label(readiness.text, systemImage: "exclamationmark.circle")
                                .font(.system(size: 9)).foregroundStyle(.secondary)
                        }.buttonStyle(.plain)
                            .help("Open FPS reader controls. Roblox stats: Shift–F5 or ⌘⇧F5.")
                    } else {
                        Circle().fill(.mint).frame(width: 4, height: 4)
                        Text(readiness.text).font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }.padding(.top, 7)
            }
            HStack(spacing: 5) {
                Circle().fill(pressureColor).frame(width: 4, height: 4)
                Text("Memory \(store.metrics.memoryPressure.lowercased())").font(.system(size: 9)).foregroundStyle(.secondary)
                Spacer()
                Text("\(preferences.interval.formatted())s").font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary)
            }.padding(.top, 12).padding(.bottom, 12)
        }.padding(.horizontal, 14)
    }

    private func hardware(_ title: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 8, weight: .medium)).tracking(0.6).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(value).font(.system(size: 23, weight: .medium, design: .rounded)).monospacedDigit()
                Text(unit).font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: title == "CPU" ? .leading : .center)
            .accessibilityElement(children: .combine)
    }

    private var pressureColor: Color {
        switch store.metrics.memoryPressure { case "Critical": return .red; case "Warning": return .orange; case "Normal": return .mint; default: return .gray }
    }
}

enum SettingsPane: Hashable { case general, menuBar, overlay, capture }

@MainActor final class SettingsNavigation: ObservableObject {
    @Published var pane: SettingsPane = .general
}

struct SettingsView: View {
    @ObservedObject var store: MonitorStore
    @ObservedObject var preferences: Preferences
    @ObservedObject var navigation: SettingsNavigation
    @State private var positionLocked = true

    var body: some View {
        TabView(selection: $navigation.pane) {
            general.tabItem { Label("General", systemImage: "gearshape") }.tag(SettingsPane.general)
            menu.tabItem { Label("Menu Bar", systemImage: "menubar.rectangle") }.tag(SettingsPane.menuBar)
            overlay.tabItem { Label("Overlay", systemImage: "rectangle.on.rectangle") }.tag(SettingsPane.overlay)
            capture.tabItem { Label("FPS & Capture", systemImage: "speedometer") }.tag(SettingsPane.capture)
        }
        .padding(16)
        .frame(minWidth: 480, minHeight: 500)
        .alert("FrameBar", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
    }

    private var general: some View {
        Form {
            Section("Monitoring") {
            HStack {
                Text("Profile")
                Spacer()
                Picker("Profile", selection: Binding(get: { preferences.profile }, set: { preferences.applyProfile($0) })) {
                    ForEach(MonitorProfile.allCases) { Text($0.rawValue).tag($0) }
                }.labelsHidden().fixedSize().frame(width: 110, alignment: .trailing)
            }.help("Quiet skips FPS reads. Debug adds game timings. Recording adds Capturely status; start recording in Capturely. Custom restores your previous readings and sampling.")
            HStack {
                Text("Hardware updates")
                Spacer()
                Picker("Hardware updates", selection: $preferences.interval) {
                    Text("0.5 seconds").tag(0.5); Text("1 second").tag(1.0); Text("2 seconds").tag(2.0)
                }.labelsHidden().fixedSize()
            }
            SettingToggle(title: "Launch at login", isOn: Binding(get: { store.loginEnabled }, set: store.setLogin))
            }
            Section("Data") {
                Button("Export recent readings…") { store.exportCSV() }
                    .help("Export the last five minutes as CSV")
                Text("Readings stay on this Mac. Nothing is uploaded.").font(.callout).foregroundStyle(.secondary)
            }
            Section {
                Button("Quit FrameBar") { NSApp.terminate(nil) }
            }
        }.formStyle(.grouped)
    }

    private var menu: some View {
        Form {
            Section("Appearance") {
            HStack {
                Text("Layout")
                Spacer()
                Picker("Layout", selection: $preferences.menuLayout) {
                    ForEach(MenuBarLayout.allCases) { Text($0.rawValue).tag($0) }
                }.labelsHidden().fixedSize().frame(width: 110, alignment: .trailing)
            }
            SettingToggle(title: "Metric labels", isOn: $preferences.menuLabels)
            SettingToggle(title: "App icon", isOn: $preferences.menuIcon).disabled(preferences.menuMetrics.isEmpty)
            }
            Section("Readings") {
            ForEach(MenuBarMetric.allCases) { metric in
                SettingToggle(title: metric.rawValue, isOn: Binding(get: { preferences.menuMetrics.contains(metric) },
                                                                  set: { preferences.setMenuMetric(metric, enabled: $0) }))
            }
            if preferences.menuMetrics.isEmpty {
                Text("Icon only. Choose any readings to add them.").font(.callout).foregroundStyle(.secondary)
            }
            Text("Game FPS appears during active Roblox only. G is the compact memory label; values use GiB.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }.formStyle(.grouped)
    }

    private var overlay: some View {
        Form {
            Section("Visibility") {
            SettingToggle(title: "Roblox overlay", isOn: $preferences.overlayEnabled)
            SettingToggle(title: "Slim layout", isOn: $preferences.compact)
            SettingToggle(title: "Hide overlay now", isOn: $store.overlayHidden)
            Text("Only in foreground Roblox. Mouse clicks pass through to the game.")
                .font(.callout).foregroundStyle(.secondary)
            }
            Section("Position & appearance") {
            HStack {
                Text("Corner")
                Spacer()
                Picker("Corner", selection: $preferences.corner) { ForEach(OverlayCorner.allCases) { Text($0.rawValue).tag($0) } }
                    .labelsHidden().fixedSize().frame(width: 110, alignment: .trailing)
            }
            OverlayPositionEditor(preferences: preferences, locked: $positionLocked)
            HStack {
                Text("Opacity")
                Spacer()
                Slider(value: $preferences.opacity, in: 0.6...1).frame(width: 110)
                Text("\(Int(preferences.opacity * 100))%").font(.system(size: 9)).monospacedDigit()
            }
            }
            Section("Shortcut") {
            SettingToggle(title: "Hide/show shortcut", isOn: $preferences.shortcutEnabled)
            Text(store.shortcutAvailable ? "⌃⌥⌘O toggles the overlay. No keyboard access permission needed." : "Shortcut unavailable; another app may be using ⌃⌥⌘O.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            DisclosureGroup("Overlay readings") {
                VStack(spacing: 10) {
                    ForEach(OverlayMetric.allCases) { metric in
                        SettingToggle(title: metric.rawValue, isOn: Binding(
                            get: { preferences.overlayMetrics.contains(metric) },
                            set: { preferences.setOverlayMetric(metric, enabled: $0) }))
                        .disabled(preferences.overlayMetrics == [metric])
                    }
                }.padding(.top, 8)
            }
        }.formStyle(.grouped)
    }

    private var capture: some View {
        Form {
            Section("FPS readers") {
            SettingToggle(title: "Desktop FPS estimate", isOn: $preferences.readDesktopFPS)
            SettingToggle(title: "Roblox stats reader", isOn: $preferences.readGameFPS)
            SettingToggle(title: "Low overhead mode", isOn: $preferences.lowPower)
            Text("Low overhead: adaptive 4–30s stats reads. Standard: 2s when stats are readable. Missing stats back off automatically.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Section("Screen access & game stats") {
            Button(store.fpsSetupPending ? "Waiting for foreground Roblox…" : "Check FPS setup") { store.checkFPSSetup() }
                .disabled(store.fpsSetupPending)
            if store.fpsSetupPending {
                HStack {
                    Text("Return to Roblox with its stats visible. One check runs there.").font(.callout).foregroundStyle(.secondary)
                    Button("Cancel") { store.fpsSetupPending = false }
                }
            }
            ForEach(store.fpsSetupItems) { item in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: item.passed ? "checkmark.circle" : "exclamationmark.circle")
                        .foregroundStyle(item.passed ? Color.mint : Color.orange)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.id).fontWeight(.medium)
                        Text(item.detail).font(.callout).foregroundStyle(.secondary)
                    }
                }.accessibilityElement(children: .combine)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(store.lastFPSStatus).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(store.permissionGranted ? "Screen access granted" : "Screen access not confirmed · relaunch after granting")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Retry stats read") { store.retryFPS() }.buttonStyle(.bordered)
                    .disabled(!store.metrics.robloxActive || !preferences.readGameFPS)
            }
            Text("Game FPS reads visible Shift–F5 or ⌘⇧F5 stats. Fn may be needed. Images are discarded.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("Desktop FPS runs only with the menu bar panel open. It pauses in games and may differ from Quartz Debug.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button(store.permissionGranted ? "Screen access settings" : "Enable screen access") {
                if store.permissionGranted { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!) }
                else { store.requestScreenAccess() }
            }.buttonStyle(.bordered)
            }
            Section("Performance") {
            Button(store.auditRunning ? "Measuring for 30 seconds…" : "Run 30-second CPU audit") { store.startCPUAudit() }
                .disabled(store.auditRunning)
            Text("Samples FrameBar's share of one CPU core. For gameplay results, return to Roblox and start Capturely yourself.")
                .font(.callout).foregroundStyle(.secondary)
            ForEach(store.auditResults, id: \.phase) { result in
                VStack(alignment: .leading, spacing: 4) {
                    Text(result.phase).fontWeight(.medium)
                    Text(String(format: "Average %.2f%% · peak sample %.2f%% · %d/%d below 1%%", result.average, result.peak, result.belowBudget, result.samples))
                        .font(.callout).monospacedDigit()
                }
            }
            PerformanceDetailsView(store: store)
            }
        }.formStyle(.grouped)
    }
}

struct OverlayPositionEditor: View {
    @ObservedObject var preferences: Preferences
    @Binding var locked: Bool
    @State private var dragStart: CGPoint?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(preferences.overlayPosition == nil ? "Position" : "Custom position")
                Spacer()
                Button {
                    locked.toggle()
                    dragStart = nil
                } label: {
                    Label(locked ? "Edit" : "Lock", systemImage: locked ? "lock.fill" : "lock.open")
                }.buttonStyle(.bordered)
                    .accessibilityLabel(locked ? "Edit overlay position" : "Lock overlay position")
            }
            GeometryReader { geometry in
                let previewSize = CGSize(width: 150, height: preferences.compact ? 24 : 40)
                let travel = CGSize(width: max(1, geometry.size.width - previewSize.width - 16),
                                    height: max(1, geometry.size.height - previewSize.height - 16))
                let point = OverlayPlacement.position(corner: preferences.corner, custom: preferences.overlayPosition)
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 9).fill(.primary.opacity(0.035))
                    RoundedRectangle(cornerRadius: 9).strokeBorder(.primary.opacity(0.1), lineWidth: 0.5)
                    Text(locked ? "GAME WINDOW" : "DRAG TO POSITION")
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Text("FPS  ·  CPU  RAM  GPU")
                        .font(.system(size: 9, weight: .medium)).foregroundStyle(.mint)
                        .frame(width: previewSize.width, height: previewSize.height)
                        .background(.mint.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.mint.opacity(0.35), lineWidth: 0.5))
                        .offset(x: 8 + point.x * travel.width, y: 8 + point.y * travel.height)
                        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                            guard !locked else { return }
                            if dragStart == nil { dragStart = point }
                            guard let start = dragStart else { return }
                            preferences.overlayPosition = OverlayPlacement.clamped(CGPoint(
                                x: start.x + value.translation.width / travel.width,
                                y: start.y + value.translation.height / travel.height))
                        }.onEnded { _ in dragStart = nil })
                        .accessibilityLabel("Overlay position preview")
                }
            }.frame(height: 100)
            if !locked {
                Text("Drag the mint preview, then lock. Position saves automatically.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text("Horizontal")
                    Spacer()
                    Slider(value: coordinate(\.x), in: 0...1).frame(width: 110)
                        .accessibilityLabel("Overlay horizontal position")
                }
                HStack {
                    Text("Vertical")
                    Spacer()
                    Slider(value: coordinate(\.y), in: 0...1).frame(width: 110)
                        .accessibilityLabel("Overlay vertical position")
                }
            }
        }
    }

    private func coordinate(_ keyPath: WritableKeyPath<CGPoint, CGFloat>) -> Binding<Double> {
        Binding(get: {
            Double(OverlayPlacement.position(corner: preferences.corner, custom: preferences.overlayPosition)[keyPath: keyPath])
        }, set: { value in
            var point = OverlayPlacement.position(corner: preferences.corner, custom: preferences.overlayPosition)
            point[keyPath: keyPath] = CGFloat(value)
            preferences.overlayPosition = OverlayPlacement.clamped(point)
        })
    }
}

struct SettingToggle: View {
    let title: String
    @Binding var isOn: Bool
    var body: some View {
        HStack {
            Text(title)
            Spacer(minLength: 10)
            Toggle(title, isOn: $isOn).labelsHidden().toggleStyle(.switch)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct DataRow: View {
    let label: String
    let value: String
    var compact = false
    var body: some View {
        HStack {
            Text(label).font(.system(size: compact ? 10 : 13)).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.system(size: compact ? 11 : 13, weight: .medium, design: .monospaced)).monospacedDigit()
        }
    }
}

struct MetricLine: View {
    let title: String
    let value: String
    let color: Color
    let values: [Double?]
    var body: some View {
        HStack(spacing: 10) {
            Text(title).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary).frame(width: 29, alignment: .leading)
            Sparkline(values: values, color: color).frame(maxWidth: .infinity).frame(height: 18)
            Text(value).font(.system(size: 16, weight: .medium, design: .rounded)).monospacedDigit().frame(width: 62, alignment: .trailing)
        }.frame(height: 29).accessibilityElement(children: .combine)
    }
}

struct Sparkline: View {
    let values: [Double?]
    let color: Color
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                var drawing = false
                for (index, value) in values.enumerated() {
                    guard let value else { drawing = false; continue }
                    let point = CGPoint(x: Double(index) / Double(max(1, values.count - 1)) * geometry.size.width,
                                        y: (1 - min(100, max(0, value)) / 100) * (geometry.size.height - 2) + 1)
                    if drawing { path.addLine(to: point) } else { path.move(to: point); drawing = true }
                }
            }.stroke(color, style: StrokeStyle(lineWidth: 1.25, lineCap: .round, lineJoin: .round))
        }.accessibilityHidden(true)
    }
}

struct GameOverlayView: View {
    @ObservedObject var store: MonitorStore
    @ObservedObject var preferences: Preferences
    static func rows(_ metrics: [OverlayMetric]) -> [[OverlayMetric]] {
        stride(from: 0, to: metrics.count, by: 4).map { Array(metrics[$0..<min($0 + 4, metrics.count)]) }
    }
    static func width(preferences: Preferences) -> CGFloat {
        guard preferences.compact else { return 232 }
        let widths: [OverlayMetric: CGFloat] = [.fps: 60, .cpu: 48, .ram: 58, .gpu: 48, .frameMS: 54, .ping: 60,
            .gameCPU: 78, .gameRAM: 82, .cpuTime: 76, .gpuTime: 76, .thermal: 92, .recording: 74]
        return max(86, rows(preferences.overlayMetrics).map { row in
            24 + row.reduce(0) { $0 + (widths[$1] ?? 48) } + CGFloat(max(0, row.count - 1)) * 9
        }.max() ?? 86)
    }
    static func height(preferences: Preferences, missingFPS: Bool) -> CGFloat {
        if preferences.compact { return 45 + CGFloat(max(0, rows(preferences.overlayMetrics).count - 1)) * 25 }
        let otherCount = preferences.overlayMetrics.filter { $0 != .fps }.count
        return 20 + (preferences.overlayMetrics.contains(.fps) ? 39 : 0)
            + CGFloat((otherCount + 2) / 3) * 22 + (missingFPS && preferences.overlayMetrics.contains(.fps) ? 15 : 0)
    }
    var body: some View {
        Group {
            if preferences.compact {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(Self.rows(preferences.overlayMetrics).enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                    ForEach(row) { metric in
                        if metric == .fps {
                            HStack(alignment: .firstTextBaseline, spacing: 3) {
                                Text(metric.reading(store.metrics)).font(.system(size: 21, weight: .semibold, design: .rounded)).foregroundStyle(.mint)
                                Text("FPS").font(.system(size: 7, weight: .medium)).foregroundStyle(.secondary)
                            }
                        } else { overlayMetric(metric.shortLabel, metric.reading(store.metrics)) }
                    }
                    }.frame(height: 21)
                    }
                }.padding(.horizontal, 12).padding(.vertical, 9)
            } else {
                VStack(spacing: 7) {
                    if preferences.overlayMetrics.contains(.fps) { HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(Format.number(store.metrics.gameFPS)).font(.system(size: 30, weight: .medium, design: .rounded)).foregroundStyle(.mint)
                        Text("FPS").font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary)
                        Spacer()
                        if let ms = store.metrics.frameMS {
                            Text(String(format: "%.1f ms", ms)).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                        } else { Text("ROBLOX").font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary) }
                    } }
                    if preferences.overlayMetrics.contains(where: { $0 != .fps }) {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 3), spacing: 7) {
                        ForEach(preferences.overlayMetrics.filter { $0 != .fps }) { metric in
                            overlayMetric(metric.shortLabel, metric.reading(store.metrics))
                        }
                        }
                    }
                    if store.metrics.gameFPS == nil && preferences.overlayMetrics.contains(.fps) {
                        Text(store.metrics.gameFPSStatus).font(.system(size: 8)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }.padding(.horizontal, 13).padding(.vertical, 10)
            }
        }.monospacedDigit().frame(width: Self.width(preferences: preferences))
            .modifier(FloatingGlass(radius: preferences.compact ? 15 : 18)).opacity(preferences.opacity)
            .preferredColorScheme(.dark)
    }
    private func overlayMetric(_ name: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(name).font(.system(size: 7, weight: .medium)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 11, weight: .medium, design: .rounded))
        }.accessibilityElement(children: .combine)
    }
}
