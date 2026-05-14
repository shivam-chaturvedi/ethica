//
//  ReviewSubmissionSheet.swift
//  Ethica
//
//  Sheet for submitting product reviews
//

import SwiftUI

struct ReviewSubmissionSheet: View {
    let productName: String
    let productBrand: String?
    let barcode: String?
    let isAlternative: Bool
    let originalProduct: String?

    @Environment(\.dismiss) var dismiss
    @State private var rating: Double = 4.0
    @State private var reviewText: String = ""
    @State private var tasteRating: Double = 4.0
    @State private var valueRating: Double = 4.0
    @State private var availabilityRating: Double = 4.0
    @State private var includeTasteRating = false
    @State private var includeValueRating = false
    @State private var includeAvailabilityRating = false
    @State private var isSubmitting = false
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        VStack(spacing: 8) {
                            if let brand = productBrand {
                                Text(brand)
                                    .font(.caption)
                                    .foregroundColor(Theme.textSecondary)
                            }
                            Text(productName)
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)

                            if isAlternative, let original = originalProduct {
                                Text("Alternative to \(original)")
                                    .font(.caption)
                                    .foregroundColor(Theme.primary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Theme.primary.opacity(0.1))
                                    )
                            }
                        }
                        .padding(.top, 8)

                        // Overall Rating
                        VStack(spacing: 12) {
                            Text("Overall Rating")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)

                            HStack(spacing: 8) {
                                ForEach(1...5, id: \.self) { star in
                                    Image(systemName: Double(star) <= rating ? "star.fill" : "star")
                                        .font(.system(size: 32))
                                        .foregroundColor(Double(star) <= rating ? .yellow : .gray)
                                        .onTapGesture {
                                            withAnimation(.spring(response: 0.3)) {
                                                rating = Double(star)
                                            }
                                        }
                                }
                            }

                            Text("\(Int(rating)) out of 5 stars")
                                .font(.caption)
                                .foregroundColor(Theme.textSecondary)
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Theme.surfaceBase)
                        )

                        // Review Text
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Your Review (Optional)")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)

                            TextEditor(text: $reviewText)
                                .frame(height: 120)
                                .padding(12)
                                .background(Theme.surfaceBase)
                                .cornerRadius(8)
                                .foregroundColor(.white)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Theme.primary.opacity(0.2), lineWidth: 1)
                                )

                            if reviewText.isEmpty {
                                Text("Share your experience with this product...")
                                    .font(.caption)
                                    .foregroundColor(Theme.textSecondary)
                                    .padding(.horizontal, 16)
                                    .padding(.top, -108)
                                    .allowsHitTesting(false)
                            }
                        }

                        // Optional Detailed Ratings
                        VStack(spacing: 16) {
                            Text("Detailed Ratings (Optional)")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            // Taste Rating
                            Toggle(isOn: $includeTasteRating) {
                                Text("Taste")
                                    .foregroundColor(.white)
                            }
                            .tint(Theme.primary)

                            if includeTasteRating {
                                VStack(spacing: 8) {
                                    HStack(spacing: 6) {
                                        ForEach(1...5, id: \.self) { star in
                                            Image(systemName: Double(star) <= tasteRating ? "star.fill" : "star")
                                                .font(.system(size: 20))
                                                .foregroundColor(Double(star) <= tasteRating ? .yellow : .gray)
                                                .onTapGesture {
                                                    withAnimation(.spring(response: 0.3)) {
                                                        tasteRating = Double(star)
                                                    }
                                                }
                                        }
                                    }
                                    Text("How does it taste?")
                                        .font(.caption)
                                        .foregroundColor(Theme.textSecondary)
                                }
                                .padding(.leading, 24)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }

                            // Value Rating
                            Toggle(isOn: $includeValueRating) {
                                Text("Value for Money")
                                    .foregroundColor(.white)
                            }
                            .tint(Theme.primary)

                            if includeValueRating {
                                VStack(spacing: 8) {
                                    HStack(spacing: 6) {
                                        ForEach(1...5, id: \.self) { star in
                                            Image(systemName: Double(star) <= valueRating ? "star.fill" : "star")
                                                .font(.system(size: 20))
                                                .foregroundColor(Double(star) <= valueRating ? .yellow : .gray)
                                                .onTapGesture {
                                                    withAnimation(.spring(response: 0.3)) {
                                                        valueRating = Double(star)
                                                    }
                                                }
                                        }
                                    }
                                    Text("Is it worth the price?")
                                        .font(.caption)
                                        .foregroundColor(Theme.textSecondary)
                                }
                                .padding(.leading, 24)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }

                            // Availability Rating
                            Toggle(isOn: $includeAvailabilityRating) {
                                Text("Availability")
                                    .foregroundColor(.white)
                            }
                            .tint(Theme.primary)

                            if includeAvailabilityRating {
                                VStack(spacing: 8) {
                                    HStack(spacing: 6) {
                                        ForEach(1...5, id: \.self) { star in
                                            Image(systemName: Double(star) <= availabilityRating ? "star.fill" : "star")
                                                .font(.system(size: 20))
                                                .foregroundColor(Double(star) <= availabilityRating ? .yellow : .gray)
                                                .onTapGesture {
                                                    withAnimation(.spring(response: 0.3)) {
                                                        availabilityRating = Double(star)
                                                    }
                                                }
                                        }
                                    }
                                    Text("How easy is it to find?")
                                        .font(.caption)
                                        .foregroundColor(Theme.textSecondary)
                                }
                                .padding(.leading, 24)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Theme.surfaceBase)
                        )

                        // Submit Button
                        Button(action: submitReview) {
                            HStack {
                                if isSubmitting {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Image(systemName: "checkmark.circle.fill")
                                    Text("Submit Review")
                                }
                            }
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Theme.primary)
                            .cornerRadius(12)
                        }
                        .disabled(isSubmitting)
                        .opacity(isSubmitting ? 0.6 : 1.0)
                    }
                    .padding()
                }
            }
            .navigationTitle("Write a Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(Theme.textSecondary)
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }

    // MARK: - Submit Review

    private func submitReview() {
        isSubmitting = true

        Task {
            do {
                try await ReviewService.shared.submitReview(
                    productName: productName,
                    productBrand: productBrand,
                    barcode: barcode,
                    rating: rating,
                    review: reviewText.isEmpty ? nil : reviewText,
                    isAlternative: isAlternative,
                    originalProduct: originalProduct,
                    tasteRating: includeTasteRating ? tasteRating : nil,
                    valueRating: includeValueRating ? valueRating : nil,
                    availabilityRating: includeAvailabilityRating ? availabilityRating : nil
                )

                await MainActor.run {
                    isSubmitting = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }
}

// MARK: - Preview

struct ReviewSubmissionSheet_Previews: PreviewProvider {
    static var previews: some View {
        ReviewSubmissionSheet(
            productName: "Beyond Burger",
            productBrand: "Beyond Meat",
            barcode: "810308001238",
            isAlternative: true,
            originalProduct: "Beef Burger"
        )
    }
}
