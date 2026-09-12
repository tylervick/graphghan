import SwiftData
import SwiftUI

struct ProjectListView: View {
    @Environment(AppModel.self) private var model
    // The brief's two-SortDescriptor form (`lastWorked` then `started`, both reversed) crashes the
    // app on launch with EXC_BAD_ACCESS inside `initializeWithCopy for ProjectListView` on this SDK
    // (iPhoneSimulator26.2) -- reproducible, not a one-off. `lastWorked` is optional, and even a
    // single-key `@Query` sort on it is untested territory here, so `@Query` is left unsorted and
    // the "most recently worked, else most recently started" order is computed in `ordered` below.
    @Query private var projects: [Project]

    private var ordered: [Project] {
        projects.sorted {
            let l = $0.lastWorked ?? .distantPast, r = $1.lastWorked ?? .distantPast
            return l != r ? l > r : $0.started > $1.started
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if projects.isEmpty {
                    ContentUnavailableView("No projects", systemImage: "checklist", description: Text("Start one from a pattern."))
                } else {
                    List(ordered) { project in
                        NavigationLink(value: project.id) { ProjectRow(project: project) }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Color.ground.weave().ignoresSafeArea())
            .tint(.moss)
            .navigationTitle("Projects")
            .navigationDestination(for: UUID.self) { id in
                if let project = ordered.first(where: { $0.id == id }) { ProjectDetailView(project: project) }
            }
            .safeAreaInset(edge: .top) {
                if let error = model.projects.lastError {
                    Banner(text: "Couldn't save your progress: \(error)", kind: .failure, action: .init(label: "Dismiss") { model.projects.lastError = nil })
                }
            }
        }
    }
}
