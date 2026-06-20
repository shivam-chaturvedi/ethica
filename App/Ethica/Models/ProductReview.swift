//
//  ProductReview.swift
//  Ethica
//
//  Product review model for user-generated reviews
//

import Foundation

#if canImport(SQLite)
import SQLite
#endif

struct ProductReview: Identifiable, Codable {
    let id: String // UUID
    let productName: String
    let productBrand: String?
    let barcode: String?
    let userId: String
    let userName: String?
    let rating: Double // 1.0 - 5.0
    let review: String?
    let timestamp: Date
    let isAlternative: Bool // Whether this is a review of an alternative product
    let originalProduct: String? // If isAlternative, what was the original product

    // Helpful votes
    let helpfulCount: Int
    let notHelpfulCount: Int

    // Review categories
    let tasteRating: Double? // 1.0 - 5.0
    let valueRating: Double? // 1.0 - 5.0 (price vs quality)
    let availabilityRating: Double? // 1.0 - 5.0 (easy to find)

    // Computed properties
    var netHelpfulVotes: Int {
        helpfulCount - notHelpfulCount
    }

    var formattedTimestamp: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }

    var starDisplay: String {
        String(repeating: "★", count: Int(rating)) + String(repeating: "☆", count: 5 - Int(rating))
    }
}

// MARK: - Review Summary (Aggregated)

struct ProductReviewSummary: Codable {
    let productName: String
    let productBrand: String?
    let totalReviews: Int
    let averageRating: Double
    let averageTasteRating: Double?
    let averageValueRating: Double?
    let averageAvailabilityRating: Double?

    // Rating distribution
    let fiveStarCount: Int
    let fourStarCount: Int
    let threeStarCount: Int
    let twoStarCount: Int
    let oneStarCount: Int

    // Top reviews (sorted by helpful votes)
    let topReviews: [ProductReview]

    var ratingPercentages: [Int: Double] {
        guard totalReviews > 0 else { return [:] }
        return [
            5: Double(fiveStarCount) / Double(totalReviews) * 100,
            4: Double(fourStarCount) / Double(totalReviews) * 100,
            3: Double(threeStarCount) / Double(totalReviews) * 100,
            2: Double(twoStarCount) / Double(totalReviews) * 100,
            1: Double(oneStarCount) / Double(totalReviews) * 100
        ]
    }

    var formattedAverageRating: String {
        String(format: "%.1f", averageRating)
    }
}

// MARK: - SQLite Table Definition

#if canImport(SQLite)
extension ProductReview {
    static let table = Table("product_reviews")
    static let idCol = Expression<String>("id")
    static let productNameCol = Expression<String>("product_name")
    static let productBrandCol = Expression<String?>("product_brand")
    static let barcodeCol = Expression<String?>("barcode")
    static let userIdCol = Expression<String>("user_id")
    static let userNameCol = Expression<String?>("user_name")
    static let ratingCol = Expression<Double>("rating")
    static let reviewCol = Expression<String?>("review")
    static let timestampCol = Expression<Date>("timestamp")
    static let isAlternativeCol = Expression<Bool>("is_alternative")
    static let originalProductCol = Expression<String?>("original_product")
    static let helpfulCountCol = Expression<Int>("helpful_count")
    static let notHelpfulCountCol = Expression<Int>("not_helpful_count")
    static let tasteRatingCol = Expression<Double?>("taste_rating")
    static let valueRatingCol = Expression<Double?>("value_rating")
    static let availabilityRatingCol = Expression<Double?>("availability_rating")

    static func createTable(db: Connection) throws {
        try db.run(table.create(ifNotExists: true) { t in
            t.column(idCol, primaryKey: true)
            t.column(productNameCol)
            t.column(productBrandCol)
            t.column(barcodeCol)
            t.column(userIdCol)
            t.column(userNameCol)
            t.column(ratingCol)
            t.column(reviewCol)
            t.column(timestampCol)
            t.column(isAlternativeCol, defaultValue: false)
            t.column(originalProductCol)
            t.column(helpfulCountCol, defaultValue: 0)
            t.column(notHelpfulCountCol, defaultValue: 0)
            t.column(tasteRatingCol)
            t.column(valueRatingCol)
            t.column(availabilityRatingCol)
        })

        // Index for faster queries
        try db.run(table.createIndex(productNameCol, ifNotExists: true))
        try db.run(table.createIndex(barcodeCol, ifNotExists: true))
    }
}

// MARK: - Review Vote Tracking

struct ReviewVote: Codable {
    let reviewId: String
    let userId: String
    let isHelpful: Bool // true = helpful, false = not helpful
    let timestamp: Date

    static let table = Table("review_votes")
    static let reviewIdCol = Expression<String>("review_id")
    static let userIdCol = Expression<String>("user_id")
    static let isHelpfulCol = Expression<Bool>("is_helpful")
    static let timestampCol = Expression<Date>("timestamp")

    static func createTable(db: Connection) throws {
        try db.run(table.create(ifNotExists: true) { t in
            t.column(reviewIdCol)
            t.column(userIdCol)
            t.column(isHelpfulCol)
            t.column(timestampCol)
            t.primaryKey(reviewIdCol, userIdCol) // User can only vote once per review
        })
    }
}
#else
struct ReviewVote: Codable {
    let reviewId: String
    let userId: String
    let isHelpful: Bool
    let timestamp: Date
}
#endif
