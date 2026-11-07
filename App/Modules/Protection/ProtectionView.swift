import AppKit
import SwiftUI

/// Protection: app permissions, read-only (build spec §6.10). Each privacy area with a line on
/// what it allows and a button to its System Settings pane. No per-app list: that data is
/// private to macOS.
struct ProtectionView: View {
    struct Area: Identifiable {
        let id: String
        let title: String
        let symbol: String
        let detail: String
    }

    static let areas: [Area] = [
        Area(id: "Privacy_Camera", title: "Camera", symbol: "camera", detail: "Apps that can turn on the camera."),
        Area(id: "Privacy_Microphone", title: "Microphone", symbol: "mic", detail: "Apps that can listen through the microphone."),
        Area(id: "Privacy_ScreenCapture", title: "Screen & System Audio Recording", symbol: "rectangle.dashed.badge.record",
             detail: "Apps that can see what's on your screen and hear the sound your Mac plays."),
        Area(id: "Privacy_Accessibility", title: "Accessibility", symbol: "accessibility",
             detail: "Apps that can control your Mac: click, type and read other apps' windows."),
        Area(id: "Privacy_AllFiles", title: "Full Disk Access", symbol: "externaldrive",
             detail: "Apps that can read every file, including Mail, Messages and Safari data."),
        Area(id: "Privacy_ListenEvent", title: "Input Monitoring", symbol: "keyboard",
             detail: "Apps that can see what you type, even in other apps."),
        Area(id: "Privacy_Automation", title: "Automation", symbol: "gearshape.2",
             detail: "Apps that can control other apps, such as Finder or Mail."),
        Area(id: "Privacy_LocationServices", title: "Location Services", symbol: "location", detail: "Apps that can tell where your Mac is."),
        Area(id: "Privacy_FilesAndFolders", title: "Files & Folders", symbol: "folder",
             detail: "Apps that can open your Desktop, Documents, Downloads or removable drives."),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Review which apps can use each of these. macOS keeps the list; switch an app off there if you don't recognise it or no longer use it.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 12)], spacing: 12) {
                    ForEach(Self.areas) { area in
                        GroupBox {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: area.symbol).font(.title2).foregroundStyle(.tint).frame(width: 30)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(area.title).font(.headline)
                                    Text(area.detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                    Button("Open in System Settings") { Self.open(area.id) }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(8)
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    /// Same fallbacks as the Full Disk Access link (spec 015 §3).
    static func open(_ anchor: String) {
        let candidates = [
            "x-apple.systempreferences:com.apple.preference.security?\(anchor)",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?\(anchor)",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension",
        ]
        for c in candidates {
            if let url = URL(string: c), NSWorkspace.shared.open(url) { return }
        }
    }
}
