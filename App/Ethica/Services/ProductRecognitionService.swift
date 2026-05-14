//
//  ProductRecognitionService.swift
//  Ethica
//
//  Real-time product detection using Vision + Backend API
//

import Foundation
import Vision
import CoreImage
import UIKit
import AVFoundation
import Combine

// Helper extension for debug logging
extension Float {
    var f2: String { String(format: "%.2f", self) }
}

extension CGFloat {
    var f2: String { String(format: "%.2f", self) }
}

class ProductRecognitionService: ObservableObject {
    static let shared = ProductRecognitionService()
    
    @Published var detectedProducts: [DetectedProduct] = []
    @Published var isProcessing = false
    
    private var objectDetectionRequest: VNDetectRectanglesRequest?
    private var lastProcessTime: Date?
    private let processingThrottle: TimeInterval = 0.3  // Fast: 300ms between scans
    private let networkService = NetworkService.shared
    
    // Store latest pixel buffer for image capture
    private var latestPixelBuffer: CVPixelBuffer?
    private var pendingAnalysis: Task<Void, Never>?
    
    // Cache for analyzed products
    private var productCache: [String: (product: DetectedProduct, timestamp: Date)] = [:]
    private let cacheExpiration: TimeInterval = 300  // 5 minutes
    
    init() {
        setupObjectDetection()
    }
    
