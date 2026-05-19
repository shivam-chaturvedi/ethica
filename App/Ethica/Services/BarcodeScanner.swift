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
        guard let prepared = Self.visionReadyImage(from: image) else {
            AppLogger.error("❌ Failed to prepare UIImage for barcode detection")
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
                .qr,
                .pdf417,
                .aztec,
                .dataMatrix
            ]

            let handler = VNImageRequestHandler(
                cgImage: prepared.cgImage,
                orientation: prepared.orientation,
                options: [:]
            )

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

    /// Returns the best retail product barcode from an image, if any.
    func detectBestProductBarcode(in image: UIImage) async -> String? {
        let barcodes = await detectBarcodes(in: image)
        return Self.bestProductBarcode(from: barcodes)
    }

    /// Prefer numeric EAN/UPC values when Vision returns multiple symbologies.
    static func bestProductBarcode(from barcodes: [String]) -> String? {
        barcodes
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .max(by: { productBarcodeScore($0) < productBarcodeScore($1) })
    }

    private static func productBarcodeScore(_ barcode: String) -> Int {
        let digits = barcode.filter(\.isNumber)
        guard digits.count == barcode.count else { return 0 }
        switch digits.count {
        case 13: return 100
        case 12: return 90
        case 14: return 80
        case 8: return 70
        default: return digits.isEmpty ? 0 : 10
        }
    }

    /// Renders UIImage into a Vision-friendly CGImage, preserving EXIF orientation when needed.
    private static func visionReadyImage(from image: UIImage) -> (cgImage: CGImage, orientation: CGImagePropertyOrientation)? {
        if let cgImage = image.cgImage {
            return (cgImage, CGImagePropertyOrientation(image.imageOrientation))
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        let rendered = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
        guard let cgImage = rendered.cgImage else { return nil }
        return (cgImage, .up)
    }
}

private extension CGImagePropertyOrientation {
    init(_ uiOrientation: UIImage.Orientation) {
        switch uiOrientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
