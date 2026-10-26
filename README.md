vi
("Shave Video"/VirtualDub, just for photos instead of video). Written in
Swift/SwiftUI + ImageIO/CoreGraphics, with no external dependencies at all.

The project (folders, the `project.yml` file, the Xcode target, entitlements,
the `PicoApp` entry point) is named **Pico** throughout — the bundle
identifier is `com.pico.Pico`. Version **1.0**. The "About Pico" panel
(Pico menu → About Pico) is entirely custom (`AboutPanel.show()` in
`PicoApp.swift`, replacing the default `CommandGroup(replacing: .appInfo)`)
— it shows the version number, "Made by Marzepam" and a clickable
"Project available on https://github.com/Marzepam" link, through the same
standard panel AppKit itself uses
(`NSApplication.orderFrontStandardAboutPanel(options:)`).

## Features

| Feature | How it works |
|---|---|
| **Open** | An `NSOpenPanel` filtered to `UTType.image` — every format the system/ImageIO can decode (HEIC, JPEG, PNG, GIF, TIFF, BMP, WebP, ICO and more), with no manually maintained extension list. |
| **Browse** | Picks a folder (`NSOpenPanel` in directory-selection mode) and shows a thumbnail grid of its contents inside the same window — the button acts as a toggle between the grid and the single-image view. |
| **Save As…** | Converts the current image to a chosen format (JPEG/PNG/TIFF/HEIC/BMP/GIF) through an `NSSavePanel` with a custom accessory view: a quality slider for JPEG/HEIC, a compression choice (LZW/none) for TIFF — nothing extra for PNG/BMP/GIF, since there's nothing to configure there. |
| **Previous / Next** | Navigates within the folder, in the app's own sort order (name / modification date / creation date / size / type, ascending or descending) — see "Sorting" below. In windowed mode this also adapts the window's width to the new image's aspect ratio (the height stays unchanged) — see "Window vs. Movi" below. |
| **Zoom In / Zoom Out / Fit to window** | Only change what's visible inside the window — the window itself never changes size when zooming (see "Window vs. Movi"). |
| **Full screen** | Toggles the window in/out of full-screen mode (`NSWindow.toggleFullScreen(_:)`); the toolbar icon and its tooltip change to match the window's actual state, tracked via the `willEnterFullScreenNotification`/`didExitFullScreenNotification` notifications — including when full screen is entered/exited some other way (the window's green button, ⌃⌘F). |

Additionally (small, natural extensions, not explicitly spelled out in the
spec but consistent with the rest of the app): double-click toggles
between "Fit to window" and actual size (100%), pinch-to-zoom and
dragging the image with the mouse when it's zoomed in beyond the window's
size, dropping a file **or a folder** onto the window (dropping a file =
"Open", dropping a folder = "Browse"), Finder's "Open With…" support, and
keyboard shortcuts: ⌘O, ⇧⌘B, ⌘S, the ←/→ arrows (no modifier), ⌘+/⌘−/⌘0 as
well as bare +/-/0, and Esc (exits the thumbnail grid). ⌘N always opens a
**new, independent window** — native window tabbing is deliberately
disabled, see below.

## Requirements

- macOS 14.0 or newer
- Xcode 15+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Building

```bash
cd Pico
xcodegen generate
open Pico.xcodeproj
```

Without XcodeGen: create a new macOS App project in Xcode (SwiftUI, no
Core Data), copy the contents of `Sources/` into the project, replace the
generated `Info.plist` with the one from this repo, add
`Pico.entitlements` as the Code Signing Entitlements file, set
`CFBundleIdentifier` to `com.pico.Pico`, and make sure
`Localizable.xcstrings` and the `*.lproj/InfoPlist.strings` files are
included in the target.

## Project structure

