import SwiftUI
import UIKit
import MetalPetal

struct FilterPreset: Identifiable, Hashable {
    let id: String
    let name: String
    let subtitle: String?
    let swatch: [Color]
    let state: PhotoEditState
}

// Hashable/Equatable based only on `id` to avoid requiring `PhotoEditState` to be Hashable
extension FilterPreset {
    static func == (lhs: FilterPreset, rhs: FilterPreset) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

enum FilterGroup: String, CaseIterable {
    case all = "All"
    case classics = "Classics"
    case cinema = "Cinema"
    case vintage = "Vintage"
    case portrait = "Portrait"
    case street = "Street"
    case dost = "DÖST"
}

struct PhotoEditorFilters: View {
    @Binding var editState: PhotoEditState
    var registerUndo: (() -> Void)? = nil
    var baseImage: UIImage?
    var applyBaseFilter: ((PhotoEditState) -> Void)? = nil
    var applyCompleteFilter: ((PhotoEditState) -> Void)? = nil
    var isFilterApplied: ((PhotoEditState) -> Bool)? = nil // Nova função para verificar se filtro está aplicado
    var isFilterAppliedToSliders: ((PhotoEditState) -> Bool)? = nil // Nova função para verificar se foi aplicado via long press
    var isFilterAppliedAsBase: ((PhotoEditState) -> Bool)? = nil // Nova função para verificar se foi aplicado via tap
    var hasFilterCombination: (() -> Bool)? = nil // Nova função para verificar se há combinação de filtros
    var getSliderFilter: (() -> PhotoEditState?)? = nil // Obtém filtro dos sliders
    var getBaseFilter: (() -> PhotoEditState?)? = nil // Obtém filtro base

    @State private var selectedGroup: FilterGroup = .all
    @State private var stage: Stage = .groups
    @State private var selectedPresetID: String? = nil
    @EnvironmentObject private var colorSchemeManager: ColorSchemeManager

    enum Stage { case groups, presets }

    @State private var thumbs: [String: UIImage] = [:]
    private let mtiContext: MTIContext? = try? MTIContext(device: MTLCreateSystemDefaultDevice()!)

    // Metal-only; removed CI kernels for grain.

    private var classicsPresets: [FilterPreset] {
        [
            FilterPreset(
                id: "bw",
                name: "B&W",
                subtitle: "Monochrome",
                swatch: [.black, .white],
                state: {
                    var s = PhotoEditState()
                    s.saturation = 0.0
                    s.contrast = 1.15
                    s.exposure = 0.05
                    return s
                }()
            ),
            FilterPreset(
                id: "vivid",
                name: "Vivid",
                subtitle: "Intense",
                swatch: [.orange, .pink],
                state: {
                    var s = PhotoEditState()
                    s.saturation = 1.25
                    s.vibrance = 0.25
                    s.contrast = 1.1
                    return s
                }()
            ),
            FilterPreset(
                id: "cool",
                name: "Cool",
                subtitle: "Cold tones",
                swatch: [.blue, .mint],
                state: {
                    var s = PhotoEditState()
                    s.colorTint = SIMD4<Float>(0.7, 0.85, 1.0, 1.0)
                    s.colorTintIntensity = 0.9
                    s.colorTintFactor = 0.22
                    s.vibrance = 0.1
                    return s
                }()
            ),
            FilterPreset(
                id: "warm",
                name: "Warm",
                subtitle: "Warm tones",
                swatch: [.yellow, .orange],
                state: {
                    var s = PhotoEditState()
                    s.colorTint = SIMD4<Float>(1.0, 0.9, 0.7, 1.0)
                    s.colorTintIntensity = 0.9
                    s.colorTintFactor = 0.22
                    s.exposure = 0.05
                    s.vibrance = 0.15
                    return s
                }()
            ),
            FilterPreset(
                id: "fade",
                name: "Fade",
                subtitle: "Soft look",
                swatch: [.gray, .white],
                state: {
                    var s = PhotoEditState()
                    s.fade = 0.22
                    s.contrast = 0.95
                    s.vibrance = 0.04
                    return s
                }()
            )
        ]
    }

