import SwiftUI

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
    case souvenir = "Souvenir"
    case dost = "DÖST"
}

struct PhotoEditorFilters: View {
    @Binding var editState: PhotoEditState
    var registerUndo: (() -> Void)? = nil

    @State private var selectedGroup: FilterGroup = .souvenir
    @State private var selectedPresetID: String? = nil
    @EnvironmentObject private var colorSchemeManager: ColorSchemeManager

    private var souvenirPresets: [FilterPreset] {
        [
            FilterPreset(
                id: "none",
                name: "Nenhum",
                subtitle: nil,
                swatch: [.gray.opacity(0.4), .gray.opacity(0.2)],
                state: PhotoEditState()
            ),
            FilterPreset(
                id: "bw",
                name: "B&W",
                subtitle: "Monocromático",
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
                subtitle: "Intenso",
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
                subtitle: "Frio",
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
                subtitle: "Quente",
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
                subtitle: "Suave",
                swatch: [.gray, .white],
                state: {
                    var s = PhotoEditState()
                    s.contrast = 0.9
                    s.brightness = 0.05
                    s.vibrance = 0.05
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
                    s.saturation = 1.05
                    s.vibrance = 0.2
                    s.colorTint = SIMD4<Float>(0.55, 0.75, 1.0, 1.0)
                    s.colorTintIntensity = 0.9
                    s.colorTintFactor = 0.28
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
                    s.contrast = 1.15
                    s.saturation = 1.2
                    s.vibrance = 0.25
                    s.colorTint = SIMD4<Float>(1.0, 0.6, 0.6, 1.0)
                    s.colorTintIntensity = 0.9
                    s.colorTintFactor = 0.22
                    return s
                }()
            ),
            FilterPreset(
                id: "dost_lilii",
                name: "LILII",
                subtitle: "Soft red",
                swatch: [.pink, .red.opacity(0.7)],
                state: {
                    var s = PhotoEditState()
                    s.contrast = 1.05
                    s.saturation = 1.1
                    s.vibrance = 0.18
                    s.colorTint = SIMD4<Float>(1.0, 0.8, 0.85, 1.0)
                    s.colorTintIntensity = 0.9
                    s.colorTintFactor = 0.20
                    return s
                }()
            )
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Group toggle
            HStack(spacing: 8) {
                ForEach(FilterGroup.allCases, id: \.self) { g in
                    Button(action: { withAnimation(.easeOut(duration: 0.2)) { selectedGroup = g } }) {
                        Text(g.rawValue)
                            .font(.callout.bold())
                            .foregroundColor(selectedGroup == g ? .white : colorSchemeManager.primaryColor)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background((selectedGroup == g ? Color.accentColor : colorSchemeManager.primaryColor.opacity(0.08)), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }
            .boxBlankStyle(cornerRadius: 12, padding: 6)

            // Presets list
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(presetsForSelected(), id: \.id) { preset in
                        Button(action: { applyPreset(preset) }) {
                            VStack(spacing: 8) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(LinearGradient(colors: preset.swatch, startPoint: .topLeading, endPoint: .bottomTrailing))
                                        .frame(width: 84, height: 84)
                                    if selectedPresetID == preset.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.title2)
                                            .foregroundColor(.white)
                                            .shadow(radius: 3)
                                    }
                                }
                                Text(preset.name)
                                    .font(.caption.bold())
                                    .foregroundColor(.primary)
                                if let sub = preset.subtitle {
                                    Text(sub)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .frame(width: 96)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 6)
            }
        }
        .padding(.horizontal)
    }

    private func presetsForSelected() -> [FilterPreset] {
        switch selectedGroup {
        case .souvenir: return souvenirPresets
        case .dost: return dostPresets
        }
    }

    private func applyPreset(_ preset: FilterPreset) {
        registerUndo?()
        withAnimation(.easeOut(duration: 0.18)) {
            editState = preset.state
            selectedPresetID = preset.id
        }
    }
}
