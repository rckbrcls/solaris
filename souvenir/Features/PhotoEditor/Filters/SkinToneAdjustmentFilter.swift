import Foundation
import MetalPetal

final class SkinToneAdjustmentFilter: NSObject, MTIFilter {
    var outputPixelFormat: MTLPixelFormat = .unspecified
    
    // Kernel simples usando nossas funções no .metal (vertexPassthrough + skinToneFragment)
    private static let kernel = MTIRenderPipelineKernel(
        vertexFunctionDescriptor: MTIFunctionDescriptor(name: "vertexPassthrough"),
        fragmentFunctionDescriptor: MTIFunctionDescriptor(name: "skinToneFragment")
    )

    var inputImage: MTIImage?
    var intensity: Float = 0.0        // -1 .. 1
    var preserveLuma: Float = 0.8     // 0 .. 1
    var skinThresholdLow: Float = 0.05
    var skinThresholdHigh: Float = 0.95

    var outputImage: MTIImage? {
        guard let inputImage = inputImage else { return nil }
        if abs(intensity) < 0.001 { return inputImage }
        struct Uniforms { let intensity: Float; let preserveLuma: Float; let skinThresholdLow: Float; let skinThresholdHigh: Float }
        let uniforms = Uniforms(
            intensity: max(-1, min(1, intensity)),
            preserveLuma: max(0, min(1, preserveLuma)),
            skinThresholdLow: skinThresholdLow,
            skinThresholdHigh: skinThresholdHigh
        )
        var u = uniforms
        let data = Data(bytes: &u, count: MemoryLayout<Uniforms>.size)
        return Self.kernel.apply(
            to: [inputImage],
            parameters: ["u": data],
            outputDimensions: inputImage.dimensions
        )
    }
}
