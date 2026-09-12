import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.tab) {
            LibraryView()
                .tabItem { Label("Patterns", systemImage: "square.grid.3x3") }
                .tag(AppModel.Tab.patterns)
            ProjectListView()
                .tabItem { Label("Projects", systemImage: "checklist") }
                .tag(AppModel.Tab.projects)
        }
        .tint(.moss)
        .font(Font.Heather.body)
        .foregroundStyle(Color.ink)
        .fullScreenCover(item: $model.workingProject) { project in
            WorkView(project: project)
        }
    }
}
