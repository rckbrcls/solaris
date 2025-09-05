import SwiftUI
import UIKit

// Slider customizado com régua visual padronizada, snap e feedback tátil
struct RulerSlider: View {
    @Binding var value: Float
    let range: ClosedRange<Float>
    let step: Float
    let format: (Float) -> String
    // Padronização: número total de marcas da régua (inclui início e fim)
    let totalTicks: Int
    // A cada quantas marcas uma marca maior aparece
    let majorTickEvery: Int
    // Aparência
    let thumbSize: CGFloat
    let rulerHeight: CGFloat
    let sliderHeight: CGFloat

    @GestureState private var dragOffset: CGFloat = 0
    @State private var isDragging = false
    @State private var didNotifyBegin = false
    @State private var lastMajorIndexFeedback: Int? = nil
    @EnvironmentObject private var colorSchemeManager: ColorSchemeManager
    let onEditingBegan: (() -> Void)?
    let onEditingEnded: (() -> Void)?

    init(
        value: Binding<Float>,
        range: ClosedRange<Float>,
        step: Float = 1.0,
        totalTicks: Int = 31, // padronizado ~30 intervalos
        majorTickEvery: Int = 5,
        thumbSize: CGFloat = 28,
        rulerHeight: CGFloat = 16,
        sliderHeight: CGFloat = 44,
        format: @escaping (Float) -> String = { String(format: "%.0f", $0) },
        onEditingBegan: (() -> Void)? = nil,
        onEditingEnded: (() -> Void)? = nil
    ) {
        self._value = value
        self.range = range
        self.step = step
        self.totalTicks = max(2, totalTicks)
        self.majorTickEvery = max(1, majorTickEvery)
        self.thumbSize = thumbSize
        self.rulerHeight = rulerHeight
        self.sliderHeight = sliderHeight
        self.format = format
        self.onEditingBegan = onEditingBegan
        self.onEditingEnded = onEditingEnded
    }