    private var dostPresets: [FilterPreset] {
        [
            FilterPreset(
                id: "dost_blue",
                name: "BLUE",
                subtitle: "Cool tone",
                swatch: [.blue, .indigo],
                state: {
                    var s = PhotoEditState()
                    s.saturation = 1.35
                    s.vibrance = 0.45
                    s.contrast = 1.25
                    s.colorTint = SIMD4<Float>(0.05, 0.30, 1.0, 1.0)
                    s.colorTintSecondary = SIMD4<Float>(0.0, 0.15, 0.90, 1.0)
                    s.isDualToneActive = true
                    s.colorTintIntensity = 1.0
                    s.colorTintFactor = 0.80
                    s.grain = 0.025
                    s.clarity = 0.20
                    return s
                }()
            ),
            FilterPreset(
                id: "dost_lu",
                name: "LU",
                subtitle: "Warm devil",
                swatch: [.red, .orange],
                state: {
                    var s = PhotoEditState()
                    s.contrast = 1.35
                    s.saturation = 1.45
                    s.vibrance = 0.40
                    s.exposure = 0.08
                    s.colorTint = SIMD4<Float>(1.0, 0.15, 0.15, 1.0)
                    s.colorTintSecondary = SIMD4<Float>(0.85, 0.25, 0.25, 1.0)
                    s.isDualToneActive = true
                    s.colorTintIntensity = 1.0
                    s.colorTintFactor = 0.75
                    s.grain = 0.03
                    s.sharpen = 0.15
                    return s
                }()
            ),
            FilterPreset(
                id: "dost_lilii",
                name: "LILII",
                subtitle: "Purple magic",
                swatch: [.purple, .pink],
                state: {
                    var s = PhotoEditState()
                    s.contrast = 1.25
                    s.saturation = 1.40
                    s.vibrance = 0.35
                    s.colorTint = SIMD4<Float>(0.60, 0.15, 0.90, 1.0)
                    s.colorTintSecondary = SIMD4<Float>(0.75, 0.30, 1.0, 1.0)
                    s.isDualToneActive = true
                    s.colorTintIntensity = 1.0
                    s.colorTintFactor = 0.70
                    s.grain = 0.02
                    s.brightness = 0.05
                    s.fade = 0.10
                    return s
                }()
            )
        ]
    }

    private var cinemaPresets: [FilterPreset] {
        [
            FilterPreset(
                id: "cinema_noir",
                name: "Film Noir",
                subtitle: "Classic drama",
                swatch: [.black, .gray],
                state: {
                    var s = PhotoEditState()
                    s.saturation = 0.0
                    s.contrast = 1.35
                    s.clarity = 0.40
                    s.grain = 0.03
                    s.brightness = -0.08
                    return s
                }()
            ),
            FilterPreset(
                id: "cinema_teal_orange",
                name: "Blockbuster",
                subtitle: "Orange & Blue",
                swatch: [.orange, .cyan],
                state: {
                    var s = PhotoEditState()
                    s.contrast = 1.25
                    s.saturation = 1.20
                    s.vibrance = 0.30
                    s.colorTint = SIMD4<Float>(0.30, 0.70, 1.0, 1.0)
                    s.colorTintSecondary = SIMD4<Float>(1.0, 0.65, 0.30, 1.0)
                    s.isDualToneActive = true
                    s.colorTintIntensity = 0.85
                    s.colorTintFactor = 0.45
                    return s
                }()
            ),
            FilterPreset(
                id: "cinema_bleach_bypass",
                name: "Bleach",
                subtitle: "Silver retention",
                swatch: [.gray, .yellow.opacity(0.7)],
                state: {
                    var s = PhotoEditState()
                    s.contrast = 1.45
                    s.saturation = 0.65
                    s.brightness = 0.08
                    s.clarity = 0.35
                    s.grain = 0.02
                    s.sharpen = 0.15
                    return s
                }()
            ),
            FilterPreset(
                id: "cinema_sepia_tone",
                name: "Sepia Tone",
                subtitle: "Classic western",
                swatch: [.brown, .yellow.opacity(0.8)],
                state: {
                    var s = PhotoEditState()
                    s.saturation = 0.0
                    s.colorTint = SIMD4<Float>(0.85, 0.65, 0.45, 1.0)
                    s.colorTintIntensity = 0.90
                    s.colorTintFactor = 0.55
                    s.contrast = 1.15
                    s.grain = 0.025
                    s.exposure = 0.05
                    return s
                }()
            ),
            FilterPreset(
                id: "cinema_negative",
                name: "Negative",
                subtitle: "Film negative",
                swatch: [.black, .white],
                state: {
                    var s = PhotoEditState()
                    s.colorInvert = 1.0
                    s.contrast = 1.10
                    s.brightness = 0.10
                    s.saturation = 0.85
                    return s
                }()
            ),
            FilterPreset(
                id: "cinema_desaturated",
                name: "Desaturated",
                subtitle: "Modern drama",
                swatch: [.gray.opacity(0.7), .blue.opacity(0.5)],
                state: {
                    var s = PhotoEditState()
                    s.saturation = 0.40
                    s.contrast = 1.20
                    s.brightness = -0.05
                    s.fade = 0.15
                    s.clarity = 0.20
                    return s
                }()
            )
        ]
    }

