import AppKit
import MetalKit
import AVFoundation
import CoreImage
import UniformTypeIdentifiers
import ImageIO

func failure(_ message: String) -> NSError {
    NSError(domain: "StarryNight", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
}

struct Parameters {
    var time: Float
    var strength: Float
    var aspect: Float
    var showMask: Float
    var artwork: Float
    var imageAspect: Float
}

final class Engine {
    let device: MTLDevice
    let queue: MTLCommandQueue
    let pipeline: MTLRenderPipelineState
    var painting: MTLTexture
    var mask: MTLTexture
    var artwork: Artwork
    let resources: URL

    init(resources: URL, artwork: Artwork = .starryNight) throws {
        self.resources = resources
        self.artwork = artwork
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw failure(L10n.tr("error.noMetal"))
        }
        self.device = device
        self.queue = queue
        let source = try String(contentsOf: resources.appendingPathComponent("Sky.metal"), encoding: .utf8)
        let library = try device.makeLibrary(source: source, options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "vertexMain")
        descriptor.fragmentFunction = library.makeFunction(name: "fragmentMain")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        let loader = MTKTextureLoader(device: device)
        painting = try Self.loadPainting(resources: resources, artwork: artwork, loader: loader)
        mask = try loader.newTexture(cgImage: Self.makeMask(artwork: artwork), options: [.SRGB: false])
    }

    func select(_ artwork: Artwork) throws {
        let loader = MTKTextureLoader(device: device)
        let image = try Self.loadPainting(resources: resources, artwork: artwork, loader: loader)
        let region = try loader.newTexture(cgImage: Self.makeMask(artwork: artwork), options: [.SRGB: false])
        painting = image
        mask = region
        self.artwork = artwork
    }

    static func crop(_ image: CGImage, artwork: Artwork) throws -> CGImage {
        let bounds = artwork.imageBounds
        let rect = CGRect(x: bounds.minX * Double(image.width), y: bounds.minY * Double(image.height),
            width: bounds.width * Double(image.width), height: bounds.height * Double(image.height))
        guard let cropped = image.cropping(to: rect) else { throw failure(L10n.tr("error.crop")) }
        return cropped
    }

    static func loadPainting(resources: URL, artwork: Artwork, loader: MTKTextureLoader) throws -> MTLTexture {
        let url = resources.appendingPathComponent("\(artwork.filename).jpg")
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw failure(L10n.tr("error.painting", artwork.title))
        }
        return try loader.newTexture(cgImage: crop(image, artwork: artwork),
            options: [.SRGB: false, .origin: MTKTextureLoader.Origin.topLeft])
    }

    static func makeMask(artwork: Artwork = .starryNight) throws -> CGImage {
        let width = 2048, height = 1622
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width*4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw failure(L10n.tr("error.maskCreate")) }
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: CGFloat(width), y: -CGFloat(height))
        func protect(_ points: [(Double, Double)]) {
            ctx.beginPath()
            ctx.move(to: CGPoint(x: points[0].0, y: points[0].1))
            for p in points.dropFirst() { ctx.addLine(to: CGPoint(x: p.0, y: p.1)) }
            ctx.closePath()
            ctx.setFillColor(CGColor(gray: 0, alpha: 1))
            ctx.fillPath()
        }
        // Conservative contours keep the entire foreground, including small branches,
        // unchanged. The inward feather leaves a narrow quiet margin on the sky side.
        if artwork == .starryNight {
        protect([(0,0.725),(0.045,0.731),(0.09,0.753),(0.15,0.753),(0.21,0.735),(0.29,0.700),
            (0.37,0.710),(0.41,0.687),(0.44,0.691),(0.47,0.715),(0.50,0.722),(0.54,0.713),(0.565,0.694),(0.592,0.658),
            (0.623,0.643),(0.651,0.627),(0.683,0.624),(0.713,0.633),(0.742,0.653),
            (0.770,0.650),(0.793,0.623),(0.813,0.605),(0.836,0.581),(0.854,0.557),
            (0.875,0.548),(0.896,0.523),(0.913,0.532),(0.921,0.509),(0.944,0.497),
            (0.971,0.501),(1,0.516),(1,1),(0,1)])
        protect([(0.182,0.077),(0.194,0.060),(0.204,0.073),(0.207,0.10),(0.207,0.149),
            (0.211,0.185),(0.211,0.214),(0.217,0.253),(0.223,0.293),(0.226,0.326),
            (0.232,0.348),(0.237,0.352),(0.239,0.398),(0.247,0.451),(0.253,0.498),
            (0.260,0.538),(0.269,0.563),(0.272,0.624),(0.288,0.693),(0.297,0.724),
            (0.319,0.740),(0.326,0.714),(0.336,0.704),(0.348,0.710),(0.354,0.745),
            (0.362,0.768),(0.376,0.784),(0.397,0.781),(0.418,0.791),(0.421,0.806),
            (0.392,0.822),(0.411,0.862),(0.433,0.890),(0.443,1),(0.105,1),
            (0.111,0.936),(0.121,0.886),(0.127,0.817),(0.134,0.75),(0.138,0.669),
            (0.139,0.596),(0.147,0.536),(0.151,0.492),(0.159,0.461),(0.159,0.415),
            (0.166,0.371),(0.168,0.324),(0.172,0.284),(0.177,0.267),(0.181,0.221),
            (0.178,0.184),(0.179,0.134),(0.181,0.10)])
        // Narrow independent tips to the left and right of the main cypress.
        protect([(0.141,0.540),(0.142,0.456),(0.148,0.429),(0.151,0.450),(0.156,0.474),(0.165,0.52),(0.18,0.7),(0.135,0.7)])
        protect([(0.267,0.7),(0.273,0.608),(0.282,0.574),(0.291,0.585),(0.302,0.621),(0.309,0.70),(0.327,0.75)])
        protect([(0.249,0.579),(0.289,0.558),(0.294,0.570),(0.261,0.610)])
        protect([(0.556,0.621),(0.567,0.621),(0.568,0.668),(0.578,0.783),(0.546,0.790),(0.552,0.708)])
        } else if artwork == .waterLilies {
            // Lily clusters are protected in image coordinates, leaving reflections free.
            for (x,y,rx,ry) in [(0.10,0.07,0.17,0.07),(0.54,0.085,0.23,0.07),
                (0.90,0.025,0.22,0.055),(0.74,0.26,0.28,0.07),
                (0.81,0.41,0.25,0.08),(0.94,0.56,0.17,0.075),
                (0.08,0.73,0.15,0.18),(0.28,0.78,0.16,0.085),
                (0.60,0.78,0.23,0.085),(0.35,0.89,0.17,0.05),
                (0.11,0.96,0.10,0.05)] {
                ctx.setFillColor(CGColor(gray: 0, alpha: 1))
                ctx.fillEllipse(in: CGRect(x:x-rx,y:y-ry,width:rx*2,height:ry*2))
            }
        } else if artwork == .wheatStacks {
            protect([(0,0.24),(1,0.24),(1,1),(0,1)])
        } else if artwork == .rhone {
            protect([(0,0),(1,0),(1,0.49),(0.55,0.47),(0.30,0.51),(0,0.60)])
            protect([(0,0.67),(0.35,0.76),(0.54,0.75),(0.70,0.78),(1,0.84),(1,1),(0,1)])
            protect([(0.43,0.76),(0.48,0.51),(0.52,0.69),(0.55,0.72),(0.55,0.79)])
        } else if artwork == .cypresses {
            protect([(0,0.67),(0.12,0.61),(0.22,0.51),(0.30,0.56),
                (0.45,0.55),(0.52,0.48),(0.65,0.49),(0.75,0.58),(1,0.53),
                (1,0.72),(0,0.72)])
            protect([(0.73,0.66),(0.74,0.37),(0.79,0.30),(0.81,0.13),
                (0.835,0.07),(0.86,0.14),(0.89,0.47),(0.91,0.66)])
        }
        guard let raw = ctx.makeImage() else { throw failure(L10n.tr("error.maskCreate")) }
        let expanded = CIImage(cgImage: raw).clampedToExtent()
            .applyingFilter("CIMorphologyMinimum", parameters: [kCIInputRadiusKey: 8])
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 4])
        guard let result = CIContext().createCGImage(expanded, from: CGRect(x:0,y:0,width:width,height:height)) else {
            throw failure(L10n.tr("error.maskSmooth"))
        }
        return try crop(result, artwork: artwork)
    }

    @discardableResult
    func render(to texture: MTLTexture, time: Float, strength: Float, maskMode: Bool = false,
                present drawable: CAMetalDrawable? = nil,
                completion: MTLCommandBufferHandler? = nil) throws -> MTLCommandBuffer {
        guard let command = queue.makeCommandBuffer() else { throw failure(L10n.tr("error.commandBuffer")) }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { throw failure(L10n.tr("error.renderEncoder")) }
        var parameters = Parameters(time:time, strength:strength,
            aspect:Float(texture.width)/Float(texture.height), showMask:maskMode ? 1 : 0,
            artwork: Float(artwork.rawValue), imageAspect: Float(painting.width)/Float(painting.height))
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(painting, index: 0)
        encoder.setFragmentTexture(mask, index: 1)
        encoder.setFragmentBytes(&parameters, length: MemoryLayout<Parameters>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        if let drawable { command.present(drawable) }
        if let completion { command.addCompletedHandler(completion) }
        command.commit()
        return command
    }

    func pixels(time: Float, strength: Float = 1.4, maskMode: Bool = false, width: Int = 1280, height: Int = 1014) throws -> Data {
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
            width: width, height: height, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: desc) else { throw failure(L10n.tr("error.texture")) }
        let command = try render(to: texture, time: time, strength: strength, maskMode: maskMode)
        command.waitUntilCompleted()
        if let error = command.error { throw error }
        var bytes = Data(count: width*height*4)
        bytes.withUnsafeMutableBytes {
            texture.getBytes($0.baseAddress!, bytesPerRow: width*4,
                from: MTLRegionMake2D(0,0,width,height), mipmapLevel: 0)
        }
        return bytes
    }

    func snapshot(to url: URL, time: Float, maskMode: Bool = false) throws {
        let width = 1280, height = Int((1280.0 * Double(painting.height) / Double(painting.width)).rounded())
        let bytes = try pixels(time: time, maskMode: maskMode, width: width, height: height)
        let provider = CGDataProvider(data: bytes as CFData)!
        let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width*4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
        let representation = NSBitmapImageRep(cgImage: image)
        try representation.representation(using: .png, properties: [:])!.write(to: url)
    }

    func export(to destination: URL, width: Int, height: Int, speed: Float, strength: Float,
                progress: @escaping (Double) -> Void) throws {
        // Write to a unique sibling; an existing movie is replaced only after success.
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".starry-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: temporary) }
        let writer = try AVAssetWriter(outputURL: temporary, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 22_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel],
            AVVideoColorPropertiesKey: [AVVideoColorPrimariesKey:AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey:AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey:AVVideoYCbCrMatrix_ITU_R_709_2]])
        input.expectsMediaDataInRealTime = false
        let attributes: [String:Any] = [kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String:width, kCVPixelBufferHeightKey as String:height,
            kCVPixelBufferMetalCompatibilityKey as String:true,
            kCVPixelBufferIOSurfacePropertiesKey as String:[:]]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: attributes)
        guard writer.canAdd(input) else { throw failure(L10n.tr("error.videoInput")) }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? failure(L10n.tr("error.exportStart")) }
        writer.startSession(atSourceTime: .zero)
        guard let pool = adaptor.pixelBufferPool else { writer.cancelWriting(); throw failure(L10n.tr("error.videoBufferPool")) }
        var cache: CVMetalTextureCache?
        guard CVMetalTextureCacheCreate(nil,nil,device,nil,&cache)==kCVReturnSuccess, let cache else {
            writer.cancelWriting(); throw failure(L10n.tr("error.videoRenderStart"))
        }
        let fps: Int32 = 30
        let count = Int((24 / Double(speed) * Double(fps)).rounded())
        do {
            for frame in 0..<count {
                let deadline = Date().addingTimeInterval(30)
                while !input.isReadyForMoreMediaData {
                    if writer.status != .writing { throw writer.error ?? failure(L10n.tr("error.videoEncoderStopped")) }
                    if Date()>deadline { throw failure(L10n.tr("error.videoWaitTimeout")) }
                    Thread.sleep(forTimeInterval: 0.002)
                }
                try autoreleasepool {
                    var buffer: CVPixelBuffer?
                    guard CVPixelBufferPoolCreatePixelBuffer(nil,pool,&buffer)==kCVReturnSuccess, let buffer else {
                        throw failure(L10n.tr("error.videoFrame"))
                    }
                    var cvTexture: CVMetalTexture?
                    guard CVMetalTextureCacheCreateTextureFromImage(nil,cache,buffer,nil,.bgra8Unorm,width,height,0,&cvTexture)==kCVReturnSuccess,
                        let cvTexture, let texture = CVMetalTextureGetTexture(cvTexture) else { throw failure(L10n.tr("error.videoTexture")) }
                    let command = try render(to:texture, time:Float(frame)/Float(count)*24, strength:strength)
                    command.waitUntilCompleted()
                    if let error = command.error { throw error }
                    guard adaptor.append(buffer, withPresentationTime: CMTime(value:Int64(frame),timescale:fps)) else {
                        throw writer.error ?? failure(L10n.tr("error.videoFrameWrite"))
                    }
                }
                if frame%15==0 { progress(Double(frame)/Double(count)) }
            }
            input.markAsFinished()
            writer.endSession(atSourceTime: CMTime(value:Int64(count),timescale:fps))
            let done = DispatchSemaphore(value: 0)
            writer.finishWriting { done.signal() }
            guard done.wait(timeout:.now()+60) == .success else { throw failure(L10n.tr("error.exportTimeout")) }
            guard writer.status == .completed else { throw writer.error ?? failure(L10n.tr("error.exportIncomplete")) }
            if FileManager.default.fileExists(atPath: destination.path) {
                _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
            } else { try FileManager.default.moveItem(at:temporary,to:destination) }
            progress(1)
        } catch { writer.cancelWriting(); throw error }
    }
}

