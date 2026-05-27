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
        await submitReviewToSupabase(
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

    private func submitReviewToSupabase(
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
        guard let accessToken = AuthenticationService.shared.authToken, !accessToken.isEmpty else { return }
        let userId = AuthenticationService.shared.currentUserId
        let userName = AuthenticationService.shared.currentDisplayName

        let payload: [String: Any] = [
            "review_id": reviewId,
            "user_id": userId as Any,
            "user_name": userName as Any,
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
            "helpful_count": 0,
            "not_helpful_count": 0,
            "created_at": ISO8601DateFormatter().string(from: Date())
        ]

        do {
            try await SupabaseAPI.shared.insertRow(accessToken: accessToken, table: "product_reviews", payload: payload)
            AppLogger.debug("✅ Review submitted to Supabase: \(reviewId)")
        } catch {
            AppLogger.debug("⚠️ Review submit to Supabase failed: \(error.localizedDescription)")
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
        do {
            let rows = try await SupabaseAPI.shared.fetchRows(
                accessToken: AuthenticationService.shared.authToken,
                table: "product_reviews",
                queryItems: [
                    URLQueryItem(name: "select", value: "review_id,product_name,product_brand,barcode,user_id,user_name,rating,review,is_alternative,original_product,taste_rating,value_rating,availability_rating,helpful_count,not_helpful_count,created_at"),
                    URLQueryItem(name: "product_name", value: "eq.\(productName)"),
                    URLQueryItem(name: "limit", value: "200")
                ]
            )

            // If Supabase has nothing (or row-level permissions prevent reads), fall back to local.
            if rows.isEmpty {
                return try getLocalReviewSummary(productName: productName)
            }

            let reviews: [ProductReview] = rows.compactMap { row in
                guard let id = row["review_id"] as? String,
                      let name = row["product_name"] as? String,
                      let rating = row["rating"] as? Double else { return nil }

                let createdAt = row["created_at"] as? String
                let ts = createdAt.flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date()

                return ProductReview(
                    id: id,
                    productName: name,
                    productBrand: row["product_brand"] as? String,
                    barcode: row["barcode"] as? String,
                    userId: (row["user_id"] as? String) ?? "anonymous",
                    userName: (row["user_name"] as? String) ?? "Anonymous",
                    rating: rating,
                    review: row["review"] as? String,
                    timestamp: ts,
                    isAlternative: (row["is_alternative"] as? Bool) ?? false,
                    originalProduct: row["original_product"] as? String,
                    helpfulCount: (row["helpful_count"] as? Int) ?? 0,
                    notHelpfulCount: (row["not_helpful_count"] as? Int) ?? 0,
                    tasteRating: row["taste_rating"] as? Double,
                    valueRating: row["value_rating"] as? Double,
                    availabilityRating: row["availability_rating"] as? Double
                )
            }

            if reviews.isEmpty {
                return try getLocalReviewSummary(productName: productName)
            }

            // Reuse the local summarizer logic by temporarily using the local path style.
            // (No persistence needed; just compute summary from fetched reviews.)
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
        } catch {
            AppLogger.warning("⚠️ Error fetching review summary from Supabase, falling back to local: \(error)")
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

        // Best-effort cloud sync to Supabase
        await submitVoteToSupabase(reviewId: reviewId, isHelpful: isHelpful)
    }

    private func submitVoteToSupabase(reviewId: String, isHelpful: Bool) async {
        guard let accessToken = AuthenticationService.shared.authToken, !accessToken.isEmpty else { return }
        let userId = AuthenticationService.shared.currentUserId

        let payload: [String: Any] = [
            "review_id": reviewId,
            "user_id": userId as Any,
            "vote": isHelpful ? "helpful" : "not_helpful",
            "created_at": ISO8601DateFormatter().string(from: Date())
        ]

        do {
            try await SupabaseAPI.shared.insertRow(accessToken: accessToken, table: "review_votes", payload: payload)
        } catch {
            AppLogger.debug("⚠️ Vote submit to Supabase failed: \(error.localizedDescription)")
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
