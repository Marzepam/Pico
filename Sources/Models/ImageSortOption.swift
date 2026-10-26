import Foundation
import SwiftUI

/// How `BrowseGridView`/Previous↔Next order a folder's images. Deliberately
/// Pico's *own* sort setting rather than an attempt to read Finder's current
/// "Uporządkuj według" for the folder: that live outside any public API —
/// it's only recoverable (unreliably, and differently across macOS versions)
/// by parsing the undocumented per-folder `.DS_Store` file. A plain in-app
/// setting is fully predictable instead, at the cost of not automatically
/// matching whatever arrangement Finder happens to be showing.
enum ImageSortField: String, CaseIterable, Identifiable {
    case name
    case dateModified
    case dateCreated
    case size
    case kind

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .name: return "Nazwa"
        case .dateModified: return "Data modyfikacji"
        case .dateCreated: return "Data utworzenia"
        case .size: return "Rozmiar"
        case .kind: return "Typ"
        }
    }
}

struct ImageSortOption: Equatable {
    var field: ImageSortField = .name
    var ascending: Bool = true

    /// Comparator used to sort a `[BrowsableImage]` array. Ties always fall
    /// back to the filename (ascending) so the order is still fully
    /// deterministic when two files share a date/size/kind.
    func comparator() -> (BrowsableImage, BrowsableImage) -> Bool {
        let primary: (BrowsableImage, BrowsableImage) -> Bool
        switch field {
        case .name:
            primary = { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .dateModified:
            primary = { $0.dateModified < $1.dateModified }
        case .dateCreated:
            primary = { $0.dateCreated < $1.dateCreated }
        case .size:
            primary = { $0.fileSize < $1.fileSize }
        case .kind:
            primary = { lhs, rhs in
                let k0 = lhs.kindLabel, k1 = rhs.kindLabel
                return k0 == k1
                    ? lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                    : k0.localizedStandardCompare(k1) == .orderedAscending
            }
        }
        let ascending = self.ascending
        return { a, b in
            ascending ? primary(a, b) : primary(b, a)
        }
    }
}
