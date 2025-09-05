//
//  PhotoEditorViewModel.swift
//  souvenir
//
//  Created by Erick Barcelos on 30/05/25.
//

import SwiftUI
import Combine
import UIKit
import CoreImage
import MetalPetal
import os.log
import CoreGraphics

struct PhotoEditState: Codable, Equatable {
    var contrast: Float = 1.0
    var brightness: Float = 0.0 // valor padrão neutro
    var exposure: Float = 0.0 // valor padrão neutro
    var saturation: Float = 1.0 // valor padrão neutro
    var vibrance: Float = 0.0 // valor padrão neutro (sem vibrance)
    var opacity: Float = 1.0 // valor padrão neutro (totalmente opaco)
    // Fade (elevação dos pretos / redução de contraste linear; 0.0 neutro)
    var fade: Float = 0.0
    var colorInvert: Float = 0.0 // valor padrão neutro (sem inversão)
    var pixelateAmount: Float = 1.0 // valor padrão neutro (sem pixelate)
    // Sharpen (0.0 neutral)
    var sharpen: Float = 0.0
    // Clarity (local contrast; 0.0 neutral)
    var clarity: Float = 0.0
    // Film grain (0.0 - 0.1 recomendado)
    var grain: Float = 0.0
    // Film grain size (0.0 fine → 1.0 coarse)
    var grainSize: Float = 0.0
    // Color tint (RGBA, valores de 0 a 1)
    var colorTint: SIMD4<Float> = SIMD4<Float>(0,0,0,0) // padrão: sem cor
    var colorTintIntensity: Float = 1.0 // valor médio para que o slider fique no meio
    var colorTintFactor: Float = 0.30 // força do viés de cor (ColorMatrix) - default 30%
    // Dual tone support
    var colorTintSecondary: SIMD4<Float> = SIMD4<Float>(0,0,0,0) // segunda cor para dual tone
    var isDualToneActive: Bool = false // indica se o dual tone está ativo
    // Duotone removido
    // Adicione outros parâmetros depois
}

class PhotoEditorViewModel: ObservableObject {
    @Published var previewImage: UIImage?
    @Published var editState = PhotoEditState()
    @Published var lastUndoMessage: String? = nil
    // Simple undo stack of edit states (one per user transaction)
    private(set) var undoStack: [PhotoEditState] = []
    private(set) var redoStack: [PhotoEditState] = []
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    private var inChangeTransaction: Bool = false
    private var cancellables = Set<AnyCancellable>()
    private var mtiContext: MTIContext? = try? MTIContext(device: MTLCreateSystemDefaultDevice()!)
    public var previewBase: UIImage?
    private var previewBaseHigh: UIImage?
    private var previewBaseLow: UIImage?
    @Published var isInteracting: Bool = false

    // Adiciona referência à imagem original em alta qualidade
    public var originalImage: UIImage?
    private var originalImageURL: URL?
    private var originalImageData: Data?

    init(image: UIImage?, originalImageURL: URL? = nil, originalImageData: Data? = nil) {
        self.originalImage = image // Em memória: preview base
        self.originalImageURL = originalImageURL
        self.originalImageData = originalImageData
        buildPreviewBases()
        if let base = self.previewBase {
            print("[PhotoEditorViewModel] previewBase size: \(base.size), scale: \(base.scale)")
            if let cg = base.cgImage {
                print("[PhotoEditorViewModel] previewBase alphaInfo: \(cg.alphaInfo), bitsPerPixel: \(cg.bitsPerPixel)")
            }
        } else {
            print("[PhotoEditorViewModel] previewBase is nil after resizeToFit")
        }
        $editState
            .removeDuplicates()
            .debounce(for: .milliseconds(16), scheduler: DispatchQueue.global(qos: .userInitiated))
            .sink { [weak self] state in
                self?.generatePreview(state: state)
            }
            .store(in: &cancellables)
    }

    func buildPreviewBases() {
        // High-quality preview for crisp zoom (e.g., up to 3x)
        let highPoints = PhotoEditorHelper.suggestedPreviewMaxPoints(doubleTapZoomScale: 3.0)
        // Low-quality preview for responsive sliding (lighter to render)
        let lowPoints = PhotoEditorHelper.suggestedPreviewMaxPoints(doubleTapZoomScale: 2.0)
        self.previewBaseHigh = originalImage?.resizeToFit(maxSize: highPoints)
        self.previewBaseLow = originalImage?.resizeToFit(maxSize: lowPoints)
        // Start with high by default
        self.previewBase = self.previewBaseHigh
        if let base = self.previewBase {
            print("[PhotoEditorViewModel] previewBase size: \(base.size), scale: \(base.scale)")
            if let cg = base.cgImage {
                print("[PhotoEditorViewModel] previewBase alphaInfo: \(cg.alphaInfo), bitsPerPixel: \(cg.bitsPerPixel)")
            }
        } else {
            print("[PhotoEditorViewModel] previewBase is nil after resizeToFit")
        }
    }

    func beginInteractiveAdjustments() {
        guard !isInteracting else { return }
        isInteracting = true
        if let low = previewBaseLow { previewBase = low }
        // register an undo point at the start of a gesture/transaction
        beginChangeTransaction()
    }