    private var vintagePresets: [FilterPreset] {
        [
            FilterPreset(
                id: "vintage_kodachrome",
                name: "Kodachrome",
                subtitle: "Vibrant colors",
                swatch: [.red, .yellow],
                state: {
                    var s = PhotoEditState()
                    s.saturation = 1.35
                    s.vibrance = 0.40
                    s.contrast = 1.15
                    s.colorTint = SIMD4<Float>(1.0, 0.85, 0.70, 1.0)
                    s.colorTintIntensity = 0.80
                    s.colorTintFactor = 0.25
                    s.grain = 0.015
                    s.sharpen = 0.10
                    return s
                }()
            ),
            FilterPreset(
                id: "vintage_cross_process",
                name: "Cross",
                subtitle: "Color shift",
                swatch: [.green, .pink],
                state: {
                    var s = PhotoEditState()
                    s.contrast = 1.35
                    s.saturation = 1.30
                    s.colorTint = SIMD4<Float>(0.85, 1.0, 0.75, 1.0)
                    s.colorTintIntensity = 0.80
                    s.colorTintFactor = 0.35
                    s.exposure = 0.10
                    s.vibrance = 0.25
                    return s
                }()
            ),
            FilterPreset(
                id: "vintage_polaroid",
                name: "Polaroid",
                subtitle: "Instant",
                swatch: [.yellow.opacity(0.8), .white],
                state: {
                    var s = PhotoEditState()
                    s.fade = 0.35
                    s.contrast = 0.85
                    s.saturation = 1.10
                    s.colorTint = SIMD4<Float>(1.0, 0.95, 0.85, 1.0)
                    s.colorTintIntensity = 0.75
                    s.colorTintFactor = 0.30
                    s.vignette = 0.40
                    s.grain = 0.025
                    return s
                }()
            ),
            FilterPreset(
                id: "vintage_film_emulation",
                name: "Film",
                subtitle: "Analog emulation",
                swatch: [.green.opacity(0.6), .orange.opacity(0.7)],
                state: {
                    var s = PhotoEditState()
                    s.contrast = 1.10
                    s.saturation = 1.05
                    s.grain = 0.035
                    s.fade = 0.12
                    s.colorTint = SIMD4<Float>(0.90, 0.95, 0.80, 1.0)
                    s.colorTintIntensity = 0.70
                    s.colorTintFactor = 0.20
                    s.clarity = 0.15
                    return s
                }()
            ),
            FilterPreset(
                id: "vintage_faded_memories",
                name: "Faded",
                subtitle: "Faded memories",
                swatch: [.gray.opacity(0.6), .pink.opacity(0.4)],
                state: {
                    var s = PhotoEditState()
                    s.fade = 0.55
                    s.contrast = 0.75
                    s.saturation = 0.80
                    s.brightness = 0.10
                    s.colorTint = SIMD4<Float>(1.0, 0.90, 0.95, 1.0)
                    s.colorTintIntensity = 0.60
                    s.colorTintFactor = 0.35
                    s.grain = 0.015
                    return s
                }()
            ),
            FilterPreset(
                id: "vintage_infrared",
                name: "Infrared",
                subtitle: "False color",
                swatch: [.white, .red],
                state: {
                    var s = PhotoEditState()
                    s.saturation = 0.0
                    s.colorTint = SIMD4<Float>(1.0, 0.3, 0.3, 1.0)
                    s.colorTintIntensity = 0.90
                    s.colorTintFactor = 0.60
                    s.contrast = 1.25
                    s.brightness = 0.15
                    s.clarity = 0.20
                    return s
                }()
            )
        ]
    }

