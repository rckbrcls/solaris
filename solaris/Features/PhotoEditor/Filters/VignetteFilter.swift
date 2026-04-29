import Foundation
import MetalPetal

final class VignetteFilter: NSObject, MTIFilter {
    var inputImage: MTIImage?
    var intensity: Float = 0.0 // 0..1
    var outputPixelFormat: MTLPixelFormat = .bgra8Unorm

    private struct Uniforms { let intensity: Float; let pad0: Float; let pad1: Float; let pad2: Float }

    private static let kernel: MTIRenderPipelineKernel = MetalFilterHelpers.makeKernel(fragmentFunction: "vignetteFragment")

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
        return out
    }
}