    var body: some View {
        GeometryReader { geo in
            // Padding simétrico para garantir que todos os ticks sejam visíveis
            let leftInset = thumbSize / 2
            let rightInset = thumbSize / 2
            let sliderWidth = max(1, geo.size.width - leftInset - rightInset)
            let valueRange = range.upperBound - range.lowerBound
            let clampedValue = min(max(value, range.lowerBound), range.upperBound)
            let percent = CGFloat((clampedValue - range.lowerBound) / valueRange)
            let currentX = percent * sliderWidth
            let spacing = sliderWidth / CGFloat(totalTicks - 1)
            let maxTickWidth: CGFloat = 2.5

            ZStack(alignment: .leading) {
                // Trilha suave ao fundo
                RoundedRectangle(cornerRadius: 6)
                    .fill(colorSchemeManager.primaryColor.opacity(0.08))
                    .frame(height: max(2, rulerHeight * 0.35))
                    .offset(y: rulerHeight * 0.3)
                    .padding(.leading, leftInset)
                    .padding(.trailing, rightInset)

                // Régua (posicionamento absoluto para garantir simetria perfeita)
                ZStack(alignment: .leading) {
                    ForEach(0..<totalTicks, id: \.self) { i in
                        let isMajor = (i % majorTickEvery == 0)
                        let tickW: CGFloat = isMajor ? 3.0 : 1.0
                        let centerX = leftInset + (CGFloat(i) / CGFloat(totalTicks - 1) * sliderWidth)
                        Capsule(style: .continuous)
                            .fill(isMajor ? colorSchemeManager.primaryColor.opacity(0.85) : colorSchemeManager.primaryColor.opacity(0.55))
                            .frame(
                                width: tickW,
                                height: isMajor ? rulerHeight : rulerHeight * 0.6
                            )
                            .position(x: centerX, y: rulerHeight / 2)
                    }
                }
                .frame(width: geo.size.width, height: rulerHeight)

                // Thumb - posicionamento corrigido para centrar nos ticks
                RoundedRectangle(cornerRadius: thumbSize / 2.5, style: .continuous)
                    .fill(Color.accentColor)
                    .shadow(color: Color.accentColor.opacity(0.25), radius: 6, x: 0, y: 2)
                    .frame(width: thumbSize * 1.2, height: thumbSize)
                    .overlay(
                        Text(format(clampedValue))
                            .font(.caption2.bold())
                            .foregroundColor(.white)
                            .frame(width: thumbSize * 1.2, height: thumbSize)
                    )
                    .offset(x: leftInset + currentX - (thumbSize * 1.2) / 2)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .updating($dragOffset) { value, state, _ in
                                state = value.translation.width
                            }
                            .onChanged { gesture in
                                if !isDragging {
                                    onEditingBegan?()
                                    didNotifyBegin = true
                                }
                                isDragging = true
                                let sliderWidth = max(1, geo.size.width - leftInset - rightInset)
                                // Corrige o cálculo para considerar a largura do thumb
                                let thumbHalfWidth = (thumbSize * 1.2) / 2
                                let localX = max(0, min(sliderWidth, gesture.location.x - leftInset))
                                let percent = localX / sliderWidth
                                var rawValue = Float(percent) * valueRange + range.lowerBound

                                // Snap forte para os majors visuais
                                let majorIndices = stride(from: 0, to: totalTicks, by: majorTickEvery).map { $0 }
                                let majorPositions = majorIndices.map { CGFloat($0) / CGFloat(totalTicks - 1) * sliderWidth }
                                let nearestMajorIndex = majorPositions.enumerated().min(by: { abs($0.element - localX) < abs($1.element - localX) })?.offset
                                let snapPx: CGFloat = max(6, spacing * 0.35)
                                if let nearestIdx = nearestMajorIndex, abs(majorPositions[nearestIdx] - localX) <= snapPx {
                                    let i = majorIndices[nearestIdx]
                                    let majorPercent = CGFloat(i) / CGFloat(totalTicks - 1)
                                    rawValue = Float(majorPercent) * valueRange + range.lowerBound
                                }

                                // Quantiza para o passo definido
                                var snapped = (rawValue / step).rounded() * step
                                snapped = min(max(snapped, range.lowerBound), range.upperBound)

                                // Haptic: quando encosta em um major visual diferente
                                if let nearestIdx = nearestMajorIndex, abs(majorPositions[nearestIdx] - localX) <= snapPx {
                                    if lastMajorIndexFeedback != nearestIdx {
                                        let generator = UIImpactFeedbackGenerator(style: .medium)
                                        generator.impactOccurred()
                                        lastMajorIndexFeedback = nearestIdx
                                    }
                                } else {
                                    let generator = UIImpactFeedbackGenerator(style: .light)
                                    generator.impactOccurred(intensity: 0.6)
                                    lastMajorIndexFeedback = nil
                                }

                                value = snapped
                            }
                            .onEnded { _ in
                                isDragging = false
                                if didNotifyBegin {
                                    onEditingEnded?()
                                }
                                didNotifyBegin = false
                                lastMajorIndexFeedback = nil
                            }
                    )
                    .animation(.easeOut(duration: 0.15), value: value)
            }
            .frame(height: sliderHeight)
        }
        .frame(height: sliderHeight)
        .boxBlankStyle(cornerRadius: 12, padding: 6)
    }
}

struct Adjustment: Identifiable, Hashable {
    let id: String
    let label: String
    let icon: String
}

struct PhotoEditorAdjustments: View {
    @Binding var contrast: Float
    @Binding var brightness: Float
    @Binding var exposure: Float
    @Binding var saturation: Float
    @Binding var vibrance: Float
    @Binding var fade: Float
    @Binding var colorInvert: Float
    @Binding var pixelateAmount: Float
    @Binding var grain: Float
    @Binding var sharpen: Float
    @Binding var clarity: Float
    @Binding var colorTint: SIMD4<Float>
    @Binding var colorTintSecondary: SIMD4<Float>
    @Binding var isDualToneActive: Bool
    @Binding var colorTintIntensity: Float
    @Binding var colorTintFactor: Float
    var onBeginAdjust: (() -> Void)? = nil
    var onEndAdjust: (() -> Void)? = nil
    @State private var selectedAdjustment: String = "contrast"
    @EnvironmentObject private var colorSchemeManager: ColorSchemeManager

    private var selectedLabel: String {
        adjustments.first(where: { $0.id == selectedAdjustment })?.label ?? ""
    }

    private let tintPresets: [SIMD4<Float>] = [
        SIMD4<Float>(x: 1.00, y: 0.29, z: 0.23, w: 1.0),
        SIMD4<Float>(x: 1.00, y: 0.55, z: 0.00, w: 1.0),
        SIMD4<Float>(x: 1.00, y: 0.84, z: 0.00, w: 1.0),
        SIMD4<Float>(x: 0.85, y: 0.80, z: 0.60, w: 1.0),
        SIMD4<Float>(x: 0.10, y: 0.78, z: 0.64, w: 1.0),
        SIMD4<Float>(x: 0.00, y: 0.68, z: 0.94, w: 1.0),
        SIMD4<Float>(x: 0.18, y: 0.39, z: 0.96, w: 1.0),
        SIMD4<Float>(x: 0.47, y: 0.33, z: 0.94, w: 1.0),
        SIMD4<Float>(x: 0.93, y: 0.33, z: 0.58, w: 1.0),
        SIMD4<Float>(x: 0.64, y: 0.86, z: 0.22, w: 1.0)
    ]

