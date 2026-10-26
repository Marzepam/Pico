import AppKit
import CoreGraphics
import SwiftUI
import UniformTypeIdentifiers

/// All viewer state and every open/browse/navigate/zoom/export action lives
/// here, mirroring Movi's `EditorViewModel` — one instance per window/tab
/// (see `PicoApp`/`ContentView`), owning its own image, folder context and
/// zoom state independently of every other open window.
@MainActor
final class ImageViewerViewModel: ObservableObject {

    // MARK: Published state

    /// The image currently on screen, already decoded upright (EXIF/TIFF
    /// orientation baked in — see `ImageExporter.loadUprightImage`). `nil`
    /// before anything's been opened, or momentarily while a new one loads.
    @Published var currentImage: CGImage?
    @Published var currentURL: URL?
    @Published var errorMessage: String?
    @Published var isLoading = false

    /// Whether the browse grid is what's currently showing instead of the
    /// single-image canvas. Toggled by the "Przeglądaj" button — see
    /// `toggleBrowse()`.
    @Published var isBrowsing = false

    /// The folder currently backing Previous/Next, and its sorted image
    /// listing — both `nil`/empty only in the brief moment before any
    /// image has been opened. Explicit "Przeglądaj" sets this directly;
    /// "Otwórz" (a single file) sets it moments later via a background
    /// scan of that file's own containing folder (see `openSingleFile`),
    /// so Previous/Next light up on their own without a second,
    /// explicit "Przeglądaj" step.
    @Published private(set) var folderURL: URL?
    @Published private(set) var folderImages: [BrowsableImage] = []
    @Published private(set) var currentIndex: Int?

    @Published var sortOption = ImageSortOption() {
        didSet {
            guard sortOption != oldValue else { return }
            resort()
        }
    }

    /// `true`: the displayed scale continuously tracks "fit the current
    /// viewport" (recomputed on every window resize — the window itself is
    /// never resized to match, unlike Movi's video window). `false`: the
    /// person zoomed explicitly (buttons, pinch, scroll, or the
    /// actual-size double-click) and `zoomScale` — a literal multiplier of
    /// the image's own pixel size, 1.0 = 100% — is what's shown,
    /// independent of the window/viewport size.
    @Published var isZoomFit = true
    @Published var zoomScale: CGFloat = 1.0
    @Published var panOffset: CGSize = .zero
    /// The scale `ImageCanvasView` is actually rendering at *while*
    /// `isZoomFit` is true — the canvas computes this from its own current
    /// viewport size (something the view model has no way to know on its
    /// own) and reports it back here purely so `FloatingControlBar`'s zoom
    /// percentage reads correctly in fit mode instead of just showing a
    /// stale/placeholder number.
    @Published var lastKnownFitScale: CGFloat = 1.0

    private let minZoom: CGFloat = 0.05
    private let maxZoom: CGFloat = 20
    private let zoomStep: CGFloat = 1.25

    // MARK: Private

    private var thumbnailCache: [URL: CGImage] = [:]

    /// Active whenever the current folder holds more than this one image —
    /// never dimmed just for sitting at the first/last position, since
    /// Poprzedni/Następny loop around (see `goToPrevious`/`goToNext`)
    /// rather than stopping at either end.
    var canGoPrevious: Bool { folderURL != nil && folderImages.count > 1 }
    var canGoNext: Bool { folderURL != nil && folderImages.count > 1 }

    // MARK: Opening a single file

    /// "Otwórz" / ⌘O / Finder "Otwórz z" / drop-one-file-on-empty-state.
    /// If `url` happens to already be one of `folderImages` (picked a file
    /// that's inside the folder already being browsed, or re-opened via
    /// Finder a file from that same folder), this just navigates to it —
    /// no rescan needed. Otherwise the image is shown immediately and its
    /// own containing folder is scanned right after, in the background, so
    /// Previous/Next light up (one or both, depending on where this image
    /// sits in that folder) without a separate, explicit "Przeglądaj" step.
    func openSingleFile(url: URL) async {
        if let folderURL, folderImages.contains(where: { $0.url == url }) {
            _ = folderURL
            await selectImage(url: url)
            isBrowsing = false
            return
        }

        await loadAndDisplay(url: url)
        isBrowsing = false
        scanContainingFolder(of: url)
    }

