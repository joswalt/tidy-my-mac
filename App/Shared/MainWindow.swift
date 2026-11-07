import SwiftUI

/// Main window: sidebar of modules and a detail column (spec 007 §1).
struct MainWindow: View {
    static let id = "main"

    @SceneStorage("selectedModule") private var selectedRaw = SidebarModule.smartCare.rawValue
    @Environment(AppModel.self) private var app
    @Environment(\.openWindow) private var openWindow

    private var selection: Binding<SidebarModule?> {
        Binding(
            get: { app.selectedModule },
            set: { app.selectedModule = $0 ?? .smartCare; selectedRaw = app.selectedModule.rawValue }
        )
    }

    var body: some View {
        NavigationSplitView {
            List(selection: selection) {
                ForEach(SidebarModule.Group.allCases, id: \.self) { group in
                    if let title = group.title {
                        Section(title) { rows(group.modules) }
                    } else {
                        Section { rows(group.modules) }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
            .safeAreaInset(edge: .bottom) { SidebarFooter() }
        } detail: {
            ModuleDetail(module: app.selectedModule)
        }
        .frame(minWidth: 900, minHeight: 600)
        .onAppear { app.openMainWindow = { openWindow(id: MainWindow.id) } }
        .toast(app.toast)
        .sheet(isPresented: Binding(get: { app.showSetup }, set: { app.showSetup = $0 })) { SetupSheet() }
        .onAppear {
            #if DEBUG
            if UserDefaults.standard.string(forKey: "TidyModule") != nil { return }
            #endif
            app.selectedModule = SidebarModule(rawValue: selectedRaw) ?? .smartCare
        }
        .alert("TidyMyMac can't start cleaning", isPresented: .constant(app.loadError != nil)) {
            Button("Quit") { NSApplication.shared.terminate(nil) }
        } message: {
            Text(app.loadError ?? "")
        }
    }

    /// Trailing figures after a scan (spec 007 §2): Applications shows its update count.
    private func badge(_ module: SidebarModule) -> Text? {
        guard module == .applications, app.applications.updateCount > 0 else { return nil }
        let n = app.applications.updateCount
        return Text(n == 1 ? "1 update" : "\(n) updates")
    }

    private func rows(_ modules: [SidebarModule]) -> some View {
        ForEach(modules) { module in
            Label(module.title, systemImage: module.symbol)
                .symbolRenderingMode(.hierarchical)
                .badge(badge(module))
                .tag(module)
        }
    }
}

/// Routes a module to its screen.
struct ModuleDetail: View {
    let module: SidebarModule

    var body: some View {
        Group {
            switch module {
            case .smartCare: SmartCareView()
            case .health: HealthView()
            case .cleanup: CleanupView()
            case .myClutter: MyClutterView()
            case .spaceLens: SpaceLensView()
            case .applications: ApplicationsView()
            case .performance: PerformanceView()
            case .protection: ProtectionView()
            case .myTools: MyToolsView()
            }
        }
        .navigationTitle(module.title)
    }
}

/// Setup status and a way back into setup (spec 007 §2).
struct SidebarFooter: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let s = app.status.storage {
                Button { app.healthTab = .overview; app.selectedModule = .health } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "internaldrive").font(.caption).foregroundStyle(app.status.lowDiskActive ? .orange : .secondary)
                        Text("\(sizeString(s.freeBytes)) free").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.plain)
                .help("Open Health")
            }
            Button { app.showSetup = true } label: {
                HStack(alignment: .top, spacing: 6) {
                    Circle().fill(app.isSetUp ? Color.green : Color.orange).frame(width: 8, height: 8).padding(.top, 4)
                    Text(app.setupLine).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
            .help("Open setup")
        }
        .padding(12)
    }
}