    func endInteractiveAdjustments() {
        isInteracting = false
        if let high = previewBaseHigh { previewBase = high }
        // finish the current transaction
        endChangeTransaction()
        // Regerar preview final em alta
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            self.generatePreview(state: self.editState)
        }
    }

    func resetPreviewBases() {
        buildPreviewBases()
    }

    // Exposed base image for thumbnails/previews (low-res preferred)
    public var previewThumbnailBase: UIImage? {
        return previewBaseLow ?? previewBase
    }

    // MARK: - Undo management
    func seedUndoBaselineIfNeeded(baseline: PhotoEditState = PhotoEditState()) {
        // Seed a single undo step to baseline on fresh sessions
        if undoStack.isEmpty && editState != baseline {
            undoStack.append(baseline)
            redoStack.removeAll()
        }
    }

    func beginChangeTransaction() {
        if !inChangeTransaction {
            undoStack.append(editState)
            // New transaction invalidates redo history
            redoStack.removeAll()
            inChangeTransaction = true
        }
    }

    func endChangeTransaction() {
        inChangeTransaction = false
    }

    func registerUndoPoint() {
        // for discrete changes (button taps)
        undoStack.append(editState)
        // Any new change invalidates redo history
        redoStack.removeAll()
    }

    func undoLastChange() {
        guard let previous = undoStack.popLast() else { return }
        let current = editState
        // push current state to redo stack so we can restore later
        redoStack.append(current)
        editState = previous
        // Build a human-readable message of what changed back
        let keys = diffChangedKeys(from: current, to: previous)
        lastUndoMessage = buildUndoMessage(fromKeys: keys)
    }

    func resetAllEditsToClean() {
        // Make the full reset redoable as a single step
        let clean = PhotoEditState()
        if editState != clean {
            let previous = editState
            // Clear undo history and set redo to restore the whole previous state
            undoStack.removeAll()
            redoStack = [previous]
            editState = clean
            lastUndoMessage = "Revertido: todos os ajustes"
        } else {
            // Nada a desfazer; não mostrar toast indevido
            lastUndoMessage = nil
        }
    }

    func clearLastUndoMessage() { lastUndoMessage = nil }

    // Load persistent history when opening editor
    func loadPersistentUndoHistory(_ history: [PhotoEditState]) {
        // Deduplicate consecutive equals and drop any trailing state equal to the current editState
        var cleaned: [PhotoEditState] = []
        cleaned.reserveCapacity(history.count)
        for s in history {
            if cleaned.last != s { cleaned.append(s) }
        }
        while let last = cleaned.last, last == editState { cleaned.removeLast() }
        // Clamp to last N steps to avoid excessive manifest size
        let limit = AppSettings.shared.historyLimit
        undoStack = Array(cleaned.suffix(limit))
        redoStack.removeAll()
    }

    // MARK: - Diff helpers
    private func diffChangedKeys(from a: PhotoEditState, to b: PhotoEditState) -> [String] {
        var keys: [String] = []
        func changed(_ x: Float, _ y: Float, eps: Float = 0.0001) -> Bool { abs(x - y) > eps }
        func colorChanged(_ c1: SIMD4<Float>, _ c2: SIMD4<Float>) -> Bool {
            changed(c1.x, c2.x) || changed(c1.y, c2.y) || changed(c1.z, c2.z) || changed(c1.w, c2.w)
        }
        if changed(a.contrast, b.contrast) { keys.append("contrast") }
        if changed(a.brightness, b.brightness) { keys.append("brightness") }
        if changed(a.exposure, b.exposure) { keys.append("exposure") }
        if changed(a.saturation, b.saturation) { keys.append("saturation") }
        if changed(a.vibrance, b.vibrance) { keys.append("vibrance") }
        if changed(a.opacity, b.opacity) { keys.append("opacity") }
        if changed(a.fade, b.fade) { keys.append("fade") }
        if changed(a.colorInvert, b.colorInvert) { keys.append("colorInvert") }
        if changed(a.pixelateAmount, b.pixelateAmount) { keys.append("pixelateAmount") }
        if changed(a.sharpen, b.sharpen) { keys.append("sharpen") }
        if changed(a.clarity, b.clarity) { keys.append("clarity") }
        if changed(a.grain, b.grain) { keys.append("grain") }
        if changed(a.grainSize, b.grainSize) { keys.append("grainSize") }
        if colorChanged(a.colorTint, b.colorTint) { keys.append("colorTint") }
        if colorChanged(a.colorTintSecondary, b.colorTintSecondary) { keys.append("colorTintSecondary") }
        if changed(a.colorTintIntensity, b.colorTintIntensity) { keys.append("colorTintIntensity") }
        if changed(a.colorTintFactor, b.colorTintFactor) { keys.append("colorTintFactor") }
        if a.isDualToneActive != b.isDualToneActive { keys.append("isDualToneActive") }
        return keys
    }

    private func buildUndoMessage(fromKeys keys: [String]) -> String {
        if keys.isEmpty { return "Nada para desfazer" }
        let names: [String: String] = [
            "contrast": "Contraste",
            "brightness": "Brilho",
            "exposure": "Exposição",
            "saturation": "Saturação",
            "vibrance": "Vibrance",
            "opacity": "Opacidade",
            "fade": "Fade",
            "colorInvert": "Inverter",
            "pixelateAmount": "Pixelizar",
            "sharpen": "Nitidez",
            "clarity": "Clareza",
            "grain": "Grão",
            "grainSize": "Tamanho do Grão",
            "colorTint": "Tint",
            "colorTintSecondary": "Tint Secundário",
            "colorTintIntensity": "Intensidade do Tint",
            "colorTintFactor": "Força do Tint",
            "isDualToneActive": "Dual Tone"
        ]
        if keys.count == 1 {
            return "Revertido: \(names[keys[0]] ?? keys[0])"
        }
        let firstTwo = keys.prefix(2).compactMap { names[$0] ?? $0 }.joined(separator: ", ")
        let rest = keys.count - 2
        return rest > 0 ? "Revertido: \(firstTwo) +\(rest)" : "Revertido: \(firstTwo)"
    }

    private func buildRestoreMessage(fromKeys keys: [String]) -> String {
        if keys.isEmpty { return "Nada para restaurar" }
        let names: [String: String] = [
            "contrast": "Contraste",
            "brightness": "Brilho",
            "exposure": "Exposição",
            "saturation": "Saturação",
            "vibrance": "Vibrance",
            "opacity": "Opacidade",
            "fade": "Fade",
            "colorInvert": "Inverter",
            "pixelateAmount": "Pixelizar",
            "sharpen": "Nitidez",
            "clarity": "Clareza",
            "grain": "Grão",
            "grainSize": "Tamanho do Grão",
            "colorTint": "Tint",
            "colorTintSecondary": "Tint Secundário",
            "colorTintIntensity": "Intensidade do Tint",
            "colorTintFactor": "Força do Tint",
            "isDualToneActive": "Dual Tone"
        ]
        if keys.count == 1 {
            return "Restaurado: \(names[keys[0]] ?? keys[0])"
        }
        let firstTwo = keys.prefix(2).compactMap { names[$0] ?? $0 }.joined(separator: ", ")
        let rest = keys.count - 2
        return rest > 0 ? "Restaurado: \(firstTwo) +\(rest)" : "Restaurado: \(firstTwo)"
    }

    func redoLastChange() {
        guard let next = redoStack.popLast() else { return }
        let current = editState
        // current becomes another undo point
        undoStack.append(current)
        editState = next
        let keys = diffChangedKeys(from: current, to: next)
        lastUndoMessage = buildRestoreMessage(fromKeys: keys)
    }

    func redoAllChanges() {
        guard !redoStack.isEmpty else { return }
        var current = editState
        var latest = current
        while let next = redoStack.popLast() {
            undoStack.append(current)
            current = next
            latest = next
        }
        editState = latest
        lastUndoMessage = "Restaurado: todos os ajustes"
    }

    /// Gera a imagem final em alta qualidade com todos os ajustes aplicados
    func generateFinalImage() -> UIImage? {
        // Carrega em alta do URL/dados no momento do export, evitando manter gigante em memória durante edição
        var sourceUIImage: UIImage?
        if let url = originalImageURL, let data = try? Data(contentsOf: url) {
            sourceUIImage = UIImage(data: data)
        } else if let data = originalImageData {
            sourceUIImage = UIImage(data: data)
        } else {
            sourceUIImage = originalImage
        }
        // Corrige orientação antes de gerar pipeline em alta
        let oriented = sourceUIImage?.fixOrientation()
        guard let base = oriented?.withAlpha(), let cgImage = base.cgImage, let mtiContext = mtiContext else { return nil }
        let state = editState
        // Repete o pipeline do generatePreview, mas usando a original
        let alphaInfo = cgImage.alphaInfo
        let bitsPerPixel = cgImage.bitsPerPixel
        if !(alphaInfo == .premultipliedLast || alphaInfo == .premultipliedFirst) { return nil }
        if bitsPerPixel != 32 { return nil }
        let mtiImage = MTIImage(cgImage: cgImage, options: [.SRGB: false], isOpaque: true)
        // Filtros (igual ao preview)
        let saturationFilter = MTISaturationFilter()
        saturationFilter.inputImage = mtiImage
        saturationFilter.saturation = state.saturation
        guard let saturatedImage = saturationFilter.outputImage else { return nil }
        let vibranceImage: MTIImage
        if state.vibrance != 0.0 {
            let vibranceFilter = MTIVibranceFilter()
            vibranceFilter.inputImage = saturatedImage
            vibranceFilter.amount = state.vibrance
            guard let output = vibranceFilter.outputImage else { return nil }
            vibranceImage = output
        } else {
            vibranceImage = saturatedImage
        }
        let exposureFilter = MTIExposureFilter()
        exposureFilter.inputImage = vibranceImage
        exposureFilter.exposure = state.exposure
        guard let exposureImage = exposureFilter.outputImage else { return nil }
        let brightnessFilter = MTIBrightnessFilter()
        brightnessFilter.inputImage = exposureImage
        brightnessFilter.brightness = state.brightness
        guard let brightImage = brightnessFilter.outputImage else { return nil }
        let contrastFilter = MTIContrastFilter()
        contrastFilter.inputImage = brightImage
        contrastFilter.contrast = state.contrast
        guard let contrastImage = contrastFilter.outputImage else { return nil }
        // Fade (elevação dos pretos via ColorMatrix: out = in*(1-f) + f)
        let imageAfterFade: MTIImage
        if state.fade > 0.0 {
            let k = 0.35 * max(0.0, min(1.0, state.fade))
            let cm = MTIColorMatrixFilter()
            cm.inputImage = contrastImage
            cm.colorMatrix = MTIColorMatrix(
                matrix: simd_float4x4(diagonal: SIMD4<Float>(1 - k, 1 - k, 1 - k, 1)),
                bias: SIMD4<Float>(k, k, k, 0)
            )
            guard let out = cm.outputImage else { return nil }
            imageAfterFade = out
        } else {
            imageAfterFade = contrastImage
        }
        let opacityFilter = MTIOpacityFilter()
        opacityFilter.inputImage = imageAfterFade
        opacityFilter.opacity = state.opacity
        guard let opacityImage = opacityFilter.outputImage else { return nil }
        let pixelatedImage: MTIImage
        if state.pixelateAmount > 1.0 {
            let pixelateFilter = MTIPixellateFilter()
            pixelateFilter.inputImage = opacityImage
            let scale = max(CGFloat(state.pixelateAmount), 1.0)
            pixelateFilter.scale = CGSize(width: scale, height: scale)
            guard let output = pixelateFilter.outputImage else { return nil }
            pixelatedImage = output
        } else {
            pixelatedImage = opacityImage
        }
        // Clarity (CLAHE) direct (MetalPetal) — no extra blends
        let clarityImage_final: MTIImage
        if state.clarity > 0.0 {
            let clahe = MTICLAHEFilter()
            clahe.inputImage = pixelatedImage
            clahe.clipLimit = max(0.0, min(2.0, 0.5 + 1.0 * state.clarity))
            clahe.tileGridSize = MTICLAHESize(width: 12, height: 12)
            guard let out = clahe.outputImage else { return nil }
            clarityImage_final = out
        } else {
            clarityImage_final = pixelatedImage
        }
        // Sharpen (Unsharp Mask) applied directly for a clean, gradual effect
        let sharpenedImage_final: MTIImage
        if state.sharpen > 0.0 {
            let usm = MTIMPSUnsharpMaskFilter()
            usm.inputImage = clarityImage_final
            usm.scale = min(max(state.sharpen, 0.0), 1.0)
            usm.radius = Float(1.0 + 2.0 * Double(state.sharpen))
            usm.threshold = 0.0
            guard let out = usm.outputImage else { return nil }
            sharpenedImage_final = out
        } else {
            sharpenedImage_final = clarityImage_final
        }
        let tintedImage: MTIImage
        if state.colorTint.x > 0.0 || state.colorTint.y > 0.0 || state.colorTint.z > 0.0 {
            if state.isDualToneActive && (state.colorTintSecondary.x > 0.0 || state.colorTintSecondary.y > 0.0 || state.colorTintSecondary.z > 0.0) {
                // Dual tone real: mapeia luminância para duas cores
                // 1. Converte para grayscale primeiro para obter luminância
                let grayscaleFilter = MTIColorMatrixFilter()
                grayscaleFilter.inputImage = sharpenedImage_final
                
                // Matriz para converter para grayscale (preserva luminância)
                let grayscaleMatrix = simd_float4x4(
                    SIMD4<Float>(0.299, 0.299, 0.299, 0),
                    SIMD4<Float>(0.587, 0.587, 0.587, 0), 
                    SIMD4<Float>(0.114, 0.114, 0.114, 0),
                    SIMD4<Float>(0, 0, 0, 1)
                )
                grayscaleFilter.colorMatrix = MTIColorMatrix(matrix: grayscaleMatrix, bias: SIMD4<Float>(0, 0, 0, 0))
                
                guard let grayscaleImage = grayscaleFilter.outputImage else { return nil }
                
                // 2. Aplica dual tone usando blend de multiply e screen
                let shadowColor = state.colorTint
                let highlightColor = state.colorTintSecondary
                let intensity = max(0.0, min(1.0, state.colorTintIntensity))
                let factor: Float = max(0.0, min(1.0, state.colorTintFactor))
                
                // Cria imagens sólidas das cores
                let shadowColorImage = MTIImage(color: MTIColor(
                    red: Float(shadowColor.x), 
                    green: Float(shadowColor.y), 
                    blue: Float(shadowColor.z), 
                    alpha: 1.0
                ), sRGB: false, size: pixelatedImage.size)
                
                let highlightColorImage = MTIImage(color: MTIColor(
                    red: Float(highlightColor.x), 
                    green: Float(highlightColor.y), 
                    blue: Float(highlightColor.z), 
                    alpha: 1.0
                ), sRGB: false, size: pixelatedImage.size)
                
                // Blend sombras: multiply (escurece)
                let shadowBlend = MTIBlendFilter(blendMode: .multiply)
                shadowBlend.inputImage = shadowColorImage
                shadowBlend.inputBackgroundImage = grayscaleImage
                shadowBlend.intensity = factor * intensity
                
                guard let shadowResult = shadowBlend.outputImage else { return nil }
                
                // Blend highlights: screen (clareia)
                let highlightBlend = MTIBlendFilter(blendMode: .screen)
                highlightBlend.inputImage = highlightColorImage
                highlightBlend.inputBackgroundImage = shadowResult
                highlightBlend.intensity = factor * intensity * 0.7 // Um pouco menos intenso
                
                guard let dualToneResult = highlightBlend.outputImage else { return nil }
                
                // Blend final com imagem original para preservar detalhes
                let finalBlend = MTIBlendFilter(blendMode: .normal)
                finalBlend.inputImage = dualToneResult
                finalBlend.inputBackgroundImage = sharpenedImage_final
                finalBlend.intensity = factor * intensity
                
                guard let output = finalBlend.outputImage else { return nil }
                tintedImage = output
            } else {
                // Tint simples original
                let neutral: Float = 0.5
                let intensity = max(0.0, min(1.0, state.colorTintIntensity))
                let factor: Float = max(0.0, min(1.0, state.colorTintFactor)) // controla a força
                let biasR = (state.colorTint.x - neutral) * factor * intensity
                let biasG = (state.colorTint.y - neutral) * factor * intensity
                let biasB = (state.colorTint.z - neutral) * factor * intensity
                let matrixFilter = MTIColorMatrixFilter()
                matrixFilter.inputImage = sharpenedImage_final
                let mat = simd_float4x4(diagonal: SIMD4<Float>(1, 1, 1, 1))
                let bias = SIMD4<Float>(biasR, biasG, biasB, 0)
                matrixFilter.colorMatrix = MTIColorMatrix(matrix: mat, bias: bias)
                guard let output = matrixFilter.outputImage else { return nil }
                tintedImage = output
            }
        } else {
            tintedImage = sharpenedImage_final
        }
        // Inversão de cores opcional (sem duotone)
        let baseImageForInvert = tintedImage
        var finalImage: MTIImage
        if state.colorInvert > 0.0 {
            let invertFilter = MTIColorInvertFilter()
            invertFilter.inputImage = baseImageForInvert
            guard let invertedImage = invertFilter.outputImage else { return nil }
            if state.colorInvert < 1.0 {
                let blendFilter = MTIBlendFilter(blendMode: .normal)
                blendFilter.inputImage = invertedImage
                blendFilter.inputBackgroundImage = baseImageForInvert
                blendFilter.intensity = state.colorInvert
                guard let blendedImage = blendFilter.outputImage else { return nil }
                finalImage = blendedImage
            } else {
                finalImage = invertedImage
            }
        } else {
            finalImage = baseImageForInvert
        }

        // Film grain: linear-space additive zero-mean; size via scaled sampling (monochrome, no hue shift)
        if state.grain > 0.0 {
            let baseK = max(0.0, min(1.0, state.grain * 10.0))
            let shapedK = Float(pow(Double(baseK), 0.7)) // more punch near the end
            let sMax: CGFloat = 8.0
            let scaleFactor = 1.0 + CGFloat(max(0.0, min(1.0, state.grainSize))) * (sMax - 1.0)
            let ampBoost = CGFloat(pow(Double(scaleFactor), 0.6)) // compensate perceived loss at larger grain
            let k = min(1.0, Float(ampBoost) * shapedK * 1.2)
            let scaleNorm = Float(max(0.0, min(1.0, (scaleFactor - 1.0) / (sMax - 1.0))))
            let noiseGain = Float(2.5 + 2.5 * scaleNorm) // 2.5x..5.0x
            let extent = CGRect(origin: .zero, size: finalImage.size)
            var scaledNoise: CIImage? = nil
            if let tex = UIImage(named: "film_grain"), let baseTile = CIImage(image: tex) {
                // Ensure monochrome
                let mono = CIFilter(name: "CIColorControls")
                mono?.setValue(baseTile, forKey: kCIInputImageKey)
                mono?.setValue(0.0, forKey: kCIInputSaturationKey)
                mono?.setValue(NSNumber(value: 1.8 + 0.7 * Double(scaleNorm)), forKey: kCIInputContrastKey)
                let tileMono = (mono?.outputImage ?? baseTile)
                // Random offset to avoid visible seams
                let tw = max(1.0, tileMono.extent.width * scaleFactor)
                let th = max(1.0, tileMono.extent.height * scaleFactor)
                let offX = CGFloat.random(in: 0..<tw)
                let offY = CGFloat.random(in: 0..<th)
                let transform = CGAffineTransform.identity
                    .scaledBy(x: scaleFactor, y: scaleFactor)
                    .translatedBy(x: offX, y: offY)
                if let tile = CIFilter(name: "CIAffineTile") {
                    tile.setValue(tileMono, forKey: kCIInputImageKey)
                    tile.setValue(NSValue(cgAffineTransform: transform), forKey: kCIInputTransformKey)
                    scaledNoise = (tile.outputImage ?? tileMono).cropped(to: extent)
                }
            }
            if scaledNoise == nil, let random = CIFilter(name: "CIRandomGenerator")?.outputImage?.cropped(to: extent) {
                // Monochrome procedural fallback
                let mono = CIFilter(name: "CIColorControls")
                mono?.setValue(random, forKey: kCIInputImageKey)
                mono?.setValue(0.0, forKey: kCIInputSaturationKey)
                mono?.setValue(NSNumber(value: 1.8 + 0.7 * Double(scaleNorm)), forKey: kCIInputContrastKey)
                let baseNoise = (mono?.outputImage ?? random)
                if let lanczos = CIFilter(name: "CILanczosScaleTransform") {
                    lanczos.setValue(baseNoise, forKey: kCIInputImageKey)
                    lanczos.setValue(scaleFactor, forKey: kCIInputScaleKey)
                    lanczos.setValue(1.0, forKey: kCIInputAspectRatioKey)
                    scaledNoise = (lanczos.outputImage ?? baseNoise).cropped(to: extent)
                } else {
                    let t = CGAffineTransform(scaleX: scaleFactor, y: scaleFactor)
                    scaledNoise = baseNoise.transformed(by: t).cropped(to: extent)
                }
            }
            if let scaledNoise = scaledNoise {
                // Convert base and noise to linear
                let toLinear1 = MTIRGBColorSpaceConversionFilter()
                toLinear1.inputColorSpace = .sRGB
                toLinear1.outputColorSpace = .linearSRGB
                toLinear1.outputAlphaType = .alphaIsOne
                toLinear1.inputImage = finalImage
                guard let baseLinear = toLinear1.outputImage else { return nil }
                let noiseMTI_sRGB = MTIImage(ciImage: scaledNoise, isOpaque: true)
                let toLinear2 = MTIRGBColorSpaceConversionFilter()
                toLinear2.inputColorSpace = .sRGB
                toLinear2.outputColorSpace = .linearSRGB
                toLinear2.outputAlphaType = .alphaIsOne
                toLinear2.inputImage = noiseMTI_sRGB
                guard let noiseLinear = toLinear2.outputImage else { return nil }
                // Center noise to zero-mean: (noise - 0.5)
                let cm = MTIColorMatrixFilter()
                cm.inputImage = noiseLinear
                cm.colorMatrix = MTIColorMatrix(matrix: simd_float4x4(diagonal: SIMD4<Float>(1,1,1,1)), bias: SIMD4<Float>(-0.5,-0.5,-0.5,0))
                guard let centeredNoise = cm.outputImage else { return nil }
                let gainF = MTIColorMatrixFilter(); gainF.inputImage = centeredNoise
                gainF.colorMatrix = MTIColorMatrix(matrix: simd_float4x4(diagonal: SIMD4<Float>(noiseGain, noiseGain, noiseGain, 1)), bias: SIMD4<Float>(0,0,0,0))
                guard let amplifiedNoise = gainF.outputImage else { return nil }
                // Add zero-mean noise scaled by k: base + k*centeredNoise
                let add = MTIBlendFilter(blendMode: .add)
                add.inputImage = amplifiedNoise
                add.inputBackgroundImage = baseLinear
                add.intensity = k
                add.outputAlphaType = .alphaIsOne
                guard let linearOut = add.outputImage else { return nil }
                // Back to sRGB
                let toSRGB = MTIRGBColorSpaceConversionFilter()
                toSRGB.inputColorSpace = .linearSRGB
                toSRGB.outputColorSpace = .sRGB
                toSRGB.outputAlphaType = .alphaIsOne
                toSRGB.inputImage = linearOut
                if let out = toSRGB.outputImage { finalImage = out }
            }
        }
        do {
            let cgimg = try mtiContext.makeCGImage(from: finalImage)
            let uiImage = UIImage(cgImage: cgimg)
            return uiImage
        } catch {
            return nil
        }
    }

    private func generatePreview(state: PhotoEditState) {
        guard let base = previewBase?.withAlpha(), let cgImage = base.cgImage, let mtiContext = mtiContext else { return }
        // Log input image info before passing to MetalPetal
        let alphaInfo = cgImage.alphaInfo
        let bitsPerPixel = cgImage.bitsPerPixel
        let bytesPerRow = cgImage.bytesPerRow
        os_log("[PhotoEditorViewModel] Input to MTIImage: alphaInfo: %{public}@, bitsPerPixel: %d, bytesPerRow: %d", String(describing: alphaInfo), bitsPerPixel, bytesPerRow)
        // Assert RGBA8888, premultiplied alpha
        if !(alphaInfo == .premultipliedLast || alphaInfo == .premultipliedFirst) {
            os_log("[PhotoEditorViewModel] Input image is not premultiplied alpha! Skipping preview generation.")
            return
        }
        if bitsPerPixel != 32 {
            os_log("[PhotoEditorViewModel] Input image is not 32bpp RGBA! Skipping preview generation.")
            return
        }
        // Tente isOpaque: true para contornar bug de alphaTypeHandlingRule
        let mtiImage = MTIImage(cgImage: cgImage, options: [.SRGB: false], isOpaque: true)
        // Filtro de saturação (MTISaturationFilter)
        let saturationFilter = MTISaturationFilter()
        saturationFilter.inputImage = mtiImage
        saturationFilter.saturation = state.saturation
        guard let saturatedImage = saturationFilter.outputImage else { return }
        // Filtro de vibrance (MTIVibranceFilter)
        let vibranceImage: MTIImage
        if state.vibrance != 0.0 {
            let vibranceFilter = MTIVibranceFilter()
            vibranceFilter.inputImage = saturatedImage
            vibranceFilter.amount = state.vibrance
            guard let output = vibranceFilter.outputImage else { return }
            vibranceImage = output
        } else {
            vibranceImage = saturatedImage
        }
        // Filtro de exposição (MTIExposureFilter)
        let exposureFilter = MTIExposureFilter()
        exposureFilter.inputImage = vibranceImage
        exposureFilter.exposure = state.exposure
        guard let exposureImage = exposureFilter.outputImage else { return }
        // Filtro de brilho (MTIBrightnessFilter específico)
        let brightnessFilter = MTIBrightnessFilter()
        brightnessFilter.inputImage = exposureImage
        brightnessFilter.brightness = state.brightness
        guard let brightImage = brightnessFilter.outputImage else { return }
        // Filtro de contraste
        let contrastFilter = MTIContrastFilter()
        contrastFilter.inputImage = brightImage
        contrastFilter.contrast = state.contrast
        guard let contrastImage = contrastFilter.outputImage else { return }
        // Fade (elevação dos pretos via ColorMatrix: out = in*(1-f) + f)
        let imageAfterFade: MTIImage
        if state.fade > 0.0 {
            let k = 0.35 * max(0.0, min(1.0, state.fade))
            let cm = MTIColorMatrixFilter()
            cm.inputImage = contrastImage
            cm.colorMatrix = MTIColorMatrix(
                matrix: simd_float4x4(diagonal: SIMD4<Float>(1 - k, 1 - k, 1 - k, 1)),
                bias: SIMD4<Float>(k, k, k, 0)
            )
            guard let out = cm.outputImage else { return }
            imageAfterFade = out
        } else {
            imageAfterFade = contrastImage
        }
        // Filtro de opacidade (usando MTIOpacityFilter especializado)
        let opacityFilter = MTIOpacityFilter()
        opacityFilter.inputImage = imageAfterFade
        opacityFilter.opacity = state.opacity
        guard let opacityImage = opacityFilter.outputImage else { return }
        
        // Filtro de pixelate (quando pixelateAmount > 1.0)
        let pixelatedImage: MTIImage
        if state.pixelateAmount > 1.0 {
            let pixelateFilter = MTIPixellateFilter()
            pixelateFilter.inputImage = opacityImage
            // O scale define o tamanho do pixel, quanto maior, mais pixelado
            let scale = max(CGFloat(state.pixelateAmount), 1.0)
            pixelateFilter.scale = CGSize(width: scale, height: scale)
            guard let output = pixelateFilter.outputImage else { return }
            pixelatedImage = output
        } else {
            pixelatedImage = opacityImage
        }
        // Clarity (CLAHE) direct for preview — no blends
        let clarityImage_preview: MTIImage
        if state.clarity > 0.0 {
            let clahe = MTICLAHEFilter()
            clahe.inputImage = pixelatedImage
            clahe.clipLimit = max(0.0, min(2.0, 0.5 + 1.0 * state.clarity))
            clahe.tileGridSize = MTICLAHESize(width: 12, height: 12)
            guard let out = clahe.outputImage else { return }
            clarityImage_preview = out
        } else {
            clarityImage_preview = pixelatedImage
        }
        // Sharpen (Unsharp Mask) applied directly
        let sharpenedImage_preview: MTIImage
        if state.sharpen > 0.0 {
            let usm = MTIMPSUnsharpMaskFilter()
            usm.inputImage = clarityImage_preview
            usm.scale = min(max(state.sharpen, 0.0), 1.0)
            usm.radius = Float(1.0 + 2.0 * Double(state.sharpen))
            usm.threshold = 0.0
            guard let out = usm.outputImage else { return }
            sharpenedImage_preview = out
        } else {
            sharpenedImage_preview = clarityImage_preview
        }
        
        // Filtro de color tint (quando uma cor for selecionada, independente da intensidade)
        let tintedImage: MTIImage
        if state.colorTint.x > 0.0 || state.colorTint.y > 0.0 || state.colorTint.z > 0.0 {
            if state.isDualToneActive && (state.colorTintSecondary.x > 0.0 || state.colorTintSecondary.y > 0.0 || state.colorTintSecondary.z > 0.0) {
                // Dual tone real: mapeia luminância para duas cores
                // 1. Converte para grayscale primeiro para obter luminância
                let grayscaleFilter = MTIColorMatrixFilter()
                grayscaleFilter.inputImage = sharpenedImage_preview
                
                // Matriz para converter para grayscale (preserva luminância)
                let grayscaleMatrix = simd_float4x4(
                    SIMD4<Float>(0.299, 0.299, 0.299, 0),
                    SIMD4<Float>(0.587, 0.587, 0.587, 0), 
                    SIMD4<Float>(0.114, 0.114, 0.114, 0),
                    SIMD4<Float>(0, 0, 0, 1)
                )
                grayscaleFilter.colorMatrix = MTIColorMatrix(matrix: grayscaleMatrix, bias: SIMD4<Float>(0, 0, 0, 0))
                
                guard let grayscaleImage = grayscaleFilter.outputImage else { return }
                
                // 2. Aplica dual tone usando blend de multiply e screen
                let shadowColor = state.colorTint
                let highlightColor = state.colorTintSecondary
                let intensity = max(0.0, min(1.0, state.colorTintIntensity))
                let factor: Float = max(0.0, min(1.0, state.colorTintFactor))
                
                // Cria imagens sólidas das cores
                let shadowColorImage = MTIImage(color: MTIColor(
                    red: Float(shadowColor.x), 
                    green: Float(shadowColor.y), 
                    blue: Float(shadowColor.z), 
                    alpha: 1.0
                ), sRGB: false, size: pixelatedImage.size)
                
                let highlightColorImage = MTIImage(color: MTIColor(
                    red: Float(highlightColor.x), 
                    green: Float(highlightColor.y), 
                    blue: Float(highlightColor.z), 
                    alpha: 1.0
                ), sRGB: false, size: pixelatedImage.size)
                
                // Blend sombras: multiply (escurece)
                let shadowBlend = MTIBlendFilter(blendMode: .multiply)
                shadowBlend.inputImage = shadowColorImage
                shadowBlend.inputBackgroundImage = grayscaleImage
                shadowBlend.intensity = factor * intensity
                
                guard let shadowResult = shadowBlend.outputImage else { return }
                
                // Blend highlights: screen (clareia)
                let highlightBlend = MTIBlendFilter(blendMode: .screen)
                highlightBlend.inputImage = highlightColorImage
                highlightBlend.inputBackgroundImage = shadowResult
                highlightBlend.intensity = factor * intensity * 0.7 // Um pouco menos intenso
                
                guard let dualToneResult = highlightBlend.outputImage else { return }
                
                // Blend final com imagem original para preservar detalhes
                let finalBlend = MTIBlendFilter(blendMode: .normal)
                finalBlend.inputImage = dualToneResult
                finalBlend.inputBackgroundImage = sharpenedImage_preview
                finalBlend.intensity = factor * intensity
                
                guard let output = finalBlend.outputImage else { return }
                tintedImage = output
            } else {
                // Tint simples original
                let neutral: Float = 0.5
                let intensity = max(0.0, min(1.0, state.colorTintIntensity))
                let factor: Float = max(0.0, min(1.0, state.colorTintFactor)) // controla a força
                let biasR = (state.colorTint.x - neutral) * factor * intensity
                let biasG = (state.colorTint.y - neutral) * factor * intensity
                let biasB = (state.colorTint.z - neutral) * factor * intensity
                let matrixFilter = MTIColorMatrixFilter()
                matrixFilter.inputImage = sharpenedImage_preview
                let mat = simd_float4x4(diagonal: SIMD4<Float>(1, 1, 1, 1))
                let bias = SIMD4<Float>(biasR, biasG, biasB, 0)
                matrixFilter.colorMatrix = MTIColorMatrix(matrix: mat, bias: bias)
                guard let output = matrixFilter.outputImage else { return }
                tintedImage = output
            }
        } else {
            tintedImage = sharpenedImage_preview
        }
        
        // Filtro de inversão de cores (quando colorInvert > 0)
        let baseImageForInvert = tintedImage
        var finalImage: MTIImage
        if state.colorInvert > 0.0 {
            let invertFilter = MTIColorInvertFilter()
            invertFilter.inputImage = baseImageForInvert
            guard let invertedImage = invertFilter.outputImage else { return }
            // Se colorInvert < 1.0, fazemos um blend entre a imagem original e a invertida
            if state.colorInvert < 1.0 {
                let blendFilter = MTIBlendFilter(blendMode: .normal)
                blendFilter.inputImage = invertedImage
                blendFilter.inputBackgroundImage = baseImageForInvert
                blendFilter.intensity = state.colorInvert
                guard let blendedImage = blendFilter.outputImage else { return }
                finalImage = blendedImage
            } else {
                finalImage = invertedImage
            }
        } else {
            finalImage = baseImageForInvert
        }

        // Film grain: linear-space additive zero-mean; size via scaled sampling (monochrome, no hue shift)
        if state.grain > 0.0 {
            let baseK = max(0.0, min(1.0, state.grain * 10.0))
            let shapedK = Float(pow(Double(baseK), 0.7))
            let sMax: CGFloat = 8.0
            let scaleFactor = 1.0 + CGFloat(max(0.0, min(1.0, state.grainSize))) * (sMax - 1.0)
            let ampBoost = CGFloat(pow(Double(scaleFactor), 0.6))
            let k = min(1.0, Float(ampBoost) * shapedK * 1.2)
            let scaleNorm = Float(max(0.0, min(1.0, (scaleFactor - 1.0) / (sMax - 1.0))))
            let noiseGain = Float(2.5 + 2.5 * scaleNorm)
            let extent = CGRect(origin: .zero, size: finalImage.size)
            if let random = CIFilter(name: "CIRandomGenerator")?.outputImage?.cropped(to: extent) {
                let mono = CIFilter(name: "CIColorControls")
                mono?.setValue(random, forKey: kCIInputImageKey)
                mono?.setValue(0.0, forKey: kCIInputSaturationKey)
                mono?.setValue(NSNumber(value: 1.8 + 0.7 * Double(scaleNorm)), forKey: kCIInputContrastKey)
                let baseNoise = (mono?.outputImage ?? random)
                let scaledNoise: CIImage
                if let lanczos = CIFilter(name: "CILanczosScaleTransform") {
                    lanczos.setValue(baseNoise, forKey: kCIInputImageKey)
                    lanczos.setValue(scaleFactor, forKey: kCIInputScaleKey)
                    lanczos.setValue(1.0, forKey: kCIInputAspectRatioKey)
                    scaledNoise = (lanczos.outputImage ?? baseNoise).cropped(to: extent)
                } else {
                    let t = CGAffineTransform(scaleX: scaleFactor, y: scaleFactor)
                    scaledNoise = baseNoise.transformed(by: t).cropped(to: extent)
                }
                
                // Convert to linear
                let toLinear1 = MTIRGBColorSpaceConversionFilter()
                toLinear1.inputColorSpace = .sRGB
                toLinear1.outputColorSpace = .linearSRGB
                toLinear1.outputAlphaType = .alphaIsOne
                toLinear1.inputImage = finalImage
                guard let baseLinear = toLinear1.outputImage else { return }
                let noiseMTI_sRGB = MTIImage(ciImage: scaledNoise, isOpaque: true)
                let toLinear2 = MTIRGBColorSpaceConversionFilter()
                toLinear2.inputColorSpace = .sRGB
                toLinear2.outputColorSpace = .linearSRGB
                toLinear2.outputAlphaType = .alphaIsOne
                toLinear2.inputImage = noiseMTI_sRGB
                guard let noiseLinear = toLinear2.outputImage else { return }
                let cm = MTIColorMatrixFilter()
                cm.inputImage = noiseLinear
                cm.colorMatrix = MTIColorMatrix(matrix: simd_float4x4(diagonal: SIMD4<Float>(1,1,1,1)), bias: SIMD4<Float>(-0.5,-0.5,-0.5,0))
                guard let centeredNoise = cm.outputImage else { return }
                let gainF = MTIColorMatrixFilter(); gainF.inputImage = centeredNoise
                gainF.colorMatrix = MTIColorMatrix(matrix: simd_float4x4(diagonal: SIMD4<Float>(noiseGain, noiseGain, noiseGain, 1)), bias: SIMD4<Float>(0,0,0,0))
                guard let amplifiedNoise = gainF.outputImage else { return }
                let add = MTIBlendFilter(blendMode: .add)
                add.inputImage = amplifiedNoise
                add.inputBackgroundImage = baseLinear
                add.intensity = k
                add.outputAlphaType = .alphaIsOne
                guard let linearOut = add.outputImage else { return }
                let toSRGB = MTIRGBColorSpaceConversionFilter()
                toSRGB.inputColorSpace = .linearSRGB
                toSRGB.outputColorSpace = .sRGB
                toSRGB.outputAlphaType = .alphaIsOne
                toSRGB.inputImage = linearOut
                if let out = toSRGB.outputImage { finalImage = out }
            }
        }

        // Geração final do preview (sem duotone)
        do {
            let cgimg = try mtiContext.makeCGImage(from: finalImage)
            let uiImage = UIImage(cgImage: cgimg)
            DispatchQueue.main.async {
                self.previewImage = uiImage
            }
            os_log("[PhotoEditorViewModel] Preview image generated successfully.")
        } catch {
            os_log("[PhotoEditorViewModel] Failed to generate preview: %{public}@", String(describing: error))
        }
    }
}