    private var portraitPresets: [FilterPreset] {
        [
            FilterPreset(
                id: "portrait_soft_skin",
                name: "Soft",
                subtitle: "Smooth skin",
                swatch: [.pink.opacity(0.3), .white],
                state: {
                    var s = PhotoEditState()
                    s.skinTone = 0.15
                    s.clarity = -0.20
                    s.brightness = 0.05
                    s.contrast = 1.05
                    s.saturation = 0.95
                    s.colorTint = SIMD4<Float>(1.0, 0.95, 0.90, 1.0)
                    s.colorTintIntensity = 0.60
                    s.colorTintFactor = 0.15
                    return s
                }()
            ),
            FilterPreset(
                id: "portrait_dramatic",
                name: "Dramatic",
                subtitle: "High contrast",
                swatch: [.black, .white],
                state: {
                    var s = PhotoEditState()
                    s.contrast = 1.35
                    s.clarity = 0.40
                    s.sharpen = 0.20
                    s.saturation = 0.90
                    s.brightness = -0.03
                    s.grain = 0.015
                    return s
                }()
            ),
            FilterPreset(
                id: "portrait_golden_hour",
                name: "Golden",
                subtitle: "Golden light",
                swatch: [.orange, .yellow],
                state: {
                    var s = PhotoEditState()
                    s.skinTone = 0.25
                    s.colorTint = SIMD4<Float>(1.0, 0.85, 0.65, 1.0)
                    s.colorTintIntensity = 0.85
                    s.colorTintFactor = 0.30
                    s.contrast = 1.10
                    s.vibrance = 0.20
                    s.exposure = 0.08
                    return s
                }()
            ),
            FilterPreset(
                id: "portrait_cool_tones",
                name: "Cool",
                subtitle: "Cool tones",
                swatch: [.blue, .cyan],
                state: {
                    var s = PhotoEditState()
                    s.skinTone = -0.20
                    s.colorTint = SIMD4<Float>(0.80, 0.90, 1.0, 1.0)
                    s.colorTintIntensity = 0.75
                    s.colorTintFactor = 0.25
                    s.contrast = 1.08
                    s.clarity = 0.15
                    s.saturation = 1.05
                    return s
                }()
            ),
            FilterPreset(
                id: "portrait_matte",
                name: "Matte",
                subtitle: "Matte finish",
                swatch: [.gray.opacity(0.7), .brown.opacity(0.5)],
                state: {
                    var s = PhotoEditState()
                    s.fade = 0.30
                    s.contrast = 0.90
                    s.saturation = 0.85
                    s.clarity = -0.10
                    s.colorTint = SIMD4<Float>(0.95, 0.90, 0.85, 1.0)
                    s.colorTintIntensity = 0.70
                    s.colorTintFactor = 0.20
                    return s
                }()
            )
        ]
    }

