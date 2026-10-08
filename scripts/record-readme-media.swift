import Foundation

@main
struct RecordReadmeMedia {
    static func main() throws {
        let resources = URL(fileURLWithPath: CommandLine.arguments[1])
        let output = URL(fileURLWithPath: CommandLine.arguments[2])
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let fps = 4, count = 24 * fps
        var catalog = [[String: Any]]()
        for artwork in Artwork.allCases {
            let engine = try Engine(resources: resources, artwork: artwork)
            let width = artwork == .starryNight ? 480 : 400
            let height = width * 5 / 8
            let first = try engine.pixels(time: 0, width: width, height: height)
            guard first == (try engine.pixels(time: 24, width: width, height: height)) else {
                throw failure("Loop endpoint mismatch: \(artwork.filename)")
            }
            let path = output.appendingPathComponent("\(artwork.filename).bgra")
            try Data().write(to: path)
            let file = try FileHandle(forWritingTo: path)
            do {
                for frame in 0..<count {
                    let pixels = try engine.pixels(time: Float(frame) / Float(fps), width: width, height: height)
                    try file.write(contentsOf: pixels)
                }
                try file.close()
            } catch {
                try? file.close()
                throw error
            }
            catalog.append(["filename": artwork.filename, "width": width, "height": height])
            print("Recorded \(artwork.filename): \(count) native Metal frames; exact 24-second loop")
        }
        let metadata: [String: Any] = ["fps": fps, "frames": count, "duration": 24,
            "strength": 1.4, "speed": 1, "artworks": catalog]
        try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
            .write(to: output.appendingPathComponent("capture.json"))
    }
}
