//
//  ReviewService.swift
//  Ethica
//
//  Service to manage product reviews
//

import Foundation
import SQLite

class ReviewService {
    static let shared = ReviewService()
    private let db: Connection?

    private init() {
        self.db = DatabaseManager.shared.db
        guard let db = db else {
            AppLogger.warning("⚠️ ReviewService: Database unavailable, reviews disabled")
            return
        }
        do {
            try ProductReview.createTable(db: db)
            try ReviewVote.createTable(db: db)
        } catch {
            AppLogger.error("❌ Error creating review tables: \(error)")
        }
    }

    // MARK: - Submit Review

    func submitReview(
        productName: String,
        productBrand: String?,
        barcode: String?,
        rating: Double,
        review: String?,
        isAlternative: Bool,
        originalProduct: String?,
        tasteRating: Double?,
        valueRating: Double?,
        availabilityRating: Double?
    ) async throws {
        guard let db = self.db else { return }
        let reviewId = UUID().uuidString
        let userId = AuthenticationService.shared.currentUserId ?? "anonymous"
        let userName = AuthenticationService.shared.currentDisplayName ?? "Anonymous"

        // Store locally
        let insert = ProductReview.table.insert(
            ProductReview.idCol <- reviewId,
            ProductReview.productNameCol <- productName,
            ProductReview.productBrandCol <- productBrand,
            ProductReview.barcodeCol <- barcode,
            ProductReview.userIdCol <- userId,
            ProductReview.userNameCol <- userName,
            ProductReview.ratingCol <- rating,
            ProductReview.reviewCol <- review,
            ProductReview.timestampCol <- Date(),
            ProductReview.isAlternativeCol <- isAlternative,
            ProductReview.originalProductCol <- originalProduct,
            ProductReview.helpfulCountCol <- 0,
            ProductReview.notHelpfulCountCol <- 0,
            ProductReview.tasteRatingCol <- tasteRating,
            ProductReview.valueRatingCol <- valueRating,
            ProductReview.availabilityRatingCol <- availabilityRating
        )

        try db.run(insert)
        AppLogger.debug("✅ Review saved locally: \(reviewId)")

        // Submit to backend
        await submitReviewToBackend(
            reviewId: reviewId,
            productName: productName,
            productBrand: productBrand,
            barcode: barcode,
            rating: rating,
            review: review,
            isAlternative: isAlternative,
            originalProduct: originalProduct,
            tasteRating: tasteRating,
            valueRating: valueRating,
            availabilityRating: availabilityRating
        )
    }

