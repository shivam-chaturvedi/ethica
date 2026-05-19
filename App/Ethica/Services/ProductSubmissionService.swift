//
//  ProductSubmissionService.swift
//  Ethica
//
//  Missing product feedback/submission (Firestore)
//

import Foundation
import UIKit
import FirebaseFirestore

enum ProductSubmissionError: LocalizedError {
    case notAuthenticated
    case invalidProductName

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Couldn’t verify your session. Please try again."
        case .invalidProductName:
            return "Please enter a product name."
        }
    }
}

struct ProductContribution {
    let barcode: String
    let productName: String
    let brand: String?
    let ingredientsText: String?
    let nutritionFactsText: String?
    let dietaryTags: [String]
    let notes: String?
    let photos: [UIImage]
}

@MainActor
final class ProductSubmissionService {
    static let shared = ProductSubmissionService()

    private let db = Firestore.firestore()
    private let maxPhotos = 4
    private let maxPhotoBytes = 280_000

    private init() {}

    func submitMissingProduct(
        barcode: String,
        productName: String,
        brand: String?,
        ingredientsText: String?
    ) async throws {
        try await submitProductContribution(
            ProductContribution(
                barcode: barcode,
                productName: productName,
                brand: brand,
                ingredientsText: ingredientsText,
                nutritionFactsText: nil,
                dietaryTags: [],
                notes: nil,
                photos: []
            )
        )
    }

    func submitProductContribution(_ contribution: ProductContribution) async throws {
        let uid = try await ensureUserId()

        let trimmedName = contribution.productName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw ProductSubmissionError.invalidProductName
        }

        let trimmedBrand = contribution.brand?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedIngredients = contribution.ingredientsText?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNutrition = contribution.nutritionFactsText?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNotes = contribution.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        let photoPayloads = encodePhotos(contribution.photos.prefix(maxPhotos))

        var payload: [String: Any] = [
            "barcode": contribution.barcode,
            "productName": trimmedName,
            "userId": uid,
            "createdAt": FieldValue.serverTimestamp(),
            "source": "ios_app",
            "status": "pending_review",
            "dietaryTags": contribution.dietaryTags
        ]

        if let trimmedBrand, !trimmedBrand.isEmpty { payload["brand"] = trimmedBrand }
        if let trimmedIngredients, !trimmedIngredients.isEmpty { payload["ingredientsText"] = trimmedIngredients }
        if let trimmedNutrition, !trimmedNutrition.isEmpty { payload["nutritionFactsText"] = trimmedNutrition }
        if let trimmedNotes, !trimmedNotes.isEmpty { payload["notes"] = trimmedNotes }
        if !photoPayloads.isEmpty { payload["photosBase64"] = photoPayloads }

        _ = try await db.collection("product_submissions").addDocument(data: payload)
    }

    private func ensureUserId() async throws -> String {
        if let uid = AuthenticationService.shared.currentUserId {
            return uid
        }
        try await AuthenticationService.shared.signInAnonymously()
        guard let uid = AuthenticationService.shared.currentUserId else {
            throw ProductSubmissionError.notAuthenticated
        }
        return uid
    }

    private func encodePhotos<S: Sequence>(_ images: S) -> [String] where S.Element == UIImage {
        images.compactMap { image in
            guard let data = compressedJPEGData(from: image) else { return nil }
            guard data.count <= maxPhotoBytes else { return nil }
            return data.base64EncodedString()
        }
    }

    private func compressedJPEGData(from image: UIImage, maxDimension: CGFloat = 900, quality: CGFloat = 0.62) -> Data? {
        let size = image.size
        let maxSide = max(size.width, size.height)
        let targetSize: CGSize
        if maxSide > maxDimension {
            let scale = maxDimension / maxSide
            targetSize = CGSize(width: size.width * scale, height: size.height * scale)
        } else {
            targetSize = size
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let rendered = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return rendered.jpegData(compressionQuality: quality)
    }
}
