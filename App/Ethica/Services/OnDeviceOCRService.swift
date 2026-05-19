//
//  OnDeviceOCRService.swift
//  Ethica
//
//  Lightweight on-device OCR using Vision (no cloud dependency)
//

import Foundation
import UIKit
import Vision

final class OnDeviceOCRService {
    static let shared = OnDeviceOCRService()

    private init() {}

    func recognizeText(from image: UIImage) async -> String {
        await withCheckedContinuation { continuation in
            guard let cgImage = image.cgImage else {
                continuation.resume(returning: "")
                return
            }

            let request = VNRecognizeTextRequest { request, _ in
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let lines: [String] = observations.compactMap { obs in
                    guard let candidate = obs.topCandidates(1).first, candidate.confidence > 0.45 else { return nil }
                    return candidate.string
                }
                let text = lines.joined(separator: "\n")
                continuation.resume(returning: text)
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            DispatchQueue.global(qos: .userInitiated).async {
                let handler = VNImageRequestHandler(cgImage: cgImage, orientation: CGImagePropertyOrientation(image.imageOrientation))
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(returning: "")
                }
            }
        }
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

