import Foundation
import CoreImage

enum LumaGrain {
    private static let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])

    static let kernel: CIColorKernel? = {
        let bundle = Bundle.main
        if let url = bundle.url(forResource: "LumaGrain", withExtension: "cikernel", subdirectory: "Features/PhotoEditor/Processing/Shaders"),
           let src = try? String(contentsOf: url),
           let k = CIColorKernel(source: src) {
            return k
        }
        if let url = bundle.url(forResource: "LumaGrain", withExtension: "cikernel"),
           let src = try? String(contentsOf: url),
           let k = CIColorKernel(source: src) {
            return k
        }
        return nil
    }()

    static func strength(for grain: Float) -> Float {
        let baseK = max(0.0, min(1.0, grain * 48.0))
        let shaped = pow(baseK, 0.55)
        return 0.40 * shaped
    }

    static func apply(to image: CIImage, grain: Float, grainSize: Float, seed: Float = 0.0) -> CIImage {
        guard grain > 0, let kernel = kernel else { return image }
        let strength = strength(for: grain)
        return kernel.apply(extent: image.extent, arguments: [image, strength, grainSize, seed]) ?? image
    }

    static func applyToCGImage(_ cgImage: CGImage, grain: Float, grainSize: Float, seed: Float = 0.0) -> CGImage {
        guard grain > 0, let _ = kernel else { return cgImage }
        let base = CIImage(cgImage: cgImage)
        let out = apply(to: base, grain: grain, grainSize: grainSize, seed: seed)
        return context.createCGImage(out, from: out.extent) ?? cgImage
    }
}

