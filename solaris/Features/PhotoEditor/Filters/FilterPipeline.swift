import MetalPetal

/// Composes an ordered list of `FilterStage`s into a single image→image transform.
struct FilterPipeline {
    let stages: [any FilterStage]

    /// The standard 15-stage pipeline matching the original render order.
    static func standard(grainSeed: Float = 0.0) -> FilterPipeline {
        FilterPipeline(stages: [
            SaturationStage(),
            VibranceStage(),
            ExposureStage(),
            BrightnessStage(),
            ContrastStage(),
            FadeStage(),
            OpacityStage(),
            PixelateStage(),
            ClarityStage(),
            SharpenStage(),
            ColorTintStage(),
            SkinToneStage(),
            ColorInvertStage(),
            VignetteStage(),
            GrainStage(seed: grainSeed),
        ])
    }

    /// Applies all non-neutral stages sequentially. Returns nil if any stage fails.
    func apply(to input: MTIImage, state: PhotoEditState) -> MTIImage? {
        var image = input
        for stage in stages {
            if stage.isNeutral(for: state) { continue }
            guard let result = stage.apply(to: image, state: state) else { return nil }
            image = result
        }
        return image
    }
}
