import SwiftUI

/// A day's progress-photo thumbnail. When locked it shows a pre-blurred smear
/// with a lock glyph and a "captured" tick — enough to say *you showed up today*
/// without revealing anything. Tapping runs through the Face ID gate upstream.
struct PicThumb: View {
    let pic: ProgressPic
    let data: Data?
    let locked: Bool
    let onTap: () -> Void

    @State private var blurred: UIImage?

    var body: some View {
        Button(action: onTap) {
            ZStack {
                if locked {
                    if let blurred {
                        Image(uiImage: blurred).resizable().scaledToFill()
                    } else {
                        Palette.chalk
                    }
                } else if let data, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Palette.chalk
                }
            }
            .frame(width: 64, height: 84)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay {
                if locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.paper)
                        .shadow(color: .black.opacity(0.5), radius: 3)
                }
            }
            .overlay(alignment: .topTrailing) {
                if locked {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Palette.paper)
                        .shadow(color: .black.opacity(0.5), radius: 2)
                        .padding(4)
                }
            }
            .overlay(alignment: .bottom) {
                Text(pic.pose.rawValue)
                    .font(Typo.monoSmall)
                    .foregroundStyle(Palette.paper)
                    .shadow(color: .black.opacity(0.7), radius: 2)
                    .padding(.bottom, 6)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(locked ? "Locked \(pic.pose.rawValue) photo" : "\(pic.pose.rawValue) photo")
        // Blur off the main thread; sharp pixels never touch the view tree.
        .task(id: pic.path) {
            guard locked, blurred == nil, let data else { return }
            blurred = await Task.detached { ProgressImage.blurredThumb(data) }.value
        }
    }
}

/// What the full-screen viewer opens onto — the day's pics, starting at the
/// tapped one. `Identifiable` so it can drive a `fullScreenCover(item:)`.
struct ProgressPicContext: Identifiable {
    let id = UUID()
    let pics: [ProgressPic]
    let startIndex: Int
}

/// Full-screen, swipeable viewer for a day's progress pics. Reached only after
/// the Face ID gate; shows the sharp images with pinch-to-zoom.
struct ProgressPicViewer: View {
    let context: ProgressPicContext
    let readData: (String) -> Data?

    @Environment(\.dismiss) private var dismiss
    @State private var index: Int

    init(context: ProgressPicContext, readData: @escaping (String) -> Data?) {
        self.context = context
        self.readData = readData
        _index = State(initialValue: context.startIndex)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $index) {
                ForEach(Array(context.pics.enumerated()), id: \.offset) { i, pic in
                    Group {
                        if let data = readData(pic.path), let image = UIImage(data: data) {
                            ZoomableImage(image: image)
                        } else {
                            Image(systemName: "photo")
                                .font(.largeTitle)
                                .foregroundStyle(.white.opacity(0.4))
                        }
                    }
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: context.pics.count > 1 ? .automatic : .never))

            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.85))
                            .shadow(radius: 4)
                    }
                    .padding(20)
                    .accessibilityLabel("Close")
                }
                Spacer()
                if context.pics.indices.contains(index) {
                    Text(context.pics[index].pose.rawValue.capitalized)
                        .font(Typo.mono)
                        .foregroundStyle(.white)
                        .padding(.bottom, 44)
                }
            }
        }
        .statusBarHidden()
    }
}

/// Pinch-and-drag zoom for a single photo, snapping back to fit on release.
private struct ZoomableImage: View {
    let image: UIImage
    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .scaleEffect(scale)
            .offset(offset)
            .gesture(
                MagnifyGesture()
                    .onChanged { scale = max(1, $0.magnification) }
                    .onEnded { _ in
                        withAnimation(.easeOut(duration: 0.2)) { scale = 1; offset = .zero }
                    }
            )
            .simultaneousGesture(
                DragGesture()
                    .onChanged { if scale > 1 { offset = $0.translation } }
                    .onEnded { _ in
                        if scale <= 1 { withAnimation(.easeOut(duration: 0.2)) { offset = .zero } }
                    }
            )
    }
}
