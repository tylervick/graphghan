import SwiftData
import SwiftUI

struct ProjectListView: View {
    // The brief's two-SortDescriptor form (`lastWorked` then `started`, both reversed) crashes the
    // app on launch with EXC_BAD_ACCESS inside `initializeWithCopy for ProjectListView` on this SDK
    // (iPhoneSimulator26.2) -- reproducible, not a one-off. Falling back to a single sort key per
    // the task's guidance.
    @Query(sort: \Project.started, order: .reverse)
    private var projects: [Project]

    var body: some View {
        NavigationStack {
            Group {
                if projects.isEmpty {
                    ContentUnavailableView("No projects", systemImage: "checklist", description: Text("Start one from a pattern."))
                } else {
                    List(projects) { project in
                        NavigationLink(value: project.id) { ProjectRow(project: project) }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Projects")
            .navigationDestination(for: UUID.self) { id in
                if let project = projects.first(where: { $0.id == id }) { ProjectDetailView(project: project) }
            }
        }
    }
}
