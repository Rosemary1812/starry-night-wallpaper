import AppKit
import CoreText

enum AppTypography {
    private static let registerFonts: Void = {
        for name in ["SourceSerif4Variable-Roman"] {
            guard let url = Bundle.main.resourceURL?.appendingPathComponent("Fonts/\(name).otf") else { continue }
            var error: Unmanaged<CFError>?
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                NSLog("StarryNight font registration: %@", String(describing: error?.takeRetainedValue()))
            }
        }
    }()

    private static func serif(_ name: String, size: CGFloat) -> NSFont {
        _ = registerFonts
        if let font = NSFont(name: name, size: size) { return font }
        if let descriptor = NSFont.systemFont(ofSize: size).fontDescriptor.withDesign(.serif),
           let font = NSFont(descriptor: descriptor, size: size) { return font }
        return .systemFont(ofSize: size)
    }

    private static func sourceSerif(size: CGFloat, weight: CGFloat) -> NSFont {
        let base = serif("SourceSerif4Variable-Roman", size: size)
        let descriptor = base.fontDescriptor.addingAttributes([
            .variation: [NSNumber(value: 0x77676874): weight, NSNumber(value: 0x6f70737a): size]
        ])
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    static var brand: NSFont { sourceSerif(size: 20, weight: 500) }

    static var artworkTitle: NSFont {
        switch L10n.resolvedLanguage {
        case "zh-Hans": return serif("STSongti-SC-Regular", size: 23)
        case "zh-Hant": return serif("STSongti-TC-Regular", size: 23)
        default: return sourceSerif(size: 24, weight: 400)
        }
    }
}
