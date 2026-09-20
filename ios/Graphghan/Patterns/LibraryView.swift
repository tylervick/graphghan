import SwiftUI
import GraphghanCore

struct LibraryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.libraryPath) {
            Group {
                if let error = model.libraryError, model.libraryItems.isEmpty {
                    ContentUnavailableView {
                        Label("No patterns yet", systemImage: "wifi.slash")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Try again") { Task { await model.loadLibrary(force: true) } }
                    }
                } else if model.libraryItems.isEmpty && model.isLoadingLibrary {
                    ProgressView("Loading patterns…")
                } else {
                    List {
                        // Headers only once a pattern has been opened from a file: until then the
                        // tab is exactly what it has always been, one list of what the site has.
                        let local = model.libraryItems.filter(\.isLocal)
                        if !local.isEmpty {
                            section(local, header: "On this iPhone")
                            section(model.libraryItems.filter { !$0.isLocal }, header: "From graphghan.milo.cat")
                        } else {
                            section(model.libraryItems, header: nil)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Color.ground.weave().ignoresSafeArea())
            .tint(.moss)
            .navigationTitle("Patterns")
            .navigationDestination(for: LibraryItem.self) { PatternDetailView(item: $0) }
            .refreshable { await model.loadLibrary(force: true) }
            .safeAreaInset(edge: .top) {
                if let banner = model.libraryBanner {
                    Banner(text: banner, kind: .info, action: .init(label: "Retry") { Task { await model.loadLibrary(force: true) } })
                }
            }
        }
        .task { await model.loadLibrary() }
    }

    @ViewBuilder
    private func section(_ items: [LibraryItem], header: String?) -> some View {
        Section {
            ForEach(items) { item in
                LibraryRow(item: item)
                    .overlay { NavigationLink(value: item) { EmptyView() }.opacity(0) }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            }
        } header: {
            if let header {
                Text(header)
                    .font(Font.Heather.label)
                    .foregroundStyle(Color.ink2)
                    .textCase(nil)
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 4, trailing: 16))
            }
        }
    }
}

struct LibraryRow: View {
    @Environment(AppModel.self) private var model
    let item: LibraryItem
    @State private var preview: UIImage?

    private var entry: IndexEntry { item.entry }

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: 12) {
                PreviewFrame(image: preview)
                VStack(alignment: .leading, spacing: 5) {
                    Text(entry.title).font(Font.Heather.heading).foregroundStyle(Color.ink).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    if !entry.dedication.isEmpty { Text(entry.dedication).font(Font.Heather.caption).foregroundStyle(Color.ink2) }
                    Text(summary).font(Font.Heather.caption).foregroundStyle(Color.ink2)
                    if item.isLocal { LocalBadge() }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(Font.Heather.label).foregroundStyle(Color.ink2).padding(.top, 4)
            }
        }
        .task(id: item.id) { preview = await model.preview(for: entry.slug, sitePath: entry.preview) }
    }

    /// A local pattern whose default chart has no stated size shows what it can, rather than an
    /// empty "× in".
    private var summary: String {
        let size = entry.sizeIn.count == 2 ? "\(entry.sizeIn[0].formatted()) × \(entry.sizeIn[1].formatted()) in · " : ""
        return "\(size)\(entry.stitch) · \(entry.colors) colors"
    }
}

/// Says where a pattern came from, because nothing else on the row can: a local pattern is not
/// on the site, is never refreshed, and is the only copy of itself.
struct LocalBadge: View {
    var body: some View {
        Text("Local")
            .font(Font.Heather.caption)
            .foregroundStyle(Color.mossDeep)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.moss.opacity(0.18)))
            .accessibilityLabel("Opened from a file")
    }
}
