import Foundation
import MetalPetal

final class LumaGrainFilter: NSObject, MTIFilter {
    var inputImage: MTIImage?
    var grain: Float = 0.0
    var grainSize: Float = 0.0
    var seed: Float = 0.0
    // Force 8-bit BGRA to reduce memory footprint on large images
    var outputPixelFormat: MTLPixelFormat = .bgra8Unorm

    private struct Uniforms { let strength: Float; let size: Float; let seed: Float; let pad: Float }

    private static let kernel: MTIRenderPipelineKernel = {
        // Try to point function descriptors to an explicit metallib if present.
        let bundle = Bundle.main
        let libURL: URL? = (
            bundle.url(forResource: "default", withExtension: "metallib") ??
            (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String).flatMap { bundle.url(forResource: $0, withExtension: "metallib") } ??
            bundle.urls(forResourcesWithExtension: "metallib", subdirectory: nil)?.first
        )
        let vDesc: MTIFunctionDescriptor
        let fDesc: MTIFunctionDescriptor
        if let url = libURL {
            vDesc = MTIFunctionDescriptor(name: "lumaGrainVertex", libraryURL: url)
            fDesc = MTIFunctionDescriptor(name: "lumaGrainFragment", libraryURL: url)
        } else {
            vDesc = MTIFunctionDescriptor(name: "lumaGrainVertex")
            fDesc = MTIFunctionDescriptor(name: "lumaGrainFragment")
        }
        return MTIRenderPipelineKernel(
            vertexFunctionDescriptor: vDesc,
            fragmentFunctionDescriptor: fDesc
        )
    }()

    private func shapedStrength(from grain: Float) -> Float {
        // Map slider 0..0.1 -> 0..1 for better range
        let k = max(0.0, min(1.0, grain * 10.0))
        // Slightly sublinear for fine control at low values
        let shaped = pow(k, 0.50)
        // Increase max amplitude for a stronger grain
        return 0.80 * shaped
    }

    var outputImage: MTIImage? {
        guard let inputImage else { return nil }
        if grain <= 0.0001 { return inputImage }
        var u = Uniforms(
            strength: shapedStrength(from: grain),
            size: max(0, min(1, grainSize)),
            seed: seed,
            pad: 0
        )
        let data = Data(bytes: &u, count: MemoryLayout<Uniforms>.size)
        let out = Self.kernel.apply(
            to: [inputImage],
            parameters: ["u": data],
            outputDimensions: inputImage.dimensions,
            outputPixelFormat: outputPixelFormat
        )
        if out == nil {
            // Helpful diagnostics if shader functions are missing from the default library.
            if let device = MTLCreateSystemDefaultDevice() {
                if let lib = try? device.makeDefaultLibrary(bundle: .main) {
                    let names = lib.functionNames
                    print("[LumaGrainFilter] Default metallib functions: \(names)")
                    let hasV = names.contains("lumaGrainVertex")
                    let hasF = names.contains("lumaGrainFragment")
                    print("[LumaGrainFilter] has lumaGrainVertex: \(hasV), has lumaGrainFragment: \(hasF)")
                } else {
                    print("[LumaGrainFilter] Failed to load default metallib from bundle.")
                }
            } else {
                print("[LumaGrainFilter] No MTLDevice available.")
            }
        }
        return out
    }
}