    private var streetPresets: [FilterPreset] {
        [
            FilterPreset(
                id: "street_urban_grit",
                name: "Grit",
                subtitle: "Raw urban",
                swatch: [.gray, .black],
                state: {
                    var s = PhotoEditState()
                    s.contrast = 1.30
                    s.clarity = 0.45
                    s.grain = 0.04
                    s.sharpen = 0.25
                    s.saturation = 0.80
                    s.brightness = -0.05
                    s.exposure = -0.10
                    return s
                }()
            ),
            FilterPreset(
                id: "street_neon_nights",
                name: "Neon",
                subtitle: "Neon nights",
                swatch: [.purple, .cyan],
                state: {
                    var s = PhotoEditState()
                    s.contrast = 1.25
                    s.saturation = 1.40
                    s.vibrance = 0.35
                    s.colorTint = SIMD4<Float>(0.70, 0.80, 1.0, 1.0)
                    s.colorTintSecondary = SIMD4<Float>(1.0, 0.40, 0.80, 1.0)
                    s.isDualToneActive = true
                    s.colorTintIntensity = 0.90
                    s.colorTintFactor = 0.50
                    s.clarity = 0.20
                    return s
                }()
            ),
            FilterPreset(
                id: "street_documentary",
                name: "Documentary",
                subtitle: "Documentary",
                swatch: [.gray.opacity(0.8), .brown.opacity(0.6)],
                state: {
                    var s = PhotoEditState()
                    s.contrast = 1.15
                    s.saturation = 0.90
                    s.clarity = 0.25
                    s.grain = 0.02
                    s.colorTint = SIMD4<Float>(0.92, 0.88, 0.82, 1.0)
                    s.colorTintIntensity = 0.70
                    s.colorTintFactor = 0.20
                    return s
                }()
            ),
            FilterPreset(
                id: "street_high_contrast_bw",
                name: "Contrast",
                subtitle: "High contrast B&W",
                swatch: [.black, .white],
                state: {
                    var s = PhotoEditState()
                    s.saturation = 0.0
                    s.contrast = 1.50
                    s.clarity = 0.50
                    s.sharpen = 0.30
                    s.grain = 0.025
                    s.brightness = 0.03
                    return s
                }()
            ),
            FilterPreset(
                id: "street_pixel_art",
                name: "Pixel",
                subtitle: "Digital retro",
                swatch: [.green, .blue],
                state: {
                    var s = PhotoEditState()
                    s.pixelateAmount = 3.0
                    s.contrast = 1.30
                    s.saturation = 1.40
                    s.sharpen = 0.20
                    s.colorTint = SIMD4<Float>(0.8, 1.0, 0.9, 1.0)
                    s.colorTintIntensity = 0.70
                    s.colorTintFactor = 0.30
                    s.clarity = 0.25
                    return s
                }()
            ),
            FilterPreset(
                id: "street_vignette_focus",
                name: "Focus",
                subtitle: "Vignette focus",
                swatch: [.black, .gray],
                state: {
                    var s = PhotoEditState()
                    s.vignette = 0.60
                    s.contrast = 1.15
                    s.clarity = 0.30
                    s.saturation = 1.10
                    s.brightness = 0.05
                    return s
                }()
            ),
            FilterPreset(
                id: "street_thermal",
                name: "Thermal",
                subtitle: "Heat vision",
                swatch: [.yellow, .red],
                state: {
                    var s = PhotoEditState()
                    s.saturation = 0.0
                    s.colorTint = SIMD4<Float>(1.0, 0.6, 0.2, 1.0)
                    s.colorTintIntensity = 0.85
                    s.colorTintFactor = 0.50
                    s.contrast = 1.30
                    s.clarity = 0.25
                    s.brightness = 0.05
                    return s
                }()
            )
        ]
    }

