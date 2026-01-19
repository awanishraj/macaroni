import Foundation
import CoreImage
import Accelerate
import AppKit

/// Processes camera frames with rotation, flip, and frame overlays
final class FrameProcessor {
    var rotation: CameraRotation = .none
    var horizontalFlip: Bool = false
    var verticalFlip: Bool = false
    var frameStyle: FrameStyle = .none

    private let context = CIContext(options: [.useSoftwareRenderer: false])

    // Cached frame overlay images
    private var frameOverlayCache: [FrameStyle: CIImage] = [:]

    init() {
        rotation = Preferences.shared.cameraRotation
        horizontalFlip = Preferences.shared.horizontalFlip
        verticalFlip = Preferences.shared.verticalFlip
        frameStyle = Preferences.shared.frameStyle
    }

    // MARK: - Public API

    /// Process a frame with all configured transformations
    func process(_ image: CIImage) -> CIImage {
        var result = image

        // Apply rotation
        result = applyRotation(result)

        // Apply flips
        result = applyFlips(result)

        // Apply frame overlay
        result = applyFrameOverlay(result)

        return result
    }

    /// Process using vImage for better performance (returns CVPixelBuffer)
    func processWithVImage(_ pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        // Create vImage buffer from pixel buffer
        var sourceFormat = vImage_CGImageFormat(
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            colorSpace: nil,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.first.rawValue),
            version: 0,
            decode: nil,
            renderingIntent: .defaultIntent
        )

        var sourceBuffer = vImage_Buffer()
        var error = vImageBuffer_InitWithCVPixelBuffer(
            &sourceBuffer,
            &sourceFormat,
            pixelBuffer,
            nil,
            nil,
            vImage_Flags(kvImageNoFlags)
        )

        guard error == kvImageNoError else {
            return nil
        }

        defer { free(sourceBuffer.data) }

        // Apply rotation using vImage
        var destBuffer = vImage_Buffer()
        let rotatedWidth: vImagePixelCount
        let rotatedHeight: vImagePixelCount

        switch rotation {
        case .none, .rotate180:
            rotatedWidth = sourceBuffer.width
            rotatedHeight = sourceBuffer.height
        case .rotate90, .rotate270:
            rotatedWidth = sourceBuffer.height
            rotatedHeight = sourceBuffer.width
        }

        error = vImageBuffer_Init(
            &destBuffer,
            rotatedHeight,
            rotatedWidth,
            32,
            vImage_Flags(kvImageNoFlags)
        )

        guard error == kvImageNoError else {
            return nil
        }

        defer { free(destBuffer.data) }

        // Perform rotation
        let rotationConstant: UInt8
        switch rotation {
        case .none: rotationConstant = 0
        case .rotate90: rotationConstant = 1
        case .rotate180: rotationConstant = 2
        case .rotate270: rotationConstant = 3
        }

        if rotationConstant != 0 {
            var bgColor: [UInt8] = [0, 0, 0, 255]
            error = vImageRotate90_ARGB8888(
                &sourceBuffer,
                &destBuffer,
                rotationConstant,
                &bgColor,
                vImage_Flags(kvImageNoFlags)
            )

            guard error == kvImageNoError else {
                return nil
            }
        } else {
            // Copy source to dest if no rotation
            memcpy(destBuffer.data, sourceBuffer.data, sourceBuffer.rowBytes * Int(sourceBuffer.height))
        }

        // Apply flips
        if horizontalFlip {
            vImageHorizontalReflect_ARGB8888(&destBuffer, &destBuffer, vImage_Flags(kvImageNoFlags))
        }

        if verticalFlip {
            vImageVerticalReflect_ARGB8888(&destBuffer, &destBuffer, vImage_Flags(kvImageNoFlags))
        }

