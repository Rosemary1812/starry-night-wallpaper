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
        } else if artwork == .impressionSunrise {
            // Full-image coordinates for the Commons 5773 × 4478 reproduction.
            // Preserve the sun and industrial skyline; only the open water moves.
            protect([(0,0),(1,0),(1,0.55),(0,0.55)])
            // Foreground rowing boat, both figures, and their painted contours.
            protect([(0.415,0.692),(0.444,0.636),(0.490,0.636),(0.506,0.682),
                (0.538,0.692),(0.546,0.742),(0.521,0.773),(0.448,0.778),
                (0.415,0.741)])
            // Middle and distant boats, including the small upright figures.
            protect([(0.227,0.603),(0.257,0.565),(0.310,0.565),(0.326,0.598),
                (0.353,0.616),(0.361,0.649),(0.327,0.674),(0.255,0.670),
                (0.225,0.642)])
            protect([(0.125,0.552),(0.164,0.532),(0.199,0.543),
                (0.229,0.574),(0.216,0.602),(0.150,0.590)])
            // The artist's signature is part of the painting, not moving water.
            protect([(0.030,0.915),(0.261,0.915),(0.261,0.986),(0.030,0.986)])
        } else if artwork == .waterlooBridge {
            // Waterloo Bridge, Sunlight: protect architecture, figures and signatures.
            protect([(0.000000,0.000000),(1.000000,0.000000),(1.000000,0.659000),(0.980000,0.650000),(0.963000,0.635000),
                (0.943000,0.632000),(0.921000,0.639000),(0.901000,0.658000),(0.884000,0.668000),(0.866000,0.667000),
                (0.856000,0.641000),(0.849000,0.615000),(0.835000,0.594000),(0.816000,0.583000),(0.795000,0.585000),
                (0.774000,0.597000),(0.754000,0.619000),(0.740000,0.649000),(0.734000,0.679000),(0.712000,0.684000),
                (0.698000,0.666000),(0.692000,0.640000),(0.680000,0.612000),(0.665000,0.592000),(0.643000,0.579000),
                (0.621000,0.579000),(0.600000,0.587000),(0.578000,0.606000),(0.559000,0.633000),(0.546000,0.660000),
                (0.541000,0.685000),(0.518000,0.686000),(0.503000,0.670000),(0.492000,0.644000),(0.476000,0.623000),
                (0.456000,0.604000),(0.434000,0.591000),(0.408000,0.588000),(0.384000,0.596000),(0.361000,0.609000),
                (0.340000,0.628000),(0.320000,0.652000),(0.305000,0.682000),(0.298000,0.718000),(0.292000,0.733000),
                (0.270000,0.736000),(0.253000,0.730000),(0.241000,0.709000),(0.230000,0.683000),(0.212000,0.660000),
                (0.191000,0.640000),(0.170000,0.626000),(0.143000,0.618000),(0.118000,0.621000),(0.091000,0.636000),
                (0.063000,0.657000),(0.039000,0.685000),(0.020000,0.717000),(0.000000,0.745000)])
            protect([(0.793000,0.933000),(1.000000,0.933000),(1.000000,1.000000),(0.793000,1.000000)])
        } else if artwork == .nocturneBognor {
            // Nocturne: Blue and Silver—Bognor: protect architecture, figures and signatures.
            protect([(0.000000,0.000000),(1.000000,0.000000),(1.000000,0.365000),(0.000000,0.365000)])
            protect([(0.000000,0.338000),(0.059000,0.338000),(0.070000,0.398000),(0.064000,0.488000),(0.071000,0.563000),
                (0.047000,0.592000),(0.000000,0.601000)])
            protect([(0.088000,0.335000),(0.119000,0.335000),(0.127000,0.391000),(0.147000,0.460000),(0.175000,0.525000),
                (0.198000,0.567000),(0.199000,0.602000),(0.177000,0.626000),(0.134000,0.627000),(0.086000,0.615000),
                (0.074000,0.592000),(0.073000,0.563000),(0.092000,0.533000),(0.085000,0.459000),(0.080000,0.395000)])
            protect([(0.305000,0.274000),(0.327000,0.274000),(0.342000,0.328000),(0.345000,0.389000),(0.351000,0.451000),
                (0.367000,0.526000),(0.382000,0.569000),(0.383000,0.608000),(0.367000,0.632000),(0.336000,0.640000),
                (0.307000,0.637000),(0.287000,0.616000),(0.278000,0.579000),(0.280000,0.558000),(0.300000,0.540000),
                (0.301000,0.466000),(0.293000,0.392000),(0.299000,0.325000)])
            protect([(0.791000,0.282000),(0.812000,0.282000),(0.816000,0.343000),(0.830000,0.391000),(0.826000,0.435000),
                (0.830000,0.467000),(0.844000,0.489000),(0.842000,0.527000),(0.820000,0.553000),(0.797000,0.561000),
                (0.782000,0.538000),(0.760000,0.523000),(0.747000,0.509000),(0.753000,0.491000),(0.776000,0.478000),
                (0.790000,0.446000),(0.790000,0.402000),(0.786000,0.353000)])
            protect([(0.000000,0.781000),(0.071000,0.779000),(0.136000,0.776000),(0.163000,0.771000),(0.170000,0.815000),
                (0.190000,0.813000),(0.190000,0.762000),(0.211000,0.755000),(0.229000,0.770000),(0.236000,0.823000),
                (0.250000,0.824000),(0.249000,0.777000),(0.266000,0.778000),(0.288000,0.791000),(0.301000,0.816000),
                (0.371000,0.817000),(0.441000,0.827000),(0.530000,0.837000),(0.641000,0.844000),(0.747000,0.852000),
                (0.843000,0.849000),(0.928000,0.847000),(1.000000,0.850000),(1.000000,1.000000),(0.000000,1.000000)])
            protect([(0.967000,0.744000),(1.000000,0.744000),(1.000000,0.901000),(0.967000,0.901000)])
        } else if artwork == .approachVenice {
            // Approach to Venice: protect architecture, figures and signatures.
            protect([(0.000000,0.000000),(1.000000,0.000000),(1.000000,0.663000),(0.000000,0.663000)])
            protect([(0.177000,0.640000),(0.209000,0.640000),(0.221000,0.657000),(0.218000,0.688000),(0.174000,0.688000)])
            protect([(0.276000,0.640000),(0.316000,0.638000),(0.319000,0.677000),(0.316000,0.717000),(0.286000,0.716000),
                (0.272000,0.690000)])
            protect([(0.142000,0.757000),(0.170000,0.749000),(0.195000,0.741000),(0.229000,0.740000),(0.252000,0.752000),
                (0.266000,0.731000),(0.280000,0.735000),(0.283000,0.764000),(0.310000,0.761000),(0.330000,0.788000),
                (0.353000,0.785000),(0.380000,0.797000),(0.390000,0.826000),(0.390000,0.857000),(0.420000,0.881000),
                (0.434000,0.890000),(0.431000,0.910000),(0.394000,0.898000),(0.389000,0.941000),(0.363000,0.978000),
                (0.318000,1.000000),(0.176000,1.000000),(0.151000,0.969000),(0.144000,0.939000),(0.159000,0.920000),
                (0.151000,0.882000),(0.144000,0.837000)])
            protect([(0.469000,0.683000),(0.483000,0.674000),(0.499000,0.677000),(0.505000,0.691000),(0.523000,0.689000),
                (0.540000,0.706000),(0.553000,0.729000),(0.574000,0.735000),(0.573000,0.750000),(0.548000,0.744000),
                (0.548000,0.774000),(0.520000,0.790000),(0.490000,0.791000),(0.473000,0.781000),(0.472000,0.753000),
                (0.431000,0.755000),(0.403000,0.769000),(0.394000,0.756000),(0.422000,0.736000),(0.424000,0.724000),
                (0.437000,0.708000),(0.468000,0.696000)])
            protect([(0.565000,0.742000),(0.583000,0.736000),(0.585000,0.717000),(0.598000,0.714000),(0.603000,0.730000),
                (0.625000,0.727000),(0.643000,0.736000),(0.650000,0.761000),(0.663000,0.772000),(0.661000,0.799000),
                (0.645000,0.811000),(0.612000,0.808000),(0.582000,0.789000),(0.563000,0.765000)])
            protect([(0.713000,0.693000),(0.728000,0.680000),(0.740000,0.686000),(0.743000,0.702000),(0.773000,0.701000),
                (0.795000,0.708000),(0.805000,0.696000),(0.821000,0.714000),(0.833000,0.716000),(0.836000,0.733000),
                (0.859000,0.736000),(0.864000,0.758000),(0.846000,0.770000),(0.830000,0.767000),(0.809000,0.782000),
                (0.777000,0.789000),(0.741000,0.778000),(0.719000,0.751000)])
            protect([(0.948000,0.750000),(0.963000,0.748000),(0.978000,0.744000),(1.000000,0.752000),(1.000000,0.835000),
                (0.963000,0.822000),(0.944000,0.807000),(0.927000,0.791000),(0.922000,0.774000),(0.943000,0.779000)])
        } else if artwork == .cliffWalk {
            // Cliff Walk at Pourville: protect architecture, figures and signatures.
            protect([(0.000000,0.357000),(1.000000,0.357000),(1.000000,0.458000),(0.000000,0.458000)])
            protect([(0.658000,0.338000),(0.680000,0.335000),(0.700000,0.347000),(0.709000,0.368000),(0.708000,0.394000),
                (0.696000,0.407000),(0.695000,0.424000),(0.712000,0.447000),(0.711000,0.490000),(0.700000,0.503000),
                (0.674000,0.504000),(0.656000,0.495000),(0.652000,0.513000),(0.642000,0.545000),(0.630000,0.554000),
                (0.608000,0.544000),(0.598000,0.525000),(0.608000,0.501000),(0.615000,0.484000),(0.617000,0.456000),
                (0.617000,0.430000),(0.614000,0.414000),(0.622000,0.398000),(0.640000,0.395000),(0.651000,0.413000),
                (0.660000,0.420000),(0.667000,0.402000),(0.656000,0.390000),(0.651000,0.369000)])
            protect([(0.998000,0.164000),(0.974000,0.184000),(0.949000,0.225000),(0.939000,0.249000),(0.916000,0.256000),
                (0.905000,0.280000),(0.899000,0.316000),(0.887000,0.351000),(0.874000,0.386000),(0.871000,0.418000),
                (0.872000,0.463000),(0.899000,0.494000),(0.938000,0.507000),(1.000000,0.518000),(1.000000,0.164000)])
            protect([(0.507000,0.392000),(0.552000,0.400000),(0.581000,0.417000),(0.615000,0.435000),(0.627000,0.459000),
                (0.603000,0.475000),(0.571000,0.476000),(0.552000,0.500000),(0.535000,0.538000),(0.520000,0.591000),
                (0.508000,0.651000),(0.491000,0.706000),(0.474000,0.750000),(0.461000,0.794000),(0.425000,0.811000),
                (0.395000,0.803000),(0.394000,0.779000),(0.406000,0.748000),(0.419000,0.719000),(0.422000,0.673000),
                (0.425000,0.634000),(0.419000,0.592000),(0.412000,0.554000),(0.411000,0.524000),(0.405000,0.500000),
                (0.410000,0.473000),(0.424000,0.450000),(0.441000,0.439000),(0.458000,0.415000),(0.478000,0.403000)])
            protect([(0.622000,0.515000),(0.652000,0.512000),(0.673000,0.536000),(0.691000,0.565000),(0.696000,0.596000),
                (0.682000,0.624000),(0.671000,0.650000),(0.648000,0.688000),(0.627000,0.722000),(0.608000,0.757000),
                (0.590000,0.797000),(0.589000,0.829000),(0.615000,0.864000),(0.648000,0.908000),(0.660000,0.951000),
                (0.663000,1.000000),(0.534000,1.000000),(0.539000,0.958000),(0.528000,0.920000),(0.504000,0.883000),
                (0.509000,0.848000),(0.534000,0.808000),(0.552000,0.773000),(0.576000,0.733000),(0.595000,0.698000),
                (0.611000,0.661000),(0.625000,0.629000),(0.630000,0.600000),(0.615000,0.574000),(0.606000,0.546000)])
            protect([(0.842000,0.944000),(0.996000,0.944000),(0.996000,0.996000),(0.842000,0.996000)])
        } else if artwork == .bridgeVilleneuve {
            // The Bridge at Villeneuve-la-Garenne: preserve painted structures and figures.
            protect([(0.000000,0.000000),(1.000000,0.000000),(1.000000,0.713000),(0.940000,0.713000),(0.890000,0.714000),
                (0.820000,0.710000),(0.770000,0.711000),(0.700000,0.710000),(0.653000,0.716000),(0.641000,0.727000),
                (0.614000,0.728000),(0.590000,0.725000),(0.562000,0.733000),(0.535000,0.733000),(0.505000,0.733000),
                (0.480000,0.727000),(0.445000,0.731000),(0.415000,0.724000),(0.380000,0.722000),(0.352000,0.720000),
                (0.331000,0.705000),(0.306000,0.715000),(0.281000,0.705000),(0.253000,0.698000),(0.222000,0.699000),
                (0.210000,0.715000),(0.205000,0.750000),(0.205000,0.820000),(0.000000,0.820000)])
            protect([(0.219000,0.671000),(0.248000,0.671000),(0.256000,0.699000),(0.261000,0.720000),(0.285000,0.720000),
                (0.299000,0.716000),(0.310000,0.721000),(0.316000,0.732000),(0.338000,0.731000),(0.354000,0.748000),
                (0.355000,0.776000),(0.333000,0.786000),(0.292000,0.788000),(0.252000,0.782000),(0.225000,0.773000),
                (0.219000,0.749000)])
            protect([(0.082000,0.917000),(0.231000,0.917000),(0.234000,0.967000),(0.080000,0.967000)])
        } else if artwork == .parliamentSunset {
            // The Houses of Parliament, Sunset: preserve painted structures and figures.
            protect([(0.000000,0.000000),(1.000000,0.000000),(1.000000,0.777000),(0.977000,0.769000),(0.955000,0.760000),
                (0.926000,0.758000),(0.900000,0.750000),(0.866000,0.744000),(0.811000,0.749000),(0.758000,0.745000),
                (0.723000,0.741000),(0.683000,0.734000),(0.630000,0.733000),(0.590000,0.737000),(0.550000,0.735000),
                (0.510000,0.739000),(0.465000,0.732000),(0.400000,0.735000),(0.336000,0.732000),(0.280000,0.726000),
                (0.230000,0.735000),(0.170000,0.731000),(0.145000,0.722000),(0.136000,0.694000),(0.129000,0.666000),
                (0.100000,0.655000),(0.045000,0.660000),(0.000000,0.660000)])
            protect([(0.513000,0.745000),(0.550000,0.741000),(0.550000,0.718000),(0.559000,0.695000),(0.580000,0.674000),
                (0.596000,0.687000),(0.610000,0.716000),(0.614000,0.740000),(0.646000,0.741000),(0.648000,0.733000),
                (0.671000,0.730000),(0.687000,0.738000),(0.699000,0.746000),(0.732000,0.750000),(0.741000,0.772000),
                (0.710000,0.783000),(0.657000,0.784000),(0.614000,0.778000),(0.575000,0.778000),(0.542000,0.774000),
                (0.514000,0.765000)])
            protect([(0.811000,0.765000),(0.842000,0.764000),(0.854000,0.771000),(0.856000,0.784000),(0.812000,0.787000)])
            protect([(0.865000,0.757000),(0.894000,0.753000),(0.905000,0.760000),(0.907000,0.776000),(0.864000,0.779000)])
            protect([(0.926000,0.737000),(0.955000,0.735000),(0.973000,0.727000),(0.987000,0.737000),(0.989000,0.761000),
                (0.976000,0.770000),(0.938000,0.767000),(0.925000,0.757000)])
            protect([(0.848000,0.792000),(0.877000,0.787000),(0.902000,0.791000),(0.910000,0.809000),(0.885000,0.819000),
                (0.852000,0.818000)])
            protect([(0.922000,0.776000),(0.949000,0.770000),(0.965000,0.778000),(0.968000,0.795000),(0.940000,0.803000),
                (0.922000,0.797000)])
            protect([(0.746000,0.941000),(1.000000,0.941000),(1.000000,1.000000),(0.746000,1.000000)])
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
    private(set) var presentedFrames = 0
    private(set) var presentedArtwork: Artwork?
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
            let generation = revealGeneration
            let artwork = engine.artwork
            let completion: MTLCommandBufferHandler = { [weak self] buffer in
                guard buffer.status == .completed else { return }
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    presentedFrames += 1
                    presentedArtwork = artwork
                    if waitingToReveal, revealGeneration == generation {
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
        let primary = GalleryActionButton(title: L10n.tr("button.setWallpaper"), target: self, action: #selector(applyWallpaper))
        primary.prominent = true
        primary.font = .systemFont(ofSize: 13, weight: .medium)
        primary.isBordered = false
        desktopButton = primary
        desktopButton.keyEquivalent = "\r"
        adjustButton = GalleryActionButton(title: L10n.tr("button.adjust"), target: self, action: #selector(showAdjustments(_:)))
        adjustButton.font = .systemFont(ofSize: 13)
        adjustButton.controlSize = .regular
        adjustButton.isBordered = false
        moreButton = GalleryActionButton(title: "", target: self, action: #selector(showMore(_:)))
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
        previousButton?.isEnabled = !exporting
        nextButton?.isEnabled = !exporting
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
        previousButton?.isEnabled = enabled
        nextButton?.isEnabled = enabled
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
        statusLabel.isHidden = !hasPublished || pending
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
            statusLabel.isHidden = false
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
            statusLabel.isHidden = false
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
            case .waterLilies: anchors = [(0.74,0.26),(0.81,0.41),(0.6,0.78),(0.415,0.795),(0.6,0.765),(0.76,0.772)]
            case .wheatStacks: anchors = [(0.43,0.55),(0.22,0.6),(0.8,0.75),(0.67,0.275)]
            case .rhone: anchors = [(0.77,0.86),(0.22,0.49),(0.5,0.7),(0.5,0.6),(0.464,0.66),(0.43,0.715),(0.685,0.71)]
            case .cypresses: anchors = [(0.84,0.3),(0.5,0.6),(0.23,0.65),(0.836,0.09),(0.55,0.515),(0.235,0.7)]
            case .impressionSunrise: anchors = [(0.609,0.309),(0.48,0.71),(0.459,0.663),(0.451,0.681),
                (0.29,0.63),(0.305,0.589),(0.18,0.57),(0.80,0.44),(0.12,0.95)]
            case .waterlooBridge: anchors = [(0.487,0.31),(0.146,0.51),(0.145,0.573),(0.268,0.693),(0.522,0.606),(0.716,0.607),(0.894,0.966)]
            case .nocturneBognor: anchors = [(0.541,0.184),(0.527,0.337),(0.12,0.54),(0.326,0.554),(0.804,0.421),(0.171,0.859),(0.209,0.814),(0.272,0.849),(0.984,0.779),(0.569,0.941)]
            case .approachVenice: anchors = [(0.216,0.553),(0.637,0.534),(0.246,0.816),(0.276,0.897),(0.357,0.848),(0.51,0.736),(0.615,0.768),(0.785,0.737),(0.98,0.788)]
            case .cliffWalk: anchors = [(0.673,0.366),(0.637,0.416),(0.671,0.46),(0.629,0.516),(0.65,0.593),(0.444,0.625),(0.951,0.341),(0.917,0.971),(0.209,0.381),(0.274,0.434)]
            case .bridgeVilleneuve: anchors = [(0.164,0.23),(0.325,0.444),(0.125,0.68),(0.561,0.46),(0.504,0.586),(0.408,0.622),(0.237,0.714),(0.278,0.76),(0.476,0.701),(0.627,0.688),(0.142,0.94)]
            case .parliamentSunset: anchors = [(0.368,0.235),(0.416,0.403),(0.811,0.287),(0.68,0.545),(0.267,0.61),(0.917,0.665),(0.584,0.72),(0.657,0.757),(0.956,0.754),(0.885,0.771),(0.889,0.971)]
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
