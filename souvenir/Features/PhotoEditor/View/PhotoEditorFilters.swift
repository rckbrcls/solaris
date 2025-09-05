import SwiftUI
import CoreImage
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
    case souvenir = "Souvenir"
    case dost = "DÖST"
}

struct PhotoEditorFilters: View {
    @Binding var editState: PhotoEditState
    var registerUndo: (() -> Void)? = nil
    var baseImage: UIImage?

    @State private var selectedGroup: FilterGroup = .souvenir
    @State private var stage: Stage = .groups
    @State private var selectedPresetID: String? = nil
    @EnvironmentObject private var colorSchemeManager: ColorSchemeManager

    enum Stage { case groups, presets }

    @State private var thumbs: [String: UIImage] = [:]
    private let ciContext = CIContext(options: [CIContextOption.useSoftwareRenderer: false])
    private let mtiContext: MTIContext? = try? MTIContext(device: MTLCreateSystemDefaultDevice()!)

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
                        withAnimation { selectedGroup = g; selectedPresetID = nil; stage = .presets }
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
                HStack(spacing: 6) {
                    ForEach(presetsForSelected(), id: \.id) { preset in
                        Button(action: { applyPreset(preset) }) {
                            VStack(spacing: 4) {
                                ZStack {
                                    if let thumb = thumbs[preset.id] {
                                        Image(uiImage: thumb)
                                            .resizable()
                                            .aspectRatio(1, contentMode: .fill)
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
                                    Group {
                                        if selectedPresetID == preset.id {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.headline)
                                                .foregroundColor(.white)
                                                .shadow(radius: 3)
                                        }
                                    }, alignment: .center
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
                                    }, alignment: .topLeading
                                )
                                .contentShape(RoundedRectangle(cornerRadius: 10))
                                Text(preset.name)
                                    .font(.caption2.bold())
                                    .foregroundColor(.primary)
                            }
                            .frame(width: 62)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
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
        if let metal = renderThumbnailMetalPetal(from: image, with: state, maxSize: maxSize) {
            return metal
        }
        let scaled = downscale(image: image, maxSide: Int(maxSize))
        guard let base = scaled, let ci = CIImage(image: base) else { return nil }
        var output: CIImage = ci
        // Saturation/Brightness/Contrast
        if let f = CIFilter(name: "CIColorControls") {
            f.setValue(output, forKey: kCIInputImageKey)
            f.setValue(state.saturation as NSNumber, forKey: kCIInputSaturationKey)
            f.setValue(state.brightness as NSNumber, forKey: kCIInputBrightnessKey)
            f.setValue(state.contrast as NSNumber, forKey: kCIInputContrastKey)
            if let o = f.outputImage { output = o }
        }
        // Vibrance
        if state.vibrance != 0.0, let f = CIFilter(name: "CIVibrance") {
            f.setValue(output, forKey: kCIInputImageKey)
            f.setValue(state.vibrance as NSNumber, forKey: "inputAmount")
            if let o = f.outputImage { output = o }
        }
        // Exposure
        if state.exposure != 0.0, let f = CIFilter(name: "CIExposureAdjust") {
            f.setValue(output, forKey: kCIInputImageKey)
            f.setValue(state.exposure as NSNumber, forKey: kCIInputEVKey)
            if let o = f.outputImage { output = o }
        }
        // Color tint (approx via bias)
        if state.colorTint.x > 0 || state.colorTint.y > 0 || state.colorTint.z > 0 {
            if let f = CIFilter(name: "CIColorMatrix") {
                f.setValue(output, forKey: kCIInputImageKey)
                let neutral: Float = 0.5
                let intensity = max(0, min(1, state.colorTintIntensity))
                let factor = max(0, min(1, state.colorTintFactor))
                let biasR = (state.colorTint.x - neutral) * factor * intensity
                let biasG = (state.colorTint.y - neutral) * factor * intensity
                let biasB = (state.colorTint.z - neutral) * factor * intensity
                f.setValue(CIVector(x: 1, y: 0, z: 0, w: 0), forKey: "inputRVector")
                f.setValue(CIVector(x: 0, y: 1, z: 0, w: 0), forKey: "inputGVector")
                f.setValue(CIVector(x: 0, y: 0, z: 1, w: 0), forKey: "inputBVector")
                f.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
                f.setValue(CIVector(x: CGFloat(biasR), y: CGFloat(biasG), z: CGFloat(biasB), w: 0), forKey: "inputBiasVector")
                if let o = f.outputImage { output = o }
            }
        }
        // Pixelate (optional)
        if state.pixelateAmount > 1.0, let f = CIFilter(name: "CIPixellate") {
            f.setValue(output, forKey: kCIInputImageKey)
            f.setValue(max(1.0, CGFloat(state.pixelateAmount)), forKey: kCIInputScaleKey)
            if let o = f.outputImage { output = o }
        }
        // Invert
        if state.colorInvert > 0.0, let f = CIFilter(name: "CIColorInvert") {
            f.setValue(output, forKey: kCIInputImageKey)
            if let o = f.outputImage { output = o }
        }
        // Render to UIImage
        if let cg = ciContext.createCGImage(output, from: output.extent) {
            return UIImage(cgImage: cg, scale: base.scale, orientation: .up)
        }
        return nil
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
        let opa = MTIOpacityFilter(); opa.inputImage = mtiImage; opa.opacity = state.opacity; if let o = opa.outputImage { mtiImage = o }
        if state.pixelateAmount > 1.0 { let pix = MTIPixellateFilter(); pix.inputImage = mtiImage; let sc = max(CGFloat(state.pixelateAmount), 1.0); pix.scale = CGSize(width: sc, height: sc); if let o = pix.outputImage { mtiImage = o } }
        if state.colorTint.x > 0 || state.colorTint.y > 0 || state.colorTint.z > 0 {
            if state.isDualToneActive && (state.colorTintSecondary.x > 0 || state.colorTintSecondary.y > 0 || state.colorTintSecondary.z > 0) {
                let gray = MTIColorMatrixFilter(); gray.inputImage = mtiImage
                let grayscaleMatrix = simd_float4x4(
                    SIMD4<Float>(0.299, 0.299, 0.299, 0),
                    SIMD4<Float>(0.587, 0.587, 0.587, 0),
                    SIMD4<Float>(0.114, 0.114, 0.114, 0),
                    SIMD4<Float>(0, 0, 0, 1)
                )
                gray.colorMatrix = MTIColorMatrix(matrix: grayscaleMatrix, bias: SIMD4<Float>(0, 0, 0, 0))
                guard let grayImg = gray.outputImage else { return nil }
                let intensity = max(0, min(1, state.colorTintIntensity))
                let factor = max(0, min(1, state.colorTintFactor))
                let shadow = MTIImage(color: MTIColor(red: state.colorTint.x, green: state.colorTint.y, blue: state.colorTint.z, alpha: 1), sRGB: false, size: grayImg.size)
                let mul = MTIBlendFilter(blendMode: .multiply); mul.inputImage = shadow; mul.inputBackgroundImage = grayImg; mul.intensity = factor * intensity
                guard let mulImg = mul.outputImage else { return nil }
                let hi = MTIImage(color: MTIColor(red: state.colorTintSecondary.x, green: state.colorTintSecondary.y, blue: state.colorTintSecondary.z, alpha: 1), sRGB: false, size: grayImg.size)
                let scr = MTIBlendFilter(blendMode: .screen); scr.inputImage = hi; scr.inputBackgroundImage = mulImg; scr.intensity = factor * intensity * 0.7
                guard let duo = scr.outputImage else { return nil }
                let fin = MTIBlendFilter(blendMode: .normal); fin.inputImage = duo; fin.inputBackgroundImage = mtiImage; fin.intensity = factor * intensity
                if let o = fin.outputImage { mtiImage = o }
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
        do {
            let out = try mtiContext.makeCGImage(from: mtiImage)
            return UIImage(cgImage: out, scale: scaled.scale, orientation: .up)
        } catch { return nil }
    }

    private func downscale(image: UIImage, maxSide: Int) -> UIImage? {
        let maxS = CGFloat(maxSide)
        let w = image.size.width
        let h = image.size.height
        let scale = max(w, h) > maxS ? maxS / max(w, h) : 1.0
        let newSize = CGSize(width: w * scale, height: h * scale)
        UIGraphicsBeginImageContextWithOptions(newSize, true, 0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
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
