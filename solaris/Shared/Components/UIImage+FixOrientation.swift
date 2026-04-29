import UIKit
import os.log

extension UIImage {
    func fixOrientation() -> UIImage {
        // Sempre cria uma nova imagem com orientação .up usando draw(in:), que respeita EXIF
        if imageOrientation == .up {
            return self
        }
        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = self.scale
        format.opaque = false
        format.preferredRange = .extended  // preserva wide gamut + HDR
        let renderer = UIGraphicsImageRenderer(size: self.size, format: format)
        let img = renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: self.size))
        }
        os_log("[fixOrientation] Orientação corrigida com sucesso (UIKit)")
        return img
    }

    func resizeToFit(maxSize: CGFloat) -> UIImage? {
        // Avoid upscaling: if already within bounds, just ensure alpha safety
        if max(size.width, size.height) <= maxSize {
            return self.withAlpha()
        }
        let aspectRatio = size.width / size.height
        var newSize: CGSize
        if size.width > size.height {
            newSize = CGSize(width: maxSize, height: maxSize / aspectRatio)
        } else {
            newSize = CGSize(width: maxSize * aspectRatio, height: maxSize)
        }
        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = UITraitCollection.current.displayScale
        format.preferredRange = .extended  // preserva wide gamut + HDR
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        let resized = renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
        // Always return a MetalPetal-safe image
        return resized.withAlpha()
    }

    func withAlpha() -> UIImage? {
        guard let cgImage = self.cgImage else {
            os_log("[withAlpha] No CGImage found.")
            return nil
        }
        let width = cgImage.width
        let height = cgImage.height
        // Preserve the original color space instead of forcing device sRGB
        let colorSpace = cgImage.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        // Preserve original bit depth (8, 10, or 16 bitsPerComponent)
        let bpc = cgImage.bitsPerComponent
        let alphaInfo: CGImageAlphaInfo = .premultipliedLast
        var bitmapInfo: UInt32 = alphaInfo.rawValue
        if bpc == 16 {
            bitmapInfo |= CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder16Little.rawValue
        } else {
            bitmapInfo |= CGBitmapInfo.byteOrder32Big.rawValue
        }

        // Log input info
        let inputAlphaInfo = cgImage.alphaInfo
        let bitsPerPixel = cgImage.bitsPerPixel
        os_log("[withAlpha] Input alphaInfo: %{public}@, bitsPerPixel: %d, bpc: %d, colorSpace: %{public}@", String(describing: inputAlphaInfo), bitsPerPixel, bpc, colorSpace.name as String? ?? "unknown")

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: bpc,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            // Fallback: try 8-bit sRGB if native format fails
            os_log("[withAlpha] Native format CGContext failed, falling back to 8-bit sRGB.")
            return withAlphaFallback8bit()
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let newCGImage = context.makeImage() else {
            os_log("[withAlpha] Failed to make new CGImage, trying fallback.")
            return withAlphaFallback8bit()
        }
        // Log output info
        let outAlphaInfo = newCGImage.alphaInfo
        let outBitsPerPixel = newCGImage.bitsPerPixel
        let outBytesPerRow = newCGImage.bytesPerRow
        os_log("[withAlpha] Output alphaInfo: %{public}@, bitsPerPixel: %d, bytesPerRow: %d", String(describing: outAlphaInfo), outBitsPerPixel, outBytesPerRow)
        // Preserva a escala original da imagem
        return UIImage(cgImage: newCGImage, scale: self.scale, orientation: .up)
    }

    /// Fallback: 8-bit sRGB for compatibility when native format CGContext creation fails
    private func withAlphaFallback8bit() -> UIImage? {
        guard let cgImage = self.cgImage else { return nil }
        let width = cgImage.width
        let height = cgImage.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            os_log("[withAlpha] 8-bit fallback CGContext also failed.")
            return nil
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let newCGImage = context.makeImage() else { return nil }
        return UIImage(cgImage: newCGImage, scale: self.scale, orientation: .up)
    }

    func horizontallyMirrored() -> UIImage {
        // Primeiro aplica orientação EXIF para que os pixels fiquem corretos antes de espelhar.
        // Sem isso, cgImage retorna pixels raw do sensor (landscape) e o espelhamento fica incorreto.
        let oriented = self.fixOrientation()
        guard let cgImage = oriented.cgImage else { return self }

        let width = cgImage.width
        let height = cgImage.height

        // Usa o mesmo colorSpace da imagem original para evitar conversões
        let colorSpace = cgImage.colorSpace ?? CGColorSpaceCreateDeviceRGB()

        // Mantém as configurações originais da imagem
        let bitsPerComponent = cgImage.bitsPerComponent
        let bitmapInfo = cgImage.bitmapInfo

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            return horizontallyMirroredFallback()
        }

        context.interpolationQuality = .high
        context.translateBy(x: CGFloat(width), y: 0)
        context.scaleBy(x: -1.0, y: 1.0)
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let newCGImage = context.makeImage() else {
            return horizontallyMirroredFallback()
        }

        return UIImage(cgImage: newCGImage, scale: self.scale, orientation: .up)
    }

    private func horizontallyMirroredFallback() -> UIImage {
        let oriented = self.fixOrientation()
        let format = UIGraphicsImageRendererFormat()
        format.scale = oriented.scale
        format.opaque = false

        let renderer = UIGraphicsImageRenderer(size: oriented.size, format: format)
        return renderer.image { context in
            let cgContext = context.cgContext
            cgContext.interpolationQuality = .high
            cgContext.translateBy(x: oriented.size.width, y: 0)
            cgContext.scaleBy(x: -1.0, y: 1.0)
            oriented.draw(in: CGRect(origin: .zero, size: oriented.size))
        }
    }
}
