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
    var colorInvert: Float = 0.0 // valor padrão neutro (sem inversão)
    var pixelateAmount: Float = 1.0 // valor padrão neutro (sem pixelate)
    // Color tint (RGBA, valores de 0 a 1)
    var colorTint: SIMD4<Float> = SIMD4<Float>(0,0,0,0) // padrão: sem cor
    var colorTintIntensity: Float = 1.0 // valor médio para que o slider fique no meio
    var colorTintFactor: Float = 0.25 // força do viés de cor (ColorMatrix) - inicia em 25
    // Dual tone support
    var colorTintSecondary: SIMD4<Float> = SIMD4<Float>(0,0,0,0) // segunda cor para dual tone
    var isDualToneActive: Bool = false // indica se o dual tone está ativo
    // Duotone removido
    // Adicione outros parâmetros depois
}

class PhotoEditorViewModel: ObservableObject {
    @Published var previewImage: UIImage?
    @Published var editState = PhotoEditState()
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
    }

    func endInteractiveAdjustments() {
        isInteracting = false
        if let high = previewBaseHigh { previewBase = high }
        // Regerar preview final em alta
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            self.generatePreview(state: self.editState)
        }
    }

    func resetPreviewBases() {
        buildPreviewBases()
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
        let opacityFilter = MTIOpacityFilter()
        opacityFilter.inputImage = contrastImage
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
        let tintedImage: MTIImage
        if state.colorTint.x > 0.0 || state.colorTint.y > 0.0 || state.colorTint.z > 0.0 {
            if state.isDualToneActive && (state.colorTintSecondary.x > 0.0 || state.colorTintSecondary.y > 0.0 || state.colorTintSecondary.z > 0.0) {
                // Dual tone real: mapeia luminância para duas cores
                // 1. Converte para grayscale primeiro para obter luminância
                let grayscaleFilter = MTIColorMatrixFilter()
                grayscaleFilter.inputImage = pixelatedImage
                
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
                finalBlend.inputBackgroundImage = pixelatedImage
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
                matrixFilter.inputImage = pixelatedImage
                let mat = simd_float4x4(diagonal: SIMD4<Float>(1, 1, 1, 1))
                let bias = SIMD4<Float>(biasR, biasG, biasB, 0)
                matrixFilter.colorMatrix = MTIColorMatrix(matrix: mat, bias: bias)
                guard let output = matrixFilter.outputImage else { return nil }
                tintedImage = output
            }
        } else {
            tintedImage = pixelatedImage
        }
        // Inversão de cores opcional (sem duotone)
        let baseImageForInvert = tintedImage
        let finalImage: MTIImage
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
        // Filtro de opacidade (usando MTIOpacityFilter especializado)
        let opacityFilter = MTIOpacityFilter()
        opacityFilter.inputImage = contrastImage
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
        
        // Filtro de color tint (quando uma cor for selecionada, independente da intensidade)
        let tintedImage: MTIImage
        if state.colorTint.x > 0.0 || state.colorTint.y > 0.0 || state.colorTint.z > 0.0 {
            if state.isDualToneActive && (state.colorTintSecondary.x > 0.0 || state.colorTintSecondary.y > 0.0 || state.colorTintSecondary.z > 0.0) {
                // Dual tone real: mapeia luminância para duas cores
                // 1. Converte para grayscale primeiro para obter luminância
                let grayscaleFilter = MTIColorMatrixFilter()
                grayscaleFilter.inputImage = pixelatedImage
                
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
                finalBlend.inputBackgroundImage = pixelatedImage
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
                matrixFilter.inputImage = pixelatedImage
                let mat = simd_float4x4(diagonal: SIMD4<Float>(1, 1, 1, 1))
                let bias = SIMD4<Float>(biasR, biasG, biasB, 0)
                matrixFilter.colorMatrix = MTIColorMatrix(matrix: mat, bias: bias)
                guard let output = matrixFilter.outputImage else { return }
                tintedImage = output
            }
        } else {
            tintedImage = pixelatedImage
        }
        
        // Filtro de inversão de cores (quando colorInvert > 0)
        let baseImageForInvert = tintedImage
        let finalImage: MTIImage
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
