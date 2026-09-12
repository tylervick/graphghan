import SwiftUI
import GraphghanCore

struct LibraryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            Group {
                if let error = model.libraryError, model.index.isEmpty {
                    ContentUnavailableView {
                        Label("No patterns yet", systemImage: "wifi.slash")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Try again") { Task { await model.loadLibrary(force: true) } }
                    }
                } else if model.index.isEmpty && model.isLoadingLibrary {
                    ProgressView("Loading patterns…")
                } else {
                    List(model.index) { entry in
                        NavigationLink(value: entry) { LibraryRow(entry: entry) }
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
            .navigationTitle("Patterns")
            .navigationDestination(for: IndexEntry.self) { PatternDetailView(entry: $0) }
            .refreshable { await model.loadLibrary(force: true) }
            .safeAreaInset(edge: .top) {
                if let banner = model.libraryBanner {
                    Banner(text: banner, kind: .info, action: .init(label: "Retry") { Task { await model.loadLibrary(force: true) } })
                }
            }
        }
        .task { await model.loadLibrary() }
    }
}

struct LibraryRow: View {
    @Environment(AppModel.self) private var model
    let entry: IndexEntry
    @State private var preview: UIImage?

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: 12) {
                PreviewFrame(image: preview)
                VStack(alignment: .leading, spacing: 5) {
                    Text(entry.title).font(Font.Heather.heading).foregroundStyle(Color.ink).lineLimit(2)
                    if !entry.dedication.isEmpty { Text(entry.dedication).font(Font.Heather.caption).foregroundStyle(Color.ink2) }
                    Text("\(entry.sizeIn[0].formatted()) × \(entry.sizeIn[1].formatted()) in · \(entry.stitch) · \(entry.colors) colors")
                        .font(Font.Heather.caption).foregroundStyle(Color.ink2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(Font.Heather.label).foregroundStyle(Color.ink2).padding(.top, 4)
            }
        }
        .task(id: entry.preview) { preview = await model.preview(for: entry.slug, sitePath: entry.preview) }
    }
}
