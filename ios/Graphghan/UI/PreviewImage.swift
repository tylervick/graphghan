import SwiftUI

/// A pattern or chart preview from the site, loaded through the model's cache.
struct PreviewImage: View {
    @Environment(AppModel.self) private var model
    let slug: String
    var sitePath: String? = nil
    var chartPath: String? = nil
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().interpolation(.none).scaledToFit()
            } else {
                Rectangle().fill(.quaternary).overlay(Image(systemName: "photo").foregroundStyle(.secondary))
            }
        }
        .task(id: sitePath ?? chartPath) {
            if let sitePath { image = await model.preview(for: slug, sitePath: sitePath) }
            else if let chartPath { image = await model.chartPreview(for: slug, path: chartPath) }
        }
    }
}
