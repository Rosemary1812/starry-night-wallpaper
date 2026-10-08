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
            throw failure("这台 Mac 无法启动 Metal 图形引擎。")
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
        guard let cropped = image.cropping(to: rect) else { throw failure("无法读取画作区域。") }
        return cropped
    }

    static func loadPainting(resources: URL, artwork: Artwork, loader: MTKTextureLoader) throws -> MTLTexture {
        let url = resources.appendingPathComponent("\(artwork.filename).jpg")
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw failure("无法读取画作：\(artwork.title)")
        }
        return try loader.newTexture(cgImage: crop(image, artwork: artwork),
            options: [.SRGB: false, .origin: MTKTextureLoader.Origin.topLeft])
    }

    static func makeMask(artwork: Artwork = .starryNight) throws -> CGImage {
        let width = 2048, height = 1622
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width*4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw failure("无法创建天空区域。") }
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
            // BEGIN mask: water-lilies
            // Follow the painted clusters, rather than freezing large ellipses of adjacent water.
            protect([(0,0),(0.36,0),(0.34,0.022),(0.29,0.027),(0.255,0.042),(0.21,0.035),(0.18,0.055),(0.13,0.047),(0.10,0.069),(0.053,0.066),(0.022,0.08),(0,0.068)])
            protect([(0,0.099),(0.075,0.091),(0.122,0.105),(0.184,0.094),(0.245,0.108),(0.235,0.134),(0.16,0.139),(0.096,0.148),(0.04,0.151),(0,0.14)])
            protect([(0.34,0.04),(0.387,0.032),(0.433,0.043),(0.494,0.029),(0.546,0.035),(0.584,0.05),(0.619,0.04),(0.653,0.052),(0.696,0.044),(0.738,0.069),(0.778,0.071),(0.813,0.086),(0.829,0.107),(0.786,0.118),(0.719,0.124),(0.676,0.134),(0.611,0.129),(0.556,0.138),(0.514,0.122),(0.47,0.112),(0.431,0.103),(0.371,0.103),(0.348,0.077)])
            protect([(0.37,0),(1,0),(1,0.067),(0.947,0.084),(0.904,0.088),(0.872,0.069),(0.843,0.05),(0.804,0.06),(0.772,0.055),(0.736,0.049),(0.7,0.027),(0.657,0.036),(0.615,0.02),(0.571,0.027),(0.526,0.022),(0.479,0.032),(0.435,0.023),(0.39,0.027)])
            protect([(0.487,0.232),(0.546,0.216),(0.593,0.219),(0.65,0.205),(0.708,0.214),(0.765,0.222),(0.813,0.217),(0.838,0.224),(0.887,0.229),(0.926,0.245),(0.927,0.269),(0.877,0.281),(0.828,0.273),(0.787,0.29),(0.745,0.286),(0.702,0.294),(0.66,0.282),(0.606,0.284),(0.563,0.272),(0.516,0.279),(0.487,0.26)])
            protect([(0.922,0.238),(0.965,0.239),(1,0.25),(1,0.287),(0.973,0.281),(0.937,0.284),(0.922,0.269)])
            protect([(0.527,0.372),(0.576,0.36),(0.626,0.371),(0.674,0.355),(0.719,0.357),(0.762,0.352),(0.801,0.348),(0.851,0.353),(0.884,0.367),(0.918,0.362),(0.961,0.377),(1,0.383),(1,0.453),(0.964,0.455),(0.929,0.44),(0.885,0.46),(0.845,0.439),(0.8,0.445),(0.76,0.441),(0.713,0.427),(0.672,0.421),(0.623,0.426),(0.58,0.412),(0.535,0.408)])
            protect([(0.928,0.454),(0.968,0.458),(1,0.453),(1,0.493),(0.965,0.495),(0.934,0.481)])
            protect([(0.829,0.516),(0.882,0.509),(0.911,0.516),(0.944,0.508),(0.973,0.52),(1,0.509),(1,0.591),(0.964,0.593),(0.934,0.574),(0.895,0.58),(0.873,0.551),(0.835,0.546)])
            protect([(0,0.573),(0.057,0.573),(0.083,0.593),(0.107,0.612),(0.098,0.641),(0.153,0.655),(0.183,0.68),(0.17,0.706),(0.192,0.736),(0.193,0.776),(0.157,0.8),(0.139,0.843),(0.12,0.864),(0.076,0.856),(0.061,0.885),(0.018,0.877),(0,0.889)])
            protect([(0.17,0.674),(0.226,0.662),(0.263,0.657),(0.289,0.671),(0.285,0.692),(0.249,0.704),(0.214,0.72),(0.183,0.713)])
            protect([(0.207,0.737),(0.24,0.716),(0.29,0.713),(0.326,0.727),(0.32,0.748),(0.286,0.751),(0.266,0.771),(0.227,0.765)])
            protect([(0.235,0.783),(0.289,0.762),(0.334,0.765),(0.37,0.774),(0.367,0.804),(0.326,0.814),(0.284,0.801),(0.245,0.811)])
            protect([(0.39,0.69),(0.424,0.683),(0.451,0.697),(0.482,0.693),(0.508,0.713),(0.528,0.71),(0.551,0.726),(0.52,0.741),(0.473,0.731),(0.437,0.733),(0.408,0.719)])
            protect([(0.401,0.769),(0.424,0.757),(0.442,0.771),(0.459,0.79),(0.505,0.796),(0.548,0.789),(0.58,0.803),(0.579,0.825),(0.546,0.839),(0.521,0.823),(0.482,0.822),(0.452,0.83),(0.422,0.82),(0.404,0.796)])
            protect([(0.57,0.757),(0.587,0.731),(0.608,0.735),(0.625,0.754),(0.657,0.755),(0.685,0.764),(0.713,0.755),(0.724,0.771),(0.698,0.794),(0.659,0.79),(0.635,0.813),(0.609,0.808),(0.593,0.789),(0.57,0.781)])
            protect([(0.67,0.704),(0.722,0.692),(0.747,0.704),(0.74,0.72),(0.701,0.731),(0.667,0.721)])
            protect([(0.744,0.756),(0.756,0.74),(0.773,0.747),(0.786,0.769),(0.787,0.79),(0.771,0.81),(0.75,0.8),(0.739,0.779)])
            protect([(0.471,0.86),(0.504,0.863),(0.539,0.868),(0.557,0.89),(0.529,0.914),(0.482,0.918),(0.456,0.903),(0.464,0.878)])
            protect([(0.266,0.858),(0.302,0.844),(0.341,0.853),(0.35,0.874),(0.319,0.887),(0.28,0.884),(0.262,0.874)])
            protect([(0.142,0.947),(0.173,0.935),(0.197,0.944),(0.22,0.961),(0.241,0.971),(0.234,0.993),(0.203,0.991),(0.179,0.978),(0.15,0.977),(0.136,0.963)])
            // Extra quiet margin around the small left pink flower.
            protect([(0.396,0.779),(0.409,0.77),(0.43,0.779),(0.438,0.802),(0.426,0.818),(0.407,0.815),(0.396,0.799)])
            // Keep the artist's signature intact.
            protect([(0.77,0.924),(1,0.924),(1,1),(0.77,1)])
            // END mask: water-lilies
        } else if artwork == .wheatStacks {
            // BEGIN mask: wheat-stacks
            // The warm sky follows the gently uneven horizon, with a quiet protective margin.
            protect([(0,0.279),(0.075,0.274),(0.15,0.278),(0.25,0.274),(0.32,0.267),(0.40,0.242),(0.46,0.247),(0.53,0.247),(0.59,0.256),(0.63,0.254),(0.68,0.245),(0.74,0.25),(0.80,0.25),(0.87,0.254),(0.94,0.259),(1,0.268),(1,1),(0,1)])
            // END mask: wheat-stacks
        } else if artwork == .rhone {
            // BEGIN mask: rhone
            // Preserve the complete far bank, buildings, sky, and stationary light sources.
            protect([(0,0),(1,0),(1,0.494),(0.935,0.489),(0.865,0.481),(0.8,0.475),(0.735,0.474),(0.675,0.47),(0.61,0.468),(0.55,0.469),(0.485,0.472),(0.42,0.482),(0.35,0.497),(0.30,0.51),(0.225,0.524),(0.15,0.546),(0.085,0.57),(0,0.603)])
            // Follow the actual sloping foreground shore, including the ridge behind the couple.
            protect([(0,0.619),(0.063,0.641),(0.114,0.673),(0.175,0.69),(0.237,0.724),(0.297,0.75),(0.355,0.753),(0.409,0.743),(0.475,0.727),(0.53,0.721),(0.589,0.712),(0.637,0.701),(0.685,0.694),(0.724,0.707),(0.763,0.73),(0.815,0.752),(0.866,0.777),(0.922,0.802),(1,0.829),(1,1),(0,1)])
            // Boat hulls, thin masts and rigging receive independent close-fitting protection.
            protect([(0.357,0.654),(0.39,0.672),(0.416,0.678),(0.444,0.691),(0.479,0.703),(0.519,0.706),(0.554,0.699),(0.564,0.719),(0.532,0.738),(0.492,0.746),(0.461,0.762),(0.427,0.752),(0.394,0.724),(0.369,0.706)])
            protect([(0.494,0.525),(0.506,0.525),(0.51,0.695),(0.504,0.735),(0.49,0.736),(0.493,0.654)])
            protect([(0.457,0.605),(0.468,0.605),(0.472,0.743),(0.457,0.747)])
            protect([(0.498,0.535),(0.504,0.534),(0.537,0.681),(0.532,0.696),(0.526,0.687)])
            protect([(0.488,0.574),(0.494,0.57),(0.472,0.697),(0.464,0.699)])
            protect([(0.522,0.614),(0.533,0.612),(0.538,0.695),(0.528,0.705)])
            // END mask: rhone
        } else if artwork == .cypresses {
            // BEGIN mask: cypresses
            // A conservative contour protects the mountain ridge and middle vegetation.
            protect([(0,0.668),(0.059,0.66),(0.097,0.627),(0.135,0.602),(0.173,0.57),(0.203,0.545),(0.235,0.527),(0.268,0.543),(0.3,0.562),(0.35,0.573),(0.405,0.57),(0.445,0.545),(0.474,0.521),(0.51,0.49),(0.554,0.482),(0.601,0.497),(0.645,0.491),(0.677,0.513),(0.713,0.551),(0.751,0.578),(0.806,0.588),(0.87,0.565),(0.916,0.542),(0.96,0.526),(1,0.53),(1,0.722),(0.885,0.724),(0.765,0.707),(0.654,0.726),(0.553,0.713),(0.42,0.731),(0.311,0.753),(0.2,0.752),(0.085,0.726),(0,0.721)])
            // Trace branch tips more closely than a single triangular silhouette.
            protect([(0.726,0.663),(0.729,0.579),(0.751,0.539),(0.762,0.493),(0.774,0.458),(0.776,0.402),(0.788,0.375),(0.798,0.349),(0.792,0.316),(0.806,0.284),(0.813,0.235),(0.818,0.185),(0.818,0.139),(0.823,0.109),(0.832,0.079),(0.836,0.065),(0.843,0.08),(0.848,0.104),(0.855,0.131),(0.857,0.173),(0.868,0.209),(0.872,0.252),(0.877,0.294),(0.885,0.327),(0.891,0.369),(0.889,0.414),(0.893,0.447),(0.899,0.469),(0.903,0.521),(0.914,0.561),(0.909,0.611),(0.919,0.659)])
            // Olive foliage extends below the mountain band; keep it distinct from the wheat.
            protect([(0.101,0.657),(0.14,0.633),(0.19,0.632),(0.237,0.654),(0.274,0.682),(0.3,0.71),(0.31,0.746),(0.286,0.787),(0.254,0.807),(0.222,0.789),(0.195,0.783),(0.168,0.759),(0.13,0.749),(0.109,0.716)])
            protect([(0.702,0.866),(0.738,0.845),(0.774,0.846),(0.819,0.837),(0.845,0.805),(0.886,0.786),(0.929,0.777),(0.965,0.769),(1,0.78),(1,1),(0.662,1),(0.668,0.949),(0.689,0.925),(0.692,0.891)])
            // END mask: cypresses
        }
        guard let raw = ctx.makeImage() else { throw failure("无法生成天空区域。") }
        let expanded = CIImage(cgImage: raw).clampedToExtent()
            .applyingFilter("CIMorphologyMinimum", parameters: [kCIInputRadiusKey: 8])
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 4])
        guard let result = CIContext().createCGImage(expanded, from: CGRect(x:0,y:0,width:width,height:height)) else {
            throw failure("无法平滑天空边缘。")
        }
        return try crop(result, artwork: artwork)
    }

    @discardableResult
    func render(to texture: MTLTexture, time: Float, strength: Float, maskMode: Bool = false,
                present drawable: CAMetalDrawable? = nil) throws -> MTLCommandBuffer {
        guard let command = queue.makeCommandBuffer() else { throw failure("无法创建渲染任务。") }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { throw failure("无法开始渲染。") }
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
        command.commit()
        return command
    }

    func pixels(time: Float, strength: Float = 1.4, maskMode: Bool = false, width: Int = 1280, height: Int = 1014) throws -> Data {
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
            width: width, height: height, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: desc) else { throw failure("无法创建画面。") }
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
        guard writer.canAdd(input) else { throw failure("无法创建视频编码器。") }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? failure("无法开始导出。") }
        writer.startSession(atSourceTime: .zero)
        guard let pool = adaptor.pixelBufferPool else { writer.cancelWriting(); throw failure("无法分配视频缓冲区。") }
        var cache: CVMetalTextureCache?
        guard CVMetalTextureCacheCreate(nil,nil,device,nil,&cache)==kCVReturnSuccess, let cache else {
            writer.cancelWriting(); throw failure("无法启动视频渲染。")
        }
        let fps: Int32 = 30
        let count = Int((24 / Double(speed) * Double(fps)).rounded())
        do {
            for frame in 0..<count {
                let deadline = Date().addingTimeInterval(30)
                while !input.isReadyForMoreMediaData {
                    if writer.status != .writing { throw writer.error ?? failure("编码已停止。") }
                    if Date()>deadline { throw failure("视频编码等待超时。") }
                    Thread.sleep(forTimeInterval: 0.002)
                }
                try autoreleasepool {
                    var buffer: CVPixelBuffer?
                    guard CVPixelBufferPoolCreatePixelBuffer(nil,pool,&buffer)==kCVReturnSuccess, let buffer else {
                        throw failure("无法分配视频帧。")
                    }
                    var cvTexture: CVMetalTexture?
                    guard CVMetalTextureCacheCreateTextureFromImage(nil,cache,buffer,nil,.bgra8Unorm,width,height,0,&cvTexture)==kCVReturnSuccess,
                        let cvTexture, let texture = CVMetalTextureGetTexture(cvTexture) else { throw failure("无法创建视频纹理。") }
                    let command = try render(to:texture, time:Float(frame)/Float(count)*24, strength:strength)
                    command.waitUntilCompleted()
                    if let error = command.error { throw error }
                    guard adaptor.append(buffer, withPresentationTime: CMTime(value:Int64(frame),timescale:fps)) else {
                        throw writer.error ?? failure("写入视频帧失败。")
                    }
                }
                if frame%15==0 { progress(Double(frame)/Double(count)) }
            }
            input.markAsFinished()
            writer.endSession(atSourceTime: CMTime(value:Int64(count),timescale:fps))
            let done = DispatchSemaphore(value: 0)
            writer.finishWriting { done.signal() }
            guard done.wait(timeout:.now()+60) == .success else { throw failure("保存视频超时。") }
            guard writer.status == .completed else { throw writer.error ?? failure("视频未完成。") }
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
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    func draw(in view: MTKView) {
        guard let drawable = currentDrawable else { return }
        do { try engine.render(to: drawable.texture, time: animation.currentTime(), strength: animation.strength,
            maskMode:animation.showMask, present:drawable) }
        catch { isPaused = true; NSLog("Starry Night: %@",error.localizedDescription) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
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
    var exporting = false
    var artworkCards: [ArtworkCard] = []
    var artworkTitle: NSTextField!
    var artworkDetails: NSTextField!
    var artworkCaption: NSTextField!
    var sleepPaused = false
    var statusTimer: Timer?
    var verificationOutput: URL?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let selected = Artwork(rawValue: UserDefaults.standard.integer(forKey: "artwork")) ?? .starryNight
        do { engine = try Engine(resources: Bundle.main.resourceURL!, artwork: selected) }
        catch { showError(error); NSApp.terminate(nil); return }
        let defaults = UserDefaults.standard
        if defaults.object(forKey:"speed") != nil { animation.speed = min(2,max(0.25,defaults.float(forKey:"speed"))) }
        if defaults.object(forKey:"strength") != nil { animation.strength = min(2.5,max(0,defaults.float(forKey:"strength"))) }
        animation.paused = WallpaperBridge.isPaused
        createMenu()
        createWindow()
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self,selector:#selector(sleep),name:NSWorkspace.screensDidSleepNotification,object:nil)
        workspace.addObserver(self,selector:#selector(wake),name:NSWorkspace.screensDidWakeNotification,object:nil)
        statusTimer = Timer.scheduledTimer(withTimeInterval:3,repeats:true) { [weak self] _ in self?.refreshStatus() }
        refreshStatus()
        NSApp.activate(ignoringOtherApps:true)
        if verificationOutput != nil { verifyGallery() }
    }

    func createMenu() {
        let menu = NSMenu()
        let main = NSMenuItem(); main.submenu = NSMenu()
        main.submenu?.addItem(withTitle:"关于流动星夜",action:#selector(about),keyEquivalent:"")
        main.submenu?.addItem(NSMenuItem.separator())
        main.submenu?.addItem(withTitle:"退出控制面板",action:#selector(quit),keyEquivalent:"q")
        menu.addItem(main)
        NSApp.mainMenu = menu
        statusItem = NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName:"moon.stars",accessibilityDescription:"流动星夜")
        let status = NSMenu()
        status.addItem(withTitle:"打开控制面板",action:#selector(showWindow),keyEquivalent:"")
        status.addItem(withTitle:"暂停 / 继续",action:#selector(togglePause),keyEquivalent:"")
        status.addItem(withTitle:"系统壁纸设置…",action:#selector(openWallpaperSettings),keyEquivalent:"")
        status.addItem(NSMenuItem.separator())
        status.addItem(withTitle:"退出控制面板（壁纸继续）",action:#selector(quit),keyEquivalent:"")
        for item in status.items { item.target = self }
        statusItem.menu = status
    }

    func button(_ text: String, action: Selector) -> NSButton {
        let b = NSButton(title:text,target:self,action:action); b.bezelStyle = .rounded; return b
    }
    func createWindow() {
        window = NSWindow(contentRect:NSRect(x:0,y:0,width:1120,height:790),
            styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        window.title = "流动星夜"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = GalleryStyle.surface
        window.minSize = NSSize(width:940,height:760)
        window.isReleasedWhenClosed = false
        window.delegate = self
        let content = GallerySurface(color: GalleryStyle.surface)
        window.contentView = content
        let brand = GalleryStyle.text("流动星夜", size: 22)
        let subtitle = GalleryStyle.text("梵高与莫奈的动态画作", size: 13, color: .secondaryLabelColor)
        let heading = GalleryStyle.column([brand, subtitle], spacing: 5)
        let live = GalleryStyle.text("实时预览", size: 13, color: GalleryStyle.accent)
        let header = GalleryStyle.row([heading, NSView(), live])

        preview = LiveView(engine:engine,animation:animation)
        preview.wantsLayer = true
        preview.layer?.cornerRadius = 3
        preview.layer?.masksToBounds = true
        let stage = GallerySurface(color: GalleryStyle.canvas, radius: 12)
        stage.addSubview(preview)
        preview.translatesAutoresizingMaskIntoConstraints = false
        let screen = NSScreen.main?.frame.size ?? NSSize(width: 16, height: 10)
        let preferredWidth = preview.widthAnchor.constraint(equalTo: stage.widthAnchor, constant: -48)
        preferredWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            preview.centerXAnchor.constraint(equalTo: stage.centerXAnchor),
            preview.centerYAnchor.constraint(equalTo: stage.centerYAnchor),
            preview.widthAnchor.constraint(lessThanOrEqualTo: stage.widthAnchor, constant: -48),
            preview.heightAnchor.constraint(lessThanOrEqualTo: stage.heightAnchor, constant: -48),
            preview.widthAnchor.constraint(equalTo: preview.heightAnchor, multiplier: screen.width/screen.height),
            preferredWidth,
            stage.heightAnchor.constraint(greaterThanOrEqualToConstant: 380)
        ])

        artworkTitle = GalleryStyle.text(engine.artwork.name, size: 23)
        artworkDetails = GalleryStyle.text("\(engine.artwork.artist) · \(engine.artwork.year)", size: 13, color: .secondaryLabelColor)
        artworkCaption = GalleryStyle.text(engine.artwork.description, size: 14, color: .secondaryLabelColor)
        let metadata = GalleryStyle.column([artworkTitle, artworkDetails], spacing: 8)
        speedLabel = GalleryStyle.text("")
        strengthLabel = GalleryStyle.text("")
        speedLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .regular)
        strengthLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .regular)
        speedSlider = NSSlider(value:Double(animation.speed),minValue:0.25,maxValue:2,target:self,action:#selector(changeValues))
        strengthSlider = NSSlider(value:Double(animation.strength),minValue:0,maxValue:2.5,target:self,action:#selector(changeValues))
        speedSlider.setAccessibilityLabel("流动速度")
        strengthSlider.setAccessibilityLabel("动效幅度")
        speedSlider.trackFillColor = GalleryStyle.accent
        strengthSlider.trackFillColor = GalleryStyle.accent
        let speedRow = GalleryStyle.row([GalleryStyle.text("流动速度"), NSView(), speedLabel])
        let strengthRow = GalleryStyle.row([GalleryStyle.text("变化幅度"), NSView(), strengthLabel])
        let speedStack = GalleryStyle.column([speedRow, speedSlider], spacing: 6)
        let strengthStack = GalleryStyle.column([strengthRow, strengthSlider], spacing: 6)
        let sliders = GalleryStyle.column([speedStack, strengthStack], spacing: 18)
        pauseButton = button(animation.paused ? "继续播放" : "暂停播放",action:#selector(togglePause))
        pauseButton.image = NSImage(systemSymbolName: animation.paused ? "play.fill" : "pause.fill", accessibilityDescription: nil)
        pauseButton.imagePosition = .imageLeading
        pauseButton.toolTip = "暂停或继续预览与当前动态壁纸"
        pauseButton.controlSize = .large
        desktopButton = button("应用到桌面与锁屏",action:#selector(applyWallpaper))
        desktopButton.bezelColor = GalleryStyle.primaryAction
        desktopButton.contentTintColor = .white
        desktopButton.controlSize = .large
        desktopButton.font = .systemFont(ofSize: 14, weight: .medium)
        desktopButton.attributedTitle = NSAttributedString(string: desktopButton.title, attributes: [
            .font: NSFont.systemFont(ofSize: 14, weight: .medium), .foregroundColor: NSColor.white
        ])
        exportButton = button("导出视频…",action:#selector(exportMovie))
        exportButton.isBordered = false
        exportButton.font = .systemFont(ofSize: 13)
        exportButton.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: nil)
        exportButton.imagePosition = .imageLeading
        let maskButton = NSButton(checkboxWithTitle:"显示活动区域",target:self,action:#selector(toggleMask(_:)))
        maskButton.font = .systemFont(ofSize: 13)
        maskButton.tintProminence = .none
        statusLabel = GalleryStyle.text("", size: 13, color: .secondaryLabelColor)
        let settingsButton = button("壁纸设置…",action:#selector(openWallpaperSettings))
        settingsButton.isBordered = false
        settingsButton.font = .systemFont(ofSize: 13)
        settingsButton.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        settingsButton.imagePosition = .imageLeading
        let secondaryActions = GalleryStyle.row([exportButton, NSView(), settingsButton], spacing: 4)
        let actions = GalleryStyle.column([statusLabel, desktopButton, secondaryActions], spacing: 12)
        let spacer = NSView()
        let inspector = GalleryStyle.column([metadata, artworkCaption, sliders, pauseButton, maskButton, spacer, actions], spacing: 12)
        inspector.setCustomSpacing(20, after: artworkCaption)
        inspector.setCustomSpacing(8, after: pauseButton)
        inspector.setCustomSpacing(0, after: maskButton)
        inspector.setCustomSpacing(16, after: spacer)
        inspector.widthAnchor.constraint(equalToConstant: 258).isActive = true
        let inspectorScroll = NSScrollView()
        inspectorScroll.drawsBackground = false
        inspectorScroll.hasVerticalScroller = true
        inspectorScroll.autohidesScrollers = true
        inspectorScroll.documentView = inspector
        inspector.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            inspectorScroll.widthAnchor.constraint(equalToConstant: 258),
            inspector.leadingAnchor.constraint(equalTo: inspectorScroll.contentView.leadingAnchor),
            inspector.topAnchor.constraint(equalTo: inspectorScroll.contentView.topAnchor),
            inspector.heightAnchor.constraint(greaterThanOrEqualTo: inspectorScroll.heightAnchor)
        ])
        let body = GalleryStyle.row([stage, inspectorScroll], spacing: 24)
        body.alignment = .top

        let collectionHeading = GalleryStyle.row([
            GalleryStyle.text("画作集", size: 14), NSView(),
            GalleryStyle.text("5 幅作品", size: 13, color: .secondaryLabelColor)
        ])
        let strip = GalleryStyle.row([], spacing: 12)
        do {
            for artwork in Artwork.allCases {
                let card = try ArtworkCard(artwork: artwork, resources: engine.resources, target: self, action: #selector(changeArtwork(_:)))
                artworkCards.append(card)
                strip.addArrangedSubview(card)
            }
        } catch { showError(error) }
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = strip
        strip.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            strip.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            strip.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            strip.heightAnchor.constraint(equalToConstant: 128),
            scroll.heightAnchor.constraint(equalToConstant: 140)
        ])
        let collection = GalleryStyle.column([collectionHeading, scroll], spacing: 10)
        let stack = GalleryStyle.column([header, body, collection], spacing: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo:content.leadingAnchor,constant:24),
            stack.trailingAnchor.constraint(equalTo:content.trailingAnchor,constant:-24),
            stack.topAnchor.constraint(equalTo:content.topAnchor,constant:12),
            stack.bottomAnchor.constraint(equalTo:content.bottomAnchor,constant:-16),
            stage.heightAnchor.constraint(equalTo: body.heightAnchor),
            inspectorScroll.heightAnchor.constraint(equalTo: body.heightAnchor),
            desktopButton.heightAnchor.constraint(equalToConstant: 40),
            pauseButton.heightAnchor.constraint(equalToConstant: 32)
        ])
        for view in [header, body, collection] { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        let inspectorViews: [NSView] = [metadata, artworkTitle, artworkDetails, artworkCaption, sliders,
                     speedStack, strengthStack, speedRow, strengthRow, speedSlider, strengthSlider,
                     pauseButton, actions, statusLabel, desktopButton, secondaryActions]
        for view in inspectorViews {
            view.widthAnchor.constraint(equalTo: inspector.widthAnchor).isActive = true
        }
        collectionHeading.widthAnchor.constraint(equalTo: collection.widthAnchor).isActive = true
        scroll.widthAnchor.constraint(equalTo: collection.widthAnchor).isActive = true
        body.setContentHuggingPriority(.defaultLow, for: .vertical)
        updateArtworkSelection()
        changeValues()
        window.center(); window.makeKeyAndOrderFront(nil)
        redraw()
    }
    @objc func changeValues() {
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
        artworkTitle.stringValue = engine.artwork.name
        artworkDetails.stringValue = "\(engine.artwork.artist) · \(engine.artwork.year)"
        artworkCaption.stringValue = engine.artwork.description
        for card in artworkCards {
            card.state = card.artwork == engine.artwork ? .on : .off
            card.needsDisplay = true
        }
    }
    func setArtworkSelectionEnabled(_ enabled: Bool) {
        for card in artworkCards { card.isEnabled = enabled; card.needsDisplay = true }
    }
    @objc func changeArtwork(_ sender: ArtworkCard) {
        let selected = sender.artwork
        do {
            try engine.select(selected)
            animation.phase = 0
            updateArtworkSelection()
            if verificationOutput == nil { UserDefaults.standard.set(selected.rawValue, forKey: "artwork") }
            redraw()
            refreshStatus()
        } catch {
            updateArtworkSelection()
            showError(error)
        }
    }
    @objc func toggleMask(_ sender: NSButton) { animation.showMask = sender.state == .on; redraw() }
    @objc func togglePause() {
        let paused = !animation.paused
        do { try WallpaperBridge.setPaused(paused) }
        catch { showError(error); return }
        animation.paused = paused
        pauseButton.title = animation.paused ? "继续播放" : "暂停播放"
        pauseButton.image = NSImage(systemSymbolName: animation.paused ? "play.fill" : "pause.fill", accessibilityDescription: nil)
        redraw()
    }
    func redraw() {
        let paused = animation.paused || sleepPaused
        preview.isPaused = paused || !window.isVisible || window.isMiniaturized
        if !sleepPaused && window.isVisible && !window.isMiniaturized { preview.draw() }
    }
    @objc func sleep() { sleepPaused = true; redraw() }
    @objc func wake() { sleepPaused = false; animation.last = CACurrentMediaTime(); redraw() }
    @objc func openWallpaperSettings() { WallpaperBridge.openSettings() }
    func refreshStatus() {
        guard statusLabel != nil, !exporting else { return }
        let defaults = UserDefaults.standard
        let pending = defaults.float(forKey:"appliedSpeed") != animation.speed
            || defaults.float(forKey:"appliedStrength") != animation.strength
            || defaults.integer(forKey:"appliedArtwork") != engine.artwork.rawValue
        if pending { statusLabel.stringValue = "预览有新变化，应用后更新桌面与锁屏。" }
        else if WallpaperBridge.isSelected { statusLabel.stringValue = "壁纸已启用，关闭窗口后仍会播放。" }
        else { statusLabel.stringValue = "在壁纸设置中选择「流动星夜」，屏幕保护程序设为与壁纸相同。" }
    }
    @objc func applyWallpaper() {
        guard !exporting else { return }
        do {
            let destination = try WallpaperBridge.prepareRender()
            let speed = animation.speed, strength = animation.strength
            let screen = NSScreen.main?.frame.size ?? NSSize(width:16,height:10)
            let width = 2560, height = Int((2560*screen.height/screen.width/2).rounded())*2
            exporting = true; desktopButton.isEnabled = false; exportButton.isEnabled = false; setArtworkSelectionEnabled(false)
            statusLabel.stringValue = "正在准备桌面与锁屏使用的循环动画…"
            DispatchQueue.global(qos:.userInitiated).async { [self] in
                do {
                    try engine.export(to:destination,width:width,height:height,speed:speed,strength:strength) { percent in
                        DispatchQueue.main.async { self.statusLabel.stringValue = "正在准备动画：\(Int(percent*100))%" }
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
                        self.statusLabel.stringValue = "应用未完成，原有壁纸保持不变。"; self.showError(error)
                    }
                }
            }
        } catch { showError(error) }
    }
    @objc func showWindow() { window.makeKeyAndOrderFront(nil); preview.isPaused = animation.paused; NSApp.activate(ignoringOtherApps:true) }
    func windowWillClose(_ notification: Notification) { preview.isPaused = true }
    func windowDidMiniaturize(_ notification: Notification) { preview.isPaused = true }
    func windowDidDeminiaturize(_ notification: Notification) { redraw() }
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
                        DispatchQueue.main.async { self.statusLabel.stringValue = "正在导出循环视频：\(Int(percent*100))%" }
                    }
                    DispatchQueue.main.async {
                        self.exporting = false; self.exportButton.isEnabled = true; self.desktopButton.isEnabled = true
                        self.setArtworkSelectionEnabled(true)
                        self.statusLabel.stringValue = "已导出 \(url.lastPathComponent)"
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.exporting = false; self.exportButton.isEnabled = true; self.desktopButton.isEnabled = true
                        self.setArtworkSelectionEnabled(true)
                        self.statusLabel.stringValue = "导出未完成，可重试。"; self.showError(error)
                    }
                }
            }
        }
    }
    func showError(_ error: Error) { let alert = NSAlert(error:error); alert.runModal() }
    @objc func about() {
        NSApp.orderFrontStandardAboutPanel(options:[.applicationName:"流动星夜",
            .applicationVersion:Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "",
            .credits:NSAttributedString(string:"本地动画制作与原生桌面、锁屏壁纸。\n壁纸扩展基于 Phosphene（MIT，© 2026 kageroumado）。")])
    }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if exporting {
            let alert = NSAlert(); alert.messageText = "视频仍在导出"; alert.informativeText = "退出会中断本次导出。"
            alert.addButton(withTitle:"继续等待"); alert.addButton(withTitle:"退出")
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
            case .waterLilies: anchors = [(0.74,0.26),(0.81,0.41),(0.6,0.78),(0.415,0.795),(0.6,0.765),(0.76,0.772)]
            case .wheatStacks: anchors = [(0.43,0.55),(0.22,0.6),(0.8,0.75),(0.67,0.275)]
            case .rhone: anchors = [(0.77,0.86),(0.22,0.49),(0.5,0.7),(0.5,0.6),(0.464,0.66),(0.43,0.715),(0.685,0.71)]
            case .cypresses: anchors = [(0.84,0.3),(0.5,0.6),(0.23,0.65),(0.836,0.09),(0.55,0.515),(0.235,0.7)]
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
            if selected == .wheatStacks {
                // Subtle local sky luminance has zero geometry displacement. Compare
                // opposite light phases at 1 LSB rather than requiring coarse blue shifts.
                let warm = try engine.pixels(time:6)
                let cool = try engine.pixels(time:18)
                changes = 0
                for i in stride(from:0,to:warm.count,by:4) {
                    if (0..<3).contains(where: { warm[i+$0] != cool[i+$0] }) { changes += 1 }
                }
            }
            let minimumChanges = selected == .wheatStacks ? 1000 : 200
            guard changes>minimumChanges else { throw failure("Insufficient motion: \(changes)") }
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
