import SwiftUI

/// The floating bar docked near the bottom of the window — same QuickTime-
/// style hairline panel as Movi's `FloatingControlBar` (plain alpha-blended
/// fill, not a live blur material — see that file's note on why), just with
/// an icon row for Pico's actions instead of transport controls, and a
/// plain info row (zoom % / filename / position) instead of a scrubber,
/// since there's no timeline to show.
///
/// All icons sit in a single `HStack` with one uniform spacing value
/// between every pair — the earlier layout mixed a fixed-width edge slot
/// with flexible `Spacer`s on either side of a tightly-packed inner group,
/// which is what made the gaps look uneven (a big gap before the group,
/// tight gaps inside it). The bar's own width is derived directly from
/// this row's icon count/size/spacing instead of being a separate guess,
/// so the two can never drift apart again.
struct FloatingControlBar: View {
    @ObservedObject var viewModel: ImageViewerViewModel
    var isFullScreen: Bool
    var onOpen: () -> Void
    var onToggleFullScreen: () -> Void
    var onSaveAs: () -> Void

    private let iconCount = 9
    private let iconSize: CGFloat = 32
    private let iconSpacing: CGFloat = 18
    private let edgeLabelWidth: CGFloat = 52
    private let infoRowHeight: CGFloat = 17
    private let horizontalPadding: CGFloat = 17
    private let verticalPadding: CGFloat = 10
    private let rowSpacing: CGFloat = 8

    private var barWidth: CGFloat {
        CGFloat(iconCount) * iconSize + CGFloat(iconCount - 1) * iconSpacing
    }

    /// Footprint grown to match the bigger/evenly-spaced icon row: width is
    /// `barWidth` plus the same horizontal padding applied in `body`,
    /// height is the icon row plus the info row plus their own spacing and
    /// vertical padding, rounded up a little — same footprint math as
    /// Movi's bar, just re-derived for the new icon size.
    static let footprintSize = CGSize(width: 466, height: 80)
    static var minWindowWidth: CGFloat { footprintSize.width * 1.2 }

    var body: some View {
        VStack(spacing: rowSpacing) {
            HStack(spacing: iconSpacing) {
                controlButton(systemName: "folder", help: "Otwórz obraz (⌘O)", action: onOpen)
                controlButton(systemName: "square.grid.2x2", help: "Przeglądaj folder (⇧⌘B)", action: viewModel.toggleBrowse)
                controlButton(systemName: "chevron.left", help: "Poprzedni obraz (←)", action: viewModel.goToPrevious)
                    .disabled(!viewModel.canGoPrevious)
                    .opacity(viewModel.canGoPrevious ? 1 : 0.3)
                controlButton(systemName: "minus.magnifyingglass", help: "Pomniejsz (⌘−)", action: viewModel.zoomOut)
                // "Dopasuj do okna" moved off `arrow.down.right.and.arrow.up.left`
                // to `viewfinder` so that icon pair is free for the new
                // Fullscreen button below, which needs both halves of it.
                controlButton(systemName: "viewfinder", help: "Dopasuj do okna (⌘0)", action: viewModel.zoomToFit)
                controlButton(systemName: "plus.magnifyingglass", help: "Powiększ (⌘+)", action: viewModel.zoomIn)
                controlButton(systemName: "chevron.right", help: "Następny obraz (→)", action: viewModel.goToNext)
                    .disabled(!viewModel.canGoNext)
                    .opacity(viewModel.canGoNext ? 1 : 0.3)
                controlButton(
                    systemName: isFullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                    help: isFullScreen ? "Wyjdź z pełnego ekranu (⌃⌘F)" : "Pełny ekran (⌃⌘F)",
                    action: onToggleFullScreen
                )
                controlButton(systemName: "square.and.arrow.down", help: "Zapisz jako… (⌘S)", action: onSaveAs)
            }

            HStack(spacing: rowSpacing) {
                Text(zoomLabel)
                    .font(.system(.caption2))
                    // `.white.opacity(…)`, not `.secondary` — same reasoning
                    // as the icon buttons above: this bar's fill stays dark
                    // on purpose in every theme, so an adaptive system color
                    // here went near-invisible in light mode.
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: edgeLabelWidth, alignment: .leading)
                    .monospacedDigit()

                Text(viewModel.currentURL?.lastPathComponent ?? "")
                    .font(.system(.caption2))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity)

                Text(positionLabel)
                    .font(.system(.caption2))
                    // Same reasoning as `zoomLabel` above.
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: edgeLabelWidth, alignment: .trailing)
                    .monospacedDigit()
            }
            .frame(height: infoRowHeight)
        }
        .frame(width: barWidth)
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color.black.opacity(0.4))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.35), radius: 14, y: 5)
    }

    private var zoomLabel: String {
        let effectivePercent = Int((viewModel.isZoomFit ? viewModel.lastKnownFitScale : viewModel.zoomScale) * 100)
        return "\(effectivePercent)%"
    }

    private var positionLabel: String {
        guard viewModel.folderURL != nil, let index = viewModel.currentIndex else { return "–" }
        return "\(index + 1)/\(viewModel.folderImages.count)"
    }

    // `help` is `LocalizedStringKey`, not `String` — see Movi's identical
    // note on this: a plain `String` parameter here would make `.help`
    // resolve to its verbatim `StringProtocol` overload instead of looking
    // the literal up in `Localizable.xcstrings`, and every tooltip below
    // would silently stay Polish in every language.
    private func controlButton(systemName: String, help: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 20, weight: .medium))
                .frame(width: iconSize, height: iconSize)
                // Explicit white, not `.primary` — `.primary` adapts to the
                // *system* appearance, but this bar's own fill
                // (`Color.black.opacity(0.4)`, in `body` below) stays dark
                // on purpose regardless of theme (see the file-header note).
                // Left on `.primary`, the icons turned near-black-on-dark in
                // light mode and were nearly invisible.
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .help(help)
    }
}
