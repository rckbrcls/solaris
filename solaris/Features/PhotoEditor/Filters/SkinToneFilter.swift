import Foundation
import MetalPetal

final class SkinToneFilter: NSObject, MTIFilter {
    var inputImage: MTIImage?
    // -1..1: negative cools, positive warms
    var amount: Float = 0.0
    // 0..1: softness around mask edge
    var softness: Float = 0.6
    // 0..1: protection near highlights
    var highlightProtect: Float = 0.5
    // 0..1: ignore pixels with saturation under this
    var saturationThreshold: Float = 0.06
    var outputPixelFormat: MTLPixelFormat = .bgra8Unorm

    private struct Uniforms { let amount: Float; let softness: Float; let highlightProtect: Float; let saturationThreshold: Float }

    private static let kernel: MTIRenderPipelineKernel = {
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
            fDesc = MTIFunctionDescriptor(name: "skinToneFragment", libraryURL: url)
        } else {
            vDesc = MTIFunctionDescriptor(name: "lumaGrainVertex")
            fDesc = MTIFunctionDescriptor(name: "skinToneFragment")
        }
        return MTIRenderPipelineKernel(vertexFunctionDescriptor: vDesc, fragmentFunctionDescriptor: fDesc)
    }()

    var outputImage: MTIImage? {
        guard let inputImage else { return nil }
        if abs(amount) <= 0.0001 { return inputImage }
        var u = Uniforms(
            amount: max(-1.0, min(1.0, amount)),
            softness: max(0.0, min(1.0, softness)),
            highlightProtect: max(0.0, min(1.0, highlightProtect)),
            saturationThreshold: max(0.0, min(1.0, saturationThreshold))
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

