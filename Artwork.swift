import Foundation
import CoreGraphics

enum Artwork: Int, CaseIterable {
    // Append new cases to preserve persisted artwork IDs and existing shortcuts.
    case starryNight, waterLilies, wheatStacks, rhone, cypresses, impressionSunrise
    case waterlooBridge, nocturneBognor, approachVenice, cliffWalk, bridgeVilleneuve, parliamentSunset

    // The Met reproduction includes the unpainted canvas edge and a black surround.
    var imageBounds: CGRect {
        switch self {
        case .cypresses: return CGRect(x: 0.033, y: 0.04, width: 0.934, height: 0.92)
        case .bridgeVilleneuve: return CGRect(x: 0.0475, y: 0.04, width: 0.9241666667, height: 0.9244444444)
        default: return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
    }

    var filename: String {
        ["starrynight", "water-lilies", "wheat-stacks", "rhone", "cypresses", "impression-sunrise",
         "waterloo-bridge", "nocturne-bognor", "approach-venice", "cliff-walk", "bridge-villeneuve", "parliament-sunset"][rawValue]
    }
    var title: String { name }
    var shortName: String { name }
    var artist: String { L10n.tr("artwork.\(filename).artist") }
    var year: String {
        ["1889", "1906", "1890–1891", "1888", "1889", "1872", "1903", "1871–1876",
         "1844", "1882", "1872", "1903"][rawValue]
    }
    var shortcutKey: String { rawValue < 9 ? String(rawValue + 1) : rawValue == 9 ? "0" : String(rawValue - 9) }
    var shortcutUsesOption: Bool { rawValue >= 10 }
    var shortcutLabel: String { "\(shortcutUsesOption ? "⌥" : "")⌘\(shortcutKey)" }
    var name: String { L10n.tr("artwork.\(filename).name") }
    var metadata: String { "\(artist) · \(year)" }
    var description: String { L10n.tr("artwork.\(filename).description") }
}
