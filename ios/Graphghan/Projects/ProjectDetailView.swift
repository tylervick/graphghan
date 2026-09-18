import SwiftUI
import GraphghanCore

struct ProjectDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let project: Project
    @State private var sequence: WorkSequence?
    @State private var summary: ProgressSummary?
    @State private var loadError: String?
    @State private var manifest: PatternManifest?
    @State private var notes: String = ""
    @State private var showJump = false
    @State private var confirmDelete = false
    @State private var confirmFinish = false
    @State private var switching = false
    /// A mutation that failed: shown as an alert, so nothing looks as though it worked when it did not.
    @State private var actionError: String?

    /// "N stitches · M min" for a stitch chart -- byte-identical to before #44 -- and the matching
    /// noun for anything else, so a filet session never gets mislabelled "stitches".
    static func sessionValueText(cells: Int, cellKind: CellKind, seconds: Int) -> String {
        "\(cells) \(cellKind.nounPlural) · \(max(1, seconds / 60)) min"
    }

    var body: some View {
        List {
            if let sequence, let summary {
                Section {
                    ProgressView(value: summary.percent, total: 100).tint(.heather)
                    LabeledContent("Row", value: project.isFinished ? "Finished" : "\(project.cursor.row) of \(sequence.passes.count)")
                    LabeledContent(sequence.cellKind.label, value: "\(summary.cellsDone.formatted()) of \(summary.totalCells.formatted())")
                    if let rate = summary.stitchesPerHour { LabeledContent("Pace", value: "\(rate.formatted()) stitches per hour") }
                    if let finish = model.projects.estimatedFinish(from: summary) {
                        LabeledContent("Estimated finish", value: finish.formatted(date: .long, time: .omitted))
                    }
                }
                Section {
                    Button { model.workingProject = project } label: { Label("Work", systemImage: "play.fill") }
                        .disabled(project.isFinished)
                    NavigationLink {
                        ChartBrowserView(title: project.title, highlightRow: project.cursor.row) { try await model.projects.chart(for: project) }
                    } label: { Label("Browse chart at row \(project.cursor.row)", systemImage: "square.grid.3x3") }
                    Button { showJump = true } label: { Label("Jump to row", systemImage: "arrow.turn.down.right") }
                }
                if let notice = manifest.flatMap({ model.projects.versionNotice(for: project, manifest: $0) }) {
                    Section("Pattern updated") { versionNotice(notice) }
                }
                Section("Notes") {
                    TextField("Yarn lots, hook, reminders…", text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                        .onChange(of: notes) { _, new in try? model.projects.setNotes(new, for: project) }
                }
                if !summary.sessions.isEmpty {
                    Section("Sessions") {
                        ForEach(Array(summary.sessions.suffix(10).reversed().enumerated()), id: \.offset) { _, s in
                            LabeledContent(s.start.formatted(date: .abbreviated, time: .shortened),
                                           value: Self.sessionValueText(cells: s.cells, cellKind: sequence.cellKind, seconds: s.seconds))
                        }
                    }
                }
                Section {
                    if project.isFinished {
                        Button("Mark unfinished") {
                            do { try model.projects.markUnfinished(project) }
                            catch { actionError = "Couldn't reopen this project: \(error.localizedDescription)" }
                        }
                    } else {
                        Button("Mark finished") { confirmFinish = true }
                    }
                    Button("Delete project", role: .destructive) { confirmDelete = true }
                }
            } else if let loadError {
                Section {
                    ContentUnavailableView("Chart missing", systemImage: "exclamationmark.triangle", description: Text(loadError))
                    Button("Download again") { Task { await redownload() } }
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle(project.title)
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(Color.ground.weave().ignoresSafeArea())
        .listRowBackgroundPanel()
        .sheet(isPresented: $showJump) {
            if let sequence {
                JumpToRowSheet(rowCount: sequence.passes.count, current: project.cursor.row) { row in
                    model.projects.apply(.jump(row: row), to: project, in: sequence)
                }
            }
        }
        .confirmationDialog("Delete this project and its progress?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                // Only leave the screen if the project really went; otherwise the list would still
                // show it and the delete would look as though it had worked.
                do {
                    try model.projects.delete(project)
                    dismiss()
                } catch {
                    actionError = "Couldn't delete this project: \(error.localizedDescription)"
                }
            }
        }
        .confirmationDialog("Mark this project finished?", isPresented: $confirmFinish, titleVisibility: .visible) {
            Button("Mark finished") {
                do { try model.projects.markFinished(project) }
                catch { actionError = "Couldn't mark this project finished: \(error.localizedDescription)" }
            }
        }
        .alert("Something went wrong", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
        .safeAreaInset(edge: .top) {
            if let error = model.projects.lastError {
                Banner(text: "Couldn't save your progress: \(error)", kind: .failure, action: .init(label: "Dismiss") { model.projects.lastError = nil })
            }
        }
        .task { await load() }
        // The summary walks every event; recompute it when the project changes outside the Work
        // screen, never on each tap behind the cover (see ProjectSummaryKey).
        .task(id: SummaryRefresh(key: ProjectSummaryKey.make(for: project, working: model.workingProject), chartID: sequence == nil ? nil : project.chartID)) {
            guard let sequence, ProjectSummaryKey.make(for: project, working: model.workingProject) != nil || summary == nil else { return }
            summary = model.projects.summary(for: project, sequence: sequence)
        }
    }

    private struct SummaryRefresh: Hashable { let key: ProjectSummaryKey?; let chartID: String? }

    private func load() async {
        notes = project.notes
        do { sequence = try await model.projects.sequence(for: project) }
        catch { loadError = "This project's chart could not be read. Download it again to continue." }
        manifest = try? await model.manifest(for: project.patternID, path: nil)
    }

    private func redownload() async {
        // Swift's `??` autoclosure for its right-hand side isn't `async`, so `manifest ?? (try?
        // await …)` can't compile here (SE-0296 doesn't cover this operator); resolve the fallback
        // with an explicit if/else instead, preserving the brief's "use the cached manifest, else
        // refetch it" behaviour.
        let resolvedManifest: PatternManifest?
        if let manifest { resolvedManifest = manifest }
        else { resolvedManifest = try? await model.manifest(for: project.patternID, path: nil) }
        guard let manifest = resolvedManifest else {
            loadError = "Couldn't reach graphghan.milo.cat."
            return
        }
        guard let chart = manifest.charts.first(where: { $0.id == project.chartID }) else {
            loadError = "This chart is no longer published; the pattern was updated after this project started."
            return
        }
        do {
            let data = try await model.patterns.chartData(for: manifest.id, path: chart.path)
            _ = try await model.charts.store(data)
        } catch {
            loadError = "Couldn't download the chart. Check your connection and try again."
            return
        }
        loadError = nil
        await load()
    }

    @ViewBuilder private func versionNotice(_ notice: ProjectService.VersionNotice) -> some View {
        switch notice {
        case .chartChanged(let newChart, let newVersion, let canSwitch):
            Text("Version \(newVersion) of this pattern changed the \(newChart.variant) · \(newChart.gaugeKey) chart. This project keeps the chart it started with.")
                .font(Font.Heather.caption)
            if canSwitch, let manifest {
                Button(switching ? "Switching…" : "Switch to the new chart") {
                    switching = true
                    Task {
                        do {
                            try await model.projects.switchChart(project, to: newChart, manifest: manifest)
                            switching = false
                            await load()
                        } catch {
                            // Nothing switched: the project keeps the chart it started with, and
                            // the notice stays on screen offering the switch again.
                            switching = false
                            actionError = "Couldn't switch to the new chart. Check your connection and try again."
                        }
                    }
                }
                .disabled(switching)
            } else {
                Text("Switching is only offered before the first row is worked.").font(Font.Heather.caption).foregroundStyle(Color.ink2)
            }
        }
    }
}
