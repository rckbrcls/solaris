import UIKit
import ImageIO
import UniformTypeIdentifiers
import AVFoundation
import MobileCoreServices

// MARK: - Shared RAW UTI constants

private let rawUTIs: Set<String> = [
    "public.camera-raw-image",
    "com.adobe.raw-image",
    "com.canon.cr2-raw-image", "com.canon.cr3-raw-image",
    "com.nikon.nrw-raw-image", "com.nikon.nef-raw-image",
    "com.sony.arw-raw-image", "com.panasonic.rw2-raw-image",
    "com.apple.raw-image", "com.fuji.raw-image", "com.olympus.orf-raw-image",
    "com.adobe.dng"
]

// MARK: - HEIC export

func exportUIImageAsHEIC(_ image: UIImage) -> Data? {
    guard let cgImage = image.cgImage else { return nil }
    let data = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(data, AVFileType.heic as CFString, 1, nil) else { return nil }
    let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 1.0]
    CGImageDestinationAddImage(dest, cgImage, options as CFDictionary)
    guard CGImageDestinationFinalize(dest) else { return nil }
    return data as Data
}

// MARK: - Full quality loading

func loadUIImageFullQuality(from data: Data) -> UIImage? {
    let srcOptions = [kCGImageSourceShouldCache: false] as CFDictionary
    guard let source = CGImageSourceCreateWithData(data as CFData, srcOptions) else {
        return UIImage(data: data)
    }

    let propertiesOptions = [kCGImageSourceShouldCache: false] as CFDictionary
    let props = CGImageSourceCopyPropertiesAtIndex(source, 0, propertiesOptions) as? [CFString: Any]
    let exifOrientation = (props?[kCGImagePropertyOrientation] as? UInt32) ?? 1

    let scale: CGFloat = UITraitCollection.current.displayScale
    let createOpts: [CFString: Any] = [
        kCGImageSourceShouldAllowFloat: true,
        kCGImageSourceShouldCacheImmediately: false
    ]
    guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, createOpts as CFDictionary) else {
        return UIImage(data: data)
    }
    let image = UIImage(cgImage: cgImage, scale: scale, orientation: UIImage.Orientation(exifOrientation: exifOrientation))
    return image.fixOrientation()
}

// MARK: - EXIF orientation extension

extension UIImage.Orientation {
    init(exifOrientation: UInt32) {
        switch exifOrientation {
        case 1: self = .up
        case 2: self = .upMirrored
        case 3: self = .down
        case 4: self = .downMirrored
        case 5: self = .leftMirrored
        case 6: self = .right
        case 7: self = .rightMirrored
        case 8: self = .left
        default: self = .up
        }
    }
}

// MARK: - Format detection

func detectImageExtension(data: Data) -> String {
    // Prefer CGImageSource UTType detection — handles HEIF variants, TIFF, WebP, AVIF, RAW, etc.
    if let source = CGImageSourceCreateWithData(data as CFData, nil),
       let uti = CGImageSourceGetType(source) as? String,
       let utType = UTType(uti),
       let ext = utType.preferredFilenameExtension {
        return ext
    }
    // Fallback: magic bytes for common formats
    if data.starts(with: [0xFF, 0xD8, 0xFF]) { return "jpg" }
    if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
    if data.starts(with: [0x00, 0x00, 0x00, 0x18]) || data.starts(with: [0x00, 0x00, 0x00, 0x1C]) { return "heic" }
    return "img"
}

// MARK: - Metadata-preserving write helper

func writeUIImageWithSourceMetadata(_ image: UIImage, preferHEIC: Bool, destDir: URL, baseName: String, sourceURL: URL) -> URL? {
    let heicUTI = UTType.heic.identifier as CFString
    let jpegUTI = UTType.jpeg.identifier as CFString

    let targetUTI: CFString = preferHEIC ? heicUTI : jpegUTI
    let ext = preferHEIC ? "heic" : "jpg"
    let destURL = destDir.appendingPathComponent("\(baseName).\(ext)")

    guard let src = CGImageSourceCreateWithURL(sourceURL as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
    let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] ?? [:]
    let profileName = (props[kCGImagePropertyProfileName] as? String) ?? ""
    let exportPref = AppSettings.shared.exportColorSpace
    let destCS: CGColorSpace = {
        switch exportPref {
        case .auto:
            return profileName.lowercased().contains("p3") ? (CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()) : (CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB())
        case .sRGB: return CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        case .displayP3: return CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()
        }
    }()
    guard let converted = convertUIImage(image, to: destCS, includeAlpha: false), let cg = converted.cgImage else { return nil }
    var outProps: [CFString: Any] = AppSettings.shared.preserveMetadata ? props : [:]
    outProps[kCGImagePropertyOrientation] = 1
    if !profileName.isEmpty && AppSettings.shared.preserveMetadata { outProps[kCGImagePropertyProfileName] = profileName }

    guard let dest = CGImageDestinationCreateWithURL(destURL as CFURL, targetUTI, 1, nil) else { return nil }
    CGImageDestinationAddImage(dest, cg, outProps as CFDictionary)
    if CGImageDestinationFinalize(dest) {
        return destURL
    } else {
        if preferHEIC {
            return writeUIImageWithSourceMetadata(image, preferHEIC: false, destDir: destDir, baseName: baseName, sourceURL: sourceURL)
        }
        return nil
    }
}