```
Pico/
├── project.yml                          ← XcodeGen project definition
├── Info.plist                           ← CFBundleDocumentTypes, CFBundleLocalizations
├── Pico.entitlements                    ← deliberately empty (no App Sandbox — see below)
└── Sources/
    ├── App/
    │   └── PicoApp.swift                 ← @main, WindowGroup, menu, "About Pico" panel
    ├── Models/
    │   ├── BrowsableImage.swift          ← metadata for one file in the browsed folder
    │   └── ImageSortOption.swift         ← sort field + direction, comparator
    ├── ViewModels/
    │   └── ImageViewerViewModel.swift    ← all state and actions (open/browse/save/zoom/navigation)
    ├── Views/
    │   ├── ContentView.swift             ← window, bar auto-hide, window sizing, drag & drop, shortcuts
    │   ├── ImageCanvasView.swift         ← single-image view (zoom/pan/gestures)
    │   ├── BrowseGridView.swift          ← thumbnail grid + sort menu
    │   ├── FloatingControlBar.swift      ← floating toolbar docked at the bottom of the window
    │   └── SaveOptionsAccessoryView.swift ← NSSavePanel accessory view ("Save As…")
    ├── Support/
    │   ├── ImageExporter.swift           ← reading (with EXIF orientation correction) and writing via ImageIO
    │   ├── SupportedImageTypes.swift     ← which formats are readable/writable, folder listing
    │   └── Array+Safe.swift
    ├── Resources/
    │   └── Localizable.xcstrings         ← String Catalog with translations (pl → en/fr/de/es)
    └── {pl,en,fr,de,es}.lproj/
        └── InfoPlist.strings             ← localization of CFBundleTypeName
```

## How it works

### State architecture

One `ImageViewerViewModel` per window (a `@StateObject` in `ContentView`,
exactly like `EditorViewModel` in Movi) — `WindowGroup` creates a separate
`ContentView` instance for every window, so each one holds its own image,
its own folder context, and its own zoom level. Menu commands
(`ImageCommands` in `PicoApp.swift`) reach the currently active window via
`@FocusedValue(\.imageViewerViewModel)`.

### Light/dark theme — follows the system, not hard-locked

An earlier version set `.preferredColorScheme(.dark)` on the whole window
in `PicoApp.swift`, which forced dark mode regardless of what mode macOS
was actually in — including "Auto", which switches light/dark on its own
based on time of day. That setting has been removed: Pico now simply
follows the system's current appearance, like any ordinary AppKit/SwiftUI
app.

Removing `.preferredColorScheme` alone wasn't enough as long as the
window background, the "Browse" grid, and some of the text used
hard-coded colors (`Color.black`, `.foregroundStyle(.white...)`) instead
of the system-adaptive equivalents — which is why, for example, the
thumbnail grid stayed black even in light mode. Fixed spots: the window
background in `ContentView` (`Color(nsColor: .windowBackgroundColor)`
instead of `Color.black`), `BrowseGridView`'s background and text (the
same `.windowBackgroundColor`, plus `.foregroundStyle(.primary)`/
`.secondary` instead of hard-coded white), and the thumbnails' borders/
fills (`Color.primary.opacity(…)` instead of `Color.white.opacity(…)` — a
light shade of gray in light mode, a light shade of white in dark mode).

A deliberate exception is the floating toolbar (`FloatingControlBar`) —
it stays a permanently dark, semi-transparent bar regardless of the
system theme, the same way QuickTime Player's or Movi's playback controls
do: the bar floats over an arbitrary image of unpredictable brightness, so
a fixed, dark contrast reads better here than a bar that itself kept
changing brightness.

That deliberate exception had a bug of its own, though: the button icons
in `controlButton` and the two side labels (zoom percentage, position in
the folder) had no color of their own hard-coded in — they relied on the
default/`.secondary`, i.e. the system-adaptive one. In dark mode that came
out as white-on-black (readable by accident), but in light mode
`.secondary`/the default color turned dark, so the icons ended up
practically black on the bar's black background, invisible. Since the
bar itself is always meant to stay dark, its contents need a hard-coded
white too, not a system color — hence `Image(systemName:)` in
`controlButton` now has `.foregroundStyle(.white)`, and the zoom/position
labels have `.foregroundStyle(.white.opacity(0.6))` (the filename in the
middle of the bar already had `.white.opacity(0.85)` and was left
unchanged).

**Correction: only the "Browse" grid follows the system — and the image
canvas's background only turns black once the first image is actually
displayed, not immediately when the window opens.** The "make everything
adaptive" approach above turned out to be too broad: the canvas showing a
single image (in both windowed and full-screen mode) is meant to always
be black regardless of system theme — the same convention as Preview,
Photos, or QuickTime, where a photo should never sit on a backdrop that
changes color on its own. What stayed adaptive is `BrowseGridView` (the
thumbnail grid) — but also the "no file" state (`emptyState`), shown
right when the window first opens, before any image has been displayed:
that's still meant to look like an ordinary system window, not a black
screen.