    /// Scans `url`'s containing folder off the main actor and, once done,
    /// adopts it as the active browse folder — purely so Previous/Next
    /// become available; this never switches into the grid view itself.
    /// Pico isn't sandboxed (see `Pico.entitlements`), so this needs no
    /// extra permission dialog beyond whatever one-time Finder/TCC prompt
    /// macOS itself shows the first time a protected folder (Desktop,
    /// Documents, Downloads, …) is read — the same prompt any ordinary,
    /// non-sandboxed Mac app triggers.
    ///
    /// Guards against the image having moved on again before the scan
    /// finishes (a second "Otwórz" or a Next/Previous press while a huge
    /// folder was still being listed) by checking `currentURL` is still
    /// `url` before adopting the result.
    private func scanContainingFolder(of url: URL) {
        let folder = url.deletingLastPathComponent()
        Task.detached(priority: .utility) { [weak self] in
            let images = SupportedImageTypes.imagesInFolder(folder)
            guard let self else { return }
            await MainActor.run {
                guard self.currentURL == url else { return }
                self.folderURL = folder
                self.folderImages = images.sorted(by: self.sortOption.comparator())
                self.currentIndex = self.folderImages.firstIndex { $0.url == url }
                self.thumbnailCache.removeAll()
            }
        }
    }

    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = SupportedImageTypes.openContentTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await openSingleFile(url: url) }
    }

    // MARK: Browsing a folder

    /// "Przeglądaj" when no folder is held yet, or to explicitly switch to
    /// a different one. While already browsing *some* folder, pressing
    /// "Przeglądaj" again just toggles the grid back into view instead of
    /// re-prompting — see `toggleBrowse()`.
    func presentBrowsePanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Przeglądaj", comment: "NSOpenPanel confirm button when picking a folder to browse")
        if let currentURL {
            panel.directoryURL = currentURL.deletingLastPathComponent()
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadFolder(url)
    }

    /// With no folder held yet, opens the folder picker. Otherwise just
    /// flips between the grid and the single-image canvas — no re-prompt,
    /// since the folder's file listing is already in hand.
    func toggleBrowse() {
        guard folderURL != nil else {
            presentBrowsePanel()
            return
        }
        isBrowsing.toggle()
    }

    func loadFolder(_ url: URL) {
        folderURL = url
        let images = SupportedImageTypes.imagesInFolder(url)
        folderImages = images.sorted(by: sortOption.comparator())
        currentIndex = currentURL.flatMap { cur in folderImages.firstIndex { $0.url == cur } }
        isBrowsing = true
        thumbnailCache.removeAll()
    }

    private func resort() {
        guard !folderImages.isEmpty else { return }
        folderImages.sort(by: sortOption.comparator())
        currentIndex = currentURL.flatMap { cur in folderImages.firstIndex { $0.url == cur } }
    }

    /// Opens a thumbnail tapped in the browse grid — always within the
    /// already-scanned folder, so this never needs a fresh folder scan.
    func selectThumbnail(_ image: BrowsableImage) {
        Task { await selectImage(url: image.url) }
        isBrowsing = false
    }

    private func selectImage(url: URL) async {
        await loadAndDisplay(url: url)
        currentIndex = folderImages.firstIndex { $0.url == url }
    }

    // MARK: Previous / Next — loop around at either end

    func goToPrevious() {
        guard canGoPrevious, let idx = currentIndex else { return }
        navigate(to: (idx - 1 + folderImages.count) % folderImages.count)
    }

    func goToNext() {
        guard canGoNext, let idx = currentIndex else { return }
        navigate(to: (idx + 1) % folderImages.count)
    }

    private func navigate(to index: Int) {
        guard let target = folderImages[safe: index] else { return }
        currentIndex = index
        Task { await loadAndDisplay(url: target.url) }
    }

    // MARK: Loading

    private func loadAndDisplay(url: URL) async {
        isLoading = true
        defer { isLoading = false }
        currentURL = url
        do {
            let image = try await Task.detached(priority: .userInitiated) {
                try ImageExporter.loadUprightImage(url: url)
            }.value
            // `currentURL` may have moved on (fast Next/Next while a big
            // file was still decoding) — don't let a stale decode clobber
            // whatever's actually selected now.
            guard currentURL == url else { return }
            // Reset right as the new image lands, not before — so the
            // previous image stays at whatever zoom it had while this one
            // is still decoding, instead of visibly snapping to "fit"
            // underneath it a moment early.
            resetZoom()
            currentImage = image
        } catch {
            guard currentURL == url else { return }
            currentImage = nil
            errorMessage = String(
                format: String(localized: "Nie udało się otworzyć pliku „%@”: %@", comment: "Error when decoding an image fails; second %@ is the underlying system error description"),
                url.lastPathComponent, error.localizedDescription
            )
        }
    }

    /// Decodes off the main actor (`ImageExporter.thumbnail` can be slow
    /// for a large source image) so populating a grid of 100+ cells never
    /// stalls scrolling/input. Cached by URL — flipping back into browse
    /// mode on the same folder doesn't redecode anything.
    func loadThumbnail(for image: BrowsableImage, maxPixelSize: CGFloat) async -> CGImage? {
        if let cached = thumbnailCache[image.url] { return cached }
        let url = image.url
        let thumb = await Task.detached(priority: .utility) {
            ImageExporter.thumbnail(url: url, maxPixelSize: maxPixelSize)
        }.value
        if let thumb {
            thumbnailCache[image.url] = thumb
        }
        return thumb
    }

    // MARK: Zoom

    func resetZoom() {
        isZoomFit = true
        zoomScale = 1
        panOffset = .zero
    }

    /// Discrete, user-initiated scale changes (this, `zoomOut()`,
    /// `toggleActualSize()`) animate themselves with `withAnimation` right
    /// here, rather than via a blanket `.animation(value:)` modifier on
    /// `ImageCanvasView` — that modifier used to animate *every* change to
    /// the displayed scale, including the continuous, already-live
    /// recompute `isZoomFit` drives every frame while the window is
    /// resizing (most visibly during the system's own fullscreen
    /// enter/exit animation), which looked stuttery/weird with a second,
    /// independently timed ease layered on top. Scoping the animation to
    /// just these explicit button/gesture actions removes that without
    /// losing the nice little transition they're meant to have.
    func zoomIn() {
        // Leaving "fit" mode: seed `zoomScale` from what's actually on
        // screen right now (`lastKnownFitScale`), not whatever it was last
        // set to before fit mode took over. Without this, the first tap
        // after opening an image (still at its initial "fit" scale, say
        // 40%) would step from a stale `zoomScale` of 1.0 instead — a
        // visible jump to 125% (zoom *in*) on the first "Powiększ" press,
        // or symmetrically a jump up to 80% on the first "Pomniejsz" press
        // when the image was showing smaller than that. Seeding here makes
        // every step land exactly one `zoomStep` away from what's visible.
        let seed = isZoomFit ? lastKnownFitScale : zoomScale
        withAnimation(.easeOut(duration: 0.15)) {
            isZoomFit = false
            zoomScale = min(maxZoom, seed * zoomStep)
        }
    }

    func zoomOut() {
        let seed = isZoomFit ? lastKnownFitScale : zoomScale
        withAnimation(.easeOut(duration: 0.15)) {
            isZoomFit = false
            zoomScale = max(minZoom, seed / zoomStep)
        }
    }

    func zoomToFit() {
        isZoomFit = true
        panOffset = .zero
    }

    /// Bound to a pinch gesture / double-click in `ImageCanvasView`.
    func setZoom(_ scale: CGFloat) {
        isZoomFit = false
        zoomScale = min(maxZoom, max(minZoom, scale))
    }

    /// Double-click on the canvas: toggle between "fit" and literal 100%.
    /// Animated like `zoomIn`/`zoomOut` — see that doc comment.
    func toggleActualSize() {
        withAnimation(.easeOut(duration: 0.15)) {
            if !isZoomFit, abs(zoomScale - 1) < 0.001 {
                isZoomFit = true
                panOffset = .zero
            } else {
                isZoomFit = false
                zoomScale = 1
                panOffset = .zero
            }
        }
    }

    // MARK: Save As

    /// Returns `true` the moment the person actually picks a destination
    /// and clicks Save — export itself happens inline (encoding a single
    /// already-decoded image is fast; no progress UI needed, unlike
    /// Movi's asynchronous video export).
    @discardableResult
    func presentSaveAsPanel() -> Bool {
        guard let currentImage, let currentURL else { return false }

        let accessoryView = SaveOptionsAccessoryView(initialFormat: .matching(
            UTType(filenameExtension: currentURL.pathExtension.lowercased())
        ))
        let panel = NSSavePanel()
        panel.accessoryView = accessoryView
        panel.directoryURL = currentURL.deletingLastPathComponent()
        panel.isExtensionHidden = false

        // Strips a trailing "_pico" before re-appending it below, so
        // re-exporting a file that was itself already saved by Pico
        // (`zdjęcie_pico.jpg` → "Zapisz jako…" again) proposes
        // `zdjęcie_pico.<ext>`, not `zdjęcie_pico_pico.<ext>`.
        var baseName = currentURL.deletingPathExtension().lastPathComponent
        if baseName.hasSuffix("_pico") {
            baseName.removeLast("_pico".count)
        }
        func applyFormat(_ format: SupportedImageTypes.WritableFormat) {
            panel.allowedContentTypes = [format.utType]
            panel.nameFieldStringValue = "\(baseName)_pico.\(format.fileExtension)"
        }
        applyFormat(accessoryView.format)
        accessoryView.onChange = { [weak accessoryView] in
            guard let accessoryView else { return }
            applyFormat(accessoryView.format)
        }

        guard panel.runModal() == .OK, let url = panel.url else { return false }

        do {
            try ImageExporter.write(currentImage, to: url, options: accessoryView.exportOptions)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: Drag & drop

    /// Accepts either a single image file (opens it, same as "Otwórz") or
    /// a folder (same as "Przeglądaj").
    func handleDrop(url: URL) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return }
        if isDirectory.boolValue {
            loadFolder(url)
        } else {
            Task { await openSingleFile(url: url) }
        }
    }
}
