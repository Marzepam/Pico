# Pico

A minimalist, native macOS image viewer, in the style of Movi
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
scales the image *inside* whatever the window's current size happens to
be.

A separate matter is **changing the image itself** (Open/Previous/Next/
clicking a thumbnail) versus **manually resizing the window** by dragging
its edge — two separate mechanisms:

1. **Every image in windowed mode** — the first one in a given window,
   after switching folders, and every subsequent Next/Previous — uses one
   and the same rule, `ContentView.fitWindowFullHeight`: the window takes
   up the **entire available screen height** between the menu bar and the
   Dock (`screen.visibleFrame.height`) and is centered; only the
   **width** is recomputed, to the current image's aspect ratio at that
   height — so there are no side bars, unless the image is narrower than
   the toolbar's minimum width allows (see point 3 below). The change is
   **instant, with no animation** (`animate: false`) — the window should
   already be at its target size the instant the new image appears, not
   visibly catching up to it with a delay.
2. **Manually resizing the window** (dragging an edge/corner) is in no
   way corrected by Pico — the image is then in dynamic "Fit" mode
   (`isZoomFit == true`, see below), so `ImageCanvasView`'s
   `GeometryReader` itself recomputes the scale live from the new window
   size; bars here are the normal, expected result of dragging the window
   to a shape the image doesn't have — just like in Preview.app. Such a
   manual change stays in effect exactly until the next image — a Next/
   Previous transition (point 1) always re-asserts the full screen height
   again, regardless of what shape the window was previously dragged into.