        // Create output pixel buffer
        var outputBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(destBuffer.width),
            Int(destBuffer.height),
            kCVPixelFormatType_32ARGB,
            nil,
            &outputBuffer
        )

        guard status == kCVReturnSuccess, let output = outputBuffer else {
            return nil
        }

        CVPixelBufferLockBaseAddress(output, [])
        let destData = CVPixelBufferGetBaseAddress(output)
        memcpy(destData, destBuffer.data, destBuffer.rowBytes * Int(destBuffer.height))
        CVPixelBufferUnlockBaseAddress(output, [])

        return output
    }

    // MARK: - Private Methods

    private func applyRotation(_ image: CIImage) -> CIImage {
        guard rotation != .none else { return image }

        let radians: CGFloat
        switch rotation {
        case .none: return image
        case .rotate90: radians = .pi / 2
        case .rotate180: radians = .pi
        case .rotate270: radians = -.pi / 2
        }

        // Rotate around center
        let centerX = image.extent.midX
        let centerY = image.extent.midY

        var transform = CGAffineTransform.identity
        transform = transform.translatedBy(x: centerX, y: centerY)
        transform = transform.rotated(by: radians)
        transform = transform.translatedBy(x: -centerX, y: -centerY)

        // For 90/270 rotations, adjust origin
        if rotation == .rotate90 || rotation == .rotate270 {
            let width = image.extent.width
            let height = image.extent.height
            let deltaX = (height - width) / 2
            let deltaY = (width - height) / 2
            transform = transform.translatedBy(x: deltaX, y: deltaY)
        }

        return image.transformed(by: transform)
    }

    private func applyFlips(_ image: CIImage) -> CIImage {
        var result = image

        if horizontalFlip {
            let transform = CGAffineTransform(scaleX: -1, y: 1)
                .translatedBy(x: -image.extent.width, y: 0)
            result = result.transformed(by: transform)
        }

        if verticalFlip {
            let transform = CGAffineTransform(scaleX: 1, y: -1)
                .translatedBy(x: 0, y: -image.extent.height)
            result = result.transformed(by: transform)
        }

        return result
    }

    private func applyFrameOverlay(_ image: CIImage) -> CIImage {
        guard frameStyle != .none else { return image }

        // Get or create frame overlay
        let overlay: CIImage
        if let cached = frameOverlayCache[frameStyle] {
            overlay = cached
        } else if let created = createFrameOverlay(for: frameStyle, size: image.extent.size) {
            frameOverlayCache[frameStyle] = created
            overlay = created
        } else {
            return image
        }

        // Scale overlay to match image size
        let scaleX = image.extent.width / overlay.extent.width
        let scaleY = image.extent.height / overlay.extent.height
        let scaledOverlay = overlay.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        // Composite overlay on top of image
        return scaledOverlay.composited(over: image)
    }

    private func createFrameOverlay(for style: FrameStyle, size: CGSize) -> CIImage? {
        // Create programmatic frame overlays
        let width = size.width
        let height = size.height

        switch style {
        case .none:
            return nil

        case .roundedCorners:
            return createRoundedCornersOverlay(width: width, height: height)

        case .polaroid:
            return createPolaroidOverlay(width: width, height: height)

        case .neonBorder:
            return createNeonBorderOverlay(width: width, height: height)

        case .vintage:
            return createVintageOverlay(width: width, height: height)
        }
    }

    private func createRoundedCornersOverlay(width: CGFloat, height: CGFloat) -> CIImage? {
        let size = NSSize(width: width, height: height)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.clear.setFill()
            rect.fill()

            // Create rounded rect path for corners mask
            let cornerRadius: CGFloat = min(width, height) * 0.05
            let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)

            // Fill outside the rounded rect with black (mask)
            NSColor.black.setFill()
            rect.fill()

            // Clear inside (reveal image)
            NSColor.clear.setFill()
            path.fill()

            return true
        }

        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        return CIImage(cgImage: cgImage)
    }

    private func createPolaroidOverlay(width: CGFloat, height: CGFloat) -> CIImage? {
        let borderWidth = width * 0.03
        let bottomBorder = height * 0.15  // Larger bottom for polaroid look

        let size = NSSize(width: width, height: height)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.clear.setFill()
            rect.fill()

            // White border
            NSColor.white.setFill()

            // Top border
            NSRect(x: 0, y: height - borderWidth, width: width, height: borderWidth).fill()

            // Left border
            NSRect(x: 0, y: 0, width: borderWidth, height: height).fill()

            // Right border
            NSRect(x: width - borderWidth, y: 0, width: borderWidth, height: height).fill()

            // Bottom border (larger)
            NSRect(x: 0, y: 0, width: width, height: bottomBorder).fill()

            return true
        }

        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        return CIImage(cgImage: cgImage)
    }

    private func createNeonBorderOverlay(width: CGFloat, height: CGFloat) -> CIImage? {
        let borderWidth = width * 0.02

        let size = NSSize(width: width, height: height)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.clear.setFill()
            rect.fill()

            // Neon cyan/magenta gradient border
            let outerRect = rect
            let innerRect = rect.insetBy(dx: borderWidth, dy: borderWidth)

            // Draw outer glow
            let glowColor = NSColor(red: 0, green: 1, blue: 1, alpha: 0.5)
            glowColor.setStroke()

            let path = NSBezierPath(rect: outerRect.insetBy(dx: borderWidth/2, dy: borderWidth/2))
            path.lineWidth = borderWidth
            path.stroke()

            // Draw inner bright line
            let brightColor = NSColor(red: 1, green: 0, blue: 1, alpha: 1)
            brightColor.setStroke()

            let innerPath = NSBezierPath(rect: innerRect.insetBy(dx: -borderWidth/4, dy: -borderWidth/4))
            innerPath.lineWidth = borderWidth / 2
            innerPath.stroke()

            return true
        }

        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        return CIImage(cgImage: cgImage)
    }

    private func createVintageOverlay(width: CGFloat, height: CGFloat) -> CIImage? {
        let size = NSSize(width: width, height: height)
        let image = NSImage(size: size, flipped: false) { rect in
            // Sepia-tinted vignette effect
            let gradient = NSGradient(colors: [
                NSColor(white: 0, alpha: 0),
                NSColor(white: 0, alpha: 0),
                NSColor(red: 0.2, green: 0.1, blue: 0, alpha: 0.3),
                NSColor(red: 0.1, green: 0.05, blue: 0, alpha: 0.5)
            ], atLocations: [0, 0.5, 0.8, 1], colorSpace: .deviceRGB)

            let center = NSPoint(x: rect.midX, y: rect.midY)
            let radius = max(width, height) * 0.7

            gradient?.draw(fromCenter: center, radius: 0, toCenter: center, radius: radius, options: [])

            return true
        }

        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        return CIImage(cgImage: cgImage)
    }

    // MARK: - Cache Management

    func clearCache() {
        frameOverlayCache.removeAll()
    }

    func invalidateCache(for style: FrameStyle) {
        frameOverlayCache.removeValue(forKey: style)
    }
}
