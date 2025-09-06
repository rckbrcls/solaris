import UIKit
import os.log

extension UIImage {
    func fixOrientation() -> UIImage {
        // Sempre cria uma nova imagem com orientação .up usando draw(in:), que respeita EXIF
        if imageOrientation == .up {
            return self
        }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = self.scale
        format.opaque = false
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
        // Use device scale to ensure pixel density matches the screen
        // This keeps previews crisp relative to zoom and device scale.
        let deviceScale = UIScreen.main.scale
        UIGraphicsBeginImageContextWithOptions(newSize, false, deviceScale)
        draw(in: CGRect(origin: .zero, size: newSize))
        let resized = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        // Always return a MetalPetal-safe image
        return resized?.withAlpha()
    }
    
    func withAlpha() -> UIImage? {
        guard let cgImage = self.cgImage else { 
            os_log("[withAlpha] No CGImage found.")
            return nil 
        }
        let width = cgImage.width
        let height = cgImage.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        
        // Log input info
        let alphaInfo = cgImage.alphaInfo
        let bitsPerPixel = cgImage.bitsPerPixel
        let bytesPerRow = cgImage.bytesPerRow
        os_log("[withAlpha] Input alphaInfo: %{public}@, bitsPerPixel: %d, bytesPerRow: %d", String(describing: alphaInfo), bitsPerPixel, bytesPerRow)
        
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { 
            os_log("[withAlpha] Failed to create CGContext.")
            return nil 
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let newCGImage = context.makeImage() else { 
            os_log("[withAlpha] Failed to make new CGImage.")
            return nil 
        }
        // Log output info
        let outAlphaInfo = newCGImage.alphaInfo
        let outBitsPerPixel = newCGImage.bitsPerPixel
        let outBytesPerRow = newCGImage.bytesPerRow
        os_log("[withAlpha] Output alphaInfo: %{public}@, bitsPerPixel: %d, bytesPerRow: %d", String(describing: outAlphaInfo), outBitsPerPixel, outBytesPerRow)
        // Assert output is RGBA8888, premultiplied alpha
        if !(outAlphaInfo == .premultipliedLast || outAlphaInfo == .premultipliedFirst) {
            os_log("[withAlpha] Output image is not premultiplied alpha! Returning nil.")
            return nil
        }
        if outBitsPerPixel != 32 {
            os_log("[withAlpha] Output image is not 32bpp RGBA! Returning nil.")
            return nil
        }
        if alphaInfo != .premultipliedLast && alphaInfo != .premultipliedFirst {
            os_log("[withAlpha] Input was not premultiplied alpha, conversion performed.")
        }
        // Preserva a escala original da imagem
        return UIImage(cgImage: newCGImage, scale: self.scale, orientation: .up)
    }
    
    func horizontallyMirrored() -> UIImage {
        // Cria uma imagem espelhada horizontalmente
        guard let cgImage = self.cgImage else { return self }
        
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
            return self
        }
        
        // Aplica transformação de espelhamento horizontal
        context.translateBy(x: CGFloat(width), y: 0)
        context.scaleBy(x: -1.0, y: 1.0)
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        guard let newCGImage = context.makeImage() else { 
            return self
        }
        
        return UIImage(cgImage: newCGImage, scale: self.scale, orientation: .up)
    }
}