    private func colorEquals(_ a: SIMD4<Float>, _ b: SIMD4<Float>, eps: Float = 0.01) -> Bool {
        abs(a.x - b.x) < eps && abs(a.y - b.y) < eps && abs(a.z - b.z) < eps && abs((a.w == 0 ? 1.0 : a.w) - (b.w == 0 ? 1.0 : b.w)) < eps
    }

    let adjustments: [Adjustment] = [
        Adjustment(id: "contrast", label: "Contraste", icon: "circle.lefthalf.fill"),
        Adjustment(id: "brightness", label: "Brilho", icon: "sun.max"),
        Adjustment(id: "exposure", label: "Exposição", icon: "sunrise"),
        Adjustment(id: "saturation", label: "Saturação", icon: "drop"),
        Adjustment(id: "vibrance", label: "Vibrance", icon: "waveform.path.ecg"),
        Adjustment(id: "fade", label: "Fade", icon: "aqi.medium"),
        Adjustment(id: "grain", label: "Grão (Film)", icon: "circle.grid.cross"),
        Adjustment(id: "sharpen", label: "Nitidez", icon: "wand.and.stars"),
        Adjustment(id: "clarity", label: "Clareza", icon: "circle.lefthalf.filled.inverse"),
        Adjustment(id: "colorInvert", label: "Inverter", icon: "circle.righthalf.filled"),
        Adjustment(id: "pixelateAmount", label: "Pixelizar", icon: "rectangle.split.3x3"),
        Adjustment(id: "colorTint", label: "Tint", icon: "paintpalette")
    ]

    private func isAdjustmentActive(_ id: String) -> Bool {
        switch id {
        case "contrast": return contrast != 1.0
        case "brightness": return brightness != 0.0
        case "exposure": return exposure != 0.0
        case "saturation": return saturation != 1.0
        case "vibrance": return vibrance != 0.0
        case "fade": return fade > 0.0
        case "grain": return grain > 0.0
        case "colorInvert": return colorInvert == 1.0
        case "sharpen": return sharpen > 0.0
        case "clarity": return clarity > 0.0
        case "pixelateAmount": return pixelateAmount != 1.0
        case "colorTint": return !(colorTint.x == 0.0 && colorTint.y == 0.0 && colorTint.z == 0.0 && colorTint.w == 0.0)
        default: return false
        }
    }

    private func uiFromFactor(_ factor: Float) -> Float {
        let clamped = min(max(factor, 0.0), 1.0)
        return (clamped / 1.0 * 100).rounded()
    }
    private func factorFromUI(_ value: Float) -> Float {
        let pct = min(max(value, 0.0), 100.0) / 100.0
        return min(max(pct * 1.0, 0.0), 1.0)
    }

