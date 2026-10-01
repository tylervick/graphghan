import SwiftUI
import GraphghanCore

struct ProjectDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let project: Project
    @State private var sequence: WorkSequence?
    @State private var summary: ProgressSummary?
    /// A pieced project's pieces, in the pattern's order (spec 2026-09-25 §6.2).
    @State private var statuses: [PieceStatus] = []
    /// The event log could not be read: shown, not hidden behind an empty summary.
    @State private var historyError: String?
    @State private var loadError: String?
    @State private var manifest: PatternManifest?
    @State private var notes: String = ""
    @State private var showJump = false
    /// Whether the pattern kept the PDF it was imported from (Task 9); false for a bundle opened
    /// on another phone, whose assembly steps then show their page numbers as plain text. Checked
    /// without loading the PDF's bytes (fix round 1) -- those are only worth the read once a step
    /// button is actually tapped.
    @State private var hasSourcePDF = false
    /// An assembly step's "Open page N" button, once its PDF has finished loading: non-nil
    /// presents the viewer sheet. Nothing is shown while the load is in flight.
    @State private var pdfViewer: PDFViewerRequest?
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
            if project.isPieced, let manifest {
                PieceListSection(statuses: statuses, assembly: manifest.assembly, assemblyDone: project.assemblyDone,
                                 onSelect: { key in
                                     Task {
                                         if await !model.openPiece(key, of: project, manifest: manifest) {
                                             actionError = "Couldn't open that piece."
                                         }
                                     }
                                 },
                                 onToggleStep: { i, on in
                                     do { try model.projects.setAssemblyStep(i, done: on, for: project) }
                                     catch { actionError = "Couldn't update that step: \(error.localizedDescription)" }
                                 },
                                 hasSourcePDF: hasSourcePDF,
                                 onOpenPage: { page in
                                     Task {
                                         // Hops off the main actor to read the file: `AppModel.sourcePDF`
                                         // awaits `LocalPatternStore`, an actor, so the read itself
                                         // happens on its executor, not here.
                                         if let data = await model.sourcePDF(for: project.patternID) {
                                             pdfViewer = PDFViewerRequest(data: data, page: page)
                                         } else {
                                             actionError = "The PDF couldn't be opened."
                                         }
                                     }
                                 })
                notesSection
                manageSection(showFinishToggle: false)
            } else if let sequence, let summary {
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
                notesSection
                if !summary.sessions.isEmpty {
                    Section("Sessions") {
                        ForEach(Array(summary.sessions.suffix(10).reversed().enumerated()), id: \.offset) { _, s in
                            LabeledContent(s.start.formatted(date: .abbreviated, time: .shortened),
                                           value: Self.sessionValueText(cells: s.cells, cellKind: sequence.cellKind, seconds: s.seconds))
                        }
                    }
                }
                manageSection(showFinishToggle: true)
            } else if let loadError {
                Section {
                    ContentUnavailableView(project.isPieced ? "Pattern missing" : "Chart missing",
                                           systemImage: "exclamationmark.triangle", description: Text(loadError))
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
        .sheet(item: $pdfViewer) { viewer in
            NavigationStack {
                PDFPageView(data: viewer.data, page: viewer.page, documentID: viewer.id)
                    .ignoresSafeArea(edges: .bottom)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { pdfViewer = nil } }
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
            if let historyError {
                Banner(text: "Couldn't read this project's history: \(historyError)", kind: .failure, action: .init(label: "Dismiss") { self.historyError = nil })
            }
        }
        .task { await load() }
        // The summary walks every event; recompute it when the project changes outside the Work
        // screen, never on each tap behind the cover (see ProjectSummaryKey).
        .task(id: SummaryRefresh(key: ProjectSummaryKey.make(for: project, working: model.workingProject), chartID: sequence == nil ? nil : project.chartID)) {
            if project.isPieced {
                if let manifest { statuses = await model.projects.statuses(for: project, manifest: manifest) }
                return
            }
            guard let sequence, ProjectSummaryKey.make(for: project, working: model.workingProject) != nil || summary == nil else { return }
            do {
                summary = try model.projects.summary(for: project, sequence: sequence)
                historyError = nil
            } catch {
                summary = nil
                historyError = error.localizedDescription
            }
        }
    }

    private struct SummaryRefresh: Hashable { let key: ProjectSummaryKey?; let chartID: String? }

    /// What `pdfViewer`'s sheet shows once an assembly step's PDF has loaded: its bytes and the
    /// page that step asked for.
    private struct PDFViewerRequest: Identifiable {
        let id = UUID()
        let data: Data
        let page: Int
    }

    @ViewBuilder private var notesSection: some View {
        Section("Notes") {
            TextField("Yarn lots, hook, reminders…", text: $notes, axis: .vertical)
                .lineLimit(3...8)
                .onChange(of: notes) { _, new in try? model.projects.setNotes(new, for: project) }
        }
    }

    /// `showFinishToggle` is false for a pieced project: its finish follows its pieces and
    /// assembly, so a manual toggle here would be undone by the next step.
    @ViewBuilder private func manageSection(showFinishToggle: Bool) -> some View {
        Section {
            if showFinishToggle {
                if project.isFinished {
                    Button("Mark unfinished") {
                        do { try model.projects.markUnfinished(project) }
                        catch { actionError = "Couldn't reopen this project: \(error.localizedDescription)" }
                    }
                } else {
                    Button("Mark finished") { confirmFinish = true }
                }
            }
            Button("Delete project", role: .destructive) { confirmDelete = true }
        }
    }

    private func load() async {
        notes = project.notes
        manifest = try? await model.manifest(for: project.patternID, path: nil)
        // A pieced project's chart lives per piece, not on the project; sequence(for:) would read
        // project.chartID directly and report "Chart missing" while the current piece is written
        // (chartID is ""), so it is only meaningful for a single-chart project.
        if project.isPieced {
            guard let manifest else {
                loadError = "This project's chart could not be read. Download it again to continue."
                return
            }
            loadError = nil
            statuses = await model.projects.statuses(for: project, manifest: manifest)
            hasSourcePDF = await model.hasSourcePDF(for: project.patternID)
        } else {
            do { sequence = try await model.projects.sequence(for: project) }
            catch { loadError = "This project's chart could not be read. Download it again to continue." }
        }
    }

    private func redownload() async {
        // A pieced project's chart lives per piece; `chartID` is "" whenever the current piece is
        // written, and looking that up in `manifest.charts` would report the wrong sentence (or
        // succeed for the wrong reason). What failed for a pieced project is the manifest fetch
        // itself, so retry via load() instead of chasing a chart that may not exist.
        if project.isPieced {
            await load()
            return
        }
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
