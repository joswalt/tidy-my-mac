import AppKit
import RuleEngine
import SwiftUI

/// "Some apps should be quit": shown after the clean confirmation when open apps own ticked items,
/// such as Google Chrome for ~/Library/Caches/Google. Quit asks each app to quit the normal way
/// (it can still ask to save), never forces it. Ignore cleans the rest and skips those apps' items.
struct QuitAppsSheet: View {
    let request: ScanSession.QuitRequest
    let onFinish: (_ proceed: Bool) -> Void

    @State private var quitting: Set<RunningApp> = []
    @State private var quit: Set<RunningApp> = []
    @State private var stuck: Set<RunningApp> = []
    @State private var finished = false

    var open: [RunningApp] { request.apps.filter { !quit.contains($0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Some apps should be quit").font(.title3.weight(.semibold))
                Text("Quit these apps so TidyMyMac can clean their caches. If you ignore them, their items are skipped this time.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
            Divider()
            VStack(spacing: 0) {
                ForEach(open) { app in
                    row(app)
                    if app != open.last { Divider().padding(.leading, 60) }
                }
            }
            .padding(.vertical, 6)
            Divider()
            HStack {
                Button("Cancel") { finished = true; onFinish(false) }.keyboardShortcut(.cancelAction)
                    .disabled(finished)
                Spacer()
                Button("Ignore") { finished = true; onFinish(true) }
                    .disabled(finished)
                    .help("Clean everything else and skip the items of these apps")
                Button("Quit All") { Task { await quitAll() } }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!quitting.isEmpty || finished)
            }
            .padding(20)
        }
        .frame(width: 440)
    }

    func row(_ app: RunningApp) -> some View {
        HStack(spacing: 12) {
            Image(nsImage: icon(app)).resizable().frame(width: 32, height: 32).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                if stuck.contains(app) {
                    Text("Didn't quit. It may be asking you something.").font(.caption).foregroundStyle(.orange)
                }
            }
            Spacer()
            if quitting.contains(app) {
                ProgressView().controlSize(.small).accessibilityLabel("Quitting \(app.name)")
            } else {
                Button("Quit") { Task { await quitOne(app) } }
                    .accessibilityLabel("Quit \(app.name)")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    func icon(_ app: RunningApp) -> NSImage {
        NSRunningApplication(processIdentifier: app.pid)?.icon ?? NSWorkspace.shared.icon(for: .application)
    }

    func quitAll() async {
        // Ask every app at once, then wait for each.
        let asked = open.filter { !quitting.contains($0) }.compactMap { app in ask(app).map { (app, $0) } }
        for (app, r) in asked { await wait(app, r) }
        finishIfAllQuit()
    }

    func quitOne(_ app: RunningApp) async {
        if let r = ask(app) { await wait(app, r) }
        finishIfAllQuit()
    }

    /// Asks the app to quit the normal way; nil if it is already gone.
    func ask(_ app: RunningApp) -> NSRunningApplication? {
        stuck.remove(app)
        guard let r = NSRunningApplication(processIdentifier: app.pid), r.bundleIdentifier == app.bundleID, !r.isTerminated else {
            quit.insert(app)
            return nil
        }
        quitting.insert(app)
        r.terminate()
        return r
    }

    /// Waits up to 15 seconds for the app to go.
    func wait(_ app: RunningApp, _ r: NSRunningApplication) async {
        let deadline = Date().addingTimeInterval(15)
        while !r.isTerminated && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(200))
        }
        quitting.remove(app)
        if r.isTerminated { quit.insert(app) } else { stuck.insert(app) }
    }

    func finishIfAllQuit() {
        guard open.isEmpty, !finished else { return }
        finished = true
        Task {
            // Let the apps' helper processes finish closing their files.
            try? await Task.sleep(for: .milliseconds(500))
            onFinish(true)
        }
    }
}

extension View {
    /// Presents QuitAppsSheet for `session.quitRequest`; continues the clean on Quit All or Ignore.
    func quitAppsPrompt(_ session: ScanSession) -> some View {
        modifier(QuitAppsPrompt(session: session))
    }
}

private struct QuitAppsPrompt: ViewModifier {
    @Bindable var session: ScanSession

    func body(content: Content) -> some View {
        content.sheet(item: $session.quitRequest) { request in
            QuitAppsSheet(request: request) { proceed in
                session.quitRequest = nil
                if proceed { request.proceed() }
            }
            .interactiveDismissDisabled()
        }
    }
}
