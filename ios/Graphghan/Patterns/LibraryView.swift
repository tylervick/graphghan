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
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Patterns")
            .navigationDestination(for: IndexEntry.self) { PatternDetailView(entry: $0) }
            .refreshable { await model.loadLibrary(force: true) }
            .safeAreaInset(edge: .top) {
                if let banner = model.libraryBanner {
                    Text(banner)
                        .font(.footnote)
                        .padding(8)
                        .frame(maxWidth: .infinity)
                        .background(.yellow.opacity(0.25))
                }
            }
        }
        .task { await model.loadLibrary() }
    }
}

struct LibraryRow: View {
    let entry: IndexEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            PreviewImage(slug: entry.slug, sitePath: entry.preview)
                .frame(width: 96, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title).font(.headline)
                if !entry.dedication.isEmpty { Text(entry.dedication).font(.subheadline).foregroundStyle(.secondary) }
                Text("\(entry.sizeIn[0].formatted()) × \(entry.sizeIn[1].formatted()) in · \(entry.stitch) · \(entry.colors) colors")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
