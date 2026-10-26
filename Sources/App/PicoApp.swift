import AppKit
import SwiftUI

@main
struct PicoApp: App {
    // No app-wide state here — each window `WindowGroup` creates owns its
    // own `ImageViewerViewModel` (a `@StateObject` in `ContentView`), so a
    // new window (⌘N, Finder "Otwórz z", …) always gets a genuinely
    // independent image/folder context. Menu commands below reach
    // whichever window is actually focused via `ImageCommands`'
    // `@FocusedValue`, fed by `ContentView`'s
    // `.focusedSceneValue(\.imageViewerViewModel, viewModel)`.
    init() {
        // Tabs turned off app-wide, per explicit request: with this
        // `false`, no window gets the "+" tab button, the "Pokaż pasek
        // kart"/"Scal wszystkie okna" items disappear from the Window
        // menu, and windows can no longer be dragged into one another's
        // tab group. Set here, before any window exists, so it's already
        // in effect for the very first one — `ContentView` additionally
        // sets each window's own `tabbingMode = .disallowed` as a second,
        // per-window guarantee.
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    var body: some Scene {
        WindowGroup {
            // No `.preferredColorScheme` override here — Pico follows
            // whatever appearance macOS is actually in, including "Auto"
            // (switches between light/dark by time of day). An earlier
            // version pinned this to `.dark` unconditionally, which is why
            // the window kept a black canvas even in light mode or during
            // the day; every color used below (`ContentView`,
            // `BrowseGridView`, …) is a system-adaptive one so the whole
            // window actually follows the change.
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        // Hands window sizing over to the content's own min size / the
        // one programmatic `setFrame` call in `ContentView.applyWindowSize`
        // instead of `WindowGroup`'s own automatic resizing fighting it —
        // same reasoning as Movi's identical setting.
        .windowResizability(.contentSize)
        .commands {
            ImageCommands()
        }
    }
}

/// Menu commands acting on whichever window/tab is currently focused —
/// mirrors Movi's `EditorCommands`. `viewModel` is `nil` only in the brief
/// window before any `ContentView` has appeared; every item below disables
/// itself gracefully in that case rather than force-unwrap.
struct ImageCommands: Commands {
    @FocusedValue(\.imageViewerViewModel) private var viewModel: ImageViewerViewModel?

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Otwórz obraz…") {
                viewModel?.presentOpenPanel()
            }
            .keyboardShortcut("o", modifiers: .command)
            .disabled(viewModel == nil)

            Button("Przeglądaj folder…") {
                viewModel?.toggleBrowse()
            }
            .keyboardShortcut("b", modifiers: [.command, .shift])
            .disabled(viewModel == nil)

            Divider()

            Button("Zapisz jako…") {
                viewModel?.presentSaveAsPanel()
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(viewModel?.currentImage == nil)
        }

        // Folded into the system "Widok"/"View" menu (after its toolbar
        // section, alongside "Enter Full Screen" etc.) rather than a new
        // top-level menu — these are ordinary view-affecting commands, and
        // that's where a Mac user already expects to find them.
        CommandGroup(after: .toolbar) {
            Button("Poprzedni obraz") {
                viewModel?.goToPrevious()
            }
            .keyboardShortcut(.leftArrow, modifiers: [])
            .disabled(!(viewModel?.canGoPrevious ?? false))

            Button("Następny obraz") {
                viewModel?.goToNext()
            }
            .keyboardShortcut(.rightArrow, modifiers: [])
            .disabled(!(viewModel?.canGoNext ?? false))

            Divider()

            Button("Powiększ") {
                viewModel?.zoomIn()
            }
            .keyboardShortcut("+", modifiers: .command)
            .disabled(viewModel?.currentImage == nil)

            Button("Pomniejsz") {
                viewModel?.zoomOut()
            }
            .keyboardShortcut("-", modifiers: .command)
            .disabled(viewModel?.currentImage == nil)

            Button("Dopasuj do okna") {
                viewModel?.zoomToFit()
            }
            .keyboardShortcut("0", modifiers: .command)
            .disabled(viewModel?.currentImage == nil)
        }

        // Replaces the system-generated "About Pico" with the same kind of
        // custom author/version panel Movi uses.
        CommandGroup(replacing: .appInfo) {
            Button("O Pico") {
                AboutPanel.show()
            }
        }
    }
}

/// Exposes the focused window/tab's `ImageViewerViewModel` to
/// `ImageCommands` — counterpart to `ContentView`'s
/// `.focusedSceneValue(\.imageViewerViewModel, viewModel)`.
private struct ImageViewerViewModelKey: FocusedValueKey {
    typealias Value = ImageViewerViewModel
}

extension FocusedValues {
    var imageViewerViewModel: ImageViewerViewModel? {
        get { self[ImageViewerViewModelKey.self] }
        set { self[ImageViewerViewModelKey.self] = newValue }
    }
}

/// The standard macOS About panel, fed just an author line and version —
/// same approach as Movi's `AboutPanel`.
enum AboutPanel {
    static func show() {
        let authorParagraph = NSMutableParagraphStyle()
        authorParagraph.alignment = .center

        let credits = NSMutableAttributedString(
            string: "Made by Marzepam\n",
            attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                .paragraphStyle: authorParagraph
            ]
        )
        let projectLine = NSAttributedString(
            string: "Project available on https://github.com/Marzepam",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: authorParagraph,
                .link: URL(string: "https://github.com/Marzepam") as Any
            ]
        )
        credits.append(projectLine)

        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationVersion: "1.0",
            .credits: credits
        ])
    }
}
