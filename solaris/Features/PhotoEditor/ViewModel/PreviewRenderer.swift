import UIKit
import MetalPetal
import os.log

/// Handles GPU rendering of preview and final images using the FilterPipeline.
final class PreviewRenderer {
    private let mtiContext: MTIContext?
    private let pipeline: FilterPipeline

    private(set) var previewBaseHigh: UIImage?
    private(set) var previewBaseLow: UIImage?
    private(set) var previewBase: UIImage?

    init(grainSeed: Float = 0.0) {
        self.mtiContext = try? MTIContext(device: MTLCreateSystemDefaultDevice()!)
        self.pipeline = FilterPipeline.standard(grainSeed: grainSeed)
    }

    // MARK: - Preview Bases

    func buildPreviewBases(from original: UIImage?) {
        let highPoints = PhotoEditorHelper.suggestedPreviewMaxPoints(doubleTapZoomScale: 3.0)
        let lowPoints = PhotoEditorHelper.suggestedPreviewMaxPoints(doubleTapZoomScale: 2.0)
        previewBaseHigh = original?.resizeToFit(maxSize: highPoints)
        previewBaseLow = original?.resizeToFit(maxSize: lowPoints)
        previewBase = previewBaseHigh
    }

    func switchToLowRes() {
        if let low = previewBaseLow { previewBase = low }
    }

    func switchToHighRes() {
        if let high = previewBaseHigh { previewBase = high }
    }

    /// Low-res base for filter thumbnails.
    var previewThumbnailBase: UIImage? {
        previewBaseLow ?? previewBase
    }

    // MARK: - Preview Generation

    func generatePreview(state: PhotoEditState) -> UIImage? {
        guard let base = previewBase?.withAlpha(),
              let cgImage = base.cgImage,
              let mtiContext else { return nil }
        let mtiImage = Self.makeMTIImage(from: cgImage)
        guard let pipelineResult = pipeline.apply(to: mtiImage, state: state) else { return nil }
        do {
            let cgimg = try mtiContext.makeCGImage(from: pipelineResult)
            return UIImage(cgImage: cgimg)
        } catch {
            os_log("[PreviewRenderer] Failed to generate preview: %{public}@", String(describing: error))
            return nil
        }
    }

    // MARK: - Final Image

    func generateFinalImage(originalURL: URL?, originalData: Data?, originalImage: UIImage?, state: PhotoEditState) -> UIImage? {
        var sourceUIImage: UIImage?
        // Use CGImageSource-based loading to preserve color profile and bit depth
        if let url = originalURL, let data = try? Data(contentsOf: url) {
            sourceUIImage = loadUIImageFullQuality(from: data)
        } else if let data = originalData {
            sourceUIImage = loadUIImageFullQuality(from: data)
        } else {
            sourceUIImage = originalImage
        }
        let oriented = sourceUIImage?.fixOrientation()
        guard let base = oriented?.withAlpha(),
              let cgImage = base.cgImage,
              let mtiContext else { return nil }
        let mtiImage = Self.makeMTIImage(from: cgImage)
        guard let pipelineResult = pipeline.apply(to: mtiImage, state: state) else { return nil }
        do {
            let cgimg = try mtiContext.makeCGImage(from: pipelineResult)
            return UIImage(cgImage: cgimg)
        } catch {
            return nil
        }
    }

    // MARK: - MTIImage Factory

    /// Creates an MTIImage with the correct color space interpretation.
    /// Uses `.SRGB: false` for P3/wide-gamut images so MetalPetal processes in the native color space.
    private static func makeMTIImage(from cgImage: CGImage) -> MTIImage {
        let isWideGamut = cgImage.colorSpace?.name == CGColorSpace.displayP3
            || cgImage.colorSpace?.name == CGColorSpace.dcip3
        return MTIImage(cgImage: cgImage, options: [.SRGB: !isWideGamut], isOpaque: true)
    }
}
