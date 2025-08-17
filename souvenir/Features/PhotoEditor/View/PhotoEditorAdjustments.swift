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
    @State private var lastMajorIndexFeedback: Int? = nil
    @EnvironmentObject private var colorSchemeManager: ColorSchemeManager

    init(
        value: Binding<Float>,
        range: ClosedRange<Float>,
        step: Float = 1.0,
        totalTicks: Int = 31, // padronizado ~30 intervalos
        majorTickEvery: Int = 5,
        thumbSize: CGFloat = 28,
        rulerHeight: CGFloat = 18,
        sliderHeight: CGFloat = 48,
        format: @escaping (Float) -> String = { String(format: "%.0f", $0) }
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
    }

    var body: some View {
        GeometryReader { geo in
            // Assimétrico: esquerda como antes (bom), direita com respiro extra
            let leftInset = thumbSize / 2
            let rightInset = max(thumbSize / 2, 12)
            let sliderWidth = max(1, geo.size.width - thumbSize - (leftInset + rightInset))
            let valueRange = range.upperBound - range.lowerBound
            let clampedValue = min(max(value, range.lowerBound), range.upperBound)
            let percent = CGFloat((clampedValue - range.lowerBound) / valueRange)
            let currentX = percent * sliderWidth
            let spacing = sliderWidth / CGFloat(totalTicks - 1)
            let maxTickWidth: CGFloat = 2.5

            ZStack(alignment: .leading) {
                // Trilha suave ao fundo
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        LinearGradient(
                            colors: [
                                colorSchemeManager.primaryColor.opacity(0.12),
                                colorSchemeManager.primaryColor.opacity(0.05)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: max(2, rulerHeight * 0.35))
                    .offset(y: rulerHeight * 0.3)
                    .padding(.leading, leftInset)
                    .padding(.trailing, rightInset)

                // Régua (posicionamento absoluto para garantir último tick visível)
        ZStack(alignment: .leading) {
                    ForEach(0..<totalTicks, id: \.self) { i in
                        let isMajor = (i % majorTickEvery == 0)
                        let tickW: CGFloat = isMajor ? 3.0 : 1.0
                        // Posição base uniformemente distribuída no domínio [0, sliderWidth]
                        let centerX = CGFloat(i) / CGFloat(totalTicks - 1) * sliderWidth
                        Capsule(style: .continuous)
                            .fill(isMajor ? colorSchemeManager.primaryColor : colorSchemeManager.primaryColor.opacity(0.55))
                            .frame(width: tickW,
                                   height: isMajor ? rulerHeight : rulerHeight * 0.6)
                            .position(x: centerX, y: rulerHeight / 2)
                    }
                    // Trailing cap suave depois do último tick
                    let endX = sliderWidth
                    RoundedRectangle(cornerRadius: 1)
                        .fill(colorSchemeManager.primaryColor.opacity(0.10))
                        .frame(width: max(6, sliderWidth * 0.06), height: max(2, rulerHeight * 0.35))
                        .position(x: endX - max(3, (sliderWidth * 0.06)/2), y: rulerHeight * 0.8)
                }
                .frame(width: sliderWidth, height: rulerHeight)
        .padding(.leading, leftInset)
        .padding(.trailing, rightInset)

                // Thumb
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
                    .offset(x: currentX + leftInset)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .updating($dragOffset) { value, state, _ in
                                state = value.translation.width
                            }
                            .onChanged { gesture in
                                isDragging = true
                                let sliderWidth = max(1, geo.size.width - thumbSize - (leftInset + rightInset))
                                let localX = max(0, min(sliderWidth, gesture.location.x - leftInset - thumbSize/2))
                                let percent = localX / sliderWidth
                                var rawValue = Float(percent) * valueRange + range.lowerBound

                                // Snap forte para os majors visuais
                                let majorIndices = stride(from: 0, to: totalTicks, by: majorTickEvery).map { $0 }
                                let majorPositions = majorIndices.map { CGFloat($0) / CGFloat(totalTicks - 1) * sliderWidth }
                                let nearestMajorIndex = majorPositions.enumerated().min(by: { abs($0.element - localX) < abs($1.element - localX) })?.offset
                                let snapPx: CGFloat = max(6, spacing * 0.35)
                                if let nearestIdx = nearestMajorIndex, abs(majorPositions[nearestIdx] - localX) <= snapPx {
                                    // trava no valor exato do major visual
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
                                    // feedback leve em mudanças discretas maiores
                                    let generator = UIImpactFeedbackGenerator(style: .light)
                                    generator.impactOccurred(intensity: 0.6)
                                    lastMajorIndexFeedback = nil
                                }

                                value = snapped
                            }
                            .onEnded { _ in
                                isDragging = false
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
//
//  PhotoEditorAdjustments.swift
//  souvenir
//
//  Created by Erick Barcelos on 30/05/25.
//

struct Adjustment: Identifiable, Hashable {
    let id: String // unique key
    let label: String
    let icon: String
}

struct PhotoEditorAdjustments: View {
    @Binding var contrast: Float
    @Binding var brightness: Float
    @Binding var exposure: Float
    @Binding var saturation: Float
    @Binding var vibrance: Float
    @Binding var colorInvert: Float
    @Binding var pixelateAmount: Float
    @Binding var colorTint: SIMD4<Float>
    @Binding var colorTintIntensity: Float
    @Binding var colorTintFactor: Float
    // Duotone removido
    @State private var selectedAdjustment: String = "contrast"
    @EnvironmentObject private var colorSchemeManager: ColorSchemeManager

    // Paleta de tint sugeridas (bonitas/versáteis)
    private let tintPresets: [SIMD4<Float>] = [
        SIMD4<Float>(1.00, 0.29, 0.23, 1.0), // vermelho coral
        SIMD4<Float>(1.00, 0.55, 0.00, 1.0), // laranja
        SIMD4<Float>(1.00, 0.84, 0.00, 1.0), // amarelo
        SIMD4<Float>(0.85, 0.80, 0.60, 1.0), // champagne
        SIMD4<Float>(0.10, 0.78, 0.64, 1.0), // teal
        SIMD4<Float>(0.00, 0.68, 0.94, 1.0), // azul claro
        SIMD4<Float>(0.18, 0.39, 0.96, 1.0), // azul acentuado
    SIMD4<Float>(0.47, 0.33, 0.94, 1.0), // roxo
    SIMD4<Float>(0.93, 0.33, 0.58, 1.0), // pink
    SIMD4<Float>(0.64, 0.86, 0.22, 1.0)  // lime
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
        Adjustment(id: "colorInvert", label: "Inverter", icon: "circle.righthalf.filled"),
        Adjustment(id: "pixelateAmount", label: "Pixelizar", icon: "rectangle.split.3x3"),
    Adjustment(id: "colorTint", label: "Tint", icon: "paintpalette")
    ]
    
    
    var body: some View {
        VStack {
            if let selected = adjustments.first(where: { $0.id == selectedAdjustment }) {
                Text(selected.label)
                    .font(.caption2)
                    .foregroundColor(colorSchemeManager.primaryColor.opacity(0.6))
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(adjustments) { adj in
                        // Define se o botão está "ativo" (valor diferente do padrão)
                        let isActive: Bool = {
                            switch adj.id {
                            case "contrast": return contrast != 1.0
                            case "brightness": return brightness != 0.0
                            case "exposure": return exposure != 0.0
                            case "saturation": return saturation != 1.0
                            case "vibrance": return vibrance != 0.0
                            case "colorInvert": return colorInvert == 1.0
                            case "pixelateAmount": return pixelateAmount != 1.0
                            case "colorTint": return !(colorTint.x == 0.0 && colorTint.y == 0.0 && colorTint.z == 0.0 && colorTint.w == 0.0)
                            case "duotone": return false
                            default: return false
                            }
                        }()
                        let isSelected = selectedAdjustment == adj.id

                        if adj.id == "colorInvert" {
                            Button(action: { selectedAdjustment = adj.id }) {
                                VStack {
                                    Image(systemName: adj.icon)
                                        .frame(width: 16, height: 16)
                                        .foregroundColor(
                                            isSelected || isActive
                                            ? colorSchemeManager.primaryColor
                                            : colorSchemeManager.primaryColor.opacity(0.55)
                                        )
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
                        } else {
                            Button(action: { selectedAdjustment = adj.id }) {
                                VStack {
                                    Image(systemName: adj.icon)
                                        .frame(width: 16, height: 16)
                                        .foregroundColor(
                                            isSelected || isActive
                                            ? colorSchemeManager.primaryColor
                                            : colorSchemeManager.primaryColor.opacity(0.55)
                                        )
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
                        }
                    }
                }
                .padding(.horizontal)
            }
            
            Group {
                if selectedAdjustment == "contrast" {
                    ContrastSlider(value: $contrast)
                        .padding(.horizontal)
                } else if selectedAdjustment == "brightness" {
                    BrightnessSlider(value: $brightness)
                        .padding(.horizontal)
                } else if selectedAdjustment == "exposure" {
                    ExposureSlider(value: $exposure)
                        .padding(.horizontal)
                } else if selectedAdjustment == "saturation" {
                    SaturationSlider(value: $saturation)
                        .padding(.horizontal)
                } else if selectedAdjustment == "vibrance" {
                    VibranceSlider(value: $vibrance)
                        .padding(.horizontal)
                } else if selectedAdjustment == "colorInvert" {
                    // Segmented-like toggle OFF/ON ocupando toda a largura
                    HStack(spacing: 12) {
            Button(action: {
                            if colorInvert != 0.0 {
                                colorInvert = 0.0
                                let gen = UIImpactFeedbackGenerator(style: .medium)
                                gen.impactOccurred()
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
                                colorInvert = 1.0
                                let gen = UIImpactFeedbackGenerator(style: .medium)
                                gen.impactOccurred()
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
                    .padding(.horizontal)
                } else if selectedAdjustment == "pixelateAmount" {
                    PixelateSlider(value: $pixelateAmount)
                        .padding(.horizontal)
                } else if selectedAdjustment == "colorTint" {
                    VStack(spacing: 10) {
                        HStack(spacing: 12) {
                            // Scroll horizontal de cores (round squares)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(Array(tintPresets.enumerated()), id: \.offset) { _, preset in
                                        let presetColor = Color(red: Double(preset.x), green: Double(preset.y), blue: Double(preset.z))
                                        let isSelectedPreset = colorEquals(colorTint, preset)
                                        Button(action: {
                                            colorTint = SIMD4<Float>(preset.x, preset.y, preset.z, 1.0)
                                            // Define uma intensidade muito sutil padrão
                                            colorTintIntensity = 0.9
                                            let gen = UIImpactFeedbackGenerator(style: .light)
                                            gen.impactOccurred()
                                        }) {
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .fill(presetColor)
                                                .frame(width: 44, height: 44)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 10)
                                                        .stroke(isSelectedPreset ? Color.accentColor : Color.clear, lineWidth: 3)
                                                        .padding(0.5)
                                                )
                                                .contentShape(RoundedRectangle(cornerRadius: 10))
                                        }
                                    }
                                    // Swatch de cor customizada com ColorPicker inline
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(LinearGradient(colors: [.red, .yellow, .green, .blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                                            .frame(width: 44, height: 44)
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(Color.accentColor.opacity((colorTint.w > 0 && !tintPresets.contains(where: { colorEquals($0, colorTint) })) ? 1 : 0), lineWidth: 3)
                                            .frame(width: 44, height: 44)
                                        ColorPicker("", selection: Binding(
                                            get: {
                                                Color(red: Double((colorTint.w == 0 ? 1.0 : colorTint.x)),
                                                      green: Double((colorTint.w == 0 ? 1.0 : colorTint.y)),
                                                      blue: Double((colorTint.w == 0 ? 1.0 : colorTint.z)),
                                                      opacity: 1.0)
                                            },
                                            set: { newColor in
                                                if let components = newColor.cgColor?.components, components.count >= 3 {
                                                    colorTint = SIMD4<Float>(Float(components[0]), Float(components[1]), Float(components[2]), 1.0)
                                                    // Define intensidade muito sutil padrão
                                                    colorTintIntensity = 0.9
                                                    let gen = UIImpactFeedbackGenerator(style: .light)
                                                    gen.impactOccurred()
                                                }
                                            }
                                        ))
                                        .labelsHidden()
                                        .frame(width: 44, height: 44)
                                        .opacity(0.02) // invisível, apenas capturando o toque
                                    }
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 6)
                            }
                            .boxBlankStyle(cornerRadius: 12, padding: 4)
                            // Botão para limpar o tint selecionado
                            Button(action: {
                                if colorTint.w != 0.0 {
                                    colorTint = SIMD4<Float>(0.0, 0.0, 0.0, 0.0)
                                    // Mantém intensidade default para uma próxima seleção
                                    colorTintIntensity = 0.9
                                    let gen = UIImpactFeedbackGenerator(style: .medium)
                                    gen.impactOccurred()
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
                        // Ruler para a força do Tint (factor)
                        RulerSlider(
                            value: Binding(
                                get: { ((min(max(colorTintFactor, 0.0), 0.25)) / 0.25 * 100).rounded() },
                                set: { colorTintFactor = min(max(($0 / 100) * 0.25, 0.0), 0.25) }
                            ),
                            range: 0...100,
                            step: 1.0,
                            totalTicks: 31,
                            majorTickEvery: 5,
                            format: { String(format: "%d", Int($0)) }
                        )
                    }
                    .padding(.horizontal)
                    // sem modal adicional
                }
            }
        }
    }
}

private struct ContrastSlider: View {
    @Binding var value: Float
    var body: some View {
        // Mapeia 0...100 para 0.5...1.5
        RulerSlider(
            value: Binding(
                get: { ((value - 0.5) * 100).rounded() },
                set: { value = ($0 / 100) + 0.5 }
            ),
            range: 0...100,
            step: 1.0,
            totalTicks: 31,
            majorTickEvery: 5,
            format: { String(format: "%d", Int($0 - 50) * 2) } // -100 a 100
        )
    }
}

private struct BrightnessSlider: View {
    @Binding var value: Float
    var body: some View {
        // Mapeia 0...100 para -0.5...0.5
        RulerSlider(
            value: Binding(
                get: { ((value + 0.5) * 100).rounded() },
                set: { value = ($0 / 100) - 0.5 }
            ),
            range: 0...100,
            step: 1.0,
            totalTicks: 31,
            majorTickEvery: 5,
            format: { String(format: "%d", Int($0 - 50) * 2) } // -100 a 100
        )
    }
}

private struct ExposureSlider: View {
    @Binding var value: Float
    var body: some View {
        // Mapeia 0...100 para -2.0...2.0
        RulerSlider(
            value: Binding(
                get: { ((value + 2.0) * 25).rounded() },
                set: { value = ($0 / 25) - 2.0 }
            ),
            range: 0...100,
            step: 1.0,
            totalTicks: 31,
            majorTickEvery: 5,
            format: { String(format: "%d", Int($0 - 50) * 2) } // -100 a 100
        )
    }
}

private struct SaturationSlider: View {
    @Binding var value: Float
    var body: some View {
        // Mapeia 0...100 para 0.0...2.0
        RulerSlider(
            value: Binding(
                get: { (value * 50).rounded() },
                set: { value = $0 / 50 }
            ),
            range: 0...100,
            step: 1.0,
            totalTicks: 31,
            majorTickEvery: 5,
            format: { String(format: "%d", Int($0) * 2 - 100) } // -100 a 100
        )
    }
}

private struct VibranceSlider: View {
    @Binding var value: Float
    var body: some View {
        // Mapeia 0...100 para -1.0...1.0
        RulerSlider(
            value: Binding(
                get: { ((value + 1.0) * 50).rounded() },
                set: { value = ($0 / 50) - 1.0 }
            ),
            range: 0...100,
            step: 1.0,
            totalTicks: 31,
            majorTickEvery: 5,
            format: { String(format: "%d", Int($0 - 50) * 2) } // -100 a 100
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
            totalTicks: 31,
            majorTickEvery: 5,
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
            totalTicks: 31,
            majorTickEvery: 5,
            format: { String(format: "%.2f", $0) }
        )
    }
}

private struct PixelateSlider: View {
    @Binding var value: Float
    var body: some View {
        // Mapeia 0...100 para 1.0...40.0
        RulerSlider(
            value: Binding(
                get: { ((value - 1.0) * (100.0 / 39.0)).rounded() },
                set: { value = ($0 * (39.0 / 100.0)) + 1.0 }
            ),
            range: 0...100,
            step: 1.0,
            totalTicks: 31,
            majorTickEvery: 5,
            format: { String(format: "%d", Int($0) * 2 - 100) } // -100 a 100
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

