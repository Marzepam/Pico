import SwiftUI

/// The single-image viewer: draws `viewModel.currentImage` at whatever
/// scale is currently in effect — either continuously fit to the available
/// space (`isZoomFit`) or a literal, window-size-independent percentage the
/// person set explicitly (buttons, pinch, or the actual-size double-click).
/// Deliberately never resizes the *window* the way Movi's video player
/// does — zooming a photo in/out is expected to change what's visible
/// inside the window, not the window itself (letterboxing around an image
/// that doesn't match the window's own shape is normal here, unlike video).
struct ImageCanvasView: View {
    @ObservedObject var viewModel: ImageViewerViewModel

    @GestureState private var dragTranslation: CGSize = .zero
    @GestureState private var magnifyBy: CGFloat = 1.0

    var body: some View {
        GeometryReader { geo in
            if let cgImage = viewModel.currentImage {
                let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
                let fit = fitScale(imageSize: imageSize, containerSize: geo.size)
                let baseScale = viewModel.isZoomFit ? fit : viewModel.zoomScale
                let liveScale = baseScale * magnifyBy
                let contentSize = CGSize(width: imageSize.width * liveScale, height: imageSize.height * liveScale)
                let clampedOffset = clampedPan(viewModel.panOffset + dragTranslation, contentSize: contentSize, containerSize: geo.size)

                // No blanket `.animation(value: baseScale)` here on purpose
                // — that used to animate *every* change to `baseScale`,
                // including the continuous, already-live recompute that
                // happens every frame while `isZoomFit` tracks a resizing
                // window (most visibly: the system's own fullscreen
                // enter/exit animation). Layering a second, independently
                // timed 0.15s ease on top of a value that's already
                // changing every frame is what made that transition look
                // "weird"/stuttery. Discrete, user-initiated scale changes
                // (zoom buttons, double-click) now animate themselves via
                // `withAnimation` right where they're set, in
                // `ImageViewerViewModel`; a window-driven resize — whether
                // from browsing to the next image or the person dragging
                // the window's edge by hand — stays unanimated dynamic
                // "fit" so it tracks the window's own already-instant
                // frame exactly, with nothing second-guessing it.
                Image(decorative: cgImage, scale: 1, orientation: .up)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: contentSize.width, height: contentSize.height)
                    .position(x: geo.size.width / 2 + clampedOffset.width, y: geo.size.height / 2 + clampedOffset.height)
                    .gesture(
                        DragGesture(minimumDistance: 2)
                            .updating($dragTranslation) { value, state, _ in
                                state = value.translation
                            }
                            .onEnded { value in
                                let proposed = viewModel.panOffset + value.translation
                                viewModel.panOffset = clampedPan(proposed, contentSize: contentSize, containerSize: geo.size)
                            }
                    )
                    .simultaneousGesture(
                        MagnificationGesture()
                            .updating($magnifyBy) { value, state, _ in
                                state = value
                            }
                            .onEnded { value in
                                viewModel.setZoom(baseScale * value)
                                viewModel.panOffset = clampedPan(viewModel.panOffset, contentSize: contentSize, containerSize: geo.size)
                            }
                    )
                    .onTapGesture(count: 2) {
                        viewModel.toggleActualSize()
                    }
            }
        }
        .contentShape(Rectangle())
        .clipped()
        .background(FitScaleTracker(viewModel: viewModel, currentImageSize: imageSize(from: viewModel.currentImage)))
    }

    // MARK: Helpers

    private func imageSize(from cgImage: CGImage?) -> CGSize? {
        guard let cgImage else { return nil }
        return CGSize(width: cgImage.width, height: cgImage.height)
    }

    private func fitScale(imageSize: CGSize, containerSize: CGSize) -> CGFloat {
        guard imageSize.width > 0, imageSize.height > 0, containerSize.width > 0, containerSize.height > 0 else { return 1 }
        return min(containerSize.width / imageSize.width, containerSize.height / imageSize.height)
    }

    /// Keeps at least a small margin of the image always reachable/visible
    /// rather than letting a drag throw it entirely off-screen: clamps so
    /// the content can't be panned further than half its own overflow past
    /// the container's edge in either axis. When the content is smaller
    /// than the container on an axis (zoomed below fit, or a landscape
    /// image against a portrait window), that axis is pinned to 0 — no
    /// panning room, same as it visually has none.
    private func clampedPan(_ proposed: CGSize, contentSize: CGSize, containerSize: CGSize) -> CGSize {
        func clampAxis(_ value: CGFloat, content: CGFloat, container: CGFloat) -> CGFloat {
            let overflow = max(0, (content - container) / 2)
            return min(overflow, max(-overflow, value))
        }
        return CGSize(
            width: clampAxis(proposed.width, content: contentSize.width, container: containerSize.width),
            height: clampAxis(proposed.height, content: contentSize.height, container: containerSize.height)
        )
    }
}

private extension CGSize {
    static func + (lhs: CGSize, rhs: CGSize) -> CGSize {
        CGSize(width: lhs.width + rhs.width, height: lhs.height + rhs.height)
    }
}

/// Zero-size helper that republishes the current fit scale to the view
/// model whenever the canvas's own layout size or the loaded image changes
/// — `GeometryReader` itself can't notify anything outside its own body, so
/// `FloatingControlBar`'s zoom-percentage label (a sibling view, not a
/// child of the canvas) needs this to stay in sync in "Dopasuj do okna"
/// mode.
private struct FitScaleTracker: View {
    @ObservedObject var viewModel: ImageViewerViewModel
    let currentImageSize: CGSize?

    var body: some View {
        GeometryReader { geo in
            Color.clear
                .onAppear { publish(containerSize: geo.size) }
                .onChange(of: geo.size) { _, newSize in publish(containerSize: newSize) }
                .onChange(of: currentImageSize) { _, _ in publish(containerSize: geo.size) }
        }
    }

    private func publish(containerSize: CGSize) {
        guard let currentImageSize, currentImageSize.width > 0, currentImageSize.height > 0,
              containerSize.width > 0, containerSize.height > 0 else { return }
        let scale = min(containerSize.width / currentImageSize.width, containerSize.height / currentImageSize.height)
        if abs(viewModel.lastKnownFitScale - scale) > 0.0005 {
            viewModel.lastKnownFitScale = scale
        }
    }
}
