//
//  ImageCutoutService.swift
//  做饭记
//
//  Optimized subject extraction using Vision framework.
//  Implements smart instance selection and edge refinement.

import UIKit
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins

/// Service for extracting foreground objects from images using Vision framework.
/// Uses VNGenerateForegroundInstanceMaskRequest (iOS 17+) for subject isolation.
final class ImageCutoutService {
    
    // MARK: - Configuration
    
    /// Edge feathering radius in pixels (0 = no feathering)
    var featherRadius: CGFloat = 1.5
    
    /// Morphology erosion radius to trim edge artifacts (0 = no erosion)
    var edgeErosionRadius: CGFloat = 1.0
    
    /// Minimum area ratio for valid instance (relative to image area)
    var minAreaRatio: CGFloat = 0.01   // At least 1% of image
    
    /// Maximum area ratio for valid instance (relative to image area)
    var maxAreaRatio: CGFloat = 0.85   // At most 85% of image
    
    // MARK: - Private
    
    private let context: CIContext
    
    init() {
        // Use GPU acceleration for better performance
        self.context = CIContext(options: [
            .useSoftwareRenderer: false,
            .highQualityDownsample: true
        ])
    }
    
    // MARK: - Public API
    
    /// Extract foreground subject from image.
    /// Returns the cutout image with transparent background, or nil if extraction fails.
    func extractForeground(from image: UIImage) async -> UIImage? {
        // Normalize orientation first to avoid rotation issues
        let normalizedImage = normalizeOrientation(image)
        guard let cgImage = normalizedImage.cgImage else { return nil }
        
        if #available(iOS 17.0, *) {
            return await extractUsingInstanceMask(cgImage: cgImage, orientation: .up)
        } else {
            return await extractUsingSaliency(cgImage: cgImage, orientation: .up)
        }
    }
    
    /// Generate sticker outline image (white silhouette for stroke effect).
    /// Use this behind the cutout with slight scale increase for sticker border.
    func generateStickerOutline(from image: UIImage, outlineWidth: CGFloat = 4) async -> UIImage? {
        // Normalize orientation first to avoid rotation issues
        let normalizedImage = normalizeOrientation(image)
        guard let cgImage = normalizedImage.cgImage else { return nil }
        
        if #available(iOS 17.0, *) {
            return await generateOutlineUsingInstanceMask(
                cgImage: cgImage,
                orientation: .up,
                outlineWidth: outlineWidth
            )
        }
        return nil
    }
    
    // MARK: - Orientation Normalization
    
    /// Normalize image orientation by actually rotating pixels.
    /// This ensures consistent processing regardless of camera orientation metadata.
    private func normalizeOrientation(_ image: UIImage) -> UIImage {
        // If already up, no work needed
        guard image.imageOrientation != .up else { return image }
        
        // Draw image into a new context with correct orientation applied
        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        defer { UIGraphicsEndImageContext() }
        
        image.draw(in: CGRect(origin: .zero, size: image.size))
        
        return UIGraphicsGetImageFromCurrentImageContext() ?? image
    }
    
    // MARK: - iOS 17+ Implementation
    
    @available(iOS 17.0, *)
    private func extractUsingInstanceMask(cgImage: CGImage, orientation: UIImage.Orientation) async -> UIImage? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(
            cgImage: cgImage,
            orientation: cgImageOrientation(from: orientation),
            options: [:]
        )
        
        do {
            try handler.perform([request])
            
            guard let observation = request.results?.first else { return nil }
            
            let allInstances = observation.allInstances
            let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
            
            // Prioritize image center (viewfinder area) for instance selection
            let selectedInstances = selectBestInstance(
                from: allInstances,
                observation: observation,
                handler: handler,
                imageSize: imageSize
            )
            
            // Generate masked image
            let maskedBuffer = try observation.generateMaskedImage(
                ofInstances: selectedInstances,
                from: handler,
                croppedToInstancesExtent: false
            )
            
            var ciImage = CIImage(cvPixelBuffer: maskedBuffer)
            
            // Apply edge refinement
            if edgeErosionRadius > 0 || featherRadius > 0 {
                let mask = try observation.generateScaledMaskForImage(
                    forInstances: selectedInstances,
                    from: handler
                )
                ciImage = refineEdges(
                    image: CIImage(cgImage: cgImage),
                    mask: CIImage(cvPixelBuffer: mask),
                    erosion: edgeErosionRadius,
                    feather: featherRadius
                ) ?? ciImage
            }
            
            return renderToUIImage(ciImage)
            
        } catch {
            print("[ImageCutoutService] Instance mask extraction failed: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Select the best instance based on coverage in the center region of the image.
    /// Prioritizes objects that occupy the most area in the viewfinder zone.
    @available(iOS 17.0, *)
    private func selectBestInstance(
        from allInstances: IndexSet,
        observation: VNInstanceMaskObservation,
        handler: VNImageRequestHandler,
        imageSize: CGSize
    ) -> IndexSet {
        // If only one instance, use it
        guard allInstances.count > 1 else {
            print("[ImageCutoutService] Only one instance detected, using it")
            return allInstances
        }
        
        print("[ImageCutoutService] Multiple instances detected: \(allInstances.count), selecting best one for center region")
        
        // Define center region (middle 50% of image)
        let centerRegion = CGRect(
            x: imageSize.width * 0.25,
            y: imageSize.height * 0.25,
            width: imageSize.width * 0.5,
            height: imageSize.height * 0.5
        )
        
        var bestInstance: Int?
        var bestCoverage: Int = 0
        
        // Test each instance individually to find the one with most coverage in center
        for instanceIndex in allInstances {
            guard let mask = try? observation.generateScaledMaskForImage(
                forInstances: IndexSet(integer: instanceIndex),
                from: handler
            ) else {
                continue
            }
            
            let coverage = calculateCenterCoverage(
                mask: mask,
                imageSize: imageSize,
                centerRegion: centerRegion
            )
            
            print("[ImageCutoutService] Instance \(instanceIndex) center coverage: \(coverage)")
            
            if coverage > bestCoverage {
                bestCoverage = coverage
                bestInstance = instanceIndex
            }
        }
        
        if let best = bestInstance, bestCoverage > 0 {
            print("[ImageCutoutService] Selected instance \(best) with coverage \(bestCoverage)")
            return IndexSet(integer: best)
        }
        
        // Fallback: use the first instance
        if let first = allInstances.first {
            print("[ImageCutoutService] Fallback to first instance: \(first)")
            return IndexSet(integer: first)
        }
        
        return allInstances
    }
    
    /// Calculate how many foreground pixels an instance has in the center region.
    private func calculateCenterCoverage(
        mask: CVPixelBuffer,
        imageSize: CGSize,
        centerRegion: CGRect
    ) -> Int {
        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }
        
        let maskWidth = CVPixelBufferGetWidth(mask)
        let maskHeight = CVPixelBufferGetHeight(mask)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(mask)
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(mask) else {
            return 0
        }
        
        let pointer = baseAddress.assumingMemoryBound(to: UInt8.self)
        
        // Scale center region to mask coordinates
        let scaleX = CGFloat(maskWidth) / imageSize.width
        let scaleY = CGFloat(maskHeight) / imageSize.height
        
        let maskRegion = CGRect(
            x: Int(centerRegion.origin.x * scaleX),
            y: Int(centerRegion.origin.y * scaleY),
            width: Int(centerRegion.width * scaleX),
            height: Int(centerRegion.height * scaleY)
        )
        
        var foregroundCount = 0
        
        let startX = max(0, Int(maskRegion.origin.x))
        let endX = min(maskWidth, Int(maskRegion.origin.x + maskRegion.width))
        let startY = max(0, Int(maskRegion.origin.y))
        let endY = min(maskHeight, Int(maskRegion.origin.y + maskRegion.height))
        
        // Sample pixels (skip some for performance)
        let step = 4
        for y in stride(from: startY, to: endY, by: step) {
            for x in stride(from: startX, to: endX, by: step) {
                let value = pointer[y * bytesPerRow + x]
                if value > 128 {
                    foregroundCount += 1
                }
            }
        }
        
        return foregroundCount
    }
    
    @available(iOS 17.0, *)
    private func generateOutlineUsingInstanceMask(
        cgImage: CGImage,
        orientation: UIImage.Orientation,
        outlineWidth: CGFloat
    ) async -> UIImage? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(
            cgImage: cgImage,
            orientation: cgImageOrientation(from: orientation),
            options: [:]
        )
        
        do {
            try handler.perform([request])
            
            guard let observation = request.results?.first else { return nil }
            
            let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
            let selectedInstances = selectBestInstance(
                from: observation.allInstances,
                observation: observation,
                handler: handler,
                imageSize: imageSize
            )
            
            let maskBuffer = try observation.generateScaledMaskForImage(
                forInstances: selectedInstances,
                from: handler
            )
            
            var maskImage = CIImage(cvPixelBuffer: maskBuffer)
            
            // Scale mask to original image size BEFORE dilation
            // This ensures outlineWidth is in original image pixels
            let scaleX = CGFloat(cgImage.width) / maskImage.extent.width
            let scaleY = CGFloat(cgImage.height) / maskImage.extent.height
            maskImage = maskImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
            
            // Dilate the scaled mask to create outline
            let dilateFilter = CIFilter.morphologyMaximum()
            dilateFilter.inputImage = maskImage
            dilateFilter.radius = Float(outlineWidth)
            
            guard let dilatedMask = dilateFilter.outputImage else { return nil }
            
            // Create white image with the dilated mask as alpha
            let whiteImage = CIImage(color: .white).cropped(to: dilatedMask.extent)
            
            guard let blendFilter = CIFilter(name: "CIBlendWithMask") else { return nil }
            blendFilter.setValue(whiteImage, forKey: kCIInputImageKey)
            blendFilter.setValue(CIImage.empty(), forKey: kCIInputBackgroundImageKey)
            blendFilter.setValue(dilatedMask, forKey: kCIInputMaskImageKey)
            
            guard let output = blendFilter.outputImage else { return nil }
            
            return renderToUIImage(output)
            
        } catch {
            print("[ImageCutoutService] Outline generation failed: \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - iOS 16 Fallback
    
    private func extractUsingSaliency(cgImage: CGImage, orientation: UIImage.Orientation) async -> UIImage? {
        let request = VNGenerateAttentionBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(
            cgImage: cgImage,
            orientation: cgImageOrientation(from: orientation),
            options: [:]
        )
        
        do {
            try handler.perform([request])
            
            guard let result = request.results?.first else { return nil }
            
            let sourceImage = CIImage(cgImage: cgImage)
            let maskImage = CIImage(cvPixelBuffer: result.pixelBuffer)
            
            // Apply with edge refinement
            guard let refined = refineEdges(
                image: sourceImage,
                mask: maskImage,
                erosion: edgeErosionRadius,
                feather: featherRadius
            ) else {
                return nil
            }
            
            return renderToUIImage(refined)
            
        } catch {
            print("[ImageCutoutService] Saliency extraction failed: \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - Edge Refinement
    
    /// Refine mask edges with erosion and feathering for cleaner cutouts.
    private func refineEdges(
        image: CIImage,
        mask: CIImage,
        erosion: CGFloat,
        feather: CGFloat
    ) -> CIImage? {
        var processedMask = mask
        
        // Step 1: Scale mask to match source image
        let scaleX = image.extent.width / mask.extent.width
        let scaleY = image.extent.height / mask.extent.height
        processedMask = processedMask.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        
        // Step 2: Morphology erosion - slightly shrink mask to remove edge artifacts
        if erosion > 0 {
            let erodeFilter = CIFilter.morphologyMinimum()
            erodeFilter.inputImage = processedMask
            erodeFilter.radius = Float(erosion)
            processedMask = erodeFilter.outputImage ?? processedMask
        }
        
        // Step 3: Gaussian blur for edge feathering (anti-aliasing)
        if feather > 0 {
            let blurFilter = CIFilter.gaussianBlur()
            blurFilter.inputImage = processedMask
            blurFilter.radius = Float(feather)
            
            // Clamp to prevent edge bleeding
            if let blurred = blurFilter.outputImage {
                processedMask = blurred.clamped(to: processedMask.extent)
            }
        }
        
        // Step 4: Apply refined mask to original image
        guard let blendFilter = CIFilter(name: "CIBlendWithMask") else { return nil }
        blendFilter.setValue(image, forKey: kCIInputImageKey)
        blendFilter.setValue(CIImage.empty(), forKey: kCIInputBackgroundImageKey)
        blendFilter.setValue(processedMask, forKey: kCIInputMaskImageKey)
        
        return blendFilter.outputImage
    }
    
    // MARK: - Rendering
    
    private func renderToUIImage(_ ciImage: CIImage) -> UIImage? {
        // Render with proper color space for transparency
        guard let cgImage = context.createCGImage(
            ciImage,
            from: ciImage.extent,
            format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
        ) else {
            return nil
        }
        
        return UIImage(cgImage: cgImage)
    }
    
    // MARK: - Utilities
    
    private func cgImageOrientation(from uiOrientation: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch uiOrientation {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}
