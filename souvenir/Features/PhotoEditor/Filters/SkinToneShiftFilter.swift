import Foundation
import MetalPetal

final class SkinToneShiftFilter: NSObject, MTIFilter {
    private static let kernel = MTIRenderPipelineKernel(
        vertexFunctionDescriptor: MTIFunctionDescriptor(name: "skinToneVertex"),
        fragmentFunctionDescriptor: MTIFunctionDescriptor(name: "skinToneShiftFragment")
    )

    var inputImage: MTIImage?
    var amount: Float = 0.0                // -1..1
    var preserveLuma: Float = 0.85         // 0..1
    var saturationLow: Float = 0.05
    var saturationHigh: Float = 0.25
    var highlightStart: Float = 0.78
    var highlightEnd: Float = 0.92
    var outputPixelFormat: MTLPixelFormat = .unspecified

    var outputImage: MTIImage? {
        guard let inputImage = inputImage else { return nil }
        if abs(amount) < 0.001 { return inputImage }
        struct Uniforms { let amount: Float; let satLow: Float; let satHigh: Float; let hiStart: Float; let hiEnd: Float; let preserveLuma: Float }
        let uniforms = Uniforms(
            amount: max(-1, min(1, amount)),
            satLow: saturationLow,
            satHigh: saturationHigh,
            hiStart: highlightStart,
            hiEnd: highlightEnd,
            preserveLuma: max(0, min(1, preserveLuma))
        )
        var u = uniforms
        let data = Data(bytes: &u, count: MemoryLayout<Uniforms>.size)
        return Self.kernel.apply(to: [inputImage], parameters: ["u": data], outputDimensions: inputImage.dimensions)
    }
}