    var body: some View {
        VStack {
            let headerColor = colorSchemeManager.primaryColor.opacity(0.6)
            if !selectedLabel.isEmpty {
                Text(selectedLabel)
                    .font(.caption2)
                    .foregroundColor(headerColor)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(adjustments) { adj in
                        let isActive = isAdjustmentActive(adj.id)
                        let isSelected = selectedAdjustment == adj.id
                        AdjustmentIconButton(
                            icon: adj.icon,
                            isActive: isActive,
                            isSelected: isSelected,
                            onTap: { selectedAdjustment = adj.id }
                        )
                        .environmentObject(colorSchemeManager)
                    }
                }
                .padding(.horizontal)
            }

            Group {
                if selectedAdjustment == "contrast" {
                    ContrastSlider(value: $contrast, onBegin: onBeginAdjust, onEnd: onEndAdjust)
                        .padding(.horizontal)
                } else if selectedAdjustment == "brightness" {
                    BrightnessSlider(value: $brightness, onBegin: onBeginAdjust, onEnd: onEndAdjust)
                        .padding(.horizontal)
                } else if selectedAdjustment == "exposure" {
                    ExposureSlider(value: $exposure, onBegin: onBeginAdjust, onEnd: onEndAdjust)
                        .padding(.horizontal)
                } else if selectedAdjustment == "saturation" {
                    SaturationSlider(value: $saturation, onBegin: onBeginAdjust, onEnd: onEndAdjust)
                        .padding(.horizontal)
                } else if selectedAdjustment == "vibrance" {
                    VibranceSlider(value: $vibrance, onBegin: onBeginAdjust, onEnd: onEndAdjust)
                        .padding(.horizontal)
                } else if selectedAdjustment == "fade" {
                    FadeSlider(value: $fade, onBegin: onBeginAdjust, onEnd: onEndAdjust)
                        .padding(.horizontal)
                } else if selectedAdjustment == "colorInvert" {
                    InvertToggle(colorInvert: $colorInvert, onBegin: onBeginAdjust, onEnd: onEndAdjust)
                        .padding(.horizontal)
                } else if selectedAdjustment == "pixelateAmount" {
                    PixelateSlider(value: $pixelateAmount, onBegin: onBeginAdjust, onEnd: onEndAdjust)
                        .padding(.horizontal)
                } else if selectedAdjustment == "grain" {
                    GrainSlider(value: $grain, onBegin: onBeginAdjust, onEnd: onEndAdjust)
                        .padding(.horizontal)
                } else if selectedAdjustment == "sharpen" {
                    SharpenSlider(value: $sharpen, onBegin: onBeginAdjust, onEnd: onEndAdjust)
                        .padding(.horizontal)
                } else if selectedAdjustment == "clarity" {
                    ClaritySlider(value: $clarity, onBegin: onBeginAdjust, onEnd: onEndAdjust)
                        .padding(.horizontal)
                } else if selectedAdjustment == "colorTint" {
                    ColorTintControls(
                        colorTint: $colorTint,
                        colorTintSecondary: $colorTintSecondary,
                        isDualToneActive: $isDualToneActive,
                        colorTintIntensity: $colorTintIntensity,
                        colorTintFactor: $colorTintFactor,
                        onBeginAdjust: onBeginAdjust,
                        onEndAdjust: onEndAdjust,
                        tintPresets: tintPresets
                    )
                    .padding(.horizontal)
                }
            }
        }
    }
}

