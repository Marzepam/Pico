import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    // Owned here, one independent instance per window — same reasoning as
    // Movi's `EditorViewModel`: `WindowGroup` spawns a genuinely separate
    // `ContentView` per window (⌘N / Finder "Otwórz z" opens a new one
    // rather than reusing the frontmost), and each should hold its own
    // image and folder context rather than sharing one app-wide instance.
    // (Window *tabbing* specifically — multiple windows merged under one
    // tab bar — is turned off; see `window.tabbingMode` below.)
    @StateObject private var viewModel = ImageViewerViewModel()
    @State private var isTargeted = false
    @State private var keyMonitor: Any?
    @State private var hostWindow: NSWindow?

    @State private var controlsVisible = true
    @State private var hideControlsWorkItem: DispatchWorkItem?
    @State private var isHoveringFloatingBar = false

    /// Drives the Fullscreen button's icon/tooltip — kept in sync with the
    /// window's *actual* fullscreen state via the notifications below
    /// rather than toggled optimistically, so it stays correct even when
    /// fullscreen is entered/exited some other way (the green button, ⌃⌘F,
    /// or the system "Zakończ pełny ekran" item while hovering the top).
    @State private var isFullScreen = false
    @State private var fullScreenObservers: [NSObjectProtocol] = []

    /// Flips to `true` the first time this window actually displays an
    /// image, and never back — see `backgroundColor`'s doc comment. Not
    /// just `viewModel.currentImage != nil`: a later decode error clears
    /// `currentImage` back to `nil` momentarily, and that shouldn't make
    /// the canvas flash back to the system-adaptive "no image yet" look.
    @State private var hasShownImage = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Three cases: Browsing shows `BrowseGridView`'s own
                // adaptive background through (`Color.clear` here, same as
                // before). With an image on screen, this is always pure
                // black regardless of system theme, in both windowed and
                // fullscreen mode — same convention as Preview/Photos/
                // QuickTime, so a photo is never framed by a competing
                // backdrop color. But the empty state — before anything's
                // been opened yet, right when the window first appears —
                // follows the system appearance like an ordinary window,
                // same as `BrowseGridView`; only the *first displayed
                // image* flips this over to black, not the window simply
                // existing.
                backgroundColor.ignoresSafeArea()

                Group {
                    if viewModel.isBrowsing {
                        BrowseGridView(viewModel: viewModel, isFullScreen: isFullScreen)
                    } else if viewModel.currentImage != nil {
                        ImageCanvasView(viewModel: viewModel)
                    } else {
                        emptyState
                    }
                }
                .ignoresSafeArea()

                WindowAccessor { window in
                    guard hostWindow !== window else { return }
                    hostWindow = window
                    window.isRestorable = false
                    // Tabs turned off per explicit request: no "+" button,
                    // no "Pokaż pasek kart"/"Scal wszystkie okna" menu
                    // items, and this window can't be dragged into another
                    // one's tab group. `PicoApp.init()` also flips the
                    // app-wide `NSWindow.allowsAutomaticWindowTabbing`
                    // switch — belt and suspenders, since that one only
                    // takes effect for windows created after it runs.
                    window.tabbingMode = .disallowed
                    // Height floor deliberately matches the width floor
                    // (not the toolbar's own, much shorter, footprint
                    // height) — otherwise the window could be dragged down
                    // into a very short, wide strip with the image reduced
                    // to a tiny sliver, which a floor this low allowed.
                    window.minSize = NSSize(width: FloatingControlBar.minWindowWidth, height: FloatingControlBar.minWindowWidth)
                    if viewModel.currentImage == nil {
                        centerOnScreen(window)
                    }
                    updateWindowTitle()
                    installFullScreenObservers(for: window)
                }
                .frame(width: 0, height: 0)

                if !viewModel.isBrowsing, viewModel.currentImage != nil {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer(minLength: 0)
                            FloatingControlBar(
                                viewModel: viewModel,
                                isFullScreen: isFullScreen,
                                onOpen: viewModel.presentOpenPanel,
                                onToggleFullScreen: toggleFullScreen,
                                onSaveAs: { viewModel.presentSaveAsPanel() }
                            )
                            .onHover { hovering in
                                isHoveringFloatingBar = hovering
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    .padding(.bottom, geo.size.height * 0.1)
                    .opacity(controlsVisible ? 1 : 0)
                    .allowsHitTesting(controlsVisible)
                    .animation(.easeInOut(duration: 0.5), value: controlsVisible)
                }

                if isTargeted {
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(Color.accentColor, lineWidth: 4)
                        .padding(20)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active:
                    showControls()
                case .ended:
                    hideControlsNow()
                }
            }
        }
        .frame(minWidth: FloatingControlBar.minWindowWidth, minHeight: FloatingControlBar.minWindowWidth)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted, perform: handleDrop)
        .onAppear {
            installKeyMonitor()
            scheduleAutoHide()
        }
        .onDisappear {
            removeKeyMonitor()
            removeFullScreenObservers()
        }
        .onReceive(viewModel.$currentImage.compactMap { $0 }) { cgImage in
            hasShownImage = true
            // Every image — the first one, after switching folders, and
            // every Następny/Poprzedni after that — gets the exact same
            // treatment: see `fitWindowFullHeight`'s doc comment.
            guard let window = hostWindow else { return }
            fitWindowFullHeight(for: CGSize(width: cgImage.width, height: cgImage.height), window: window)
        }
        .onChange(of: viewModel.currentURL) { _, _ in
            updateWindowTitle()
        }
        .onChange(of: viewModel.isBrowsing) { _, isBrowsing in
            // Only entering Browse restores anything — leaving it back to
            // the canvas (with no new image load) is left completely
            // alone, exactly as before this feature existed; the next
            // image load re-asserts `fitWindowFullHeight` as usual.
            guard isBrowsing, let window = hostWindow else { return }
            applyBrowseWindowSize(window: window)
        }
        .alert("Błąd", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .onOpenURL { url in
            Task { await viewModel.openSingleFile(url: url) }
        }
        .focusedSceneValue(\.imageViewerViewModel, viewModel)
    }

    /// Mirrors the reasoning right below, in `backgroundColor`: with an image
    /// on screen the backdrop is always black, so these need an explicit
    /// white that won't go dark-on-dark; with no image yet, the backdrop
    /// is the system-adaptive one, so these go back to `.tertiary`/
    /// `.secondary` to match it in either theme.
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("Otwórz obraz (⌘O) albo przeciągnij go tutaj")
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button("Otwórz obraz…", action: viewModel.presentOpenPanel)
                    .buttonStyle(.borderedProminent)
                Button("Przeglądaj folder…", action: viewModel.presentBrowsePanel)
                    .buttonStyle(.bordered)
            }
        }
    }

    /// `Browsing` → `Color.clear` (lets `BrowseGridView`'s own adaptive
    /// background show through, unchanged from before). No image loaded
    /// yet → the system-adaptive window background, same as an ordinary
    /// window and the same color `BrowseGridView` uses, so the window
    /// looks like a normal Mac window right when it first appears. Once
    /// an image has actually been displayed at least once, this flips to
    /// pure black and stays there even after that image is later closed
    /// back to the empty state — deliberately a one-way switch per
    /// window: the whole point is that the *first displayed image* is
    /// what darkens the canvas, not the window merely existing.
    private var backgroundColor: Color {
        if viewModel.isBrowsing { return .clear }
        return hasShownImage ? .black : Color(nsColor: .windowBackgroundColor)
    }

    // MARK: Drag & drop

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            Task { @MainActor in
                viewModel.handleDrop(url: url)
            }
        }
        return true
    }

    // MARK: Keyboard shortcuts

    /// Plain, unmodified single-key shortcuts — arrows for Previous/Next,
    /// +/-/0 as a bare-key convenience alongside the ⌘-modified versions
    /// in `PicoApp`'s menu commands, and Escape to back out of the browse
    /// grid. Mirrors Movi's split between a local key monitor for this
    /// kind of shortcut and native `Commands` for the ⌘-modified ones.
    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard NSApp.keyWindow === hostWindow else { return event }

            if let special = event.specialKey {
                switch special {
                case .leftArrow:
                    viewModel.goToPrevious()
                    return nil
                case .rightArrow:
                    viewModel.goToNext()
                    return nil
                default:
                    break
                }
            }

            if event.keyCode == 53 { // Escape
                if viewModel.isBrowsing {
                    viewModel.isBrowsing = false
                    return nil
                }
                return event
            }

            switch event.charactersIgnoringModifiers {
            case "+", "=":
                viewModel.zoomIn()
                return nil
            case "-", "_":
                viewModel.zoomOut()
                return nil
            case "0":
                viewModel.zoomToFit()
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
    }

    // MARK: Fullscreen

    private func toggleFullScreen() {
        hostWindow?.toggleFullScreen(nil)
    }

    /// Tracks the *actual* fullscreen state of this window/tab via
    /// notifications scoped to it (`object: window`), rather than flipping
    /// `isFullScreen` optimistically inside `toggleFullScreen()` — that
    /// would drift out of sync whenever fullscreen is entered or exited
    /// some other way (the window's green button, the system menu, or
    /// `ImageCommands`' own fullscreen entry if one is ever added).
    private func installFullScreenObservers(for window: NSWindow) {
        removeFullScreenObservers()
        let center = NotificationCenter.default
        let enter = center.addObserver(forName: NSWindow.willEnterFullScreenNotification, object: window, queue: .main) { _ in
            isFullScreen = true
            // If the windowed view was showing the image at an explicit,
            // literal-percentage zoom (pinch, the zoom buttons, or
            // double-click) rather than dynamic "Dopasuj", that scale was
            // chosen for the *old*, much smaller windowed content rect.
            // Left alone, it would still apply inside the much bigger (and
            // differently shaped) fullscreen viewport — the image shows
            // tiny in the middle with gaps on every side instead of
            // filling it. Switching to dynamic fit mode makes
            // `ImageCanvasView` immediately recompute the correct scale
            // itself from its own `GeometryReader`, against whatever size
            // the fullscreen viewport actually turns out to be. (Ordinary
            // browsing is already in fit mode — see
            // `fitWindowFullHeight` — so this is a no-op then.)
            viewModel.zoomToFit()
        }
        let exit = center.addObserver(forName: NSWindow.didExitFullScreenNotification, object: window, queue: .main) { _ in
            isFullScreen = false
            // Re-run the same full-height sizing logic used for every
            // other image — while still in fullscreen, the window's own
            // frame is the screen's, so this must wait until just now,
            // once there's a normal window frame to resize again.
            if let cgImage = viewModel.currentImage {
                fitWindowFullHeight(for: CGSize(width: cgImage.width, height: cgImage.height), window: window)
            }
        }
        // Live-saves the Browse size on every manual resize while browsing
        // — not just on quit — so whatever size the window is at when the
        // app happens to close (quit, crash, "Zakończ") is what's already
        // persisted; there's no separate "save on quit" step to miss.
        // Guarded to windowed mode only: in fullscreen the frame is the
        // screen's own size, which isn't a Browse size worth remembering.
        let resize = center.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) { _ in
            guard viewModel.isBrowsing, !window.styleMask.contains(.fullScreen) else { return }
            saveBrowseWindowSize(window.frame.size)
        }
        fullScreenObservers = [enter, exit, resize]
    }

    private func removeFullScreenObservers() {
        let center = NotificationCenter.default
        for observer in fullScreenObservers {
            center.removeObserver(observer)
        }
        fullScreenObservers = []
    }

    // MARK: Auto-hide floating bar + window buttons on inactivity
    //
    // Identical mechanism to Movi's `ContentView` — see that file's notes
    // on why `.onHover` (not `.onContinuousHover`) is used for the bar
    // itself, and why fullscreen skips the native window-button fade.

    private func showControls() {
        hideControlsWorkItem?.cancel()
        if !controlsVisible {
            controlsVisible = true
        }
        setWindowButtonsHidden(false)
        scheduleAutoHide()
    }

    private func hideControlsNow() {
        hideControlsWorkItem?.cancel()
        hideControlsWorkItem = nil
        controlsVisible = false
        setWindowButtonsHidden(true)
    }

    private func scheduleAutoHide() {
        hideControlsWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            guard !isHoveringFloatingBar else {
                scheduleAutoHide()
                return
            }
            controlsVisible = false
            setWindowButtonsHidden(true)
        }
        hideControlsWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: workItem)
    }

    private func setWindowButtonsHidden(_ hidden: Bool) {
        guard let window = hostWindow, !window.styleMask.contains(.fullScreen) else { return }
        let targetAlpha: CGFloat = hidden ? 0 : 1
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.5
            for type: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
                window.standardWindowButton(type)?.animator().alphaValue = targetAlpha
            }
        }
    }

    // MARK: Window sizing — every image uses the full available screen height, centered; only width adapts

    /// Every image shown in windowed mode — the first one, right after
    /// switching to a different folder, and every Następny/Poprzedni
    /// after that — uses the *entire* available vertical space between
    /// the menu bar and the Dock (`screen.visibleFrame.height`), centered
    /// on the screen; only the window's *width* is recomputed, to the new
    /// image's own aspect ratio at that height, so there's no side bar
    /// unless the image is narrower than the toolbar's own minimum width
    /// allows (an explicit floor — see `window.minSize`, which now sets
    /// the same floor on height too, so a manual drag-resize can't turn
    /// the window into a short strip with the image reduced to a tiny
    /// icon either). A manual resize of the window by hand is left
    /// completely alone until the *next* image loads — this always
    /// re-asserts the full-height rule again then, rather than
    /// remembering whatever height the person last dragged it to.
    ///
    /// Leaves the view model's zoom mode exactly as `resetZoom()` already
    /// set it for this new image (dynamic "Dopasuj") rather than computing
    /// a final scale and handing it over the way an earlier version did
    /// (`applyExplicitScale`): since the window ends up sized to exactly
    /// the scale this produces anyway, `ImageCanvasView`'s own live
    /// `GeometryReader`-driven fit recomputes to the identical result —
    /// and staying in that dynamic mode is what lets a manual drag-resize
    /// of the window, at any later point, keep rescaling the image
    /// correctly instead of leaving it "stuck" at a fixed size.
    ///
    /// No animation on the resize itself — it should already be the
    /// right size the instant the new image appears, not visibly
    /// catching up to it. Only resizes in windowed mode: fullscreen's
    /// content rect is the screen's own size, which this must never
    /// fight (its own exit handler in `installFullScreenObservers`
    /// re-runs this once fullscreen ends).
    private func fitWindowFullHeight(for imageSize: CGSize, window: NSWindow) {
        guard !window.styleMask.contains(.fullScreen), imageSize.width > 0, imageSize.height > 0,
              let screen = window.screen ?? NSScreen.main else { return }

        let visible = screen.visibleFrame
        let availableHeight = visible.height

        var targetWidth = imageSize.width * (availableHeight / imageSize.height)
        if targetWidth > visible.width {
            targetWidth = visible.width
        }
        if targetWidth < window.minSize.width {
            targetWidth = window.minSize.width
        }

        let targetContentSize = NSSize(width: targetWidth, height: availableHeight)
        var targetFrame = window.frameRect(forContentRect: NSRect(origin: .zero, size: targetContentSize))
        targetFrame.origin.x = visible.midX - targetFrame.width / 2
        targetFrame.origin.y = visible.minY

        let currentFrame = window.frame
        if abs(currentFrame.width - targetFrame.width) > 0.5
            || abs(currentFrame.height - targetFrame.height) > 0.5
            || abs(currentFrame.origin.x - targetFrame.origin.x) > 0.5
            || abs(currentFrame.origin.y - targetFrame.origin.y) > 0.5 {
            window.setFrame(targetFrame, display: true, animate: false)
        }
    }

    // MARK: Browse-mode window size memory
    //
    // Separate from — and doesn't interact with — ordinary image viewing's
    // `fitWindowFullHeight` above: Browsing is the one mode where the
    // window just keeps whatever size the person last left it at, restored
    // across app launches via `UserDefaults`. `saveBrowseWindowSize` runs
    // on every resize while `isBrowsing` (installed in
    // `installFullScreenObservers`); `applyBrowseWindowSize` runs once,
    // the moment Browsing turns on (`onChange(of: viewModel.isBrowsing)`
    // in `body`).

    private static let browseWidthKey = "pico.browseWindowWidth"
    private static let browseHeightKey = "pico.browseWindowHeight"

    /// No stored size yet (first-ever launch, or before this feature
    /// existed) leaves the window exactly as it is — same as the behavior
    /// before Browse had any size memory at all.
    private func applyBrowseWindowSize(window: NSWindow) {
        guard !window.styleMask.contains(.fullScreen) else { return }
        let defaults = UserDefaults.standard
        let width = defaults.double(forKey: Self.browseWidthKey)
        let height = defaults.double(forKey: Self.browseHeightKey)
        guard width > 0, height > 0, let screen = window.screen ?? NSScreen.main else { return }

        let visible = screen.visibleFrame
        let clampedWidth = min(max(width, window.minSize.width), visible.width)
        let clampedHeight = min(max(height, window.minSize.height), visible.height)

        let targetContentSize = NSSize(width: clampedWidth, height: clampedHeight)
        var targetFrame = window.frameRect(forContentRect: NSRect(origin: .zero, size: targetContentSize))
        // Keeps the window's current center rather than re-centering on
        // the screen, so switching into Browse resizes in place instead of
        // also jumping the window somewhere new.
        let currentCenter = CGPoint(x: window.frame.midX, y: window.frame.midY)
        targetFrame.origin.x = currentCenter.x - targetFrame.width / 2
        targetFrame.origin.y = currentCenter.y - targetFrame.height / 2

        if targetFrame.maxX > visible.maxX { targetFrame.origin.x = visible.maxX - targetFrame.width }
        if targetFrame.minX < visible.minX { targetFrame.origin.x = visible.minX }
        if targetFrame.maxY > visible.maxY { targetFrame.origin.y = visible.maxY - targetFrame.height }
        if targetFrame.minY < visible.minY { targetFrame.origin.y = visible.minY }

        window.setFrame(targetFrame, display: true, animate: false)
    }

    private func saveBrowseWindowSize(_ size: NSSize) {
        let defaults = UserDefaults.standard
        defaults.set(size.width, forKey: Self.browseWidthKey)
        defaults.set(size.height, forKey: Self.browseHeightKey)
    }

    private func centerOnScreen(_ window: NSWindow) {
        guard let screen = window.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        var frame = window.frame
        frame.origin.x = visible.midX - frame.width / 2
        frame.origin.y = visible.midY - frame.height / 2
        window.setFrame(frame, display: true, animate: false)
    }

    /// The window has no visible title bar (`.hiddenTitleBar`), but
    /// `window.title` still names the window in Mission Control, the Dock's
    /// window-list menu, and ⌘` window switching, so it's kept current even
    /// without a title bar to display it in.
    private func updateWindowTitle() {
        guard let window = hostWindow else { return }
        if let url = viewModel.currentURL {
            window.title = url.deletingPathExtension().lastPathComponent
        } else {
            window.title = String(localized: "Brak pliku", comment: "Window title fallback when no image is loaded")
        }
    }
}

/// Resolves the `NSWindow` hosting this SwiftUI view tree — identical
/// bridge to Movi's `WindowAccessor`.
private struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                onResolve(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                onResolve(window)
            }
        }
    }
}
