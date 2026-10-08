import Foundation
import CoreGraphics

enum Artwork: Int, CaseIterable {
    case starryNight, waterLilies, wheatStacks, rhone, cypresses

    // The Met reproduction includes the unpainted canvas edge and a black surround.
    var imageBounds: CGRect {
        self == .cypresses ? CGRect(x: 0.033, y: 0.04, width: 0.934, height: 0.92)
            : CGRect(x: 0, y: 0, width: 1, height: 1)
    }

    var filename: String {
        ["starrynight", "water-lilies", "wheat-stacks", "rhone", "cypresses"][rawValue]
    }
    var title: String { name }
    var shortName: String { name }
    var artist: String { L10n.tr("artwork.\(filename).artist") }
    var year: String { ["1889", "1906", "1890–1891", "1888", "1889"][rawValue] }
    var shortcutKey: String { String(rawValue + 1) }
    var shortcutUsesOption: Bool { false }
    var shortcutLabel: String { "⌘\(shortcutKey)" }
    var name: String { L10n.tr("artwork.\(filename).name") }
    var metadata: String { "\(artist) · \(year)" }
    var description: String { L10n.tr("artwork.\(filename).description") }
}