    // Force immediate scan (called by tap-to-scan)
    func forceScan() {
        AppLogger.debug("🎯 FORCE SCAN triggered by user")
        lastProcessTime = nil  // Reset throttle
        
        guard let pixelBuffer = latestPixelBuffer else {
            AppLogger.error("❌ No frame available for force scan")
            return
        }
        
        // Process immediately
        let requestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self, let request = self.objectDetectionRequest else { return }
            
            do {
                try requestHandler.perform([request])
            } catch {
                AppLogger.error("❌ Force scan error: \(error)")
            }
            
            DispatchQueue.main.async {
                self.isProcessing = false
            }
        }
    }
    
    private func setupObjectDetection() {
        objectDetectionRequest = VNDetectRectanglesRequest { [weak self] request, error in
            guard let self = self else { return }
            
            if let error = error {
                AppLogger.error("❌ Object detection error: \(error.localizedDescription)")
                return
            }
            
            guard let observations = request.results as? [VNRectangleObservation] else {
                return
            }
            
            self.processObjectObservations(observations)
        }
        
        // Configure for product package detection (very lenient settings)
        objectDetectionRequest?.minimumAspectRatio = 0.15  // Even wider range
        objectDetectionRequest?.maximumAspectRatio = 4.0   // Tall/wide packages
        objectDetectionRequest?.minimumSize = 0.03         // Smaller objects
        objectDetectionRequest?.minimumConfidence = 0.25   // Lower confidence
        objectDetectionRequest?.maximumObservations = 1    // Only center object
        
        AppLogger.debug("✅ AR Detection: minSize=0.03, minConf=0.25, focusing on CENTER object")
    }
    
    // Main entry point: Process camera frame
    func processFrame(_ pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation = .up) {
        // Throttle processing
        if let lastTime = lastProcessTime, Date().timeIntervalSince(lastTime) < processingThrottle {
            return
        }
        
        guard !isProcessing else { 
            AppLogger.debug("⏸️ Already processing, skipping frame")
            return 
        }
        
        AppLogger.debug("📸 Processing new camera frame...")
        
        // Store the latest pixel buffer for image capture
        self.latestPixelBuffer = pixelBuffer
        
        DispatchQueue.main.async {
            self.isProcessing = true
        }
        
        lastProcessTime = Date()
        
        let requestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self, let request = self.objectDetectionRequest else { return }
            
            do {
                try requestHandler.perform([request])
            } catch {
                AppLogger.error("❌ Failed to perform object detection: \(error)")
            }
            
            DispatchQueue.main.async {
                self.isProcessing = false
            }
        }
    }
    
    private func processObjectObservations(_ observations: [VNRectangleObservation]) {
        AppLogger.debug("📦 INSTANT: Detected \(observations.count) objects (showing immediately)")
        
        // Log detections
        for (i, obs) in observations.enumerated().prefix(3) {
            let box = obs.boundingBox
            AppLogger.debug("   [\(i)] conf=\(obs.confidence.f2) pos=(\(box.minX.f2),\(box.minY.f2)) size=(\(box.width.f2)x\(box.height.f2))")
        }
        
        // Clean expired cache
        cleanCache()
        
        // Get largest/most prominent object (center of frame)
        guard let centerObject = observations.first else {
            DispatchQueue.main.async {
                self.detectedProducts = []
            }
            return
        }
        
        let boundingBox = centerObject.boundingBox
        let cacheKey = String(format: "%.2f_%.2f", boundingBox.midX, boundingBox.midY)
        
        // Check cache first
        if let cached = productCache[cacheKey], Date().timeIntervalSince(cached.timestamp) < cacheExpiration {
            AppLogger.debug("💾 Using cached result")
            DispatchQueue.main.async {
                self.detectedProducts = [cached.product]
            }
            return
        }
        
        // **INSTANT FEEDBACK**: Show rectangle immediately with "Analyzing..." status
        var placeholder = DetectedProduct(
            name: "🔍 Analyzing...",
            brand: "Please wait",
            boundingBox: boundingBox,
            confidence: centerObject.confidence,
            barcode: nil
        )
        placeholder.safetyStatus = .unknown
        
        DispatchQueue.main.async {
            self.detectedProducts = [placeholder]
        }
        
        // Cancel any pending analysis
        pendingAnalysis?.cancel()
        
        // **BACKGROUND ANALYSIS**: Analyze via backend asynchronously
        AppLogger.debug("🎯 Triggering backend analysis...")
        pendingAnalysis = Task {
            await analyzeProduct(at: boundingBox, cacheKey: cacheKey)
        }
    }
    
    private func analyzeProduct(at boundingBox: CGRect, cacheKey: String) async {
        AppLogger.debug("📸 Analyzing product at region...")
        
        // Get the latest pixel buffer
        guard let pixelBuffer = self.latestPixelBuffer else {
            AppLogger.error("❌ No pixel buffer available")
            return
        }
            
            // Convert FULL frame to UIImage (not cropped - backend needs full label)
            guard let fullImage = self.convertPixelBufferToImage(pixelBuffer) else {
                AppLogger.error("❌ Failed to convert pixel buffer to image")
                return
            }
            
            AppLogger.debug("✅ Full frame size: \(fullImage.size.width)x\(fullImage.size.height)px")
            
            // Get user preferences
            let prefs = PreferencesManager.shared.preferences
            AppLogger.debug("👤 User preferences: allergens=\(prefs.selectedAllergens.count) diets=\(prefs.selectedDiets.count)")
            
            // Send FULL FRAME to backend for OCR + barcode analysis
            do {
                AppLogger.debug("🔄 Sending FULL FRAME to backend for OCR + barcode detection...")
                guard let result = try await self.networkService.analyzeImage(
                    fullImage,
                    preferences: prefs,
                    useBarcodeScanning: true,  // Enable barcode detection
                    useRestaurantMode: false
                ) else {
                    AppLogger.error("❌ Backend returned nil - no ingredients/barcode detected")
                    await self.createUnknownProduct(boundingBox: boundingBox, reason: "No readable data")
                    return
                }
                
                AppLogger.debug("✅ Backend success: '\(result.productName)' conf=\(result.confidence) safe=\(result.isSafe)")
                AppLogger.debug("   📋 Ingredients: \(result.ingredients.count), Allergens: \(result.detectedAllergens.count)")
                AppLogger.debug("   🏷️ Barcode: \(result.sourceBarcode ?? "none")")
                
                AppLogger.debug("✅ Backend success: '\(result.productName)' conf=\(result.confidence) safe=\(result.isSafe) violations=\(result.violations.count) warnings=\(result.cautionWarnings.count)")
                
                // Create DetectedProduct from analysis result
                var product = DetectedProduct(
                    name: result.productName,
                    brand: nil, // AnalysisResult doesn't have brand field
                    boundingBox: boundingBox,
                    confidence: Float(result.confidence),
                    barcode: result.sourceBarcode
                )
                
                // Map safety status based on violations and warnings
                if !result.violations.isEmpty {
                    product.safetyStatus = .danger
                    product.isSafeForUser = false
                } else if !result.cautionWarnings.isEmpty {
                    product.safetyStatus = .caution
                    product.isSafeForUser = true
                } else if result.isSafe {
                    product.safetyStatus = .safe
                    product.isSafeForUser = true
                } else {
                    product.safetyStatus = .unknown
                    product.isSafeForUser = false
                }
                
                product.allergenWarnings = result.detectedAllergens
                product.co2 = result.co2Emissions
                product.waterUsage = result.waterUsage
                product.healthScore = result.healthScore
                
                // Cache the result
                self.productCache[cacheKey] = (product, Date())
                
                // Update UI
                await MainActor.run {
                    if let index = self.detectedProducts.firstIndex(where: { 
                        abs($0.boundingBox.midX - boundingBox.midX) < 0.05 &&
                        abs($0.boundingBox.midY - boundingBox.midY) < 0.05
                    }) {
                        self.detectedProducts[index] = product
                    } else {
                        self.detectedProducts.append(product)
                    }
                    AppLogger.debug("✅ Product displayed: \(product.name) - \(product.safetyStatus)")
                }
                
            } catch {
                AppLogger.error("❌ Backend analysis error: \(error.localizedDescription)")
                await self.createUnknownProduct(boundingBox: boundingBox, reason: "Analysis error")
            }
    }
    
    private func createUnknownProduct(boundingBox: CGRect, reason: String) async {
        let product = DetectedProduct(
            name: "Unknown Product",
            brand: reason,
            boundingBox: boundingBox,
            confidence: 0.0,
            barcode: nil
        )
        
        await MainActor.run {
            if !self.detectedProducts.contains(where: { 
                abs($0.boundingBox.midX - boundingBox.midX) < 0.05 &&
                abs($0.boundingBox.midY - boundingBox.midY) < 0.05
            }) {
                self.detectedProducts.append(product)
            }
        }
    }
    
    private func cleanCache() {
        let now = Date()
        productCache = productCache.filter { _, value in
            now.timeIntervalSince(value.timestamp) < cacheExpiration
        }
    }
    
    // MARK: - Image Capture & Backend Integration
    
    private func convertPixelBufferToImage(_ pixelBuffer: CVPixelBuffer) -> UIImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        
        return UIImage(cgImage: cgImage, scale: 1.0, orientation: .up)
    }
    
    private func cropImage(from pixelBuffer: CVPixelBuffer, rect: CGRect) -> UIImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let imageSize = ciImage.extent.size
        
        // Add 30% padding around detected rectangle for more context
        let padding: CGFloat = 0.3
        let expandedRect = CGRect(
            x: max(0, rect.origin.x - rect.width * padding),
            y: max(0, rect.origin.y - rect.height * padding),
            width: min(1.0 - rect.origin.x, rect.width * (1 + 2 * padding)),
            height: min(1.0 - rect.origin.y, rect.height * (1 + 2 * padding))
        )
        
        // Convert normalized coordinates to pixel coordinates
        let cropRect = CGRect(
            x: expandedRect.origin.x * imageSize.width,
            y: (1.0 - expandedRect.origin.y - expandedRect.height) * imageSize.height, // Flip Y coordinate
            width: expandedRect.width * imageSize.width,
            height: expandedRect.height * imageSize.height
        )
        
        AppLogger.debug("✂️ Cropping: original=(\(rect.width.f2)x\(rect.height.f2)) expanded=(\(expandedRect.width.f2)x\(expandedRect.height.f2)) pixels=(\(cropRect.width)x\(cropRect.height))")
        
        // Crop the image
        guard let cropped = ciImage.cropped(to: cropRect).transformed(by: CGAffineTransform(translationX: -cropRect.origin.x, y: -cropRect.origin.y)) as CIImage? else {
            return nil
        }
        
        let context = CIContext()
        guard let cgImage = context.createCGImage(cropped, from: cropped.extent) else {
            return nil
        }
        
        return UIImage(cgImage: cgImage)
    }
}
