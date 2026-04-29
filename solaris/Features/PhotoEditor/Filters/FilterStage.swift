import MetalPetal

/// A single stage in the GPU filter pipeline.
/// Each stage declares when it's neutral (can be skipped) and how to transform an MTIImage.
protocol FilterStage {
    var name: String { get }
    /// Returns true when the stage would produce no visible change for the given state.
    func isNeutral(for state: PhotoEditState) -> Bool
    /// Applies the transformation. Returns nil on failure.
    func apply(to image: MTIImage, state: PhotoEditState) -> MTIImage?
}
