import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Pure ImageIO helpers for reading an upright, correctly-oriented
/// `CGImage` from disk and writing one back out in a chosen format — no
/// dependency on SwiftUI/AppKit, used identically by the viewer canvas, the
/// browse grid's thumbnails, and "Zapisz jako…".
enum ImageExporter {

    enum ExportError: LocalizedError {
        case sourceCreationFailed
        case decodeFailed
        case destinationCreationFailed
        case writeFailed

        var errorDescription: String? {
            switch self {
            case .sourceCreationFailed:
                return String(localized: "Nie udało się otworzyć pliku jako obrazu.", comment: "Error when ImageIO can't even create a source for a file")
            case .decodeFailed:
                return String(localized: "Nie udało się zdekodować obrazu.", comment: "Error when ImageIO can't decode the pixel data")
            case .destinationCreationFailed:
                return String(localized: "Nie udało się utworzyć pliku docelowego dla wybranego formatu.", comment: "Error when CGImageDestination can't be created for the chosen format")
            case .writeFailed:
                return String(localized: "Zapis obrazu się nie powiódł.", comment: "Error when finalizing the image write fails")
            }
        }
    }

    // MARK: Reading

    /// Decodes `url`'s image at full resolution and bakes its EXIF/TIFF
    /// orientation tag into the pixel data, so the result is always
    /// "upright" — the same orientation every other app would display it
    /// in — regardless of how the source camera/scanner tagged it.
    /// `CGImageSourceCreateImageAtIndex` on its own does *not* apply this
    /// tag; left uncorrected, a portrait photo shot with the phone rotated
    /// would come out sideways both on screen and in any exported copy.
    static func loadUprightImage(url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw ExportError.sourceCreationFailed
        }
        guard let raw = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ExportError.decodeFailed
        }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let rawOrientation = (properties?[kCGImagePropertyOrientation] as? UInt32) ?? CGImagePropertyOrientation.up.rawValue
        guard let orientation = CGImagePropertyOrientation(rawValue: rawOrientation), orientation != .up else {
            return raw
        }
        return applying(orientation, to: raw) ?? raw
    }

    /// The 8 EXIF/TIFF orientation tags, each as the `CGAffineTransform`
    /// that maps the raw (as-decoded) pixel rect onto an upright one, plus
    /// that upright rect's size (width/height swap for the 4 tags that
    /// involve a 90°/270° rotation).
    private static func uprightTransform(for orientation: CGImagePropertyOrientation, width: CGFloat, height: CGFloat) -> (transform: CGAffineTransform, size: CGSize) {
        switch orientation {
        case .up:
            return (.identity, CGSize(width: width, height: height))
        case .upMirrored:
            return (CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: width, ty: 0), CGSize(width: width, height: height))
        case .down:
            return (CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: width, ty: height), CGSize(width: width, height: height))
        case .downMirrored:
            return (CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: height), CGSize(width: width, height: height))
        case .left:
            return (CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: height, ty: 0), CGSize(width: height, height: width))
        case .leftMirrored:
            return (CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: 0, ty: 0), CGSize(width: height, height: width))
        case .right:
            return (CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: width), CGSize(width: height, height: width))
        case .rightMirrored:
            return (CGAffineTransform(a: 0, b: -1, c: -1, d: 0, tx: height, ty: width), CGSize(width: height, height: width))
        @unknown default:
            return (.identity, CGSize(width: width, height: height))
        }
    }

    /// Draws `image` into a fresh bitmap context through the orientation's
    /// transform, producing an upright copy. Returns `nil` (caller falls
    /// back to the raw, un-rotated image rather than crashing) on the rare
    /// pixel format `CGContext` itself refuses to back a context with —
    /// seen in practice for some CMYK/indexed source files.
    private static func applying(_ orientation: CGImagePropertyOrientation, to image: CGImage) -> CGImage? {
        let (transform, size) = uprightTransform(for: orientation, width: CGFloat(image.width), height: CGFloat(image.height))
        guard let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: image.bitsPerComponent,
            bytesPerRow: 0,
            space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: image.bitmapInfo.rawValue
        ) else { return nil }

        context.concatenate(transform)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }

    // MARK: Writing — "Zapisz jako…"

    struct SaveOptions {
        var format: SupportedImageTypes.WritableFormat
        /// 0...1 — only consulted when `format.supportsQuality`.
        var quality: Double = 0.9
        /// Only consulted when `format.supportsCompressionChoice` (TIFF):
        /// `true` writes LZW (lossless, typically ~2:1 on photos), `false`
        /// writes uncompressed.
        var tiffUseLZW: Bool = true
    }

    /// Encodes `image` (expected to already be upright — see
    /// `loadUprightImage` above) to `url` in `options.format`. Always
    /// writes exactly the pixels handed in: converting to a format whose
    /// tag conventions differ from the source (e.g. opening a
    /// sideways-tagged HEIC and "Zapisz jako" JPEG) still comes out
    /// correctly oriented, because the orientation was already baked into
    /// the pixels at load time rather than carried as a tag to reinterpret.
    static func write(_ image: CGImage, to url: URL, options: SaveOptions) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, options.format.utType.identifier as CFString, 1, nil) else {
            throw ExportError.destinationCreationFailed
        }

        var properties: [CFString: Any] = [:]
        if options.format.supportsQuality {
            properties[kCGImageDestinationLossyCompressionQuality] = options.quality
        }
        if options.format.supportsCompressionChoice {
            // TIFF compression tag values per the TIFF 6.0 spec: 1 = no
            // compression, 5 = LZW (lossless).
            properties[kCGImagePropertyTIFFDictionary] = [
                kCGImagePropertyTIFFCompression: options.tiffUseLZW ? 5 : 1
            ]
        }

        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ExportError.writeFailed
        }
    }

    // MARK: Thumbnails

    /// A downsampled thumbnail for the browse grid — goes through
    /// ImageIO's own thumbnail generator (`kCGImageSourceCreateThumbnail…`)
    /// rather than `loadUprightImage` + a manual resize: ImageIO decodes
    /// directly at (close to) the target size instead of fully decoding a
    /// possibly huge original just to shrink it afterward, and
    /// `kCGImageSourceCreateThumbnailWithTransform` already bakes in the
    /// orientation tag on its own.
    static func thumbnail(url: URL, maxPixelSize: CGFloat) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
