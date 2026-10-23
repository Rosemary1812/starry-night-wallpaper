import AppKit
import CoreImage

extension Engine {
    func captureStudyCycle(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let width = 640, height = Int((640.0 * Double(painting.height) / Double(painting.width)).rounded())
        func save(_ data: Data, _ name: String) throws {
            let image = CGImage(width:width,height:height,bitsPerComponent:8,bitsPerPixel:32,
                bytesPerRow:width*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,
                bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                provider:CGDataProvider(data:data as CFData)!,decode:nil,shouldInterpolate:false,intent:.defaultIntent)!
            try NSBitmapImageRep(cgImage:image).representation(using:.png,properties:[:])!.write(to:directory.appendingPathComponent(name))
        }
        try save(pixels(time:0,strength:0,width:width,height:height),"neutral.png")
        try save(pixels(time:0,maskMode:true,width:width,height:height),"overlay.png")
        for i in 0...720 {
            try autoreleasepool {
                try save(pixels(time:Float(i)/30,width:width,height:height),String(format:"frame-%04d.png",i))
            }
        }
        print("Captured 721 native Metal frames: \(artwork.filename), 640×\(height), strength 1.4, 30 fps, 24 s")
    }

    static func studyMask(artwork: Artwork) throws -> CGImage {
        let size = 2048
        guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
            bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw failure("Mask allocation failed") }
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        ctx.translateBy(x: 0, y: CGFloat(size))
        ctx.scaleBy(x: CGFloat(size), y: -CGFloat(size))
        func region(_ points: [(Double, Double)], _ color: CGColor) {
            ctx.setFillColor(color)
            ctx.beginPath()
            ctx.move(to: CGPoint(x: points[0].0, y: points[0].1))
            for p in points.dropFirst() { ctx.addLine(to: CGPoint(x:p.0,y:p.1)) }
            ctx.closePath(); ctx.fillPath()
        }
        let white = CGColor(gray: 1, alpha: 1)
        switch artwork {
        case .theScream:
            // Only sky bands below the inscription, above the fjord and figures.
            region([(0.045,0.105),(0.895,0.105),(0.895,0.255),(0.77,0.265),
                    (0.6,0.30),(0.45,0.315),(0.28,0.30),(0.045,0.29)], white)
        case .circularForms:
            // Independent RGB motion groups, with quiet margins between overlapping circles.
            for (rect, color) in [
                (CGRect(x:0.07,y:0.05,width:0.32,height:0.59), CGColor(red:1,green:0,blue:0,alpha:1)),
                (CGRect(x:0.46,y:0.04,width:0.51,height:0.91), CGColor(red:0,green:1,blue:0,alpha:1)),
                (CGRect(x:0.765,y:0.10,width:0.16,height:0.25), CGColor(red:0,green:0,blue:1,alpha:1))] {
                ctx.setFillColor(color); ctx.fillEllipse(in: rect)
            }
        case .concentricCircles:
            for row in 0..<3 { for col in 0..<4 {
                let color = (row + col) % 3
                ctx.setFillColor(CGColor(red:color == 0 ? 1 : 0,green:color == 1 ? 1 : 0,
                    blue:color == 2 ? 1 : 0,alpha:1))
                ctx.fillEllipse(in:CGRect(x:Double(col)/4+0.035,y:Double(row)/3+0.045,width:0.18,height:0.24))
            } }
        default: break
        }
        guard let raw = ctx.makeImage() else { throw failure("Mask image failed") }
        let softened = CIImage(cgImage:raw).clampedToExtent()
            .applyingFilter("CIGaussianBlur",parameters:[kCIInputRadiusKey:8])
        guard let result = CIContext().createCGImage(softened,from:CGRect(x:0,y:0,width:size,height:size)) else {
            throw failure("Mask smoothing failed")
        }
        return try crop(result,artwork:artwork)
    }
}
