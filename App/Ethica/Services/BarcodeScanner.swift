//
//  BarcodeScanner.swift
//  Ethica
//
//  Barcode detection using Vision framework

import Foundation
import Vision
import UIKit

class BarcodeScanner {
    
    /// Detect barcodes in an image
    /// - Parameter image: UIImage to scan for barcodes
    /// - Returns: Array of detected barcode strings (EAN-13, UPC-A, etc.)
    func detectBarcodes(in image: UIImage) async -> [String] {
        guard let cgImage = image.cgImage else {
            AppLogger.error("❌ Failed to convert UIImage to CGImage")
            return []
        }
        
        return await withCheckedContinuation { continuation in
            // Flag to prevent double-resume (VNDetectBarcodesRequest callback + catch block)
            var resumed = false
            let resumeOnce: ([String]) -> Void = { value in
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: value)
            }

            let request = VNDetectBarcodesRequest { request, error in
                if let error = error {
                    AppLogger.error("❌ Barcode detection error: \(error.localizedDescription)")
                    resumeOnce([])
                    return
                }

                guard let observations = request.results as? [VNBarcodeObservation] else {
                    resumeOnce([])
                    return
                }

                let barcodes = observations.compactMap { $0.payloadStringValue }
                AppLogger.debug("📊 Detected \(barcodes.count) barcode(s): \(barcodes)")
                resumeOnce(barcodes)
            }

            // Support common retail barcode types
            request.symbologies = [
                .ean13,
                .ean8,
                .upce,
                .code128,
                .code39,
                .code93,
                .itf14,
                .qr
            ]

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    AppLogger.error("❌ Failed to perform barcode detection: \(error)")
                    resumeOnce([])
                }
            }
        }
    }
}
