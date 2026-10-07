import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: swift scripts/make-preview-gif.swift INPUT.mp4 OUTPUT.gif\n", stderr)
    exit(2)
}

let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
let asset = AVURLAsset(url: inputURL)
let generator = AVAssetImageGenerator(asset: asset)
generator.appliesPreferredTrackTransform = true
generator.maximumSize = CGSize(width: 720, height: 720)
generator.requestedTimeToleranceBefore = .zero
generator.requestedTimeToleranceAfter = .zero
let frameCount = 96
let duration = CMTimeGetSeconds(asset.duration)
guard duration.isFinite, duration > 0 else {
    fputs("Input video has no finite duration\n", stderr)
    exit(1)
}
let frameDuration = duration / Double(frameCount)

guard let destination = CGImageDestinationCreateWithURL(
    outputURL as CFURL,
    UTType.gif.identifier as CFString,
    frameCount,
    nil
) else {
    fputs("Cannot create \(outputURL.path)\n", stderr)
    exit(1)
}

let frameProperties = [kCGImagePropertyGIFDictionary: [
    kCGImagePropertyGIFDelayTime: frameDuration,
]] as CFDictionary
let fileProperties = [kCGImagePropertyGIFDictionary: [
    kCGImagePropertyGIFLoopCount: 0,
]] as CFDictionary

CGImageDestinationSetProperties(destination, fileProperties)

for frame in 0..<frameCount {
    let time = CMTime(seconds: Double(frame) * frameDuration, preferredTimescale: 600)
    let image = try generator.copyCGImage(at: time, actualTime: nil)
    CGImageDestinationAddImage(destination, image, frameProperties)
}

guard CGImageDestinationFinalize(destination) else {
    fputs("Cannot finalize \(outputURL.path)\n", stderr)
    exit(1)
}
