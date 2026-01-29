import Foundation
import MetalPetal

final class VignetteFilter: NSObject, MTIFilter {
    var inputImage: MTIImage?
    var intensity: Float = 0.0 // 0..1
    var outputPixelFormat: MTLPixelFormat = .bgra8Unorm

    private struct Uniforms { let intensity: Float; let pad0: Float; let pad1: Float; let pad2: Float }

    private static let kernel: MTIRenderPipelineKernel = {
        // Try to resolve an explicit metallib if present; fallback to default.
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
            fDesc = MTIFunctionDescriptor(name: "vignetteFragment", libraryURL: url)
        } else {
            vDesc = MTIFunctionDescriptor(name: "lumaGrainVertex")
            fDesc = MTIFunctionDescriptor(name: "vignetteFragment")
        }
        return MTIRenderPipelineKernel(vertexFunctionDescriptor: vDesc, fragmentFunctionDescriptor: fDesc)
    }()

    var outputImage: MTIImage? {
        guard let inputImage else { return nil }
        let v = max(0, min(1, intensity))
        if v <= 0.0001 { return inputImage }
        var u = Uniforms(intensity: v, pad0: 0, pad1: 0, pad2: 0)
        let data = Data(bytes: &u, count: MemoryLayout<Uniforms>.size)
        let out = Self.kernel.apply(
            to: [inputImage],
            parameters: ["uv": data],
            outputDimensions: inputImage.dimensions,
            outputPixelFormat: outputPixelFormat
        )
        if out == nil {
            if let device = MTLCreateSystemDefaultDevice() {
                if let lib = try? device.makeDefaultLibrary(bundle: .main) {
                    print("[VignetteFilter] Default metallib functions: \(lib.functionNames)")
                } else {
                    print("[VignetteFilter] Failed to load default metallib from bundle.")
                }
            }
        }
        return out
    }
}

