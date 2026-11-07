import SwiftUI

/// Main window: sidebar of modules and a detail column (spec 007 §1).
struct MainWindow: View {
    static let id = "main"

    @SceneStorage("selectedModule") private var selectedRaw = SidebarModule.smartCare.rawValue

    private var selection: Binding<SidebarModule?> {
        Binding(
            get: { SidebarModule(rawValue: selectedRaw) ?? .smartCare },
            set: { selectedRaw = ($0 ?? .smartCare).rawValue }
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
        } detail: {
            ModuleDetail(module: selection.wrappedValue ?? .smartCare)
        }
        .frame(minWidth: 900, minHeight: 600)
    }

    private func rows(_ modules: [SidebarModule]) -> some View {
        ForEach(modules) { module in
            Label(module.title, systemImage: module.symbol)
                .symbolRenderingMode(.hierarchical)
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