    var body: some View {
        ZStack {
            if stage == .groups {
                groupList
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
            } else {
                presetsList
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: stage)
        .onAppear { scheduleThumbRenders() }
        .onChange(of: selectedGroup) { _ in
            selectedPresetID = nil
            scheduleThumbRenders()
        }
        .onChange(of: baseImage?.cgImage) { _ in
            thumbs.removeAll()
            scheduleThumbRenders()
        }
    }

    private var allPresets: [FilterPreset] {
        return classicsPresets + cinemaPresets + vintagePresets + portraitPresets + streetPresets + dostPresets
    }

    private func presetsForSelected() -> [FilterPreset] {
        switch selectedGroup {
        case .all: return allPresets
        case .classics: return classicsPresets
        case .cinema: return cinemaPresets
        case .vintage: return vintagePresets
        case .portrait: return portraitPresets
        case .street: return streetPresets
        case .dost: return dostPresets
        }
    }

    private func groupDescription(for group: FilterGroup) -> String {
        switch group {
        case .all: return "All filters"
        case .classics: return "Classic filters"
        case .cinema: return "Cinematic effects"
        case .vintage: return "Nostalgic aesthetic"
        case .portrait: return "Portrait optimized"
        case .street: return "Urban photography"
        case .dost: return "DÖST universe"
        }
    }

    private func applyPreset(_ preset: FilterPreset) {
        // Long press: aplica filtro nos sliders (editState)
        print("[Filter UI] Long press on: \(preset.name)")
        let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
        impactFeedback.impactOccurred()
        
        withAnimation(.easeOut(duration: 0.18)) {
            selectedPresetID = preset.id
            applyCompleteFilter?(preset.state)
        }
    }
    
    private func applyPresetVisualOnly(_ preset: FilterPreset) {
        // Tap simples: aplica filtro como base visual (baseFilterState)
        print("[Filter UI] Tap on: \(preset.name)")
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
        
        withAnimation(.easeOut(duration: 0.18)) {
            selectedPresetID = preset.id
            applyBaseFilter?(preset.state)
        }
    }
    
    /// Determina a cor da borda do filtro baseada no tipo de aplicação
    private func filterBorderColor(for preset: FilterPreset) -> Color {
        let isAppliedToSliders = isFilterAppliedToSliders?(preset.state) ?? false
        let isAppliedAsBase = isFilterAppliedAsBase?(preset.state) ?? false
        
        // Prioriza slider filter (verde esmeralda)
        if isAppliedToSliders {
            return ColorSchemeManager.emerald
        }
        
        // Depois base filter (azul accent)
        if isAppliedAsBase {
            return Color.accentColor
        }
        
        return Color.clear
    }
    
    /// Determina se deve mostrar indicador circular verde para filtros aplicados via long press
    private func shouldShowSliderIndicator(for preset: FilterPreset) -> Bool {
        return isFilterAppliedToSliders?(preset.state) ?? false
    }
    
    /// Determina se deve mostrar indicador circular azul para filtros aplicados via tap
    private func shouldShowBaseIndicator(for preset: FilterPreset) -> Bool {
        return isFilterAppliedAsBase?(preset.state) ?? false
    }

    // MARK: - Views
    private var groupList: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(FilterGroup.allCases, id: \.self) { g in
                        Button(action: {
                            withAnimation { selectedGroup = g; selectedPresetID = nil; stage = .presets }
                        }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(g.rawValue)
                                        .font(.body.bold())
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                    Text(groupDescription(for: g))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 8)
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 10)
                            .padding(.horizontal, 12)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.08), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private var presetsList: some View {
        VStack(spacing: 10) {
            HStack {
                Button(action: { withAnimation { stage = .groups } }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.caption)
                            .foregroundColor(.primary)
                        Text("Back")
                            .font(.caption2)
                            .foregroundColor(.primary)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.08), lineWidth: 1))
                }
                .buttonStyle(.plain)
                Spacer()
                Text(selectedGroup.rawValue)
                    .font(.headline)
            }
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(presetsForSelected(), id: \.id) { preset in
                        VStack(spacing: 4) {
                            ZStack {
                                if let thumb = thumbs[preset.id] {
                                    Image(uiImage: thumb)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 56, height: 56)
                                        .clipped()
                                        .cornerRadius(10)
                                } else {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(LinearGradient(colors: preset.swatch, startPoint: .topLeading, endPoint: .bottomTrailing))
                                        .frame(width: 56, height: 56)
                                        .redacted(reason: .placeholder)
                                }
                            }
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(filterBorderColor(for: preset), lineWidth: 3)
                            )
                            .overlay(
                                Group {
                                    if selectedGroup == .dost {
                                        HStack {
                                            Text(badgeText(for: preset))
                                                .font(.system(size: 9, weight: .black, design: .rounded))
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 3)
                                                .background(Color.black.opacity(0.55), in: Capsule())
                                                .padding(4)
                                            Spacer()
                                        }
                                    }
                                    
                                    // Indicadores para filtros aplicados
                                    VStack {
                                        HStack {
                                            // Indicador para filtro base (tap simples) - círculo azul
                                            if shouldShowBaseIndicator(for: preset) {
                                                Circle()
                                                    .fill(Color.accentColor)
                                                    .frame(width: 10, height: 10)
                                                    .overlay(
                                                        Circle()
                                                            .fill(Color.white)
                                                            .frame(width: 3, height: 3)
                                                    )
                                                    .padding(6)
                                            }
                                            
                                            Spacer()
                                            
                                            // Indicador para filtro nos sliders (long press) - círculo verde esmeralda
                                            if shouldShowSliderIndicator(for: preset) {
                                                Circle()
                                                    .fill(ColorSchemeManager.emerald)
                                                    .frame(width: 10, height: 10)
                                                    .overlay(
                                                        Circle()
                                                            .fill(Color.white)
                                                            .frame(width: 3, height: 3)
                                                    )
                                                    .padding(6)
                                            }
                                        }
                                        
                                        Spacer()
                                    }
                                }, alignment: .topLeading
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 10))
                            .onTapGesture {
                                // Tap simples: aplica visual mas mantém sliders
                                applyPresetVisualOnly(preset)
                            }
                            .onLongPressGesture(minimumDuration: 0.5) {
                                // Long press: aplica filtro completo (altera sliders)
                                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                                impactFeedback.impactOccurred()
                                applyPreset(preset)
                            }
                            Text(preset.name)
                                .font(.caption2.bold())
                                .foregroundColor(.primary)
                                .lineLimit(1)
                        }
                        .frame(width: 62)
                    }
                }
                .padding(.horizontal, 12) // Aumentado para acomodar o stroke de 3pt
            }
        }
    }

    // MARK: - Thumbnails
    private func scheduleThumbRenders() {
        guard let base = baseImage else { return }
        let presets = presetsForSelected()
        let targetSize: CGFloat = 112 // render 2x for crisp 56pt
        for p in presets {
            if thumbs[p.id] != nil { continue }
            DispatchQueue.global(qos: .userInitiated).async {
                if let img = renderThumbnail(from: base, with: p.state, maxSize: targetSize) {
                    DispatchQueue.main.async { thumbs[p.id] = img }
                }
            }
        }
    }

    private func renderThumbnail(from image: UIImage, with state: PhotoEditState, maxSize: CGFloat) -> UIImage? {
        // MetalPetal-only thumbnails (remove Core Image fallback)
        return renderThumbnailMetalPetal(from: image, with: state, maxSize: maxSize)
    }

    private func renderThumbnailMetalPetal(from image: UIImage, with state: PhotoEditState, maxSize: CGFloat) -> UIImage? {
        guard let mtiContext else { return nil }
        guard let scaled = downscale(image: image, maxSide: Int(maxSize)), let cg = scaled.cgImage else { return nil }
        var mtiImage = MTIImage(cgImage: cg, options: [.SRGB: false], isOpaque: true)
        let sat = MTISaturationFilter(); sat.inputImage = mtiImage; sat.saturation = state.saturation; if let o = sat.outputImage { mtiImage = o }
        if state.vibrance != 0.0 { let vib = MTIVibranceFilter(); vib.inputImage = mtiImage; vib.amount = state.vibrance; if let o = vib.outputImage { mtiImage = o } }
        let exp = MTIExposureFilter(); exp.inputImage = mtiImage; exp.exposure = state.exposure; if let o = exp.outputImage { mtiImage = o }
        let bri = MTIBrightnessFilter(); bri.inputImage = mtiImage; bri.brightness = state.brightness; if let o = bri.outputImage { mtiImage = o }
        let con = MTIContrastFilter(); con.inputImage = mtiImage; con.contrast = state.contrast; if let o = con.outputImage { mtiImage = o }
        // Fade (elevação dos pretos): out = in*(1-f) + f
        if state.fade > 0.0 {
            let k = 0.35 * max(0.0, min(1.0, state.fade))
            let cm = MTIColorMatrixFilter(); cm.inputImage = mtiImage
            cm.colorMatrix = MTIColorMatrix(matrix: simd_float4x4(diagonal: SIMD4<Float>(1 - k, 1 - k, 1 - k, 1)), bias: SIMD4<Float>(k, k, k, 0))
            if let o = cm.outputImage { mtiImage = o }
        }
        let opa = MTIOpacityFilter(); opa.inputImage = mtiImage; opa.opacity = state.opacity; if let o = opa.outputImage { mtiImage = o }
        if state.pixelateAmount > 1.0 { let pix = MTIPixellateFilter(); pix.inputImage = mtiImage; let sc = max(CGFloat(state.pixelateAmount), 1.0); pix.scale = CGSize(width: sc, height: sc); if let o = pix.outputImage { mtiImage = o } }
        // Clarity (CLAHE) direct for thumbnails
        if state.clarity > 0.0 {
            let cla = MTICLAHEFilter(); cla.inputImage = mtiImage; cla.clipLimit = max(0.0, min(2.0, 0.5 + 1.0 * state.clarity)); cla.tileGridSize = MTICLAHESize(width: 12, height: 12); if let o = cla.outputImage { mtiImage = o }
        }
        // Sharpen (Unsharp Mask) for thumbnails
        if state.sharpen > 0.0 {
            let usm = MTIMPSUnsharpMaskFilter(); usm.inputImage = mtiImage; usm.scale = min(max(state.sharpen, 0.0), 1.0); usm.radius = Float(1.0 + 3.0 * Double(state.sharpen)); usm.threshold = 0.0; if let o = usm.outputImage { mtiImage = o }
        }
        if state.colorTint.x > 0 || state.colorTint.y > 0 || state.colorTint.z > 0 {
            if state.isDualToneActive && (state.colorTintSecondary.x > 0 || state.colorTintSecondary.y > 0 || state.colorTintSecondary.z > 0) {
                let f = DuotoneFilter()
                f.inputImage = mtiImage
                f.shadowColor = SIMD3<Float>(state.colorTint.x, state.colorTint.y, state.colorTint.z)
                f.highlightColor = SIMD3<Float>(state.colorTintSecondary.x, state.colorTintSecondary.y, state.colorTintSecondary.z)
                f.intensity = max(0, min(1, state.colorTintIntensity))
                f.factor = max(0, min(1, state.colorTintFactor))
                f.gamma = 1.0
                f.outputPixelFormat = .bgra8Unorm
                if let o = f.outputImage { mtiImage = o }
            } else {
                let neutral: Float = 0.5
                let intensity = max(0, min(1, state.colorTintIntensity))
                let factor = max(0, min(1, state.colorTintFactor))
                let biasR = (state.colorTint.x - neutral) * factor * intensity
                let biasG = (state.colorTint.y - neutral) * factor * intensity
                let biasB = (state.colorTint.z - neutral) * factor * intensity
                let mat = MTIColorMatrixFilter(); mat.inputImage = mtiImage
                mat.colorMatrix = MTIColorMatrix(matrix: simd_float4x4(diagonal: SIMD4<Float>(1,1,1,1)), bias: SIMD4<Float>(biasR, biasG, biasB, 0))
                if let o = mat.outputImage { mtiImage = o }
            }
        }
        // Skin tone (thumbnail) via shader for parity with preview/final
        if abs(state.skinTone) > 0.001 {
            let st = SkinToneFilter()
            st.inputImage = mtiImage
            st.amount = state.skinTone
            st.softness = 0.6
            st.highlightProtect = 0.6
            st.saturationThreshold = 0.06
            st.outputPixelFormat = .bgra8Unorm
            if let o = st.outputImage { mtiImage = o }
        }
        // Vignette (Metal)
        if state.vignette > 0.0 {
            let vf = VignetteFilter()
            vf.inputImage = mtiImage
            vf.intensity = state.vignette
            vf.outputPixelFormat = .bgra8Unorm
            if let out = vf.outputImage { mtiImage = out }
        }
        
        // Color invert (add this missing filter)
        if state.colorInvert > 0.0 {
            let invertFilter = MTIColorInvertFilter()
            invertFilter.inputImage = mtiImage
            if let invertedImage = invertFilter.outputImage {
                if state.colorInvert < 1.0 {
                    // Blend between original and inverted
                    let blendFilter = MTIBlendFilter(blendMode: .normal)
                    blendFilter.inputImage = invertedImage
                    blendFilter.inputBackgroundImage = mtiImage
                    blendFilter.intensity = state.colorInvert
                    mtiImage = blendFilter.outputImage ?? mtiImage
                } else {
                    mtiImage = invertedImage
                }
            }
        }
        
        // Film Grain via MetalPetal shader before CGImage generation
        do {
            if state.grain > 0.0 {
                let f = LumaGrainFilter()
                f.inputImage = mtiImage
                f.grain = state.grain
                f.grainSize = state.grainSize
                f.outputPixelFormat = .bgra8Unorm
                if let outImage = f.outputImage { mtiImage = outImage } else { print("[Thumbnails] LumaGrainFilter produced nil output.") }
            }
            let out = try mtiContext.makeCGImage(from: mtiImage)
            return UIImage(cgImage: out, scale: scaled.scale, orientation: .up)
        } catch { return nil }
    }

    private func downscale(image: UIImage, maxSide: Int) -> UIImage? {
        let targetSize = CGFloat(maxSide)
        let w = image.size.width
        let h = image.size.height
        
        // Calculate scale to fill the square (crop mode)
        let scale = max(targetSize / w, targetSize / h)
        let scaledSize = CGSize(width: w * scale, height: h * scale)
        
        // Create a square canvas
        let squareSize = CGSize(width: targetSize, height: targetSize)
        
        UIGraphicsBeginImageContextWithOptions(squareSize, true, 0)
        
        // Center the scaled image in the square canvas (this will crop excess)
        let x = (targetSize - scaledSize.width) / 2
        let y = (targetSize - scaledSize.height) / 2
        let drawRect = CGRect(x: x, y: y, width: scaledSize.width, height: scaledSize.height)
        
        image.draw(in: drawRect)
        
        let out = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return out
    }

    private func badgeText(for preset: FilterPreset) -> String {
        let upper = preset.name.uppercased()
        if upper.count <= 5 { return upper }
        if let first = upper.first { return String(first) }
        return "DÖST"
    }
}
