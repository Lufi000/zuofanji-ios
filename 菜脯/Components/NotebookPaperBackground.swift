import SwiftUI

struct NotebookPaperBackground: View {
    var lineSpacing: CGFloat = 28

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                AppTheme.notebookPaper

                Path { path in
                    var y: CGFloat = lineSpacing
                    while y < geo.size.height + lineSpacing {
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: geo.size.width, y: y))
                        y += lineSpacing
                    }
                }
                .stroke(AppTheme.notebookLine.opacity(0.65), lineWidth: 0.7)
            }
        }
    }
}