3. **The window's minimum size** (`window.minSize`) now has the same
   value on both axes — `FloatingControlBar.minWindowWidth` — instead of,
   as before, a much lower minimum on height (just enough for the
   toolbar's own footprint). Without this, the window could be dragged
   into a very short, wide strip in which the image was reduced to a tiny
   icon — the same floor on both axes rules that out.
   `fitWindowFullHeight` uses this same minimum as the lower bound on
   width (for very narrow/portrait images at full screen height).

   This function does **not** force an explicit scale onto the view model
   (the way one earlier version did, `applyExplicitScale`) — it stays in
   dynamic "Fit" mode (already set earlier by `resetZoom()` for every
   newly loaded image), so `ImageCanvasView` itself recomputes the scale
   from the window's actual, current size. This is also a **bug fix**:
   one earlier version set an explicit, fixed scale after every image
   change, which left the image "frozen" at that scale, unresponsive to
   any later manual window resize, until the next image change. Leaving
   "Fit" mode on fixes this — browsing and manually dragging the window
   always cooperate with each other, regardless of order.

In full screen, the mechanism from point 1 doesn't run at all — the
window's content is then the size of the screen, so instead
`installFullScreenObservers` switches, on entering full screen, back to
dynamic "Fit" mode (`viewModel.zoomToFit()`) — only useful if the image
happened to be in explicit zoom mode (pinch/buttons) right before
entering full screen; during ordinary browsing, "Fit" mode is already on,
so this call then changes nothing. **Exiting** full screen, in turn,
re-runs `fitWindowFullHeight` — the same rule as for any other image.

### Zoom: "Fit" mode versus an explicit percentage

`isZoomFit: Bool` + `zoomScale: CGFloat` in `ImageViewerViewModel`. When
`isZoomFit == true`, `ImageCanvasView` continuously recomputes the scale
from its own current viewport size (via `GeometryReader`) — so resizing
the window automatically recomputes the fit. When someone explicitly
zooms in/out (buttons, ⌘+/⌘−, pinch, double-click), the mode switches to
an explicit percentage, independent of the window size — as requested. A
small separate view, `FitScaleTracker`, publishes the currently computed
"fit" scale back to the view model purely so the percentage label in the
toolbar (a sibling view, not a child of the canvas) can show it correctly
in "Fit" mode too.

**Scale animation — only where it's a discrete, deliberate change.**
`ImageCanvasView` used to have a blanket
`.animation(.easeOut(duration: 0.15), value: baseScale)` modifier on the
image, animating *every* change to the displayed scale — including the
continuous, already-live-computed recalculation of "Fit" mode while the
window is being resized. Most visible in full-screen mode: the system's
own enter/exit full-screen animation already resizes the window smoothly,
frame by frame, and a separate, independently-synced 0.15s animation
layered on top of that looked "jittery"/off. The modifier was removed
from `ImageCanvasView` entirely; the animation moved to the specific
places in `ImageViewerViewModel` that actually decide on a scale change —
`zoomIn()`, `zoomOut()`, `toggleActualSize()` — wrapped in
`withAnimation(.easeOut(duration: 0.15))`. Scale changes that are already
synced to something else that's itself smooth/instant are left without
animation — `zoomToFit()` and "Fit" mode in general (both while manually
dragging the window and while the image changes —
`fitWindowFullHeight` deliberately leaves this mode on, see above) —
`ImageCanvasView` recomputes that scale itself, every frame, from the
window's current size, so adding animation here would just desync the
image from the window again — as well as `setZoom(_:)` (pinch — already
tracked live during the gesture).

Panning is clamped (`clampedPan`) so the image can never be dragged
entirely out of the window — an axis with no overflow (e.g. when the
image is smaller than the window in that dimension) is simply locked at
zero.

### Sorting — its own, not a mirror of Finder's

The exact "Sort by" order for a given folder in Finder isn't exposed
through any public API — the only way to read it would be parsing the
undocumented, binary `.DS_Store` format, which is unreliable and differs
between macOS versions (see the discussion before this was implemented).
Instead, Pico has its own, fully predictable sorting (`ImageSortOption`:
field + direction), set from the "Sort" menu in the grid view — by name,
ascending, by default. Ties (e.g. the same file size) are always broken
by name, so the order is always deterministic.

### Previous/Next after "Open" — background folder scan, no sandbox

Pico is **not sandboxed** — `Pico.entitlements` is deliberately empty.
The app isn't going to the Mac App Store, so App Sandbox isn't required,
and dropping it removes the source of an earlier limitation: under full
sandboxing, picking a **single file** via `NSOpenPanel` only grants access
to that one file, not to its siblings in the folder, so Previous/Next had
no way to work after a plain "Open". Without the sandbox, that problem
goes away.

Instead, `ImageViewerViewModel.openSingleFile(url:)` shows the opened
image right away first, and immediately after, in the background
(`scanContainingFolder(of:)`, `Task.detached` off the main actor), scans
its parent folder using plain `FileManager.contentsOfDirectory` — no
extra window or consent prompt (beyond the possible one-time system
prompt for access to a protected location like Desktop/Documents/
Downloads, identical to any other non-sandboxed Mac app). Once the scan
finishes, Pico adopts that folder as the active browsing context — which
is why Previous/Next turn on by themselves (together, see below — they no
longer dim separately at the ends of the list), with no switch to the
grid view and no separate "Browse" step. If the image changes again in
the meantime (a quick second "Open", or Next/Previous, before a large
folder finishes scanning), the result of the stale scan is simply
discarded.

If "Open" points at a file that already belongs to the folder currently
being browsed (e.g. re-opening, via Finder's "Open With…", a file from
the same folder, or clicking a thumbnail), Pico recognizes this from the
`folderImages` list itself and doesn't rescan anything — Previous/Next
are active immediately.

### Previous/Next loop around instead of dimming at the ends of the list

`canGoPrevious`/`canGoNext` in `ImageViewerViewModel` only check whether
the active folder has more than one image (`folderImages.count > 1`) —
they no longer check whether the current index happens to be the
first/last one. So both icons are always either enabled together or
dimmed together, never separately. The transition itself computes the
new index modulo the image count (`(idx + 1) % folderImages.count`, and
likewise backward), so Next on the last image jumps to the first, and
Previous on the first jumps to the last, instead of stopping at either
end.

### Save As — options only where they make sense

`SaveOptionsAccessoryView` is a custom `NSSavePanel` accessory view,
written in plain AppKit (`NSStackView` + `NSPopUpButton`/`NSSlider` driven
by target/action) — **not** a SwiftUI view embedded via `NSHostingView`.
The first version did it that way, but it turned out that a SwiftUI
`Picker` embedded in a panel's `accessoryView` is an unreliable
combination: even with an explicit frame and `sizingOptions` set on
`NSHostingView`, the format dropdown would sometimes be unclickable until
something else forced a layout pass (visible as "the format list suddenly
appears after clicking Save"). A plain `NSPopUpButton` doesn't go through
that bridge at all and is clickable right away. Choosing a format live
updates `panel.allowedContentTypes` and the file name's extension through
a closure, `onChange: (() -> Void)?`, called from each control's action.
The quality slider only shows for JPEG/HEIC (`supportsQuality`), the
LZW/none compression choice only for TIFF (`supportsCompressionChoice`);
PNG/BMP/GIF show nothing extra, since there's nothing to configure there
— `NSStackView.isHidden` on the relevant row group hides/shows them
without changing the panel's width. The default file name is always
`<original>_pico.<extension>` (the same pattern as `_movi` in Movi; if
`<original>` already ends in `_pico` — because the file being saved was
already a Pico export — that suffix is stripped first, so it doesn't end
up as `_pico_pico`) — it never silently overwrites the original.

The save formats are deliberately narrower than the read formats: ImageIO
can **read** WebP and ICO, but has no encoder for them, so those two
formats are view-only — they'll never show up as a "Save As…" target.

### App icon

Supplied by the author (the file `icon-source/pico-icon-1024.png`) — a
glossy, white sphere with a rainbow, watercolor "eye" in the middle, set
on a white, rounded card with a soft shadow underneath, cropped edge to
edge (the card fills the entire square, with no margin around it). Used
**as a whole, as a full 1024×1024 square** (without cutting out the
sphere itself or adding its own transparency) — macOS applies its own
"squircle" mask at display time, per Apple's guidelines, so the card's
white background stays invisible anyway in most of the places the icon
appears. Scaled (Lanczos) down to all 10 sizes `AppIcon.appiconset`
requires.

### Toolbar — one shared spacing grid

All of `FloatingControlBar`'s icons (Open, Browse, Previous, Zoom Out,
Fit to window, Zoom In, Next, Full screen, Save As) sit in a single
`HStack` with one, uniform gap between every pair — no mixing a
fixed-width edge slot with flexible `Spacer`s, which previously produced
uneven gaps (a large gap before the group, tight gaps inside it). The
bar's own width (`barWidth`) is computed directly from the icon count,
their size, and the spacing, so it can no longer drift out of sync with
the actual content. The "Fit to window" icon's symbol changed to
`viewfinder`, to free up the
`arrow.up.left.and.arrow.down.right`/`arrow.down.right.and.arrow.up.left`
pair for the new full-screen button.

## Known limitations

- Animated GIFs only show their first frame — no animation playback.
- The grid's thumbnail preview doesn't auto-refresh if the folder's
  contents change on disk while the window is already open (click
  "Browse"/"Change folder…" again).
- Save formats are limited to those ImageIO has an encoder for
  (JPEG/PNG/TIFF/HEIC/BMP/GIF) — WebP and ICO are read-only.
- Finder's "Open With…" sometimes needs a LaunchServices refresh after the
  app is first built (e.g. relaunching Finder, or logging out/in) — see
  the comment next to `CFBundleDocumentTypes` in `Info.plist`.

## License

Code is free to use and modify in any way — no additional restrictions.
