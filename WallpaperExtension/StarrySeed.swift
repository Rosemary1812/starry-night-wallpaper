import Foundation

// Seed only our extension's private container. Never replace a user's applied render.
func seedStarryNight() {
    let fm = FileManager.default
    let docs = fm.homeDirectoryForCurrentUser.appendingPathComponent("Documents")
    let id = "6C4C93AC-2C50-450A-BFE7-FD7346B1B4EF"
    let dir = docs.appendingPathComponent("videos/\(id)")
    let video = dir.appendingPathComponent("starry-night.mp4")
    guard !fm.fileExists(atPath:video.path),
          let bundled = Bundle.main.url(forResource:"wallpaper",withExtension:"mp4") else { return }
    do {
        try fm.createDirectory(at:dir,withIntermediateDirectories:true)
        try fm.copyItem(at:bundled,to:video)
        let entry = VideoEntry(id:id,name:"StarryNight",filename:video.lastPathComponent,
            duration:24,fps:30,resolution:CGSize(width:2560,height:1600),dateAdded:Date())
        try JSONEncoder().encode(entry).write(to:dir.appendingPathComponent("metadata.json"),options:.atomic)
        let prefs: [String:Bool] = ["userPaused":false,"alwaysPauseDesktop":false,
            "pauseWhenOccluded":false,"desktopOccluded":false,"screenSaverIsOurs":true]
        let prefURL = docs.appendingPathComponent("phosphene-prefs.json")
        if !fm.fileExists(atPath:prefURL.path) {
            try JSONSerialization.data(withJSONObject:prefs).write(to:prefURL,options:.atomic)
        }
    } catch { extensionLog("Starry Night seed failed: \(error)") }
}