    private func submitReviewToBackend(
        reviewId: String,
        productName: String,
        productBrand: String?,
        barcode: String?,
        rating: Double,
        review: String?,
        isAlternative: Bool,
        originalProduct: String?,
        tasteRating: Double?,
        valueRating: Double?,
        availabilityRating: Double?
    ) async {
        guard let url = URL(string: "\(AppConfig.backendURL)/submit-review") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        await AuthenticationService.shared.addAuthToken(to: &request)

        let body: [String: Any] = [
            "review_id": reviewId,
            "product_name": productName,
            "product_brand": productBrand as Any,
            "barcode": barcode as Any,
            "rating": rating,
            "review": review as Any,
            "is_alternative": isAlternative,
            "original_product": originalProduct as Any,
            "taste_rating": tasteRating as Any,
            "value_rating": valueRating as Any,
            "availability_rating": availabilityRating as Any,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                AppLogger.warning("⚠️ Failed to submit review to backend")
                return
            }

            AppLogger.debug("✅ Review submitted to backend: \(reviewId)")
        } catch {
            AppLogger.error("❌ Error submitting review to backend: \(error)")
        }
    }

    // MARK: - Fetch Reviews

    func getReviewsForProduct(productName: String) throws -> [ProductReview] {
        guard let db = self.db else { return [] }
        let query = ProductReview.table
            .filter(ProductReview.productNameCol == productName)
            .order(ProductReview.timestampCol.desc)

        let rows = try db.prepare(query)

        return try rows.map { row in
            ProductReview(
                id: try row.get(ProductReview.idCol),
                productName: try row.get(ProductReview.productNameCol),
                productBrand: try row.get(ProductReview.productBrandCol),
                barcode: try row.get(ProductReview.barcodeCol),
                userId: try row.get(ProductReview.userIdCol),
                userName: try row.get(ProductReview.userNameCol),
                rating: try row.get(ProductReview.ratingCol),
                review: try row.get(ProductReview.reviewCol),
                timestamp: try row.get(ProductReview.timestampCol),
                isAlternative: try row.get(ProductReview.isAlternativeCol),
                originalProduct: try row.get(ProductReview.originalProductCol),
                helpfulCount: try row.get(ProductReview.helpfulCountCol),
                notHelpfulCount: try row.get(ProductReview.notHelpfulCountCol),
                tasteRating: try row.get(ProductReview.tasteRatingCol),
                valueRating: try row.get(ProductReview.valueRatingCol),
                availabilityRating: try row.get(ProductReview.availabilityRatingCol)
            )
        }
    }

    func getReviewSummary(productName: String) async throws -> ProductReviewSummary {
        // Fetch from backend for aggregated reviews across all users
        guard let url = URL(string: "\(AppConfig.backendURL)/get-review-summary") else {
            throw NSError(domain: "ReviewService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        await AuthenticationService.shared.addAuthToken(to: &request)

        let body: [String: Any] = [
            "product_name": productName
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                // Fallback to local reviews
                return try getLocalReviewSummary(productName: productName)
            }

            let summary = try JSONDecoder().decode(ProductReviewSummary.self, from: data)
            AppLogger.debug("✅ Fetched review summary from backend: \(summary.totalReviews) reviews")
            return summary
        } catch {
            AppLogger.warning("⚠️ Error fetching review summary from backend, falling back to local: \(error)")
            return try getLocalReviewSummary(productName: productName)
        }
    }

    private func getLocalReviewSummary(productName: String) throws -> ProductReviewSummary {
        let reviews = try getReviewsForProduct(productName: productName)

        guard !reviews.isEmpty else {
            return ProductReviewSummary(
                productName: productName,
                productBrand: nil,
                totalReviews: 0,
                averageRating: 0,
                averageTasteRating: nil,
                averageValueRating: nil,
                averageAvailabilityRating: nil,
                fiveStarCount: 0,
                fourStarCount: 0,
                threeStarCount: 0,
                twoStarCount: 0,
                oneStarCount: 0,
                topReviews: []
            )
        }

        let totalReviews = reviews.count
        let averageRating = reviews.reduce(0.0) { $0 + $1.rating } / Double(totalReviews)

        let tasteRatings = reviews.compactMap { $0.tasteRating }
        let averageTasteRating = tasteRatings.isEmpty ? nil : tasteRatings.reduce(0.0, +) / Double(tasteRatings.count)

        let valueRatings = reviews.compactMap { $0.valueRating }
        let averageValueRating = valueRatings.isEmpty ? nil : valueRatings.reduce(0.0, +) / Double(valueRatings.count)

        let availabilityRatings = reviews.compactMap { $0.availabilityRating }
        let averageAvailabilityRating = availabilityRatings.isEmpty ? nil : availabilityRatings.reduce(0.0, +) / Double(availabilityRatings.count)

        let fiveStarCount = reviews.filter { Int($0.rating) == 5 }.count
        let fourStarCount = reviews.filter { Int($0.rating) == 4 }.count
        let threeStarCount = reviews.filter { Int($0.rating) == 3 }.count
        let twoStarCount = reviews.filter { Int($0.rating) == 2 }.count
        let oneStarCount = reviews.filter { Int($0.rating) == 1 }.count

        let topReviews = reviews.sorted { $0.netHelpfulVotes > $1.netHelpfulVotes }.prefix(5)

        return ProductReviewSummary(
            productName: productName,
            productBrand: reviews.first?.productBrand,
            totalReviews: totalReviews,
            averageRating: averageRating,
            averageTasteRating: averageTasteRating,
            averageValueRating: averageValueRating,
            averageAvailabilityRating: averageAvailabilityRating,
            fiveStarCount: fiveStarCount,
            fourStarCount: fourStarCount,
            threeStarCount: threeStarCount,
            twoStarCount: twoStarCount,
            oneStarCount: oneStarCount,
            topReviews: Array(topReviews)
        )
    }

    // MARK: - Vote on Review

    func voteOnReview(reviewId: String, isHelpful: Bool) async throws {
        guard let db = self.db else { return }
        let userId = AuthenticationService.shared.currentUserId ?? "anonymous"

        // Check if user already voted
        let existingVote = try? db.pluck(
            ReviewVote.table
                .filter(ReviewVote.reviewIdCol == reviewId && ReviewVote.userIdCol == userId)
        )

        if let existing = existingVote {
            // Update existing vote
            let oldVote = try existing.get(ReviewVote.isHelpfulCol)
            if oldVote == isHelpful {
                // Same vote, remove it (toggle off)
                try db.run(
                    ReviewVote.table
                        .filter(ReviewVote.reviewIdCol == reviewId && ReviewVote.userIdCol == userId)
                        .delete()
                )

                // Decrement count
                if isHelpful {
                    try db.run(
                        ProductReview.table
                            .filter(ProductReview.idCol == reviewId)
                            .update(ProductReview.helpfulCountCol -= 1)
                    )
                } else {
                    try db.run(
                        ProductReview.table
                            .filter(ProductReview.idCol == reviewId)
                            .update(ProductReview.notHelpfulCountCol -= 1)
                    )
                }
            } else {
                // Different vote, update it
                try db.run(
                    ReviewVote.table
                        .filter(ReviewVote.reviewIdCol == reviewId && ReviewVote.userIdCol == userId)
                        .update(ReviewVote.isHelpfulCol <- isHelpful)
                )

                // Update counts
                if isHelpful {
                    try db.run(
                        ProductReview.table
                            .filter(ProductReview.idCol == reviewId)
                            .update(
                                ProductReview.helpfulCountCol += 1,
                                ProductReview.notHelpfulCountCol -= 1
                            )
                    )
                } else {
                    try db.run(
                        ProductReview.table
                            .filter(ProductReview.idCol == reviewId)
                            .update(
                                ProductReview.helpfulCountCol -= 1,
                                ProductReview.notHelpfulCountCol += 1
                            )
                    )
                }
            }
        } else {
            // New vote
            let insert = ReviewVote.table.insert(
                ReviewVote.reviewIdCol <- reviewId,
                ReviewVote.userIdCol <- userId,
                ReviewVote.isHelpfulCol <- isHelpful,
                ReviewVote.timestampCol <- Date()
            )
            try db.run(insert)

            // Increment count
            if isHelpful {
                try db.run(
                    ProductReview.table
                        .filter(ProductReview.idCol == reviewId)
                        .update(ProductReview.helpfulCountCol += 1)
                )
            } else {
                try db.run(
                    ProductReview.table
                        .filter(ProductReview.idCol == reviewId)
                        .update(ProductReview.notHelpfulCountCol += 1)
                )
            }
        }

        // Submit vote to backend
        await submitVoteToBackend(reviewId: reviewId, isHelpful: isHelpful)
    }

    private func submitVoteToBackend(reviewId: String, isHelpful: Bool) async {
        guard let url = URL(string: "\(AppConfig.backendURL)/vote-review") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10
        await AuthenticationService.shared.addAuthToken(to: &request)

        let body: [String: Any] = [
            "review_id": reviewId,
            "is_helpful": isHelpful
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (_, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                AppLogger.warning("⚠️ Failed to submit vote to backend")
                return
            }

            AppLogger.debug("✅ Vote submitted to backend")
        } catch {
            AppLogger.error("❌ Error submitting vote to backend: \(error)")
        }
    }

    // MARK: - Check User's Vote

    func getUserVote(reviewId: String) throws -> Bool? {
        guard let db = self.db else { return nil }
        let userId = AuthenticationService.shared.currentUserId ?? "anonymous"

        guard let vote = try? db.pluck(
            ReviewVote.table
                .filter(ReviewVote.reviewIdCol == reviewId && ReviewVote.userIdCol == userId)
        ) else {
            return nil
        }

        return try vote.get(ReviewVote.isHelpfulCol)
    }
}
