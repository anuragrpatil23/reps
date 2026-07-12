import SwiftUI

/// Swipe-left-to-delete for rows in a custom card "list" (where SwiftUI's
/// List-only `.swipeActions` isn't available). Swipe reveals a Delete button;
/// tap it to confirm, or a decisive full swipe deletes outright. Only reacts to
/// predominantly-horizontal drags so it doesn't fight the vertical scroll.
struct SwipeToDeleteRow<Content: View>: View {
    /// Opaque background so the row hides the delete button at rest — pass the
    /// enclosing card's stock color.
    let background: Color
    let onDelete: () -> Void
    @ViewBuilder var content: () -> Content

    /// Resting position: 0 = closed, -revealWidth = open.
    @State private var committed: CGFloat = 0
    /// Live drag delta while the finger is down.
    @GestureState private var drag: CGFloat = 0

    private let revealWidth: CGFloat = 84
    private let deleteThreshold: CGFloat = 200

    private var offset: CGFloat { min(0, max(-revealWidth, committed + drag)) }

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(role: .destructive) { delete() } label: {
                Image(systemName: "trash")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Palette.paper)
                    .frame(width: revealWidth)
                    .frame(maxHeight: .infinity)
                    .background(Palette.madder)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(background)
                .offset(x: offset)
                .highPriorityGesture(
                    DragGesture(minimumDistance: 14)
                        .updating($drag) { value, state, _ in
                            guard abs(value.translation.width) > abs(value.translation.height) else { return }
                            state = value.translation.width
                        }
                        .onEnded { value in
                            let total = committed + value.translation.width
                            if -total > deleteThreshold {
                                delete()               // decisive full swipe
                            } else {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                    committed = -total > revealWidth / 2 ? -revealWidth : 0
                                }
                            }
                        }
                )
        }
        .clipped()
    }

    /// The data change removes the row from the list; reset so a reused view
    /// starts closed.
    private func delete() {
        committed = 0
        onDelete()
    }
}
