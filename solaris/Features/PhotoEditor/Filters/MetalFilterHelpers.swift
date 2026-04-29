import Foundation
import MetalPetal

enum MetalFilterHelpers {
    static func makeKernel(fragmentFunction: String) -> MTIRenderPipelineKernel {
        let bundle = Bundle.main
        let libURL: URL? = (
            bundle.url(forResource: "default", withExtension: "metallib") ??
            (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String).flatMap { bundle.url(forResource: $0, withExtension: "metallib") } ??
            bundle.urls(forResourcesWithExtension: "metallib", subdirectory: nil)?.first
        )
        let vDesc: MTIFunctionDescriptor
        let fDesc: MTIFunctionDescriptor
        if let url = libURL {
            vDesc = MTIFunctionDescriptor(name: "passthroughVertex", libraryURL: url)
            fDesc = MTIFunctionDescriptor(name: fragmentFunction, libraryURL: url)
        } else {
            vDesc = MTIFunctionDescriptor(name: "passthroughVertex")
            fDesc = MTIFunctionDescriptor(name: fragmentFunction)
        }
        return MTIRenderPipelineKernel(vertexFunctionDescriptor: vDesc, fragmentFunctionDescriptor: fDesc)
    }
}
