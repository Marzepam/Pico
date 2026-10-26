import Foundation
import UniformTypeIdentifiers

/// Central place for "which files count as an image". Rather than
/// hand-listing extensions (heic/heif/jpg/jpeg/png/gif/tiff/tif/bmp/webp/
/// ico/…), every check here goes through `UTType.conforms(to: .image)` —
/// the same umbrella every bitmap format ImageIO/the system knows how to
/// decode already belongs to, so a format the system gains in a future
/// macOS release is picked up automatically, with no code change here.
enum SupportedImageTypes {

    /// `true` for any file ImageIO can plausibly open as a bitmap image.
    static func isSupportedImage(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else { return false }
        return type.conforms(to: .image)
    }

    /// Open-panel content type: "any image", not a hand-picked subset — see
    /// the type-level doc comment above.
    static let openContentTypes: [UTType] = [.image]

    /// Formats Pico can *write* via `ImageExporter` ("Zapisz jako…"). This
    /// is narrower than the readable set on purpose: ImageIO's
    /// `CGImageDestination` only has encoders for some of what it can
    /// decode — notably it can read WebP (macOS 11+) and ICO but has no
    /// encoder for either, so those stay view-only and never appear as a
    /// save destination.
    enum WritableFormat: String, CaseIterable, Identifiable {
        case jpeg, png, tiff, heic, bmp, gif

        var id: String { rawValue }

        var utType: UTType {
            switch self {
            case .jpeg: return .jpeg
            case .png: return .png
            case .tiff: return .tiff
            case .heic: return .heic
            case .bmp: return .bmp
            case .gif: return .gif
            }
        }

        var fileExtension: String {
            switch self {
            case .jpeg: return "jpg"
            case .png: return "png"
            case .tiff: return "tiff"
            case .heic: return "heic"
            case .bmp: return "bmp"
            case .gif: return "gif"
            }
        }

        var displayName: String {
            switch self {
            case .jpeg: return "JPEG"
            case .png: return "PNG"
            case .tiff: return "TIFF"
            case .heic: return "HEIC"
            case .bmp: return "BMP"
            case .gif: return "GIF"
            }
        }

        /// Whether this format's encoder takes a lossy-quality setting —
        /// drives whether `SaveOptionsView` shows the quality slider.
        var supportsQuality: Bool {
            self == .jpeg || self == .heic
        }

        /// Whether this format's encoder has a meaningful compression
        /// choice of its own (distinct from a quality percentage) — only
        /// TIFF does, via `kCGImagePropertyTIFFCompression`.
        var supportsCompressionChoice: Bool {
            self == .tiff
        }

        /// The best starting format for "Zapisz jako…" when the currently
        /// displayed image's own format is one Pico can write — falls back
        /// to `.png` (lossless, universally supported) for a format Pico
        /// can only read (WebP, ICO, …).
        static func matching(_ type: UTType?) -> WritableFormat {
            guard let type else { return .png }
            return allCases.first { $0.utType == type } ?? .png
        }
    }

    /// Lists the direct (non-recursive) image children of a folder —
    /// subfolders and non-image files are skipped. Sorting is applied by
    /// the caller via `ImageSortOption`, not here.
    static func imagesInFolder(_ folderURL: URL) -> [BrowsableImage] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .creationDateKey, .fileSizeKey, .contentTypeKey, .isDirectoryKey]
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: folderURL, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
        ) else { return [] }

        return entries.compactMap { url in
            guard isSupportedImage(url) else { return nil }
            return BrowsableImage(url: url)
        }
    }
}