private struct InvertToggle: View {
    @EnvironmentObject private var colorSchemeManager: ColorSchemeManager
    @Binding var colorInvert: Float
    var onBegin: (() -> Void)? = nil
    var onEnd: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            Button(action: {
                if colorInvert != 0.0 {
                    onBegin?()
                    colorInvert = 0.0
                    let gen = UIImpactFeedbackGenerator(style: .medium)
                    gen.impactOccurred()
                    onEnd?()
                }
            }) {
                Text("Off")
                    .font(.callout.bold())
                    .frame(maxWidth: .infinity, minHeight: 32)
                    .padding(.vertical, 2)
                    .foregroundColor(colorInvert == 0.0 ? Color.white : colorSchemeManager.primaryColor)
                    .background(colorInvert == 0.0 ? Color.accentColor : colorSchemeManager.primaryColor.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            Button(action: {
                if colorInvert != 1.0 {
                    onBegin?()
                    colorInvert = 1.0
                    let gen = UIImpactFeedbackGenerator(style: .medium)
                    gen.impactOccurred()
                    onEnd?()
                }
            }) {
                Text("On")
                    .font(.callout.bold())
                    .frame(maxWidth: .infinity, minHeight: 32)
                    .padding(.vertical, 2)
                    .foregroundColor(colorInvert == 1.0 ? Color.white : colorSchemeManager.primaryColor)
                    .background(colorInvert == 1.0 ? Color.accentColor : colorSchemeManager.primaryColor.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }
}

private struct ColorTintControls: View {
    @EnvironmentObject private var colorSchemeManager: ColorSchemeManager
    @Binding var colorTint: SIMD4<Float>
    @Binding var colorTintSecondary: SIMD4<Float>
    @Binding var isDualToneActive: Bool
    @Binding var colorTintIntensity: Float
    @Binding var colorTintFactor: Float
    var onBeginAdjust: (() -> Void)? = nil
    var onEndAdjust: (() -> Void)? = nil
    let tintPresets: [SIMD4<Float>]

    private func colorEquals(_ a: SIMD4<Float>, _ b: SIMD4<Float>, eps: Float = 0.01) -> Bool {
        abs(a.x - b.x) < eps && abs(a.y - b.y) < eps && abs(a.z - b.z) < eps && abs((a.w == 0 ? 1.0 : a.w) - (b.w == 0 ? 1.0 : b.w)) < eps
    }
    private func uiFromFactor(_ factor: Float) -> Float {
        let clamped = min(max(factor, 0.0), 1.0)
        return (clamped / 1.0 * 100).rounded()
    }
    private func factorFromUI(_ value: Float) -> Float {
        let pct = min(max(value, 0.0), 100.0) / 100.0
        return min(max(pct * 1.0, 0.0), 1.0)
    }
    private func colorsAreVerySimilar(_ a: SIMD4<Float>, _ b: SIMD4<Float>, threshold: Float = 0.06) -> Bool {
        let dx = a.x - b.x
        let dy = a.y - b.y
        let dz = a.z - b.z
        let dist = sqrt(dx*dx + dy*dy + dz*dz)
        return dist < threshold
    }

    var body: some View {
        VStack(spacing: 10) {
            // Indicador de dual tone
            if isDualToneActive {
                HStack(spacing: 8) {
                    Text("Dual Tone Ativo")
                        .font(.caption)
                        .foregroundColor(colorSchemeManager.primaryColor.opacity(0.7))
                    
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color(red: Double(colorTint.x), green: Double(colorTint.y), blue: Double(colorTint.z)))
                            .frame(width: 12, height: 12)
                        Circle()
                            .fill(Color(red: Double(colorTintSecondary.x), green: Double(colorTintSecondary.y), blue: Double(colorTintSecondary.z)))
                            .frame(width: 12, height: 12)
                    }
                    
                    Spacer()
                    
                    Button("Limpar") {
                        onBeginAdjust?()
                        isDualToneActive = false
                        colorTintSecondary = SIMD4<Float>(x: 0.0, y: 0.0, z: 0.0, w: 0.0)
                        let gen = UIImpactFeedbackGenerator(style: .medium)
                        gen.impactOccurred()
                        onEndAdjust?()
                    }
                    .font(.caption)
                    .foregroundColor(.red)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(colorSchemeManager.primaryColor.opacity(0.06))
                .cornerRadius(8)
            }
            
            HStack(spacing: 12) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(tintPresets.enumerated()), id: \.offset) { _, preset in
                            let presetColor = Color(red: Double(preset.x), green: Double(preset.y), blue: Double(preset.z))
                            let isSelectedPreset = colorEquals(colorTint, preset)
                            let isSelectedSecondary = isDualToneActive && colorEquals(colorTintSecondary, preset)
                            
                            // Gestos exclusivos: LongPress (dual tone) OU Tap (primária), nunca ambos
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(presetColor)
                                .frame(width: 44, height: 44)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(
                                            isSelectedPreset ? Color.accentColor :
                                            isSelectedSecondary ? Color.orange : Color.clear,
                                            lineWidth: 3
                                        )
                                        .padding(0.5)
                                        .allowsHitTesting(false)
                                )
                                .overlay(
                                    // Indicador visual para dual tone
                                    Group {
                                        if isSelectedSecondary {
                                            Image(systemName: "2.circle.fill")
                                                .foregroundColor(.white)
                                                .background(Circle().fill(Color.orange))
                                                .font(.caption2)
                                                .offset(x: 12, y: -12)
                                        }
                                    }
                                )
                                .contentShape(RoundedRectangle(cornerRadius: 10))
                                .padding(2)
                                .gesture(
                                    LongPressGesture(minimumDuration: 0.5)
                                        .exclusively(before: TapGesture())
                                        .onEnded { outcome in
                                            switch outcome {
                                            case .first:
                                                // Long press: set secondary for dual tone (only if distinct)
                                                if colorTint.w > 0 {
                                                    let candidate = SIMD4<Float>(x: preset.x, y: preset.y, z: preset.z, w: 1.0)
                                                    if !(colorEquals(colorTint, candidate) || colorsAreVerySimilar(colorTint, candidate)) {
                                                        onBeginAdjust?()
                                                        colorTintSecondary = candidate
                                                        isDualToneActive = true
                                                        let gen = UIImpactFeedbackGenerator(style: .heavy)
                                                        gen.impactOccurred()
                                                        onEndAdjust?()
                                                    } else {
                                                        let gen = UIImpactFeedbackGenerator(style: .rigid)
                                                        gen.impactOccurred(intensity: 0.5)
                                                    }
                                                }
                                            case .second:
                                                // Tap: select primary
                                                onBeginAdjust?()
                                                let hadColor = (colorTint.w > 0)
                                                colorTint = SIMD4<Float>(x: preset.x, y: preset.y, z: preset.z, w: 1.0)
                                                colorTintIntensity = 0.9
                                                if !hadColor { colorTintFactor = 0.30 }
                                                if isDualToneActive && colorsAreVerySimilar(colorTint, colorTintSecondary) {
                                                    isDualToneActive = false
                                                    colorTintSecondary = SIMD4<Float>(x: 0, y: 0, z: 0, w: 0)
                                                }
                                                let gen = UIImpactFeedbackGenerator(style: .light)
                                                gen.impactOccurred()
                                                onEndAdjust?()
                                            }
                                        }
                                )
                                .zIndex(2)
                        }
                        ZStack {
                            ColorPicker("", selection: Binding(
                                get: {
                                    Color(red: Double((colorTint.w == 0 ? 1.0 : colorTint.x)),
                                          green: Double((colorTint.w == 0 ? 1.0 : colorTint.y)),
                                          blue: Double((colorTint.w == 0 ? 1.0 : colorTint.z)),
                                          opacity: 1.0)
                                },
                                set: { newColor in
                                    #if canImport(UIKit)
                                    let ui = UIColor(cgColor: newColor.cgColor ?? UIColor.white.cgColor)
                                    var r: CGFloat = 1, g: CGFloat = 1, b: CGFloat = 1, a: CGFloat = 1
                                    if ui.getRed(&r, green: &g, blue: &b, alpha: &a) {
                                        onBeginAdjust?()
                                        let hadColor = (colorTint.w > 0)
                                        colorTint = SIMD4<Float>(x: Float(r), y: Float(g), z: Float(b), w: 1.0)
                                        colorTintIntensity = 0.9
                                        if !hadColor { colorTintFactor = 0.30 }
                                        if isDualToneActive && colorsAreVerySimilar(colorTint, colorTintSecondary) {
                                            isDualToneActive = false
                                            colorTintSecondary = SIMD4<Float>(x: 0, y: 0, z: 0, w: 0)
                                        }
                                        let gen = UIImpactFeedbackGenerator(style: .light)
                                        gen.impactOccurred()
                                        onEndAdjust?()
                                    }
                                    #else
                                    if let components = newColor.cgColor?.components, components.count >= 3 {
                                        onBeginAdjust?()
                                        let hadColor = (colorTint.w > 0)
                                        colorTint = SIMD4<Float>(x: Float(components[0]), y: Float(components[1]), z: Float(components[2]), w: 1.0)
                                        colorTintIntensity = 0.9
                                        if !hadColor { colorTintFactor = 0.30 }
                                        if isDualToneActive && colorsAreVerySimilar(colorTint, colorTintSecondary) {
                                            isDualToneActive = false
                                            colorTintSecondary = SIMD4<Float>(x: 0, y: 0, z: 0, w: 0)
                                        }
                                        onEndAdjust?()
                                    }
                                    #endif
                                }
                            ))
                            .labelsHidden()
                            .frame(width: 44, height: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(LinearGradient(colors: [.red, .yellow, .green, .blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .allowsHitTesting(false)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.accentColor.opacity((colorTint.w > 0 && !tintPresets.contains(where: { colorEquals($0, colorTint) })) ? 1 : 0), lineWidth: 3)
                                    .allowsHitTesting(false)
                            )
                            .overlay(
                                // Indicador para dual tone no ColorPicker
                                Group {
                                    if isDualToneActive {
                                        HStack(spacing: 2) {
                                            Circle()
                                                .fill(Color(red: Double(colorTint.x), green: Double(colorTint.y), blue: Double(colorTint.z)))
                                                .frame(width: 8, height: 8)
                                            Circle()
                                                .fill(Color(red: Double(colorTintSecondary.x), green: Double(colorTintSecondary.y), blue: Double(colorTintSecondary.z)))
                                                .frame(width: 8, height: 8)
                                        }
                                        .offset(y: 12)
                                    }
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                    .zIndex(1)
                }
                .boxBlankStyle(cornerRadius: 12, padding: 4)
                .zIndex(1)
                Button(action: {
                    if colorTint.w != 0.0 || isDualToneActive {
                        onBeginAdjust?()
                        colorTint = SIMD4<Float>(x: 0.0, y: 0.0, z: 0.0, w: 0.0)
                        colorTintSecondary = SIMD4<Float>(x: 0.0, y: 0.0, z: 0.0, w: 0.0)
                        isDualToneActive = false
                        colorTintIntensity = 0.9
                        let gen = UIImpactFeedbackGenerator(style: .medium)
                        gen.impactOccurred()
                        onEndAdjust?()
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                        .frame(width: 24, height: 24)
                        .padding(10)
                        .background(colorSchemeManager.primaryColor.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            if colorTint.w > 0.0 || isDualToneActive {
                RulerSlider(
                    value: Binding(
                        get: { uiFromFactor(colorTintFactor) },
                        set: { colorTintFactor = factorFromUI($0) }
                    ),
                    range: 0...100,
                    step: 1.0,
                    totalTicks: 101,
                    majorTickEvery: 10,
                    format: { String(format: "%d", Int($0)) },
                    onEditingBegan: onBeginAdjust,
                    onEditingEnded: onEndAdjust
                )
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }
}

private struct AdjustmentIconButton: View {
    @EnvironmentObject private var colorSchemeManager: ColorSchemeManager
    let icon: String
    let isActive: Bool
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        let iconColor: Color = (isSelected || isActive)
            ? colorSchemeManager.primaryColor
            : colorSchemeManager.primaryColor.opacity(0.55)
        return Button(action: onTap) {
            VStack {
                Image(systemName: icon)
                    .frame(width: 16, height: 16)
                    .foregroundColor(iconColor)
            }
            .padding(8)
            .boxBlankStyle(cornerRadius: 8, padding: 10)
            .background(isSelected ? colorSchemeManager.primaryColor.opacity(0.10) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isActive ? Color.accentColor : Color.clear, lineWidth: 3)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

private struct ContrastSlider: View {
    @Binding var value: Float
    var onBegin: (() -> Void)? = nil
    var onEnd: (() -> Void)? = nil
    var body: some View {
        // Mapeia 0...100 para 0.5...1.5
        RulerSlider(
            value: Binding(
                get: { ((value - 0.5) * 100).rounded() },
                set: { value = ($0 / 100) + 0.5 }
            ),
            range: 0...100,
            step: 1.0,
            totalTicks: 101,
            majorTickEvery: 10,
            format: { String(format: "%d", Int($0 - 50) * 2) }, // -100 a 100
            onEditingBegan: onBegin,
            onEditingEnded: onEnd
        )
    }
}

private struct BrightnessSlider: View {
    @Binding var value: Float
    var onBegin: (() -> Void)? = nil
    var onEnd: (() -> Void)? = nil
    var body: some View {
        // Mapeia 0...100 para -0.5...0.5
        RulerSlider(
            value: Binding(
                get: { ((value + 0.5) * 100).rounded() },
                set: { value = ($0 / 100) - 0.5 }
            ),
            range: 0...100,
            step: 1.0,
            totalTicks: 101,
            majorTickEvery: 10,
            format: { String(format: "%d", Int($0 - 50) * 2) }, // -100 a 100
            onEditingBegan: onBegin,
            onEditingEnded: onEnd
        )
    }
}

private struct ExposureSlider: View {
    @Binding var value: Float
    var onBegin: (() -> Void)? = nil
    var onEnd: (() -> Void)? = nil
    var body: some View {
        // Mapeia 0...100 para -2.0...2.0
        RulerSlider(
            value: Binding(
                get: { ((value + 2.0) * 25).rounded() },
                set: { value = ($0 / 25) - 2.0 }
            ),
            range: 0...100,
            step: 1.0,
            totalTicks: 101,
            majorTickEvery: 10,
            format: { String(format: "%d", Int($0 - 50) * 2) }, // -100 a 100
            onEditingBegan: onBegin,
            onEditingEnded: onEnd
        )
    }
}

private struct SaturationSlider: View {
    @Binding var value: Float
    var onBegin: (() -> Void)? = nil
    var onEnd: (() -> Void)? = nil
    var body: some View {
        // Mapeia 0...100 para 0.0...2.0
        RulerSlider(
            value: Binding(
                get: { (value * 50).rounded() },
                set: { value = $0 / 50 }
            ),
            range: 0...100,
            step: 1.0,
            totalTicks: 101,
            majorTickEvery: 10,
            format: { String(format: "%d", Int($0) * 2 - 100) }, // -100 a 100
            onEditingBegan: onBegin,
            onEditingEnded: onEnd
        )
    }
}

private struct VibranceSlider: View {
    @Binding var value: Float
    var onBegin: (() -> Void)? = nil
    var onEnd: (() -> Void)? = nil
    var body: some View {
        // Mapeia 0...100 para -1.0...1.0
        RulerSlider(
            value: Binding(
                get: { ((value + 1.0) * 50).rounded() },
                set: { value = ($0 / 50) - 1.0 }
            ),
            range: 0...100,
            step: 1.0,
            totalTicks: 101,
            majorTickEvery: 10,
            format: { String(format: "%d", Int($0 - 50) * 2) }, // -100 a 100
            onEditingBegan: onBegin,
            onEditingEnded: onEnd
        )
    }
}

private struct OpacitySlider: View {
    @Binding var value: Float
    var body: some View {
        // Mapeia 0...100 para 0.0...1.0
        RulerSlider(
            value: Binding(
                get: { (value * 100).rounded() },
                set: { value = $0 / 100 }
            ),
            range: 0...100,
            step: 1.0,
            totalTicks: 101,
            majorTickEvery: 10,
            format: { String(format: "%d", 100 - Int($0)) } // 100 a 0
        )
    }
}

private struct ColorInvertSlider: View {
    @Binding var value: Float
    var body: some View {
        RulerSlider(
            value: $value,
            range: 0.0...1.0,
            step: 0.01,
            totalTicks: 101,
            majorTickEvery: 10,
            format: { String(format: "%.2f", $0) }
        )
    }
}

private struct PixelateSlider: View {
    @Binding var value: Float
    var onBegin: (() -> Void)? = nil
    var onEnd: (() -> Void)? = nil
    var body: some View {
        // Mapeia 0...100 para 1.0...40.0
        RulerSlider(
            value: Binding(
                get: { ((value - 1.0) * (100.0 / 39.0)).rounded() },
                set: { value = ($0 * (39.0 / 100.0)) + 1.0 }
            ),
            range: 0...100,
            step: 1.0,
            totalTicks: 101,
            majorTickEvery: 10,
            format: { String(format: "%d", Int($0) * 2 - 100) }, // -100 a 100
            onEditingBegan: onBegin,
            onEditingEnded: onEnd
        )
    }
}

private struct SharpenSlider: View {
    @Binding var value: Float // 0.0 ... 1.0
    var onBegin: (() -> Void)? = nil
    var onEnd: (() -> Void)? = nil
    var body: some View {
        // Map 0...100 -> 0.0...1.0
        RulerSlider(
            value: Binding(
                get: { (value * 100).rounded() },
                set: { value = $0 / 100 }
            ),
            range: 0...100,
            step: 1.0,
            totalTicks: 101,
            majorTickEvery: 10,
            format: { String(format: "%d", Int($0)) },
            onEditingBegan: onBegin,
            onEditingEnded: onEnd
        )
    }
}

private struct ClaritySlider: View {
    @Binding var value: Float // 0.0 ... 1.0
    var onBegin: (() -> Void)? = nil
    var onEnd:   (() -> Void)? = nil
    var body: some View {
        RulerSlider(
            value: Binding(
                get: { (value * 100).rounded() },
                set: { value = $0 / 100 }
            ),
            range: 0...100,
            step: 1.0,
            totalTicks: 101,
            majorTickEvery: 10,
            format: { String(format: "%d", Int($0)) },
            onEditingBegan: onBegin,
            onEditingEnded: onEnd
        )
    }
}

private struct GrainSlider: View {
    @Binding var value: Float // 0.0 ... 0.1 (UI shows 0..100)
    var onBegin: (() -> Void)? = nil
    var onEnd: (() -> Void)? = nil
    var body: some View {
        // Map 0...100 -> 0.0...0.1
        RulerSlider(
            value: Binding(
                get: { (value * 1000).rounded() },
                set: { value = $0 / 1000 }
            ),
            range: 0...100,
            step: 1.0,
            totalTicks: 101,
            majorTickEvery: 10,
            format: { String(format: "%d", Int($0)) },
            onEditingBegan: onBegin,
            onEditingEnded: onEnd
        )
    }
}

// GrainSizeSlider removed; grain size is fixed in pipeline

private struct FadeSlider: View {
    @Binding var value: Float // 0.0 ... 1.0
    var onBegin: (() -> Void)? = nil
    var onEnd: (() -> Void)? = nil
    var body: some View {
        // Map 0...100 -> 0.0...1.0
        RulerSlider(
            value: Binding(
                get: { (value * 100).rounded() },
                set: { value = $0 / 100 }
            ),
            range: 0...100,
            step: 1.0,
            totalTicks: 101,
            majorTickEvery: 10,
            format: { String(format: "%d", Int($0)) },
            onEditingBegan: onBegin,
            onEditingEnded: onEnd
        )
    }
}

private struct ColorTintSlider: View {
    @Binding var value: Float
    var body: some View {
        // Mapeia 0...100 para 0.0...6.0
        RulerSlider(
            value: Binding(
                get: { (value * (100.0 / 6.0)).rounded() },
                set: { value = $0 * (6.0 / 100.0) }
            ),
            range: 0...100,
            step: 1.0,
            totalTicks: 31,
            majorTickEvery: 5,
            format: { String(format: "%d", Int($0) * 2 - 100) } // -100 a 100
        )
    }
}

// Sliders de Duotone removidos
