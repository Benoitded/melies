import SwiftUI

/// Subtle transparency grid shown behind the video, as in image editors.
struct Checkerboard: View {
    @Environment(\.colorScheme) private var scheme
    private let cell: CGFloat = 10

    var body: some View {
        Canvas { context, size in
            let light = scheme == .dark ? Color(white: 0.17) : Color(white: 0.93)
            let dark = scheme == .dark ? Color(white: 0.13) : Color(white: 0.87)
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(light))
            var path = Path()
            let cols = Int(size.width / cell) + 1
            let rows = Int(size.height / cell) + 1
            for row in 0..<rows {
                for col in 0..<cols where (row + col).isMultiple(of: 2) {
                    path.addRect(CGRect(x: CGFloat(col) * cell, y: CGFloat(row) * cell, width: cell, height: cell))
                }
            }
            context.fill(path, with: .color(dark))
        }
    }
}
