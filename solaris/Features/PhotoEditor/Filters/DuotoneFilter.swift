import Foundation
import MetalPetal

final class DuotoneFilter: NSObject, MTIFilter {
    var inputImage: MTIImage?
    var shadowColor: SIMD3<Float> = SIMD3<Float>(0.0, 0.0, 0.0)
    var highlightColor: SIMD3<Float> = SIMD3<Float>(1.0, 1.0, 1.0)
    var intensity: Float = 1.0
    var factor: Float = 1.0
    var gamma: Float = 1.0
    var outputPixelFormat: MTLPixelFormat = .bgra8Unorm

    private struct Uniforms {
        let shadow_r: Float; let shadow_g: Float; let shadow_b: Float; let intensity: Float
        let highlight_r: Float; let highlight_g: Float; let highlight_b: Float; let factor: Float
        let gamma: Float; let pad0: Float; let pad1: Float; let pad2: Float
    }

    private static let kernel: MTIRenderPipelineKernel = MetalFilterHelpers.makeKernel(fragmentFunction: "duotoneFragment")

    var outputImage: MTIImage? {
        guard let inputImage else { return nil }
        let i = max(0, min(1, intensity))
        let f = max(0, min(1, factor))
        let g = max(0.01, gamma)
        var u = Uniforms(
            shadow_r: shadowColor.x, shadow_g: shadowColor.y, shadow_b: shadowColor.z, intensity: i,
            highlight_r: highlightColor.x, highlight_g: highlightColor.y, highlight_b: highlightColor.z, factor: f,
            gamma: g, pad0: 0, pad1: 0, pad2: 0
        )
        let data = Data(bytes: &u, count: MemoryLayout<Uniforms>.size)
        return Self.kernel.apply(
            to: [inputImage],
            parameters: ["u": data],
            outputDimensions: inputImage.dimensions,
            outputPixelFormat: outputPixelFormat
        )
    }
}

