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
    // Duotone removido
    // Adicione outros parâmetros depois
}

class PhotoEditorViewModel: ObservableObject {
    @Published var previewImage: UIImage?
    @Published var editState = PhotoEditState()
    private var cancellables = Set<AnyCancellable>()
    private var mtiContext: MTIContext? = try? MTIContext(device: MTLCreateSystemDefaultDevice()!)
    public var previewBase: UIImage?

    // Adiciona referência à imagem original em alta qualidade
    public var originalImage: UIImage?

    init(image: UIImage?) {
        self.originalImage = image // Mantém a original para exportação final
        self.previewBase = image?.resizeToFit(maxSize: 1024)
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

    /// Gera a imagem final em alta qualidade com todos os ajustes aplicados
    func generateFinalImage() -> UIImage? {
        guard let base = originalImage?.withAlpha(), let cgImage = base.cgImage, let mtiContext = mtiContext else { return nil }
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
            // Aplica um leve viés de cor via ColorMatrix, preservando a imagem base
            let neutral: Float = 0.5
            let intensity = max(0.0, min(1.0, state.colorTintIntensity))
            let factor: Float = 0.12 // força máxima do viés (um pouco mais forte)
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
            // Aplica um leve viés de cor via ColorMatrix, preservando a imagem base
            let neutral: Float = 0.5
            let intensity = max(0.0, min(1.0, state.colorTintIntensity))
            let factor: Float = 0.12 // força máxima do viés (um pouco mais forte)
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
