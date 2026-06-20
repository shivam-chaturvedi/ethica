//
//  BarcodeScanner.swift
//  Ethica
//
//  Barcode detection using Vision framework

import Foundation
import Vision
import UIKit
import CoreImage

class BarcodeScanner {

    /// Returns the best retail product barcode from an image, if any.
    func detectBestProductBarcode(in image: UIImage) async -> String? {
        let prepared = image.normalizedForBarcodeScan()

        if let fromBarcode = await detectFromBarcodeSymbols(in: prepared) {
            return fromBarcode
        }

        if let fromText = await detectFromPrintedText(in: prepared) {
            AppLogger.debug("📊 Barcode recovered from printed text: \(fromText)")
            return fromText
        }

        return nil
    }

    /// Detect barcodes in an image (tries multiple rendered variants; stops on first hit).
    func detectBarcodes(in image: UIImage) async -> [String] {
        if let best = await detectFromBarcodeSymbols(in: image) {
            return [best]
        }
        return []
    }

    private func detectFromBarcodeSymbols(in image: UIImage) async -> String? {
        for candidate in Self.visionScanVariants(from: image) {
            if Task.isCancelled { return nil }

            let found = await detectBarcodesOnce(in: candidate.image, orientation: candidate.orientation)
            if let best = Self.bestProductBarcode(from: found) {
                return Self.normalizeProductBarcode(best)
            }
        }
        return nil
    }

    private func detectFromPrintedText(in image: UIImage) async -> String? {
        guard let cgImage = image.cgImage else { return nil }

        return await withCheckedContinuation { continuation in
            var resumed = false
            let resumeOnce: (String?) -> Void = { value in
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: value)
            }

            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    AppLogger.error("❌ Barcode text OCR error: \(error.localizedDescription)")
                    resumeOnce(nil)
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    resumeOnce(nil)
                    return
                }

                var candidates: [String] = []
                let allText = observations
                    .compactMap { ($0 as? VNRecognizedTextObservation)?.topCandidates(1).first?.string }
                    .joined(separator: "\n")

                for observation in observations {
                    guard let text = observation.topCandidates(1).first?.string else { continue }
                    candidates.append(contentsOf: Self.extractProductBarcodes(from: text))
                }
                candidates.append(contentsOf: Self.extractProductBarcodes(from: allText))

                if let best = Self.bestProductBarcode(from: candidates) {
                    resumeOnce(best)
                    return
                }

