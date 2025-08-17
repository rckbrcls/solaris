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
            let sliderWidth = max(1, geo.size.width - thumbSize)
            let valueRange = range.upperBound - range.lowerBound
            let clampedValue = min(max(value, range.lowerBound), range.upperBound)
            let percent = CGFloat((clampedValue - range.lowerBound) / valueRange)
            let currentX = percent * sliderWidth
            let spacing = sliderWidth / CGFloat(totalTicks - 1)

            ZStack(alignment: .leading) {
                // Trilha suave ao fundo
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        LinearGradient(
                            colors: [
                                colorSchemeManager.primaryColor.opacity(0.14),
                                colorSchemeManager.primaryColor.opacity(0.06)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: max(2, rulerHeight * 0.35))
                    .offset(y: rulerHeight * 0.3)
                    .padding(.horizontal, thumbSize/2)

                // Régua
                HStack(spacing: 0) {
                    ForEach(0..<totalTicks, id: \.self) { i in
                        let isMajor = (i % majorTickEvery == 0)
                        Capsule(style: .continuous)
                            .fill(isMajor ? colorSchemeManager.primaryColor : colorSchemeManager.primaryColor.opacity(0.55))
                            .frame(width: isMajor ? 2.5 : 1.5,
                                   height: isMajor ? rulerHeight : rulerHeight * 0.6)
                        if i != totalTicks - 1 {
                            Spacer(minLength: spacing - ((isMajor ? 2.5 : 1.5)))
                                .frame(width: spacing - ((isMajor ? 2.5 : 1.5)))
                        }
                    }
                }
                .frame(height: rulerHeight)
                .padding(.horizontal, thumbSize/2)

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
                    .offset(x: currentX)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .updating($dragOffset) { value, state, _ in
                                state = value.translation.width
                            }
                            .onChanged { gesture in
                                isDragging = true
                                let sliderWidth = max(1, geo.size.width - thumbSize)
                                let localX = max(0, min(sliderWidth, gesture.location.x - thumbSize/2))
                                let percent = localX / sliderWidth
                                var rawValue = Float(percent) * valueRange + range.lowerBound

                                // Snap forte para os majors visuais
                                let majorIndices = stride(from: 0, to: totalTicks, by: majorTickEvery).map { $0 }
                                let majorPositions = majorIndices.map { CGFloat($0) * spacing }
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
    @Binding var opacity: Float
    @Binding var colorInvert: Float
    @Binding var pixelateAmount: Float
    @Binding var colorTint: SIMD4<Float>
    @Binding var colorTintIntensity: Float
    @Binding var duotoneEnabled: Bool
    @Binding var duotoneShadowColor: SIMD4<Float>
    @Binding var duotoneHighlightColor: SIMD4<Float>
    @Binding var duotoneShadowIntensity: Float
    @Binding var duotoneHighlightIntensity: Float
    @State private var selectedAdjustment: String = "contrast"
    @EnvironmentObject private var colorSchemeManager: ColorSchemeManager

    let adjustments: [Adjustment] = [
        Adjustment(id: "contrast", label: "Contraste", icon: "circle.lefthalf.fill"),
        Adjustment(id: "brightness", label: "Brilho", icon: "sun.max"),
        Adjustment(id: "exposure", label: "Exposição", icon: "sunrise"),
        Adjustment(id: "saturation", label: "Saturação", icon: "drop"),
        Adjustment(id: "vibrance", label: "Vibrance", icon: "waveform.path.ecg"),
        Adjustment(id: "opacity", label: "Opacidade", icon: "circle.dashed"),
        Adjustment(id: "colorInvert", label: "Inverter", icon: "circle.righthalf.filled"),
        Adjustment(id: "pixelateAmount", label: "Pixelizar", icon: "rectangle.split.3x3"),
        Adjustment(id: "colorTint", label: "Tint", icon: "paintpalette"),
        Adjustment(id: "duotone", label: "Duotone", icon: "circles.hexagonpath.fill")
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
                            case "opacity": return opacity != 1.0
                            case "colorInvert": return colorInvert == 1.0
                            case "pixelateAmount": return pixelateAmount != 1.0
                            case "colorTint": return !(colorTint.x == 0.0 && colorTint.y == 0.0 && colorTint.z == 0.0 && colorTint.w == 0.0)
                            case "duotone": return duotoneEnabled
                            default: return false
                            }
                        }()

                        if adj.id == "colorInvert" {
                            Button(action: {
                                // Toggle colorInvert
                                colorInvert = colorInvert == 1.0 ? 0.0 : 1.0
                                selectedAdjustment = adj.id
                            }) {
                                VStack {
                                    Image(systemName: adj.icon)
                                        .frame(width: 16, height: 16)
                                        .foregroundColor(isActive ? colorSchemeManager.primaryColor : colorSchemeManager.primaryColor.opacity(0.55))
                                }
                                .padding(8)
                                .boxBlankStyle(cornerRadius: 8, padding: 10)
                                .background(isActive ? colorSchemeManager.primaryColor.opacity(0.08) : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        } else {
                            Button(action: { selectedAdjustment = adj.id }) {
                                VStack {
                                    Image(systemName: adj.icon)
                                        .frame(width: 16, height: 16)
                                        .foregroundColor(isActive ? colorSchemeManager.primaryColor : colorSchemeManager.primaryColor.opacity(0.55))
                                }
                                .padding(8)
                                .boxBlankStyle(cornerRadius: 8, padding: 10)
                                .background(isActive ? colorSchemeManager.primaryColor.opacity(0.08) : Color.clear)
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
                } else if selectedAdjustment == "opacity" {
                    OpacitySlider(value: $opacity)
                        .padding(.horizontal)
                } else if selectedAdjustment == "colorInvert" {
                    // Não mostra slider, só mostra se está ativado
                    HStack {
                        Image(systemName: "circle.righthalf.filled")
                            .foregroundColor(colorInvert == 1.0 ? colorSchemeManager.primaryColor : colorSchemeManager.primaryColor.opacity(0.55))
                        Text(colorInvert == 1.0 ? "Invertido" : "Normal")
                            .foregroundColor(colorSchemeManager.primaryColor.opacity(0.7))
                    }
                    .padding(.horizontal)
                } else if selectedAdjustment == "pixelateAmount" {
                    PixelateSlider(value: $pixelateAmount)
                        .padding(.horizontal)
                } else if selectedAdjustment == "colorTint" {
                    HStack(spacing: 16) {
                        ColorPicker("Cor do Tint", selection: Binding(
                            get: {
                                Color(red: Double(colorTint.x), green: Double(colorTint.y), blue: Double(colorTint.z), opacity: Double(colorTint.w))
                            },
                            set: { newColor in
                                if let components = newColor.cgColor?.components, components.count >= 3 {
                                    colorTint = SIMD4<Float>(Float(components[0]), Float(components[1]), Float(components[2]), components.count > 3 ? Float(components[3]) : 1.0)
                                }
                            }
                        ))
                        .frame(width: 48, height: 48)
                        .scaleEffect(1.5)

                        Button(action: {
                            // Remove cor: define como transparente
                            colorTint = SIMD4<Float>(0.0, 0.0, 0.0, 0.0)
                        }) {
                            Text("Remover cor")
                                .font(.caption)
                                .foregroundColor(.red)
                                .padding(8)
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                        }
                    }
                    .padding(.horizontal)
                } else if selectedAdjustment == "duotone" {
                    VStack(spacing: 12) {
                        Toggle("Ativar Duotone", isOn: $duotoneEnabled)
                            .padding(.horizontal)
                        DuotoneShadowIntensitySlider(value: $duotoneShadowIntensity)
                            .padding(.horizontal)
                        DuotoneHighlightIntensitySlider(value: $duotoneHighlightIntensity)
                            .padding(.horizontal)
                        HStack {
                            VStack {
                                Text("Sombras")
                                    .font(.caption)
                                    .foregroundColor(colorSchemeManager.primaryColor.opacity(0.6))
                                ColorPicker("", selection: Binding(
                                    get: {
                                        Color(red: Double(duotoneShadowColor.x), 
                                             green: Double(duotoneShadowColor.y),
                                             blue: Double(duotoneShadowColor.z),
                                             opacity: Double(duotoneShadowColor.w))
                                    },
                                    set: { newColor in
                                        if let components = newColor.cgColor?.components, components.count >= 3 {
                                            duotoneShadowColor = SIMD4<Float>(
                                                Float(components[0]),
                                                Float(components[1]),
                                                Float(components[2]), 
                                                components.count > 3 ? Float(components[3]) : 1.0
                                            )
                                        }
                                    }
                                ))
                                .labelsHidden()
                            }
                            Spacer()
                            VStack {
                                Text("Destaques")
                                    .font(.caption)
                                    .foregroundColor(colorSchemeManager.primaryColor.opacity(0.6))
                                ColorPicker("", selection: Binding(
                                    get: {
                                        Color(red: Double(duotoneHighlightColor.x),
                                             green: Double(duotoneHighlightColor.y),
                                             blue: Double(duotoneHighlightColor.z),
                                             opacity: Double(duotoneHighlightColor.w))
                                    },
                                    set: { newColor in
                                        if let components = newColor.cgColor?.components, components.count >= 3 {
                                            duotoneHighlightColor = SIMD4<Float>(
                                                Float(components[0]),
                                                Float(components[1]), 
                                                Float(components[2]),
                                                components.count > 3 ? Float(components[3]) : 1.0
                                            )
                                        }
                                    }
                                ))
                                .labelsHidden()
                            }
                        }
                        .padding(.horizontal)
                    }
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

private struct DuotoneShadowIntensitySlider: View {
    @Binding var value: Float
    var body: some View {
        VStack(alignment: .leading) {
            Text("Intensidade Sombras")
                .font(.caption)
                .foregroundColor(.secondary)
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
}

private struct DuotoneHighlightIntensitySlider: View {
    @Binding var value: Float
    var body: some View {
        VStack(alignment: .leading) {
            Text("Intensidade Destaques")
                .font(.caption)
                .foregroundColor(.secondary)
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
}

