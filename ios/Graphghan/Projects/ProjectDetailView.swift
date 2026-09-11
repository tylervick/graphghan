import SwiftUI
import GraphghanCore

struct ProjectDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let project: Project
    @State private var sequence: WorkSequence?
    @State private var loadError: String?
    @State private var manifest: PatternManifest?
    @State private var notes: String = ""
    @State private var showJump = false
    @State private var confirmDelete = false
    @State private var switching = false

    var body: some View {
        List {
            if let sequence {
                let summary = model.projects.summary(for: project, sequence: sequence)
                Section {
                    ProgressView(value: summary.percent, total: 100)
                    LabeledContent("Row", value: project.isFinished ? "Finished" : "\(project.cursor.row) of \(sequence.passes.count)")
                    LabeledContent("Stitches", value: "\(summary.stitchesDone.formatted()) of \(summary.totalStitches.formatted())")
                    if let rate = summary.stitchesPerHour { LabeledContent("Pace", value: "\(rate.formatted()) stitches per hour") }
                    if let finish = model.projects.estimatedFinish(for: project, sequence: sequence) {
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
                                           value: "\(s.stitches) stitches · \(max(1, s.seconds / 60)) min")
                        }
                    }
                }
                Section {
                    if !project.isFinished {
                        Button("Mark finished") { try? model.projects.markFinished(project) }
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
        .sheet(isPresented: $showJump) {
            if let sequence {
                JumpToRowSheet(rowCount: sequence.passes.count, current: project.cursor.row) { row in
                    try? model.projects.apply(.jump(row: row), to: project, in: sequence)
                }
            }
        }
        .confirmationDialog("Delete this project and its progress?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                try? model.projects.delete(project)
                dismiss()
            }
        }
        .safeAreaInset(edge: .top) {
            if let error = model.projects.lastError {
                HStack {
                    Text("Couldn't save your progress: \(error)")
                        .font(.footnote)
                    Spacer()
                    Button("Dismiss") { model.projects.lastError = nil }
                        .font(.footnote)
                }
                .padding(8)
                .frame(maxWidth: .infinity)
                .background(.yellow.opacity(0.25))
            }
        }
        .task { await load() }
    }

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
        guard let manifest = resolvedManifest,
              let chart = manifest.charts.first(where: { $0.id == project.chartID }) else { return }
        if let data = try? await model.patterns.chartData(for: manifest.id, path: chart.path), (try? await model.charts.store(data)) != nil {
            loadError = nil
            await load()
        }
    }

    @ViewBuilder private func versionNotice(_ notice: ProjectService.VersionNotice) -> some View {
        switch notice {
        case .chartChanged(let newChart, let newVersion, let canSwitch):
            Text("Version \(newVersion) of this pattern changed the \(newChart.variant) · \(newChart.gaugeKey) chart. This project keeps the chart it started with.")
                .font(.footnote)
            if canSwitch, let manifest {
                Button(switching ? "Switching…" : "Switch to the new chart") {
                    switching = true
                    Task {
                        try? await model.projects.switchChart(project, to: newChart, manifest: manifest)
                        switching = false
                        await load()
                    }
                }
                .disabled(switching)
            } else {
                Text("Switching is only offered before the first row is worked.").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}