In `ContentView` this third case is handled by `backgroundColor`
(replacing the earlier, simpler `isBrowsing ? clear : black` condition):
`isBrowsing` → `Color.clear` (lets `BrowseGridView`'s own background show
through); otherwise, as long as `hasShownImage` is `false` →
`Color(nsColor: .windowBackgroundColor)` (adaptive, like an ordinary
window); from the moment `hasShownImage` is set to `true` →
`Color.black`, and that never flips back — even if the canvas later
briefly returns to `nil` (a decode error), the background stays black
instead of flickering back to the adaptive one. `hasShownImage` is a
`@State` set once, in the same `onReceive(viewModel.$currentImage...)`
that already calls `fitWindowFullHeight`. The `emptyState` text/icon went
back to adaptive `.tertiary`/`.secondary`, since they now sit on an
adaptive background, not a black one.

### Browse window size — remembered across launches

Only the "Browse" grid has its own window-size memory — ordinary image
viewing works exactly as described below (`fitWindowFullHeight`, full
screen height for every image) and is in no way affected by this. In
`ContentView`:

- `saveBrowseWindowSize(_:)` saves the window's current size to
  `UserDefaults` (`pico.browseWindowWidth`/`pico.browseWindowHeight`) on
  every `NSWindow.didResizeNotification`, as long as `viewModel.isBrowsing`
  is `true` at that moment and the window isn't in full screen (there the
  frame size is just the screen's own size, not worth remembering). The
  save happens live, on every drag, so whatever is saved at the moment
  the app happens to close is always current — there's no separate
  "save on quit" hook to get right.
- `applyBrowseWindowSize(window:)` reads those two values and — if they've
  been saved (on the very first launch they haven't, so the window is
  left unchanged) — resizes the window to that size, clamped to
  `window.minSize` and to the screen's visible area, keeping the window's
  current center. Called once, in `onChange(of: viewModel.isBrowsing)` in
  `body`, only when Browse mode is turning on — leaving it (without
  loading a new image) is left unchanged, same as before.

Effect: enlarging the window while Browsing is remembered, and the next
time Browse mode is entered — in the same session, or after relaunching
the app — restores that exact size.

### Window tabbing — disabled

macOS's native window tabbing is deliberately disabled, per explicit
request: `PicoApp.init()` sets `NSWindow.allowsAutomaticWindowTabbing =
false` before the first window is even created (removing the "+" button
and the "Show Tab Bar"/"Merge All Windows" items from the Window menu,
app-wide), and `ContentView` additionally sets
`window.tabbingMode = .disallowed` on every window individually, as soon
as it's resolved (`WindowAccessor`) — belt and suspenders, not just the
global switch. ⌘N still opens a new window (that's `WindowGroup`'s
ordinary behavior, independent of tabbing) — it simply never joins
another window's tab bar.

### EXIF orientation correction

`CGImageSourceCreateImageAtIndex` does **not** automatically apply the
EXIF/TIFF orientation tag — a photo taken with the phone held upright
would come out sideways, both on screen and in the exported copy.
`ImageExporter.loadUprightImage(url:)` reads that tag separately
(`kCGImagePropertyOrientation`) and, if it differs from the "normal"
orientation, redraws the image through the appropriate
`CGAffineTransform` in a fresh `CGContext`, so the resulting `CGImage` is
always already "upright". Thanks to this, "Save As…" always writes pixels
in the correct orientation, even when converting between formats with
different tag-writing conventions (e.g. a sideways-oriented HEIC →
JPEG) — because the orientation has already been baked into the pixels
themselves rather than carried over as a tag to be reinterpreted.

If `CGContext` fails to be created for some unusual pixel format (this
happens with some CMYK/indexed files), the code silently falls back to
the un-rotated image instead of crashing — still to be tested against
real files in Xcode; this is the one place in the app where I allow a
silent degradation instead of a hard error, since the alternative would
be a crash on a file that could still be viewed anyway (just possibly
rotated wrong).

### Window vs. Movi — zoom never resizes the window; every image uses the full screen height

This is the biggest difference from Movi. Movi locks the window's aspect
ratio to the video's (`NSWindow.contentAspectRatio` +  a custom
`NSWindowDelegate.windowWillResize`), so the video always fills the
window with no black bars — that made sense there, because zoom = window
size.

In Pico, **Zoom In/Zoom Out/Fit to window never change the window's
size** — that requirement stands unchanged: the window has no aspect-ratio
lock and no custom `NSWindowDelegate`; instead `ImageCanvasView` fits/
scales the image *inside* whatever the window's current size happens t
