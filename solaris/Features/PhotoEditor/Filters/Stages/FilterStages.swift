import MetalPetal
import os.log

// MARK: - 1. Saturation

struct SaturationStage: FilterStage {
    let name = "Saturation"
    func isNeutral(for state: PhotoEditState) -> Bool { state.saturation == 1.0 }
    func apply(to image: MTIImage, state: PhotoEditState) -> MTIImage? {
        let f = MTISaturationFilter()
        f.inputImage = image
        f.saturation = state.saturation
        return f.outputImage
    }
}

// MARK: - 2. Vibrance

struct VibranceStage: FilterStage {
    let name = "Vibrance"
    func isNeutral(for state: PhotoEditState) -> Bool { state.vibrance == 0.0 }
    func apply(to image: MTIImage, state: PhotoEditState) -> MTIImage? {
        let f = MTIVibranceFilter()
        f.inputImage = image
        f.amount = state.vibrance
        return f.outputImage
    }
}

// MARK: - 3. Exposure

struct ExposureStage: FilterStage {
    let name = "Exposure"
    func isNeutral(for state: PhotoEditState) -> Bool { state.exposure == 0.0 }
    func apply(to image: MTIImage, state: PhotoEditState) -> MTIImage? {
        let f = MTIExposureFilter()
        f.inputImage = image
        f.exposure = state.exposure
        return f.outputImage
    }
}

// MARK: - 4. Brightness

struct BrightnessStage: FilterStage {
    let name = "Brightness"
    func isNeutral(for state: PhotoEditState) -> Bool { state.brightness == 0.0 }
    func apply(to image: MTIImage, state: PhotoEditState) -> MTIImage? {
        let f = MTIBrightnessFilter()
        f.inputImage = image
        f.brightness = state.brightness
        return f.outputImage
    }
}

// MARK: - 5. Contrast

struct ContrastStage: FilterStage {
    let name = "Contrast"
    func isNeutral(for state: PhotoEditState) -> Bool { state.contrast == 1.0 }
    func apply(to image: MTIImage, state: PhotoEditState) -> MTIImage? {
        let f = MTIContrastFilter()
        f.inputImage = image
        f.contrast = state.contrast
        return f.outputImage
    }
}

// MARK: - 6. Fade

struct FadeStage: FilterStage {
    let name = "Fade"
    func isNeutral(for state: PhotoEditState) -> Bool { state.fade <= 0.0 }
    func apply(to image: MTIImage, state: PhotoEditState) -> MTIImage? {
        let k = 0.35 * max(0.0, min(1.0, state.fade))
        let cm = MTIColorMatrixFilter()
        cm.inputImage = image
        cm.colorMatrix = MTIColorMatrix(
            matrix: simd_float4x4(diagonal: SIMD4<Float>(1 - k, 1 - k, 1 - k, 1)),
            bias: SIMD4<Float>(k, k, k, 0)
        )
        return cm.outputImage
    }
}

// MARK: - 7. Opacity

struct OpacityStage: FilterStage {
    let name = "Opacity"
    func isNeutral(for state: PhotoEditState) -> Bool { state.opacity == 1.0 }
    func apply(to image: MTIImage, state: PhotoEditState) -> MTIImage? {
        let f = MTIOpacityFilter()
        f.inputImage = image
        f.opacity = state.opacity
        return f.outputImage
    }
}

// MARK: - 8. Pixelate

struct PixelateStage: FilterStage {
    let name = "Pixelate"
    func isNeutral(for state: PhotoEditState) -> Bool { state.pixelateAmount <= 1.0 }
    func apply(to image: MTIImage, state: PhotoEditState) -> MTIImage? {
        let f = MTIPixellateFilter()
        f.inputImage = image
        let scale = max(CGFloat(state.pixelateAmount), 1.0)
        f.scale = CGSize(width: scale, height: scale)
        return f.outputImage
    }
}

// MARK: - 9. Clarity (CLAHE)

struct ClarityStage: FilterStage {
    let name = "Clarity"
    func isNeutral(for state: PhotoEditState) -> Bool { state.clarity <= 0.0 }
    func apply(to image: MTIImage, state: PhotoEditState) -> MTIImage? {
        let f = MTICLAHEFilter()
        f.inputImage = image
        f.clipLimit = max(0.0, min(2.0, 0.5 + 1.0 * state.clarity))
        f.tileGridSize = MTICLAHESize(width: 12, height: 12)
        return f.outputImage
    }
}

// MARK: - 10. Sharpen

struct SharpenStage: FilterStage {
    let name = "Sharpen"
    func isNeutral(for state: PhotoEditState) -> Bool { state.sharpen <= 0.0 }
    func apply(to image: MTIImage, state: PhotoEditState) -> MTIImage? {
        let f = MTIMPSUnsharpMaskFilter()
        f.inputImage = image
        f.scale = min(max(state.sharpen, 0.0), 1.0)
        f.radius = Float(1.0 + 2.0 * Double(state.sharpen))
        f.threshold = 0.0
        return f.outputImage
    }
}

