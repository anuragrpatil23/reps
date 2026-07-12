import SwiftUI

/// Swipe-left-to-delete for rows in a custom card "list" (where SwiftUI's
/// List-only `.swipeActions` isn't available). As you drag left a red delete
/// panel grows in from the trailing edge; release past the threshold to delete,
/// otherwise it snaps back. No row background needed (nothing overlaps at rest),
/// so it sits seamlessly on the card. Only reacts to predominantly-horizontal
/// drags so it doesn't fight the vertical scroll.
struct SwipeToDeleteRow<Content: View>: View {
    let onDelete: () -> Void
    @ViewBuilder var content: () -> Content

    @GestureState private var drag: CGFloat = 0
    private let deleteThreshold: CGFloat = 160
    private let maxReveal: CGFloat = 96

    /// How much of the delete panel is showing (0 at rest).
    private var reveal: CGFloat { min(maxReveal, max(0, -drag)) }

    var body: some View {
        HStack(spacing: 0) {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
            Rectangle()
                .fill(Palette.madder)
                .frame(width: reveal)
                .overlay {
                    Image(systemName: "trash")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Palette.paper)
                        .opacity(reveal > 24 ? 1 : 0)
                }
                .clipped()
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 14)
                .updating($drag) { value, state, _ in
                    guard value.translation.width < 0,
                          abs(value.translation.width) > abs(value.translation.height) else { return }
                    state = value.translation.width
                }
                .onEnded { value in
                    if -value.translation.width > deleteThreshold { onDelete() }
                }
        )
    }
}
