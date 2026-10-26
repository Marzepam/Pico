import SwiftUI

/// The thumbnail grid shown instead of the single-image canvas while
/// `viewModel.isBrowsing` — "Przeglądaj". A single click opens an image
/// (there's no multi-select/batch action in Pico, so a plain click-to-open
/// is simpler and more discoverable than requiring a double-click).
struct BrowseGridView: View {
    @ObservedObject var viewModel: ImageViewerViewModel
    var isFullScreen: Bool

    private let columns = [GridItem(.adaptive(minimum: 130, maximum: 170), spacing: 18)]

    /// Leading clearance in windowed mode: just enough to clear the
    /// traffic-light buttons with a little breathing room, not tied to the
    /// window's own width — the buttons themselves sit at a fixed inset
    /// regardless of how wide the window is, so a width-proportional gap
    /// (tried previously) only overshoots on a wide window. In fullscreen
    /// there are no traffic lights to clear at all, so the header's
    /// leading inset instead mirrors `trailingPadding` — the same 16pt gap
    /// the "Zmień folder…" button keeps from the right edge — for a
    /// symmetric corner-to-corner look.
    private let trafficLightClearance: CGFloat = 78
    private let trailingPadding: CGFloat = 16

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if viewModel.folderImages.isEmpty {
                emptyFolderState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 22) {
                        ForEach(viewModel.folderImages) { image in
                            ThumbnailCell(
                                viewModel: viewModel,
                                image: image,
                                isSelected: image.url == viewModel.currentURL
                            )
                        }
                    }
                    .padding(20)
                }
            }
        }
        // System-adaptive, not a hardcoded black — this is what kept the
        // grid black regardless of macOS's own light/dark (or time-of-day
        // "Auto") appearance; `ContentView`'s own background behind this
        // view was the same fix. `Divider()` above is left with its plain,
        // system-provided style rather than the earlier hardcoded
        // `Color.white.opacity(0.1)` overlay, for the same reason.
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 14) {
            Text(viewModel.folderURL?.lastPathComponent ?? "")
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text(String(format: String(localized: "Liczba zdjęć: %d", comment: "Count label in the browse grid header, e.g. 'Image count: 24'"), viewModel.folderImages.count))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            sortMenu

            Button {
                viewModel.presentBrowsePanel()
            } label: {
                Label("Zmień folder…", systemImage: "folder.badge.gearshape")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.leading, isFullScreen ? trailingPadding : trafficLightClearance)
        .padding(.trailing, trailingPadding)
        .padding(.vertical, 16)
    }

    private var sortMenu: some View {
        Menu {
            ForEach(ImageSortField.allCases) { field in
                Button {
                    viewModel.sortOption.field = field
                } label: {
                    HStack {
                        Text(field.label)
                        if viewModel.sortOption.field == field {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            Divider()
            Button {
                viewModel.sortOption.ascending.toggle()
            } label: {
                Label(
                    viewModel.sortOption.ascending ? "Rosnąco" : "Malejąco",
                    systemImage: viewModel.sortOption.ascending ? "arrow.up" : "arrow.down"
                )
            }
        } label: {
            Label("Sortuj", systemImage: "arrow.up.arrow.down")
        }
        .controlSize(.small)
        .fixedSize()
    }

    private var emptyFolderState: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("W tym folderze nie ma obsługiwanych obrazów")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ThumbnailCell: View {
    @ObservedObject var viewModel: ImageViewerViewModel
    let image: BrowsableImage
    let isSelected: Bool

    @State private var thumbnail: CGImage?

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                if let thumbnail {
                    Image(decorative: thumbnail, scale: 1, orientation: .up)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(5)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .frame(height: 118)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: isSelected ? 2 : 1)
            )

            Text(image.name)
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.selectThumbnail(image)
        }
        .task(id: image.url) {
            thumbnail = await viewModel.loadThumbnail(for: image, maxPixelSize: 240)
        }
    }
}
