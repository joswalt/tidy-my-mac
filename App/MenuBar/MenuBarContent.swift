import Monitors
import SwiftUI

/// The menu bar label: the template sweep glyph, with a dot while an alert is active (spec 011 §1).
/// It also gives the app model a way to open the main window from anywhere.
struct MenuBarLabel: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(nsImage: MenuBarGlyph.image(badge: app.status.showsBadge))
            .onAppear { app.openMainWindow = { openWindow(id: MainWindow.id) } }
    }
}

/// The popover (spec 011, spec 007 §5): status pill, four monitors, two alert switches, buttons.
struct MenuBarContent: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let status = app.status
        let monitor = app.menuBarMonitor
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("TidyMyMac").font(.headline)
                Spacer()
                StatusPill(text: pillText, alert: pillText != "All good")
            }
            VStack(spacing: 2) {
                MonitorRow(symbol: "cpu", title: "CPU", value: monitor.cpu.map(MonitorFormat.percent) ?? "…", help: "Open Activity Monitor", action: openActivityMonitor) {
                    Sparkline(values: monitor.cpuHistory).frame(height: 22)
                }
                MonitorRow(symbol: "memorychip", title: "Memory", value: memoryText(monitor.memory), help: "Open Activity Monitor", action: openActivityMonitor) {
                    if let p = monitor.memory?.pressure {
                        Text("Pressure: \(p.label)").font(.caption).foregroundStyle(pressureColor(p))
                    }
                }
                MonitorRow(symbol: "internaldrive", title: "Storage",
                           value: status.storage.map { "Free \(MonitorFormat.bytes($0.freeBytes)) of \(MonitorFormat.bytes($0.totalBytes))" } ?? "…",
                           help: "Open Disk Map", action: { app.open(.diskMap) }) {
                    if let s = status.storage {
                        ProgressView(value: s.usedFraction).tint(status.lowDiskActive ? .orange : .accentColor)
                    }
                }
                MonitorRow(symbol: "network", title: "Network", value: "↓ \(MonitorFormat.rate(monitor.down))  ↑ \(MonitorFormat.rate(monitor.up))",
                           help: "Open Activity Monitor", action: openActivityMonitor) { EmptyView() }
            }
            Divider()
            AlertSwitches(status: status)
            Divider()
            HStack {
                Button("Open TidyMyMac") { app.showWindow() }
                Spacer()
                Button("Run Tidy Up") { app.runTidyUp() }.buttonStyle(.borderedProminent)
            }
            HStack {
                SettingsLink { Text("Settings…") }.buttonStyle(.link)
                Spacer()
                Button("Quit TidyMyMac") { NSApplication.shared.terminate(nil) }.buttonStyle(.link).keyboardShortcut("q")
            }
            .font(.caption)
        }
        .padding(14)
        .frame(width: 320)
        .onAppear { monitor.open() }
        .onDisappear { monitor.close() }
    }

    var pillText: String {
        let s = app.status
        if s.lowDiskActive { return "Low disk space" }
        if s.trashActive { return "Trash over \(s.trashGB) GB" }
        if app.menuBarMonitor.memory?.pressure == .critical { return "Memory pressure critical" }
        return "All good"
    }

    func memoryText(_ m: MemorySample?) -> String {
        guard let m else { return "…" }
        return "\(MonitorFormat.bytes(Int64(m.usedBytes))) of \(MonitorFormat.bytes(Int64(m.totalBytes)))"
    }

    func pressureColor(_ p: MemoryPressure) -> Color {
        switch p { case .normal: .green; case .warning: .yellow; case .critical: .red }
    }

    func openActivityMonitor() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ActivityMonitor") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}

struct StatusPill: View {
    let text: String
    let alert: Bool

    var body: some View {
        Label(text, systemImage: alert ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .foregroundStyle(alert ? Color.orange : Color.green)
            .background((alert ? Color.orange : Color.green).opacity(0.15), in: Capsule())
    }
}

struct MonitorRow<Detail: View>: View {
    let symbol: String
    let title: String
    let value: String
    let help: String
    let action: () -> Void
    @ViewBuilder let detail: () -> Detail

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Label(title, systemImage: symbol).foregroundStyle(.secondary)
                    Spacer()
                    Text(value).monospacedDigit()
                }
                detail()
            }
            .padding(.vertical, 6).padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// CPU over the last 60 samples.
struct Sparkline: View {
    let values: [Double]

    var body: some View {
        GeometryReader { geo in
            let n = MenuBarMonitor.historyLength
            let step = geo.size.width / CGFloat(n - 1)
            let start = CGFloat(n - values.count) * step
            Path { p in
                for (i, v) in values.enumerated() {
                    let pt = CGPoint(x: start + CGFloat(i) * step, y: geo.size.height * (1 - CGFloat(v)))
                    if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                }
            }
            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

/// Low disk and full Trash switches (spec 011 §4); also in Settings › Alerts.
struct AlertSwitches: View {
    @Environment(AppModel.self) private var app
    @Bindable var status: StatusModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Alert when free space is below \(status.lowDiskGB) GB", isOn: $status.lowDiskAlertOn)
            Toggle("Alert when the Trash is over \(status.trashGB) GB", isOn: $status.trashAlertOn)
                .disabled(app.fullDiskAccess != .granted)
            if app.fullDiskAccess != .granted {
                HStack(spacing: 4) {
                    Text("Needs Full Disk Access").font(.caption).foregroundStyle(.secondary)
                    Button("Set Up…") { app.showSetup = true; app.showWindow() }.buttonStyle(.link).font(.caption)
                }
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }
}
