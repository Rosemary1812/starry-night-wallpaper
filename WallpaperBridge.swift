import AppKit

enum WallpaperBridge {
    static let identifier = "local.starrynight.flow.extension"
    static let videoID = "6C4C93AC-2C50-450A-BFE7-FD7346B1B4EF"
    static var documents: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/\(identifier)/Data/Documents")
    }
    static var renders: URL { documents.appendingPathComponent("videos/\(videoID)") }
    static var isSelected: Bool {
        let store = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist")
        guard let data = try? Data(contentsOf:store),
              let plist = try? PropertyListSerialization.propertyList(from:data,format:nil) as? [String:Any]
        else { return false }
        func containsProvider(_ value: Any) -> Bool {
            if let dict = value as? [String:Any] {
                if dict["Provider"] as? String == identifier { return true }
                return dict.values.contains(where:containsProvider)
            }
            if let values = value as? [Any] { return values.contains(where:containsProvider) }
            return false
        }
        // SystemDefault is only a fallback, not proof that a visible Space uses us.
        return ["AllSpacesAndDisplays","Displays","Spaces"].contains { key in
            plist[key].map(containsProvider) ?? false
        }
    }
    static func prepareRender() throws -> URL {
        guard FileManager.default.fileExists(atPath:documents.path) else {
            throw failure(L10n.tr("error.extensionFirstRun"))
        }
        try FileManager.default.createDirectory(at:renders,withIntermediateDirectories:true)
        return renders.appendingPathComponent("render-\(UUID().uuidString).mp4")
    }
    static func publish(_ video: URL, speed: Float, width: Int, height: Int, name: String) throws {
        struct Entry: Encodable {
            let id: String; let name: String; let filename: String
            let duration: Double; let fps: Double; let resolution: CGSize; let dateAdded: Date
        }
        let entry = Entry(id:videoID,name:name,filename:video.lastPathComponent,
            duration:24/Double(speed),fps:30,resolution:CGSize(width:width,height:height),dateAdded:Date())
        try JSONEncoder().encode(entry).write(to:renders.appendingPathComponent("metadata.json"),options:.atomic)
        let thumbnail = renders.appendingPathComponent("thumbnail.jpg")
        if FileManager.default.fileExists(atPath:thumbnail.path) { try FileManager.default.removeItem(at:thumbnail) }
        notify("libraryChanged")
    }
    static func setPaused(_ paused: Bool) throws {
        let prefs: [String:Bool] = ["userPaused":paused,"alwaysPauseDesktop":false,
            "pauseWhenOccluded":false,"desktopOccluded":false,"screenSaverIsOurs":true]
        try JSONSerialization.data(withJSONObject:prefs).write(
            to:documents.appendingPathComponent("phosphene-prefs.json"),options:.atomic)
        notify("prefsChanged")
    }
    static var isPaused: Bool {
        guard let data = try? Data(contentsOf:documents.appendingPathComponent("phosphene-prefs.json")),
              let prefs = try? JSONSerialization.jsonObject(with:data) as? [String:Any] else { return false }
        return prefs["userPaused"] as? Bool ?? false
    }
    static func notify(_ event: String) {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName("local.starrynight.flow.\(event)" as CFString),nil,nil,true)
    }
    static func openSettings() {
        NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.Wallpaper-Settings.extension")!)
    }
}