// MARK: - Color space conversion

fileprivate func convertUIImage(_ image: UIImage, to colorSpace: CGColorSpace, includeAlpha: Bool) -> UIImage? {
    guard let cg = image.cgImage else { return nil }
    let width = cg.width
    let height = cg.height
    // Preserve source bit depth: use 16-bit for wide/HDR sources (supports 10-bit HEIC export)
    let sourceBPC = cg.bitsPerComponent
    let bpc = sourceBPC >= 16 ? 16 : sourceBPC > 8 ? 16 : 8
    let alphaInfo: CGImageAlphaInfo = includeAlpha ? .premultipliedLast : .noneSkipLast
    var bitmapInfo: UInt32 = alphaInfo.rawValue
    if bpc == 16 {
        bitmapInfo |= CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder16Little.rawValue
    } else {
        bitmapInfo |= CGBitmapInfo.byteOrder32Big.rawValue
    }
    guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: bpc, bytesPerRow: 0, space: colorSpace, bitmapInfo: bitmapInfo) else {
        // Fallback: 8-bit if native depth fails
        let fallbackInfo = alphaInfo.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let fallbackCtx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: fallbackInfo) else { return nil }
        if !includeAlpha {
            fallbackCtx.setFillColor(UIColor.white.cgColor)
            fallbackCtx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        fallbackCtx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let outCG = fallbackCtx.makeImage() else { return nil }
        return UIImage(cgImage: outCG, scale: image.scale, orientation: .up)
    }
    if !includeAlpha {
        ctx.setFillColor(UIColor.white.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    }
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
    guard let outCG = ctx.makeImage() else { return nil }
    return UIImage(cgImage: outCG, scale: image.scale, orientation: .up)
}

// MARK: - RAW detection

func detectImageRawInfo(data: Data) -> (Bool, String?) {
    let srcOptions = [kCGImageSourceShouldCache: false] as CFDictionary
    guard let source = CGImageSourceCreateWithData(data as CFData, srcOptions) else { return (false, nil) }
    guard let typeId = CGImageSourceGetType(source) else { return (false, nil) }
    let uti = typeId as String
    return (rawUTIs.contains(uti), uti)
}

func rawFileExtension(from uti: String?) -> String? {
    guard let uti else { return nil }
    switch uti {
    case "com.adobe.dng": return "dng"
    case "com.canon.cr2-raw-image": return "cr2"
    case "com.canon.cr3-raw-image": return "cr3"
    case "com.nikon.nrw-raw-image": return "nrw"
    case "com.nikon.nef-raw-image": return "nef"
    case "com.sony.arw-raw-image": return "arw"
    case "com.panasonic.rw2-raw-image": return "rw2"
    case "com.olympus.orf-raw-image": return "orf"
    case "public.camera-raw-image", "com.adobe.raw-image", "com.apple.raw-image", "com.fuji.raw-image": return "raw"
    default: return nil
    }
}

// MARK: - Thumbnail helpers

func loadUIImageThumbnail(from data: Data, maxPixel: Int) -> UIImage? {
    let srcOptions = [kCGImageSourceShouldCache: false] as CFDictionary
    guard let source = CGImageSourceCreateWithData(data as CFData, srcOptions) else { return nil }
    let opts: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        kCGImageSourceShouldCacheImmediately: false
    ]
    if let cgThumb = CGImageSourceCreateThumbnailAtIndex(source, 0, opts as CFDictionary) {
        return UIImage(cgImage: cgThumb, scale: UITraitCollection.current.displayScale, orientation: .up)
    }
    return nil
}

// MARK: - Encoding helpers

func encodeUIImageBestEffort(_ image: UIImage) -> (Data, String) {
    if let heic = exportUIImageAsHEIC(image) { return (heic, "heic") }
    if let jpg = image.jpegData(compressionQuality: 1.0) { return (jpg, "jpg") }
    if let png = image.pngData() { return (png, "png") }
    return (Data(), "img")
}

func encodeThumbnailImage(_ image: UIImage) -> (Data, String)? {
    if let jpg = image.jpegData(compressionQuality: 0.88) { return (jpg, "jpg") }
    if let heic = exportUIImageAsHEIC(image) { return (heic, "heic") }
    return nil
}

// MARK: - Image metadata helper

func imageDimensions(at url: URL) -> (Int, Int, Bool) {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return (0, 0, false) }
    let props = CGImageSourceCopyPropertiesAtIndex(src, 0, [kCGImageSourceShouldCache: false] as CFDictionary) as? [CFString: Any]
    let w = (props?[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
    let h = (props?[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
    let typeId = CGImageSourceGetType(src)
    let isRaw: Bool = {
        guard let typeId = typeId else { return false }
        let uti = typeId as String
        return rawUTIs.contains(uti)
    }()
    return (w, h, isRaw)
}
