import SwiftUI

/// Describes how to map a model value (e.g. 0.5…1.5) to/from a UI range (0…100),
/// plus formatting and tick configuration for the ruler.
struct SliderMapping {
    /// Convert model value → UI value
    let toUI: (Float) -> Float
    /// Convert UI value → model value
    let fromUI: (Float) -> Float
    /// Format UI value for display label
    let format: (Float) -> String
    let range: ClosedRange<Float>
    let step: Float
    let totalTicks: Int
    let majorTickEvery: Int

    init(
        toUI: @escaping (Float) -> Float,
        fromUI: @escaping (Float) -> Float,
        format: @escaping (Float) -> String,
        range: ClosedRange<Float> = 0...100,
        step: Float = 1.0,
        totalTicks: Int = 101,
        majorTickEvery: Int = 10
    ) {
        self.toUI = toUI
        self.fromUI = fromUI
        self.format = format
        self.range = range
        self.step = step
        self.totalTicks = totalTicks
        self.majorTickEvery = majorTickEvery
    }
}

/// A reusable slider that wraps `RulerSlider` with a `SliderMapping` transform.
struct MappedSlider: View {
    @Binding var value: Float
    let mapping: SliderMapping
    var onBegin: (() -> Void)? = nil
    var onEnd: (() -> Void)? = nil

    var body: some View {
        RulerSlider(
            value: Binding(
                get: { mapping.toUI(value).rounded() },
                set: { value = mapping.fromUI($0) }
            ),
            range: mapping.range,
            step: mapping.step,
            totalTicks: mapping.totalTicks,
            majorTickEvery: mapping.majorTickEvery,
            format: mapping.format,
            onEditingBegan: onBegin,
            onEditingEnded: onEnd
        )
    }
}

// MARK: - Preset Mappings

extension SliderMapping {
    /// Contrast: model 0.5…1.5 ↔ UI 0…100, display -100…100
    static let contrast = SliderMapping(
        toUI: { (($0 - 0.5) * 100) },
        fromUI: { ($0 / 100) + 0.5 },
        format: { String(format: "%d", Int($0 - 50) * 2) }
    )

    /// Brightness: model -0.5…0.5 ↔ UI 0…100, display -100…100
    static let brightness = SliderMapping(
        toUI: { (($0 + 0.5) * 100) },
        fromUI: { ($0 / 100) - 0.5 },
        format: { String(format: "%d", Int($0 - 50) * 2) }
    )

    /// Exposure: model -2.0…2.0 ↔ UI 0…100, display -100…100
    static let exposure = SliderMapping(
        toUI: { (($0 + 2.0) * 25) },
        fromUI: { ($0 / 25) - 2.0 },
        format: { String(format: "%d", Int($0 - 50) * 2) }
    )

    /// Saturation: model 0.0…2.0 ↔ UI 0…100, display -100…100
    static let saturation = SliderMapping(
        toUI: { ($0 * 50) },
        fromUI: { $0 / 50 },
        format: { String(format: "%d", Int($0) * 2 - 100) }
    )

    /// Vibrance: model -1.0…1.0 ↔ UI 0…100, display -100…100
    static let vibrance = SliderMapping(
        toUI: { (($0 + 1.0) * 50) },
        fromUI: { ($0 / 50) - 1.0 },
        format: { String(format: "%d", Int($0 - 50) * 2) }
    )

    /// Fade: model 0.0…1.0 ↔ UI 0…100, display 0…100
    static let fade = SliderMapping(
        toUI: { ($0 * 100) },
        fromUI: { $0 / 100 },
        format: { String(format: "%d", Int($0)) }
    )

    /// Vignette: model 0.0…1.0 ↔ UI 0…100, display 0…100
    static let vignette = SliderMapping(
        toUI: { ($0 * 100) },
        fromUI: { $0 / 100 },
        format: { String(format: "%d", Int($0)) }
    )

    /// Opacity: model 0.0…1.0 ↔ UI 0…100, display inverted 100…0
    static let opacity = SliderMapping(
        toUI: { ($0 * 100) },
        fromUI: { $0 / 100 },
        format: { String(format: "%d", 100 - Int($0)) }
    )

    /// Color Invert: model 0.0…1.0 direct, display as decimal
    static let colorInvert = SliderMapping(
        toUI: { $0 },
        fromUI: { $0 },
        format: { String(format: "%.2f", $0) },
        range: 0.0...1.0,
        step: 0.01
    )

    /// Pixelate: model 1.0…40.0 ↔ UI 0…100, display -100…100
    static let pixelate = SliderMapping(
        toUI: { (($0 - 1.0) * (100.0 / 39.0)) },
        fromUI: { ($0 * (39.0 / 100.0)) + 1.0 },
        format: { String(format: "%d", Int($0) * 2 - 100) }
    )

    /// Sharpen: model 0.0…1.0 ↔ UI 0…100, display 0…100
    static let sharpen = SliderMapping(
        toUI: { ($0 * 100) },
        fromUI: { $0 / 100 },
        format: { String(format: "%d", Int($0)) }
    )

    /// Clarity: model 0.0…1.0 ↔ UI 0…100, display 0…100
    static let clarity = SliderMapping(
        toUI: { ($0 * 100) },
        fromUI: { $0 / 100 },
        format: { String(format: "%d", Int($0)) }
    )

    /// Grain: model 0.0…0.1 ↔ UI 0…100, display 0…100
    static let grain = SliderMapping(
        toUI: { ($0 * 1000) },
        fromUI: { $0 / 1000 },
        format: { String(format: "%d", Int($0)) }
    )

    /// Color Tint Intensity: model 0.0…6.0 ↔ UI 0…100, display -100…100
    static let colorTintIntensity = SliderMapping(
        toUI: { ($0 * (100.0 / 6.0)) },
        fromUI: { $0 * (6.0 / 100.0) },
        format: { String(format: "%d", Int($0) * 2 - 100) },
        range: 0...100,
        step: 1.0,
        totalTicks: 31,
        majorTickEvery: 5
    )

    /// Skin Tone: model -1.0…1.0 ↔ UI 0…100, display -100…100
    static let skinTone = SliderMapping(
        toUI: { (($0 + 1.0) * 50) },
        fromUI: { ($0 / 50) - 1.0 },
        format: { String(format: "%d", Int($0 - 50) * 2) }
    )
}
