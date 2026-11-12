import SwiftUI

extension EnvironmentValues {
    /// True while an `ImageRenderer` is drawing the view, as the snapshot tests do. The renderer
    /// cannot draw a UIKit view and paints a placeholder where one stands, so a view that lays a
    /// UIKit one over its own drawing (the look-ahead view's zoom surface) leaves it out.
    @Entry var rendersToImage = false
}
