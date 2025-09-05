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
    @State private var stage: Stage = .groups
    @State private var selectedPresetID: String? = nil
    @EnvironmentObject private var colorSchemeManager: ColorSchemeManager

    enum Stage { case groups, presets }

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
                    s.saturation = 1.15
                    s.vibrance = 0.35
                    s.contrast = 1.08
                    s.colorTint = SIMD4<Float>(0.50, 0.72, 1.0, 1.0)
                    s.colorTintIntensity = 0.95
                    s.colorTintFactor = 0.40
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
                    s.contrast = 1.20
                    s.saturation = 1.30
                    s.vibrance = 0.35
                    s.exposure = 0.05
                    s.colorTint = SIMD4<Float>(1.0, 0.55, 0.55, 1.0)
                    s.colorTintIntensity = 0.95
                    s.colorTintFactor = 0.38
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
                    s.contrast = 1.12
                    s.saturation = 1.25
                    s.vibrance = 0.30
                    s.colorTint = SIMD4<Float>(1.0, 0.78, 0.86, 1.0)
                    s.colorTintIntensity = 0.95
                    s.colorTintFactor = 0.32
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

    // MARK: - Views
    private var groupList: some View {
        VStack(spacing: 12) {
            Text("Categorias de filtros")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
            VStack(spacing: 10) {
                ForEach(FilterGroup.allCases, id: \.self) { g in
                    Button(action: {
                        withAnimation { selectedGroup = g; stage = .presets }
                    }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(g.rawValue)
                                    .font(.body.bold())
                                    .foregroundColor(.primary)
                                Text(g == .souvenir ? "Clássicos do app" : "Universo DÖST — cores intensas")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                        .padding(14)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.08), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)
                }
            }
        }
    }

    private var presetsList: some View {
        VStack(spacing: 10) {
            HStack {
                Button(action: { withAnimation { stage = .groups } }) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                        Text("Categorias")
                    }
                }
                .buttonStyle(.plain)
                Spacer()
                Text(selectedGroup.rawValue)
                    .font(.headline)
                Spacer().frame(width: 24)
            }
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(presetsForSelected(), id: \.id) { preset in
                        Button(action: { applyPreset(preset) }) {
                            VStack(spacing: 6) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(LinearGradient(colors: preset.swatch, startPoint: .topLeading, endPoint: .bottomTrailing))
                                        .frame(width: 70, height: 70)
                                    if selectedPresetID == preset.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.title3)
                                            .foregroundColor(.white)
                                            .shadow(radius: 3)
                                    }
                                }
                                Text(preset.name)
                                    .font(.caption.bold())
                                    .foregroundColor(.primary)
                            }
                            .frame(width: 78)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
            }
        }
    }
}
