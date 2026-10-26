import Foundation
import UniformTypeIdentifiers

/// One entry in a browsed folder's image list — a lightweight snapshot of
/// the file-system metadata `ImageSortOption` sorts by, built once when the
/// folder is opened (see `ImageViewerViewModel.loadFolder`). Not a live
/// view of the folder: adding/removing files there while Pico has it open
/// isn't picked up until the folder is browsed again.
struct BrowsableImage: Identifiable, Equatable {
    let url: URL
    let name: String
    let dateModified: Date
    let dateCreated: Date
    let fileSize: Int
    let contentType: UTType?

    var id: URL { url }

    /// Short, localized-by-the-system label for the sort-by-Kind option and
    /// the browse grid's per-cell caption — "JPEG image", "obraz PNG", etc.,
    /// exactly as Finder itself would describe the file. Falls back to the
    /// bare file extension on the rare file whose type `UTType` can't
    /// resolve a localized description for.
    var kindLabel: String {
        contentType?.localizedDescription?.capitalized
            ?? url.pathExtension.uppercased()
    }

    init?(url: URL) {
        let values = try? url.resourceValues(forKeys: [
            .contentModificationDateKey, .creationDateKey, .fileSizeKey, .contentTypeKey, .isDirectoryKey
        ])
        guard values?.isDirectory != true else { return nil }
        self.url = url
        self.name = url.lastPathComponent
        self.dateModified = values?.contentModificationDate ?? .distantPast
        self.dateCreated = values?.creationDate ?? .distantPast
        self.fileSize = values?.fileSize ?? 0
        self.contentType = values?.contentType
    }
}