                resumeOnce(nil)
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            if #available(iOS 16.0, *) {
                request.automaticallyDetectsLanguage = true
            }

            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    AppLogger.error("❌ Failed to perform barcode text OCR: \(error)")
                    resumeOnce(nil)
                }
            }
        }
    }

    private func detectBarcodesOnce(in cgImage: CGImage, orientation: CGImagePropertyOrientation) async -> [String] {
        await withCheckedContinuation { continuation in
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
                if !barcodes.isEmpty {
                    AppLogger.debug("📊 Detected \(barcodes.count) barcode(s): \(barcodes)")
                }
                resumeOnce(barcodes)
            }

            request.symbologies = Self.supportedSymbologies

            let handler = VNImageRequestHandler(
                cgImage: cgImage,
                orientation: orientation,
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

    /// Load a picked photo at full resolution for display + scanning.
    static func imageForBarcodeScan(from data: Data) -> UIImage? {
        if let source = CGImageSourceCreateWithData(data as CFData, nil) {
            let options: [CFString: Any] = [
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceCreateThumbnailFromImageIfAbsent: false,
                kCGImageSourceCreateThumbnailFromImageAlways: false
            ]
            if let cgImage = CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary) {
                return UIImage(cgImage: cgImage, scale: 1.0, orientation: .up)
            }
        }

        return UIImage(data: data)
    }

    /// Prefer numeric EAN/UPC values when Vision returns multiple symbologies.
    static func bestProductBarcode(from barcodes: [String]) -> String? {
        let normalized = barcodes.map { normalizeProductBarcode($0) }.filter { !$0.isEmpty }

        let checksumValid = normalized.filter { hasValidGS1Checksum($0) }
        let pool = checksumValid.isEmpty ? normalized.filter { isValidProductBarcode($0) } : checksumValid

        return pool.max(by: { productBarcodeScore($0) < productBarcodeScore($1) })
    }

    static func extractProductBarcodes(from text: String) -> [String] {
        var candidates: [String] = []

        let labeledPatterns = [
            #/(?i)barcode\s*[:-]?\s*(\d{8,14})/#,
            #/(?i)ean[-\s]?13\s*[:-]?\s*(\d{13})/#,
            #/(?i)ean\s*[:-]?\s*(\d{13})/#,
            #/(?i)gtin\s*[:-]?\s*(\d{8,14})/#
        ]

        for pattern in labeledPatterns {
            for match in text.matches(of: pattern) {
                candidates.append(String(match.1))
            }
        }

        let normalized = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")

        for match in normalized.matches(of: #/\d{8,14}/#) {
            let run = String(match.0)
            candidates.append(contentsOf: checksumValidSubstrings(in: run))
        }

        return candidates
    }

    private static func checksumValidSubstrings(in digitRun: String) -> [String] {
        var results: [String] = []

        if [8, 12, 13, 14].contains(digitRun.count), hasValidGS1Checksum(digitRun) {
            results.append(digitRun)
        }

        if digitRun.count > 13 {
            let chars = Array(digitRun)
            for start in 0...(chars.count - 13) {
                let sub = String(chars[start..<(start + 13)])
                if hasValidGS1Checksum(sub) {
                    results.append(sub)
                }
            }
        }

        if digitRun.count == 14, hasValidGS1Checksum(String(digitRun.prefix(13))) {
            results.append(String(digitRun.prefix(13)))
        }

        return results
    }

    static func hasValidGS1Checksum(_ barcode: String) -> Bool {
        let digits = barcode.filter(\.isNumber)
        guard digits.count == barcode.count else { return false }

        let nums = digits.compactMap { Int(String($0)) }
        guard nums.count == digits.count else { return false }

        switch digits.count {
        case 8, 12, 13:
            guard let expected = gs1CheckDigit(for: Array(nums.dropLast())) else { return false }
            return expected == nums.last
        case 14:
            guard let expected = gs1CheckDigit(for: Array(nums.dropLast())) else { return false }
            return expected == nums.last
        default:
            return false
        }
    }

    private static func gs1CheckDigit(for body: [Int]) -> Int? {
        guard !body.isEmpty else { return nil }
        var sum = 0
        for (index, digit) in body.enumerated() {
            sum += digit * (index % 2 == 0 ? 1 : 3)
        }
        return (10 - (sum % 10)) % 10
    }

    /// Normalize to digits; pad 12-digit UPC-A to 13-digit EAN-13 for database lookup.
    static func normalizeProductBarcode(_ raw: String) -> String {
        let digits = raw.filter(\.isNumber)
        guard !digits.isEmpty else {
            return raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if digits.count == 12 {
            return "0" + digits
        }
        return digits
    }

    /// Barcode forms to try with OpenFoodFacts (EAN-13 + UPC-A variants + OCR repair).
    static func lookupBarcodeCandidates(_ raw: String) -> [String] {
        let digits = raw.filter(\.isNumber)
        guard !digits.isEmpty else { return [] }

        var candidates: [String] = []
        let normalized = normalizeProductBarcode(digits)
        candidates.append(normalized)

        if normalized.count == 13, normalized.hasPrefix("0") {
            candidates.append(String(normalized.dropFirst()))
        }
        if digits != normalized {
            candidates.append(digits)
        }

        candidates.append(contentsOf: checksumValidSubstrings(in: digits))

        if digits.count > 13 {
            let chars = Array(digits)
            for start in 0...(chars.count - 13) {
                let sub = String(chars[start..<(start + 13)])
                if hasValidGS1Checksum(sub) {
                    candidates.append(sub)
                    if sub.hasPrefix("0") {
                        candidates.append(String(sub.dropFirst()))
                    }
                }
            }
        }

        var seen = Set<String>()
        return candidates
            .map { normalizeProductBarcode($0) }
            .filter { isValidProductBarcode($0) }
            .filter { seen.insert($0).inserted }
    }

    static func isValidProductBarcode(_ barcode: String) -> Bool {
        let digits = barcode.filter(\.isNumber)
        guard !digits.isEmpty, digits.count == barcode.count else { return false }
        guard [8, 12, 13, 14].contains(digits.count) else { return false }
        return hasValidGS1Checksum(digits)
    }

    private static let supportedSymbologies: [VNBarcodeSymbology] = [
        .ean13, .ean8, .upce, .code128, .code39, .code93, .itf14,
        .qr, .pdf417, .aztec, .dataMatrix
    ]

    private static func productBarcodeScore(_ barcode: String) -> Int {
        let digits = barcode.filter(\.isNumber)
        guard digits.count == barcode.count else { return 0 }

        var score = 0
        if hasValidGS1Checksum(digits) { score += 1_000 }

        switch digits.count {
        case 13: score += 100
        case 12: score += 90
        case 14: score += 80
        case 8: score += 70
        default: score += digits.isEmpty ? 0 : 10
        }
        return score
    }

    private static func visionScanVariants(from image: UIImage) -> [(image: CGImage, orientation: CGImagePropertyOrientation)] {
        let base = image.normalizedForBarcodeScan()
        var uiCandidates: [UIImage] = [base]

        let pixelWidth = base.pixelWidth
        let pixelHeight = base.pixelHeight
        let maxDimension = CGFloat(max(pixelWidth, pixelHeight))
        let minDimension = CGFloat(min(pixelWidth, pixelHeight))

        if maxDimension > 2800 {
            uiCandidates.append(base.scaledBitmap(maxPixelDimension: 2800))
        }

        if minDimension < 1100 {
            let targetMin: CGFloat = minDimension < 400 ? 1400 : 1100
            uiCandidates.append(base.scaledBitmap(minPixelDimension: targetMin))
        }

        if let boosted = base.contrastBoosted() {
            uiCandidates.append(boosted)
        }

        var results: [(CGImage, CGImagePropertyOrientation)] = []
        var seenKeys = Set<String>()

        for (index, candidate) in uiCandidates.enumerated() {
            guard let cgImage = candidate.cgImage else { continue }
            let key = "\(cgImage.width)x\(cgImage.height)"
            guard seenKeys.insert(key).inserted else { continue }

            results.append((cgImage, .up))

            // Only try rotated variants on the primary image.
            if index == 0 {
                for orientation: CGImagePropertyOrientation in [.down, .left, .right] {
                    results.append((cgImage, orientation))
                }
            }
        }

        return results
    }
}

extension UIImage {
    var pixelWidth: Int {
        cgImage?.width ?? Int(size.width * scale)
    }

    var pixelHeight: Int {
        cgImage?.height ?? Int(size.height * scale)
    }

    /// Renders the image upright at true pixel resolution for Vision / previews.
    func normalizedForBarcodeScan() -> UIImage {
        fixedOrientation().renderedPixelBitmap()
    }

    /// Renders the image upright so Vision / previews see the same orientation as the user.
    func fixedOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        return renderedPixelBitmap()
    }

    func renderedPixelBitmap() -> UIImage {
        if let cgImage, imageOrientation == .up, scale == 1.0 {
            return UIImage(cgImage: cgImage, scale: 1.0, orientation: .up)
        }

        let pixelSize = CGSize(
            width: CGFloat(pixelWidth),
            height: CGFloat(pixelHeight)
        )
        guard pixelSize.width > 0, pixelSize.height > 0 else { return self }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        return UIGraphicsImageRenderer(size: pixelSize, format: format).image { _ in
            UIColor.white.setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: pixelSize)).fill()
            draw(in: CGRect(origin: .zero, size: pixelSize))
        }
    }

    func scaledBitmap(maxPixelDimension: CGFloat) -> UIImage {
        let maxDimension = CGFloat(max(pixelWidth, pixelHeight))
        guard maxDimension > maxPixelDimension else { return self }
        let scale = maxPixelDimension / maxDimension
        return scaledBitmap(to: CGSize(
            width: CGFloat(pixelWidth) * scale,
            height: CGFloat(pixelHeight) * scale
        ))
    }

    func scaledBitmap(minPixelDimension: CGFloat) -> UIImage {
        let minDimension = CGFloat(min(pixelWidth, pixelHeight))
        guard minDimension < minPixelDimension else { return self }
        let scale = minPixelDimension / minDimension
        return scaledBitmap(to: CGSize(
            width: CGFloat(pixelWidth) * scale,
            height: CGFloat(pixelHeight) * scale
        ))
    }

    private func scaledBitmap(to pixelSize: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        return UIGraphicsImageRenderer(size: pixelSize, format: format).image { _ in
            UIColor.white.setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: pixelSize)).fill()
            draw(in: CGRect(origin: .zero, size: pixelSize))
        }
    }

    func contrastBoosted() -> UIImage? {
        guard let cgImage else { return nil }
        let input = CIImage(cgImage: cgImage)
        let output = input
            .applyingFilter("CIColorControls", parameters: [
                kCIInputContrastKey: 1.25,
                kCIInputBrightnessKey: 0.02,
                kCIInputSaturationKey: 0.0
            ])
            .applyingFilter("CISharpenLuminance", parameters: [
                kCIInputSharpnessKey: 0.4
            ])

        let context = CIContext(options: nil)
        guard let enhanced = context.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: enhanced, scale: 1.0, orientation: .up)
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
