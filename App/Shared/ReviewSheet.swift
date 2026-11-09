import RuleEngine
import SwiftUI

/// Grouped review of everything found (spec 007 §3.4): a disclosure per category with a
/// tri-state tick, item rows, a filter and the same live summary as the footer.
struct ReviewSheet: View {
    @Bindable var session: ScanSession
    var onDryRun: (() -> Void)? = nil
    let onClean: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var filter = Filter.all
    @State private var expanded: Set<String> = []

    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", selected = "Selected"
        var id: String { rawValue }
    }

    var groups: [RuleScanResult] { (session.report?.results ?? []).filter { !$0.candidates.isEmpty } }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Review").font(.title2)
                Spacer()
                let all = groups.flatMap(\.candidates)
                CheckAllButtons(canCheckAll: !all.filter { $0.risk != .risky }.allSatisfy(session.selection.contains),
                                canCheckNone: all.contains(where: session.selection.contains),
                                allNote: all.contains { $0.risk == .risky } ? "Check every item except risky ones, which you check one by one" : nil,
                                checkAll: { session.selection.setGroup(all, true) },
                                checkNone: { session.selection.setGroup(all, false) })
                Picker("Show", selection: $filter) {
                    ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).fixedSize()
            }
            .padding(20)
            List {
                ForEach(groups, id: \.rule.id) { group in
                    let items = filter == .all ? group.candidates : group.candidates.filter(session.selection.contains)
                    if !items.isEmpty {
                        DisclosureGroup(isExpanded: Binding(get: { expanded.contains(group.rule.id) },
                                                            set: { if $0 { expanded.insert(group.rule.id) } else { expanded.remove(group.rule.id) } })) {
                            ForEach(items) { c in ReviewRow(session: session, candidate: c) }
                        } label: {
                            HStack {
                                if group.rule.risk == .risky {
                                    Image(systemName: "hand.raised").foregroundStyle(.secondary).help("Risky items are ticked one by one")
                                        .accessibilityLabel("Risky items are ticked one by one")
                                } else {
                                    TriStateBox(state: session.selection.state(of: group.candidates), name: group.rule.title) {
                                        session.selection.setGroup(group.candidates, session.selection.state(of: group.candidates) != .all)
                                    }
                                }
                                Text(group.rule.title).font(.headline)
                                RiskBadge(risk: group.rule.risk)
                                Spacer()
                                Text(sizeString(group.totalBytes)).monospacedDigit().foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            FooterBar(summary: session.summary.line) {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                if let onDryRun {
                    Button("Dry Run") { dismiss(); onDryRun() }
                        .help("List exactly what would be removed, without changing anything")
                        .disabled(session.summary.itemCount == 0)
                }
                Button(session.summary.itemCount == 0 ? "Clean" : "Clean \(sizeString(session.summary.totalBytes))") { dismiss(); onClean() }
                    .buttonStyle(.borderedProminent)
                    .disabled(session.summary.itemCount == 0)
            }
        }
        .frame(minWidth: 720, minHeight: 520)
    }
}

struct ReviewRow: View {
    @Bindable var session: ScanSession
    let candidate: Candidate

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(get: { session.selection.contains(candidate) }, set: { session.selection.set(candidate, $0) }))
                .labelsHidden()
                .accessibilityLabel("Select \(candidate.name)")
            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.name).lineLimit(1)
                PathText(path: candidate.path)
            }
            Spacer()
            DestinationLabel(action: candidate.action)
            Text(sizeString(candidate.allocatedBytes)).monospacedDigit().frame(width: 80, alignment: .trailing)
        }
    }
}
