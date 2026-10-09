import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count >= 4 else {
    fputs("Usage: swift scripts/make-image-sequence-gif.swift OUTPUT.gif INPUT.png...\n", stderr)
    exit(2)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let options = CommandLine.arguments.dropFirst(2)
let fps = options.first(where: { $0.hasPrefix("--fps=") }).flatMap { Double($0.dropFirst(6)) }
let maxPixels = options.first(where: { $0.hasPrefix("--max-pixels=") }).flatMap { Int($0.dropFirst(13)) }
let inputURLs = options.filter { !$0.hasPrefix("--") }.map { URL(fileURLWithPath: $0) }
guard let destination = CGImageDestinationCreateWithURL(
    outputURL as CFURL,
    UTType.gif.identifier as CFString,
    inputURLs.count,
    nil
) else {
    fputs("Cannot create \(outputURL.path)\n", stderr)
    exit(1)
}

let fileProperties = [kCGImagePropertyGIFDictionary: [
    kCGImagePropertyGIFLoopCount: 0,
]] as CFDictionary
CGImageDestinationSetProperties(destination, fileProperties)

for (index, url) in inputURLs.enumerated() {
    let delay = fps.map { rate in
        (round(Double(index + 1) * 100 / max(1, rate)) - round(Double(index) * 100 / max(1, rate))) / 100
    } ?? 0.75
    let frameProperties = [kCGImagePropertyGIFDictionary: [
        kCGImagePropertyGIFDelayTime: delay,
        kCGImagePropertyGIFUnclampedDelayTime: delay,
    ]] as CFDictionary
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = maxPixels.map({ maximum in
              CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: maximum
              ] as CFDictionary)
          }) ?? CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        fputs("Cannot read \(url.path)\n", stderr)
        exit(1)
    }
    CGImageDestinationAddImage(destination, image, frameProperties)
}

guard CGImageDestinationFinalize(destination) else {
    fputs("Cannot finalize \(outputURL.path)\n", stderr)
    exit(1)
}
