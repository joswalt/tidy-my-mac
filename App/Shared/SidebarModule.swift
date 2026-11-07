import SwiftUI

/// The nine sidebar modules in their three groups (spec 007 §2, style guide §6).
enum SidebarModule: String, CaseIterable, Identifiable, Hashable {
    case smartCare, health
    case cleanup, myClutter, spaceLens
    case applications, performance, protection
    case myTools

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smartCare: "Smart Care"
        case .health: "Health"
        case .cleanup: "Cleanup"
        case .myClutter: "My Clutter"
        case .spaceLens: "Space Lens"
        case .applications: "Applications"
        case .performance: "Performance"
        case .protection: "Protection"
        case .myTools: "My Tools"
        }
    }

    var symbol: String {
        switch self {
        case .smartCare: "sparkles"
        case .health: "heart.text.square"
        case .cleanup: "bubbles.and.sparkles"
        case .myClutter: "doc.on.doc"
        case .spaceLens: "chart.pie"
        case .applications: "square.grid.2x2"
        case .performance: "gauge.with.dots.needle.67percent"
        case .protection: "lock.shield"
        case .myTools: "wrench.and.screwdriver"
        }
    }

    enum Group: CaseIterable {
        case top, cleanUp, maintain, bottom

        var title: String? {
            switch self {
            case .top, .bottom: nil
            case .cleanUp: "Clean up"
            case .maintain: "Maintain"
            }
        }

        var modules: [SidebarModule] {
            switch self {
            case .top: [.smartCare, .health]
            case .cleanUp: [.cleanup, .myClutter, .spaceLens]
            case .maintain: [.applications, .performance, .protection]
            case .bottom: [.myTools]
            }
        }
    }
}