// MARK: - 11. Color Tint / Duotone

struct ColorTintStage: FilterStage {
    let name = "ColorTint"

    func isNeutral(for state: PhotoEditState) -> Bool {
        state.colorTint.x <= 0.0 && state.colorTint.y <= 0.0 && state.colorTint.z <= 0.0
    }

    func apply(to image: MTIImage, state: PhotoEditState) -> MTIImage? {
        if state.isDualToneActive &&
            (state.colorTintSecondary.x > 0.0 || state.colorTintSecondary.y > 0.0 || state.colorTintSecondary.z > 0.0) {
            let f = DuotoneFilter()
            f.inputImage = image
            f.shadowColor = SIMD3<Float>(state.colorTint.x, state.colorTint.y, state.colorTint.z)
            f.highlightColor = SIMD3<Float>(state.colorTintSecondary.x, state.colorTintSecondary.y, state.colorTintSecondary.z)
            f.intensity = max(0.0, min(1.0, state.colorTintIntensity))
            f.factor = max(0.0, min(1.0, state.colorTintFactor))
            f.gamma = 1.0
            f.outputPixelFormat = .bgra8Unorm
            return f.outputImage
        } else {
            let neutral: Float = 0.5
            let intensity = max(0.0, min(1.0, state.colorTintIntensity))
            let factor = max(0.0, min(1.0, state.colorTintFactor))
            let biasR = (state.colorTint.x - neutral) * factor * intensity
            let biasG = (state.colorTint.y - neutral) * factor * intensity
            let biasB = (state.colorTint.z - neutral) * factor * intensity
            let matrixFilter = MTIColorMatrixFilter()
            matrixFilter.inputImage = image
            let mat = simd_float4x4(diagonal: SIMD4<Float>(1, 1, 1, 1))
            let bias = SIMD4<Float>(biasR, biasG, biasB, 0)
            matrixFilter.colorMatrix = MTIColorMatrix(matrix: mat, bias: bias)
            return matrixFilter.outputImage
        }
    }
}

// MARK: - 12. Skin Tone

struct SkinToneStage: FilterStage {
    let name = "SkinTone"
    func isNeutral(for state: PhotoEditState) -> Bool { abs(state.skinTone) <= 0.001 }
    func apply(to image: MTIImage, state: PhotoEditState) -> MTIImage? {
        let f = SkinToneFilter()
        f.inputImage = image
        f.amount = state.skinTone
        f.softness = 0.6
        f.highlightProtect = 0.6
        f.saturationThreshold = 0.06
        f.outputPixelFormat = .bgra8Unorm
        return f.outputImage ?? image
    }
}

// MARK: - 13. Color Invert

struct ColorInvertStage: FilterStage {
    let name = "ColorInvert"
    func isNeutral(for state: PhotoEditState) -> Bool { state.colorInvert <= 0.0 }
    func apply(to image: MTIImage, state: PhotoEditState) -> MTIImage? {
        let invertFilter = MTIColorInvertFilter()
        invertFilter.inputImage = image
        guard let invertedImage = invertFilter.outputImage else { return nil }
        if state.colorInvert < 1.0 {
            let blendFilter = MTIBlendFilter(blendMode: .normal)
            blendFilter.inputImage = invertedImage
            blendFilter.inputBackgroundImage = image
            blendFilter.intensity = state.colorInvert
            return blendFilter.outputImage
        }
        return invertedImage
    }
}

// MARK: - 14. Vignette

struct VignetteStage: FilterStage {
    let name = "Vignette"
    func isNeutral(for state: PhotoEditState) -> Bool { state.vignette <= 0.0 }
    func apply(to image: MTIImage, state: PhotoEditState) -> MTIImage? {
        let f = VignetteFilter()
        f.inputImage = image
        f.intensity = state.vignette
        f.outputPixelFormat = .bgra8Unorm
        return f.outputImage ?? image
    }
}

// MARK: - 15. Grain

struct GrainStage: FilterStage {
    let name = "Grain"
    let seed: Float

    init(seed: Float = 0.0) {
        self.seed = seed
    }

    func isNeutral(for state: PhotoEditState) -> Bool { state.grain <= 0.0 }
    func apply(to image: MTIImage, state: PhotoEditState) -> MTIImage? {
        let f = LumaGrainFilter()
        f.inputImage = image
        f.grain = state.grain
        f.grainSize = state.grainSize
        f.seed = seed
        f.outputPixelFormat = .bgra8Unorm
        if let out = f.outputImage {
            return out
        }
        os_log("[GrainStage] LumaGrainFilter produced nil output (Metal shader not available).")
        return image
    }
}