final class AnimationState {
    var speed: Float = 1
    var strength: Float = 1.4
    var paused = false
    var showMask = false
    var phase: Float = 0
    var last = CACurrentMediaTime()
    func currentTime() -> Float {
        let now = CACurrentMediaTime()
        if !paused { phase += Float(min(now-last,0.1))*speed }
        last = now
        phase.formTruncatingRemainder(dividingBy: 24)
        return phase
    }
}

final class LiveView: MTKView, MTKViewDelegate {
    let engine: Engine
    let animation: AnimationState
    private var revealGeneration = 0
    private var waitingToReveal = false
    init(engine: Engine, animation: AnimationState) {
        self.engine = engine; self.animation = animation
        super.init(frame: .zero, device: engine.device)
        colorPixelFormat = .bgra8Unorm
        colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        preferredFramesPerSecond = 30
        framebufferOnly = true
        delegate = self
    }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    func concealForTransition() {
        revealGeneration += 1
        waitingToReveal = false
        alphaValue = 0
    }
    func revealAfterRendering() {
        waitingToReveal = true
        draw()
    }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    func draw(in view: MTKView) {
        guard let drawable = currentDrawable else { return }
        do {
            var completion: MTLCommandBufferHandler?
            if waitingToReveal {
                let generation = revealGeneration
                completion = { [weak self] buffer in
                    guard buffer.status == .completed else { return }
                    DispatchQueue.main.async { [weak self] in
                        guard let self, waitingToReveal, revealGeneration == generation else { return }
                        waitingToReveal = false
                        alphaValue = 1
                    }
                }
            }
            try engine.render(to: drawable.texture, time: animation.currentTime(), strength: animation.strength,
                maskMode:animation.showMask, present:drawable, completion: completion)
        }
        catch { isPaused = true; NSLog("Starry Night: %@",error.localizedDescription) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, ArtworkCarouselDelegate {
    var engine: Engine!
    let animation = AnimationState()
    var window: NSWindow!
    var preview: LiveView!
    var statusItem: NSStatusItem!
    var speedSlider: NSSlider!
    var strengthSlider: NSSlider!
    var speedLabel: NSTextField!
    var strengthLabel: NSTextField!
    var statusLabel: NSTextField!
    var pauseButton: NSButton!
    var desktopButton: NSButton!
    var exportButton: NSButton!
    var adjustButton: NSButton!
    var moreButton: NSButton!
    var maskButton: NSButton!
    var carousel: ArtworkCarouselView!
    var thumbnailRail: ArtworkThumbnailRail!
    var previousButton: NSButton!
    var nextButton: NSButton!
    var adjustmentPopover: NSPopover?
    var languagePopup: NSPopUpButton?
    var exporting = false
    var artworkTitle: NSTextField!
    var artworkDetails: NSTextField!
    var artworkCaption: NSTextField!
    var brandLabel: NSTextField!
    var countLabel: NSTextField!
    var sleepPaused = false
    var statusTimer: Timer?
    var verificationOutput: URL?
    var carouselMoving = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let selected = Artwork(rawValue: UserDefaults.standard.integer(forKey: "artwork")) ?? .starryNight
        do { engine = try Engine(resources: Bundle.main.resourceURL!, artwork: selected) }
        catch { showError(error); NSApp.terminate(nil); return }
        let defaults = UserDefaults.standard
        if defaults.object(forKey:"speed") != nil { animation.speed = min(2,max(0.25,defaults.float(forKey:"speed"))) }
        if defaults.object(forKey:"strength") != nil { animation.strength = min(2.5,max(0,defaults.float(forKey:"strength"))) }
        animation.paused = defaults.bool(forKey: "previewPaused")
        createMenu()
        createWindow()
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self,selector:#selector(sleep),name:NSWorkspace.screensDidSleepNotification,object:nil)
        workspace.addObserver(self,selector:#selector(wake),name:NSWorkspace.screensDidWakeNotification,object:nil)
        statusTimer = Timer.scheduledTimer(withTimeInterval:3,repeats:true) { [weak self] _ in self?.refreshStatus() }
        refreshStatus()
        if verificationOutput == nil { NSApp.activate(ignoringOtherApps:true) }
        if verificationOutput != nil { verifyGallery() }
    }

    func createMenu() {
        if statusItem != nil { NSStatusBar.system.removeStatusItem(statusItem) }
        let menu = NSMenu()
        let main = NSMenuItem(); main.submenu = NSMenu()
        main.submenu?.addItem(withTitle:L10n.tr("menu.about"),action:#selector(about),keyEquivalent:"")
        main.submenu?.addItem(NSMenuItem.separator())
        main.submenu?.addItem(withTitle:L10n.tr("menu.quit"),action:#selector(quit),keyEquivalent:"q")
        menu.addItem(main)
        NSApp.mainMenu = menu
        guard verificationOutput == nil else { return }
        statusItem = NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName:"moon.stars",accessibilityDescription:L10n.tr("app.name"))
        let status = NSMenu()
        status.addItem(withTitle:L10n.tr("menu.open"),action:#selector(showWindow),keyEquivalent:"")
        status.addItem(withTitle:L10n.tr("menu.pause"),action:#selector(togglePause),keyEquivalent:"")
        status.addItem(withTitle:L10n.tr("menu.wallpaperSettings"),action:#selector(openWallpaperSettings),keyEquivalent:"")
        status.addItem(NSMenuItem.separator())
        status.addItem(withTitle:L10n.tr("menu.quitKeepsWallpaper"),action:#selector(quit),keyEquivalent:"")
        for item in status.items { item.target = self }
        statusItem.menu = status
    }

    func button(_ text: String, action: Selector) -> NSButton {
        let b = NSButton(title:text,target:self,action:action); b.bezelStyle = .rounded; return b
    }
    func createWindow() {
        window = NSWindow(contentRect:NSRect(x:0,y:0,width:1200,height:760),
            styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        window.title = L10n.tr("app.name")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = GalleryStyle.surface
        window.minSize = NSSize(width:760,height:620)
        window.isReleasedWhenClosed = false
        window.delegate = self
        brandLabel = GalleryStyle.text(L10n.tr("app.name"), size: 14)
        brandLabel.font = AppTypography.brand
        countLabel = GalleryStyle.text(L10n.tr("app.collectionCount", Artwork.allCases.count), size: 12, color: .secondaryLabelColor)

        preview = LiveView(engine:engine,animation:animation)
        do {
            carousel = try ArtworkCarouselView(resources: engine.resources, liveView: preview, selected: engine.artwork)
            carousel.delegate = self
        } catch { showError(error) }
        artworkTitle = GalleryStyle.text(engine.artwork.name, size: 24)
        artworkTitle.font = GalleryStyle.artworkTitleFont
        artworkTitle.alignment = .left
        artworkTitle.maximumNumberOfLines = 0
        artworkTitle.lineBreakMode = .byWordWrapping
        artworkDetails = GalleryStyle.text(engine.artwork.metadata, size: 13)
        artworkDetails.font = .systemFont(ofSize: 13, weight: .regular)
        artworkDetails.alignment = .left
        artworkCaption = GalleryStyle.text(engine.artwork.description, size: 13, color: .secondaryLabelColor)
        statusLabel = GalleryStyle.text("", size: 12, color: .secondaryLabelColor)
        statusLabel.alignment = .left
        desktopButton = button(L10n.tr("button.setWallpaper"),action:#selector(applyWallpaper))
        desktopButton.bezelColor = .controlAccentColor
        desktopButton.controlSize = .regular
        desktopButton.keyEquivalent = "\r"
        window.defaultButtonCell = desktopButton.cell as? NSButtonCell
        adjustButton = button(L10n.tr("button.adjust"),action:#selector(showAdjustments(_:)))
        adjustButton.controlSize = .regular
        adjustButton.isBordered = false
        moreButton = button("",action:#selector(showMore(_:)))
        moreButton.controlSize = .regular
        moreButton.isBordered = false
        moreButton.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: nil)
        moreButton.imagePosition = .imageOnly
        moreButton.toolTip = L10n.tr("menu.auxiliary")
        moreButton.setAccessibilityLabel(L10n.tr("menu.auxiliary"))
        exportButton = button(L10n.tr("button.export"),action:#selector(exportMovie))
        exportButton.isHidden = true
        previousButton = button("", action: #selector(selectPrevious))
        nextButton = button("", action: #selector(selectNext))
        for (control, symbol, key) in [(previousButton!, "chevron.left", "button.previous"),
                                       (nextButton!, "chevron.right", "button.next")] {
            control.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            control.isBordered = false
            control.imagePosition = .imageOnly
            control.toolTip = L10n.tr(key)
            control.setAccessibilityLabel(L10n.tr(key))
        }
        thumbnailRail = ArtworkThumbnailRail(carousel: carousel, target: self, action: #selector(selectThumbnail(_:)))
        let content = ExhibitionLayoutView(carousel: carousel, title: artworkTitle, artist: artworkDetails,
            status: statusLabel, primary: desktopButton, secondary: adjustButton, more: moreButton,
            brand: brandLabel, count: countLabel, previous: previousButton, next: nextButton, thumbnails: thumbnailRail)
        window.contentView = content
        updateArtworkSelection()
        window.center()
        if verificationOutput == nil { window.makeKeyAndOrderFront(nil) }
        redraw()
    }
    @objc func changeValues() {
        guard speedSlider != nil, strengthSlider != nil else { return }
        animation.speed = Float(speedSlider.doubleValue)
        animation.strength = Float(strengthSlider.doubleValue)
        speedLabel.stringValue = String(format:"%.2f×",animation.speed)
        strengthLabel.stringValue = String(format:"%.0f%%",animation.strength*100)
        if verificationOutput == nil {
            UserDefaults.standard.set(animation.speed,forKey:"speed")
            UserDefaults.standard.set(animation.strength,forKey:"strength")
        }
        redraw()
        refreshStatus()
    }
    func updateArtworkSelection() {
        artworkTitle.font = GalleryStyle.artworkTitleFont
        artworkTitle.stringValue = engine.artwork.name
        artworkDetails.stringValue = engine.artwork.metadata
        artworkCaption.stringValue = engine.artwork.description
        carousel?.setSelected(engine.artwork)
        thumbnailRail?.selectedIndex = engine.artwork.rawValue
        refreshNavigation()
        window.contentView?.needsLayout = true
        window.contentView?.layoutSubtreeIfNeeded()
    }

    func refreshNavigation() {
        previousButton?.isEnabled = !exporting && carousel.motion.target > 0
        nextButton?.isEnabled = !exporting && carousel.motion.target < Artwork.allCases.count - 1
        for button in thumbnailRail?.buttons ?? [] { button.isEnabled = !exporting }
    }

    @objc func selectPrevious() { carousel.selectRelative(-1); refreshNavigation() }
    @objc func selectNext() { carousel.selectRelative(1); refreshNavigation() }
    @objc func selectThumbnail(_ sender: NSButton) {
        guard let artwork = Artwork(rawValue: sender.tag) else { return }
        carousel.select(artwork)
        refreshNavigation()
    }
    func setArtworkSelectionEnabled(_ enabled: Bool) {
        carousel?.selectionEnabled = enabled
        adjustButton?.isEnabled = enabled
        moreButton?.isEnabled = enabled
        previousButton?.isEnabled = enabled && carousel.motion.target > 0
        nextButton?.isEnabled = enabled && carousel.motion.target < Artwork.allCases.count - 1
        for button in thumbnailRail?.buttons ?? [] { button.isEnabled = enabled }
    }
    func artworkCarousel(_ carousel: ArtworkCarouselView, didSelect artwork: Artwork) {
        changeArtwork(to: artwork)
    }
    func artworkCarousel(_ carousel: ArtworkCarouselView, isMoving: Bool) {
        carouselMoving = isMoving
        desktopButton?.isEnabled = !isMoving && !exporting
        refreshNavigation()
        redraw()
    }
    func changeArtwork(to selected: Artwork) {
        do {
            let changed = engine.artwork != selected
            if changed { preview.concealForTransition() }
            try engine.select(selected)
            animation.phase = 0
            updateArtworkSelection()
            if verificationOutput == nil { UserDefaults.standard.set(selected.rawValue, forKey: "artwork") }
            redraw()
            refreshStatus()
            if changed && verificationOutput == nil && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                for label in [artworkTitle!, artworkDetails!] {
                    label.layer?.removeAllAnimations()
                    label.alphaValue = 0.45
                    NSAnimationContext.runAnimationGroup { context in
                        context.duration = 0.16
                        label.animator().alphaValue = 1
                    }
                }
            }
        } catch {
            updateArtworkSelection()
            showError(error)
        }
    }
    @objc func toggleMask(_ sender: NSButton) { animation.showMask = sender.state == .on; redraw() }
    @objc func togglePause() {
        let paused = !animation.paused
        animation.paused = paused
        if verificationOutput == nil { UserDefaults.standard.set(paused, forKey: "previewPaused") }
        pauseButton?.title = animation.paused ? L10n.tr("button.resume") : L10n.tr("button.pause")
        pauseButton?.image = NSImage(systemSymbolName: animation.paused ? "play.fill" : "pause.fill", accessibilityDescription: nil)
        redraw()
    }
    func redraw() {
        let paused = animation.paused || sleepPaused || carouselMoving
        preview.isPaused = paused || !window.isVisible || window.isMiniaturized
        if !sleepPaused && !carouselMoving && window.isVisible && !window.isMiniaturized { preview.draw() }
    }
    @objc func sleep() { sleepPaused = true; redraw() }
    @objc func wake() { sleepPaused = false; animation.last = CACurrentMediaTime(); redraw() }
    @objc func openWallpaperSettings() { WallpaperBridge.openSettings() }
    @objc func showAdjustments(_ sender: NSButton) {
        let popover = NSPopover()
        popover.behavior = .transient
        let controller = NSViewController()
        controller.view = makeAdjustmentView()
        popover.contentViewController = controller
        adjustmentPopover = popover
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
    }
    func makeAdjustmentView() -> NSView {
        let container = GallerySurface(color: GalleryStyle.surface, radius: 8)
        container.translatesAutoresizingMaskIntoConstraints = false
        let title = GalleryStyle.text(L10n.tr("label.adjustments"), size: 15)
        speedLabel = GalleryStyle.text("")
        strengthLabel = GalleryStyle.text("")
        speedLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        strengthLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        for label in [speedLabel!, strengthLabel!] {
            label.maximumNumberOfLines = 1
            label.alignment = .right
            label.setContentCompressionResistancePriority(.required, for: .horizontal)
            label.widthAnchor.constraint(greaterThanOrEqualToConstant: 52).isActive = true
        }
        speedSlider = NSSlider(value:Double(animation.speed),minValue:0.25,maxValue:2,target:self,action:#selector(changeValues))
        strengthSlider = NSSlider(value:Double(animation.strength),minValue:0,maxValue:2.5,target:self,action:#selector(changeValues))
        speedSlider.setAccessibilityLabel(L10n.tr("accessibility.speed"))
        strengthSlider.setAccessibilityLabel(L10n.tr("accessibility.strength"))
        speedSlider.trackFillColor = GalleryStyle.accent
        strengthSlider.trackFillColor = GalleryStyle.accent
        func valueRow(_ key: String, value: NSTextField) -> NSView {
            let row = NSView()
            let label = GalleryStyle.text(L10n.tr(key))
            label.translatesAutoresizingMaskIntoConstraints = false
            value.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(label)
            row.addSubview(value)
            NSLayoutConstraint.activate([
                row.heightAnchor.constraint(equalToConstant: 20),
                label.leadingAnchor.constraint(equalTo: row.leadingAnchor),
                label.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                value.trailingAnchor.constraint(equalTo: row.trailingAnchor),
                value.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                label.trailingAnchor.constraint(lessThanOrEqualTo: value.leadingAnchor, constant: -8)
            ])
            return row
        }
        let speedRow = valueRow("label.speed", value: speedLabel)
        let strengthRow = valueRow("label.strength", value: strengthLabel)
        let speedStack = GalleryStyle.column([speedRow, speedSlider], spacing: 6)
        let strengthStack = GalleryStyle.column([strengthRow, strengthSlider], spacing: 6)
        pauseButton = button(animation.paused ? L10n.tr("button.resume") : L10n.tr("button.pause"),action:#selector(togglePause))
        pauseButton.image = NSImage(systemSymbolName: animation.paused ? "play.fill" : "pause.fill", accessibilityDescription: nil)
        pauseButton.imagePosition = .imageLeading
        pauseButton.toolTip = L10n.tr("tooltip.pause")
        maskButton = NSButton(checkboxWithTitle:L10n.tr("label.debugMask"),target:self,action:#selector(toggleMask(_:)))
        maskButton.state = animation.showMask ? .on : .off
        maskButton.toolTip = L10n.tr("tooltip.debugMask")
        languagePopup = NSPopUpButton()
        for language in AppLanguage.allCases {
            languagePopup?.addItem(withTitle: language.menuTitle)
            languagePopup?.lastItem?.representedObject = language.rawValue
        }
        languagePopup?.selectItem(withTitle: AppLanguage.current.menuTitle)
        languagePopup?.target = self
        languagePopup?.action = #selector(changeLanguage(_:))
        let languageRow = NSView()
        let languageLabel = GalleryStyle.text(L10n.tr("label.language"))
        languageLabel.translatesAutoresizingMaskIntoConstraints = false
        languagePopup!.translatesAutoresizingMaskIntoConstraints = false
        languageRow.addSubview(languageLabel)
        languageRow.addSubview(languagePopup!)
        NSLayoutConstraint.activate([
            languageRow.heightAnchor.constraint(equalToConstant: 26),
            languageLabel.leadingAnchor.constraint(equalTo: languageRow.leadingAnchor),
            languageLabel.centerYAnchor.constraint(equalTo: languageRow.centerYAnchor),
            languagePopup!.trailingAnchor.constraint(equalTo: languageRow.trailingAnchor),
            languagePopup!.centerYAnchor.constraint(equalTo: languageRow.centerYAnchor),
            languagePopup!.widthAnchor.constraint(equalToConstant: 184),
            languageLabel.trailingAnchor.constraint(lessThanOrEqualTo: languagePopup!.leadingAnchor, constant: -8)
        ])
        let stack = GalleryStyle.column([title, speedStack, strengthStack, pauseButton, maskButton, languageRow], spacing: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: 320),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),
            speedStack.widthAnchor.constraint(equalTo: stack.widthAnchor),
            strengthStack.widthAnchor.constraint(equalTo: stack.widthAnchor),
            speedRow.widthAnchor.constraint(equalTo: speedStack.widthAnchor),
            strengthRow.widthAnchor.constraint(equalTo: strengthStack.widthAnchor),
            speedSlider.widthAnchor.constraint(equalTo: speedStack.widthAnchor),
            strengthSlider.widthAnchor.constraint(equalTo: strengthStack.widthAnchor),
            pauseButton.widthAnchor.constraint(equalTo: stack.widthAnchor),
            languageRow.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        changeValues()
        return container
    }
    @objc func changeLanguage(_ sender: NSPopUpButton) {
        guard let raw = sender.selectedItem?.representedObject as? String,
              let language = AppLanguage(rawValue: raw) else { return }
        AppLanguage.current = language
        adjustmentPopover?.close()
        adjustmentPopover = nil
        applyLocalization()
    }
    @objc func showMore(_ sender: NSButton) {
        let menu = NSMenu()
        menu.addItem(withTitle:L10n.tr("button.export"),action:#selector(exportMovie),keyEquivalent:"")
        menu.addItem(withTitle:L10n.tr("button.details"),action:#selector(showArtworkDetails),keyEquivalent:"")
        menu.addItem(withTitle:L10n.tr("button.sources"),action:#selector(showSourcesAndLicenses),keyEquivalent:"")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle:L10n.tr("button.wallpaperSettings"),action:#selector(openWallpaperSettings),keyEquivalent:"")
        for item in menu.items { item.target = self }
        menu.popUp(positioning:nil, at:NSPoint(x:0, y:sender.bounds.height + 4), in:sender)
    }
    @objc func showArtworkDetails() {
        let alert = NSAlert()
        alert.messageText = engine.artwork.name
        alert.informativeText = "\(engine.artwork.metadata)\n\n\(engine.artwork.description)"
        alert.runModal()
    }
    @objc func showSourcesAndLicenses() {
        let url = Bundle.main.resourceURL?.appendingPathComponent("THIRD-PARTY-NOTICES.md")
        if let url { NSWorkspace.shared.open(url) }
    }
    func applyLocalization() {
        window.title = L10n.tr("app.name")
        brandLabel.stringValue = L10n.tr("app.name")
        countLabel.stringValue = L10n.tr("app.collectionCount", Artwork.allCases.count)
        desktopButton.title = L10n.tr("button.setWallpaper")
        adjustButton.title = L10n.tr("button.adjust")
        moreButton.toolTip = L10n.tr("menu.auxiliary")
        moreButton.setAccessibilityLabel(L10n.tr("menu.auxiliary"))
        exportButton.title = L10n.tr("button.export")
        previousButton.toolTip = L10n.tr("button.previous")
        previousButton.setAccessibilityLabel(L10n.tr("button.previous"))
        nextButton.toolTip = L10n.tr("button.next")
        nextButton.setAccessibilityLabel(L10n.tr("button.next"))
        thumbnailRail.relocalize()
        carousel.relocalize()
        createMenu()
        updateArtworkSelection()
        refreshStatus()
    }
    func refreshStatus() {
        guard statusLabel != nil, !exporting else { return }
        let defaults = UserDefaults.standard
        let pending = defaults.float(forKey:"appliedSpeed") != animation.speed
            || defaults.float(forKey:"appliedStrength") != animation.strength
            || defaults.integer(forKey:"appliedArtwork") != engine.artwork.rawValue
        let hasPublished = defaults.object(forKey:"appliedArtwork") != nil
            && defaults.object(forKey:"appliedSpeed") != nil && defaults.object(forKey:"appliedStrength") != nil
        if !hasPublished { statusLabel.stringValue = L10n.tr("status.firstRun") }
        else if pending { statusLabel.stringValue = L10n.tr("status.pending") }
        else if WallpaperBridge.isSelected { statusLabel.stringValue = L10n.tr("status.appliedSelected") }
        else if FileManager.default.fileExists(atPath: WallpaperBridge.documents.path) {
            statusLabel.stringValue = L10n.tr("status.appliedNotSelected")
        } else { statusLabel.stringValue = L10n.tr("status.firstRun") }
        statusLabel.toolTip = L10n.tr("status.help")
        window.contentView?.needsLayout = true
        window.contentView?.layoutSubtreeIfNeeded()
    }
    @objc func applyWallpaper() {
        guard !exporting else { return }
        do {
            let destination = try WallpaperBridge.prepareRender()
            let speed = animation.speed, strength = animation.strength
            let screen = NSScreen.main?.frame.size ?? NSSize(width:16,height:10)
            let width = 2560, height = Int((2560*screen.height/screen.width/2).rounded())*2
            exporting = true; desktopButton.isEnabled = false; exportButton.isEnabled = false; setArtworkSelectionEnabled(false)
            statusLabel.stringValue = L10n.tr("status.preparing")
            DispatchQueue.global(qos:.userInitiated).async { [self] in
                do {
                    try engine.export(to:destination,width:width,height:height,speed:speed,strength:strength) { percent in
                        DispatchQueue.main.async { self.statusLabel.stringValue = L10n.tr("status.rendering", Int(percent*100)) }
                    }
                    try WallpaperBridge.publish(destination,speed:speed,width:width,height:height, name: engine.artwork.title)
                    DispatchQueue.main.async {
                        let defaults = UserDefaults.standard
                        defaults.set(speed,forKey:"appliedSpeed"); defaults.set(strength,forKey:"appliedStrength")
                        defaults.set(self.engine.artwork.rawValue,forKey:"appliedArtwork")
                        self.exporting = false; self.desktopButton.isEnabled = true; self.exportButton.isEnabled = true
                        self.setArtworkSelectionEnabled(true)
                        self.refreshStatus()
                        if !WallpaperBridge.isSelected { WallpaperBridge.openSettings() }
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.exporting = false; self.desktopButton.isEnabled = true; self.exportButton.isEnabled = true
                        self.setArtworkSelectionEnabled(true)
                        self.statusLabel.stringValue = L10n.tr("status.applyFailed"); self.showError(error)
                    }
                }
            }
        } catch { showError(error) }
    }
    @objc func showWindow() { window.makeKeyAndOrderFront(nil); preview.isPaused = animation.paused; NSApp.activate(ignoringOtherApps:true) }
    func windowWillClose(_ notification: Notification) { preview.isPaused = true }
    func windowDidMiniaturize(_ notification: Notification) { preview.isPaused = true }
    func windowDidDeminiaturize(_ notification: Notification) { redraw() }
    func windowDidResignKey(_ notification: Notification) { carousel?.cancelInteraction() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showWindow(); return true }
    @objc func exportMovie() {
        guard !exporting else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = "\(engine.artwork.filename)-flow.mp4"
        panel.directoryURL = Bundle.main.bundleURL.deletingLastPathComponent()
        panel.beginSheetModal(for:window) { [self] response in
            guard response == .OK, let url = panel.url else { return }
            exporting = true; exportButton.isEnabled = false; desktopButton.isEnabled = false; setArtworkSelectionEnabled(false)
            let speed = animation.speed, strength = animation.strength
            let screen = NSScreen.main?.frame.size ?? NSSize(width:16,height:10)
            let width = 3840, height = Int((3840*screen.height/screen.width/2).rounded())*2
            DispatchQueue.global(qos:.userInitiated).async { [self] in
                do {
                    try engine.export(to:url,width:width,height:height,speed:speed,strength:strength) { percent in
                        DispatchQueue.main.async { self.statusLabel.stringValue = L10n.tr("status.exporting", Int(percent*100)) }
                    }
                    DispatchQueue.main.async {
                        self.exporting = false; self.exportButton.isEnabled = true; self.desktopButton.isEnabled = true
                        self.setArtworkSelectionEnabled(true)
                        self.statusLabel.stringValue = L10n.tr("status.exported", url.lastPathComponent)
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.exporting = false; self.exportButton.isEnabled = true; self.desktopButton.isEnabled = true
                        self.setArtworkSelectionEnabled(true)
                        self.statusLabel.stringValue = L10n.tr("status.exportFailed"); self.showError(error)
                    }
                }
            }
        }
    }
    func showError(_ error: Error) { let alert = NSAlert(error:error); alert.runModal() }
    @objc func about() {
        NSApp.orderFrontStandardAboutPanel(options:[.applicationName:L10n.tr("app.name"),
            .applicationVersion:Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "",
            .credits:NSAttributedString(string:L10n.tr("about.credits"))])
    }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if exporting {
            let alert = NSAlert(); alert.messageText = L10n.tr("alert.exporting.title"); alert.informativeText = L10n.tr("alert.exporting.message")
            alert.addButton(withTitle:L10n.tr("alert.exporting.wait")); alert.addButton(withTitle:L10n.tr("alert.exporting.quit"))
            return alert.runModal() == .alertFirstButtonReturn ? .terminateCancel : .terminateNow
        }
        return .terminateNow
    }
}

@main
struct StarryNightMain {
static func main() {
let args = CommandLine.arguments
if args.count>1 && args[1] != "--ui-check" {
    do {
        let resources = Bundle.main.resourceURL!
        let selected: Artwork
        if let index = args.firstIndex(of: "--artwork"), index + 1 < args.count,
           let artwork = Artwork.allCases.first(where: { $0.filename == args[index + 1] }) {
            selected = artwork
        } else { selected = .starryNight }
        let engine = try Engine(resources:resources, artwork: selected)
        if args[1] == "--snapshot", args.count>=4 {
            try engine.snapshot(to:URL(fileURLWithPath:args[2]),time:Float(args[3]) ?? 0,
                maskMode:args.contains("--mask"))
        } else if args[1] == "--export", args.count>=3 {
            let width = args.count>3 ? Int(args[3])! : 2560
            let height = args.count>4 ? Int(args[4])! : 1600
            try engine.export(to:URL(fileURLWithPath:args[2]),width:width,height:height,speed:1,strength:1.4) {
                if Int($0*100)%10==0 { print("Export \(Int($0*100))%") }
            }
        } else if args[1] == "--verify" {
            let original = try engine.pixels(time:0,strength:0)
            let first = try engine.pixels(time:0)
            let middle = try engine.pixels(time:8)
            let loop = try engine.pixels(time:24)
            guard first == loop else { throw failure("Loop endpoint mismatch") }
            func pixelDifference(_ a:Data,_ b:Data,_ x:Int,_ y:Int)->Int {
                let i=(y*1280+x)*4
                return (0..<3).map { abs(Int(a[i+$0])-Int(b[i+$0])) }.reduce(0,+)
            }
            // Compare protected samples to the untouched source and to a later frame.
            let protected = [(260,300),(260,600),(380,840),(800,880),(1050,730),(1200,640),
                (718,650),(720,700),(550,725),(150,800),(347,575)]
            for (x,y) in selected == .starryNight ? protected : [] {
                guard pixelDifference(first,original,x,y)==0 && pixelDifference(first,middle,x,y)==0 else {
                    throw failure("Foreground moved at \(x),\(y)")
                }
            }
            let anchors: [(Double, Double)]
            switch selected {
            case .starryNight: anchors = []
            case .waterLilies: anchors = [(0.74,0.26),(0.81,0.41),(0.60,0.78)]
            case .wheatStacks: anchors = [(0.43,0.55),(0.22,0.60),(0.80,0.75)]
            case .rhone: anchors = [(0.77,0.86),(0.22,0.49),(0.50,0.70)]
            case .cypresses: anchors = [(0.84,0.30),(0.50,0.60),(0.23,0.65)]
            }
            let outputAspect = 1280.0/1014.0
            let imageAspect = Double(engine.painting.width)/Double(engine.painting.height)
            for (sourceX,sourceY) in anchors {
                let bounds = selected.imageBounds
                let px = (sourceX-bounds.minX)/bounds.width
                let py = (sourceY-bounds.minY)/bounds.height
                let x = Int((outputAspect > imageAspect ? px : (px-0.5)*imageAspect/outputAspect+0.5)*1280)
                let y = Int((outputAspect > imageAspect ? (py-0.5)*outputAspect/imageAspect+0.5 : py)*1014)
                if x >= 0 && x < 1280 && y >= 0 && y < 1014 {
                    guard pixelDifference(first,original,x,y)==0 && pixelDifference(first,middle,x,y)==0 else {
                        throw failure("Protected subject moved at \(px),\(py)")
                    }
                }
            }
            var changes=0
            for y in stride(from:40,to:500,by:20) { for x in stride(from:450,to:1200,by:20) {
                if pixelDifference(first,middle,x,y)>5 { changes += 1 }
            } }
            if selected != .starryNight {
                changes = 0
                for i in stride(from:0,to:first.count,by:4) {
                    if abs(Int(first[i])-Int(middle[i])) > 2 { changes += 1 }
                }
            }
            guard changes>200 else { throw failure("Insufficient motion: \(changes)") }
            print("PASS: \(selected.filename); exact loop endpoints; \(changes) samples moving")
        } else { throw failure("Unknown arguments") }
    } catch { fputs("\(error.localizedDescription)\n",stderr); exit(1) }
} else {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = AppDelegate()
    if args.count == 3, args[1] == "--ui-check" {
        delegate.verificationOutput = URL(fileURLWithPath: args[2], isDirectory: true)
    }
    app.delegate = delegate
    app.run()
}
}
}
