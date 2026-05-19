//
//  MissingProductSubmissionView.swift
//  Ethica
//
//  Product not found — lightweight contribution flow
//

import SwiftUI

struct DietaryContributionTag: Identifiable, Hashable {
    let id: String
    let label: String
    let icon: String

    static let all: [DietaryContributionTag] = [
        DietaryContributionTag(id: "halal", label: "Halal", icon: "moon.fill"),
        DietaryContributionTag(id: "vegan", label: "Vegan", icon: "leaf.fill"),
        DietaryContributionTag(id: "vegetarian", label: "Vegetarian", icon: "carrot.fill"),
        DietaryContributionTag(id: "gluten_free", label: "Gluten Free", icon: "g.circle.fill"),
        DietaryContributionTag(id: "gmo_free", label: "GMO Free", icon: "leaf.arrow.circlepath"),
        DietaryContributionTag(id: "nut_free", label: "Nut Free", icon: "xmark.circle.fill"),
        DietaryContributionTag(id: "dairy_free", label: "Dairy Free", icon: "drop.fill"),
        DietaryContributionTag(id: "other", label: "Other", icon: "ellipsis.circle.fill")
    ]
}

struct MissingProductSubmissionView: View {
    let barcode: String
    var previewImage: UIImage?
    var onSkip: (() -> Void)?
    var onScanIngredients: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    @State private var productName = ""
    @State private var brand = ""
    @State private var ingredientsText = ""
    @State private var nutritionFactsText = ""
    @State private var notes = ""
    @State private var selectedTags: Set<String> = []
    @State private var productPhotos: [UIImage] = []

    @State private var isSubmitting = false
    @State private var isRunningOCR = false
    @State private var showThankYou = false
    @State private var showExpandedForm = false
    @State private var showCamera = false
    @State private var showPhotoLibrary = false
    @State private var capturedImage: UIImage?
    @State private var alertMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundPrimary.ignoresSafeArea()

                if showThankYou {
                    thankYouView
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: Spacing.lg) {
                            headerSection
                            contributionPromptSection

                            if showExpandedForm {
                                formSections
                            }
                        }
                        .padding(Spacing.lg)
                        .padding(.bottom, Spacing.xl)
                    }
                }

                if isSubmitting || isRunningOCR {
                    Color.black.opacity(0.25).ignoresSafeArea()
                    ProgressView()
                        .tint(Theme.primary)
                        .scaleEffect(1.2)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(showThankYou ? "Done" : "Not now") {
                        if showThankYou {
                            dismissFlow()
                        } else {
                            skip()
                        }
                    }
                    .foregroundColor(Theme.textSecondary)
                }
            }
        }
        .sheet(isPresented: $showPhotoLibrary) {
            ImagePicker(image: $capturedImage)
        }
        .sheet(isPresented: $showCamera) {
            CameraPicker(image: $capturedImage)
        }
        .onChange(of: capturedImage) { _, newImage in
            guard let image = newImage else { return }
            productPhotos.append(image)
            capturedImage = nil
            runOCROnImage(image)
        }
        .alert("Submission", isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            if let previewImage {
                Image(uiImage: previewImage)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 140)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .cornerRadius(Spacing.radiusMD)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: Spacing.radiusMD)
                        .fill(Theme.surfaceSecondary)
                        .frame(height: 120)
                    Image(systemName: "barcode.viewfinder")
                        .font(.system(size: 44))
                        .foregroundColor(Theme.textMuted)
                }
            }

            Text("We couldn’t find this product in our database yet.")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(Theme.textPrimary)

            Text("Barcode: \(barcode)")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Theme.textTertiary)
        }
    }

    private var contributionPromptSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Would you like to help improve the database by contributing this product?")
                .font(.system(size: 15))
                .foregroundColor(Theme.textSecondary)

            if !showExpandedForm {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showExpandedForm = true
                    }
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Yes, contribute product")
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.primary)
                    .cornerRadius(Spacing.radiusMD)
                }

                Button(action: skip) {
                    Text("Skip for now")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Theme.textTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }

                if let onScanIngredients {
                    Button {
                        dismiss()
                        onScanIngredients()
                    } label: {
                        Label("Scan ingredient list instead", systemImage: "text.viewfinder")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Theme.primary)
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    // MARK: - Form

    private var formSections: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            labeledField("Product Name", required: true) {
                TextField("e.g. Organic Almond Milk", text: $productName)
                    .textInputAutocapitalization(.words)
            }

            labeledField("Brand (optional)") {
                TextField("e.g. Califia Farms", text: $brand)
                    .textInputAutocapitalization(.words)
            }

            photosSection
            ingredientsSection
            nutritionSection
            dietaryTagsSection
            notesSection
            submitSection
        }
    }

    private var photosSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Product Photos")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Theme.textSecondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    ForEach(Array(productPhotos.enumerated()), id: \.offset) { index, photo in
                        ZStack(alignment: .topTrailing) {
                            Image(uiImage: photo)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 88, height: 88)
                                .clipped()
                                .cornerRadius(12)

                            Button {
                                productPhotos.remove(at: index)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.white)
                                    .shadow(radius: 2)
                            }
                            .offset(x: 6, y: -6)
                        }
                    }

                    if productPhotos.count < 4 {
                        Menu {
                            Button("Take Photo") { showCamera = true }
                            Button("Choose from Library") { showPhotoLibrary = true }
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: "camera.fill")
                                Text("Add")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundColor(Theme.primary)
                            .frame(width: 88, height: 88)
                            .background(Theme.surfaceBase)
                            .cornerRadius(12)
                        }
                    }
                }
            }

            Text("Photos help us verify the product. OCR will auto-fill ingredients when possible.")
                .font(.system(size: 12))
                .foregroundColor(Theme.textTertiary)
        }
    }

    private var ingredientsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("Ingredients")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.textSecondary)
                Spacer()
                if isRunningOCR {
                    ProgressView().scaleEffect(0.8)
                }
            }

            TextEditor(text: $ingredientsText)
                .frame(minHeight: 100)
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(Theme.surfaceBase)
                .cornerRadius(Spacing.radiusMD)
        }
    }

    private var nutritionSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Nutrition Facts (optional)")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Theme.textSecondary)

            TextEditor(text: $nutritionFactsText)
                .frame(minHeight: 80)
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(Theme.surfaceBase)
                .cornerRadius(Spacing.radiusMD)
        }
    }

    private var dietaryTagsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Dietary Tags")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Theme.textSecondary)

            FlowLayout(spacing: 8) {
                ForEach(DietaryContributionTag.all) { tag in
                    let selected = selectedTags.contains(tag.id)
                    Button {
                        if selected {
                            selectedTags.remove(tag.id)
                        } else {
                            selectedTags.insert(tag.id)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: tag.icon)
                                .font(.system(size: 11))
                            Text(tag.label)
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundColor(selected ? .white : Theme.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(selected ? Theme.primary : Theme.surfaceBase)
                        .cornerRadius(20)
                    }
                }
            }
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Notes (optional)")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Theme.textSecondary)

            TextField("Allergies, preferences, or other details", text: $notes, axis: .vertical)
                .lineLimit(3...6)
                .padding(12)
                .background(Theme.surfaceBase)
                .cornerRadius(Spacing.radiusMD)
        }
    }

    private var submitSection: some View {
        VStack(spacing: Spacing.sm) {
            Button(action: submit) {
                HStack {
                    Image(systemName: "paperplane.fill")
                    Text(isSubmitting ? "Submitting…" : "Submit Product")
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(canSubmit ? Theme.primary : Theme.surfaceSecondary)
                .cornerRadius(Spacing.radiusMD)
            }
            .disabled(!canSubmit || isSubmitting)

            Button(action: skip) {
                Text("Skip for now")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Theme.textTertiary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var thankYouView: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundColor(Theme.primary)

            Text("Thank you!")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(Theme.textPrimary)

            Text("Your contribution helps improve the app for everyone.")
                .font(.system(size: 16))
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xl)

            Spacer()

            Button(action: dismissFlow) {
                Text("Continue")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.primary)
                    .cornerRadius(Spacing.radiusMD)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.bottom, Spacing.xl)
        }
    }

    // MARK: - Helpers

    private var canSubmit: Bool {
        !productName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @ViewBuilder
    private func labeledField<Content: View>(
        _ title: String,
        required: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.textSecondary)
                if required {
                    Text("*")
                        .foregroundColor(Theme.error)
                }
            }
            content()
                .autocorrectionDisabled()
                .padding(12)
                .background(Theme.surfaceBase)
                .cornerRadius(Spacing.radiusMD)
        }
    }

    private func runOCROnImage(_ image: UIImage) {
        isRunningOCR = true
        Task {
            let text = await OnDeviceOCRService.shared.recognizeText(from: image)
            await MainActor.run {
                isRunningOCR = false
                applyOCRText(text)
            }
        }
    }

    private func applyOCRText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let lower = trimmed.lowercased()
        let looksNutrition = lower.contains("nutrition") ||
            lower.contains("calories") ||
            lower.contains("serving size") ||
            lower.contains("total fat") ||
            lower.contains("protein")

        if looksNutrition {
            if nutritionFactsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                nutritionFactsText = trimmed
            } else {
                nutritionFactsText += "\n\n" + trimmed
            }
        } else if ingredientsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ingredientsText = trimmed
        } else {
            ingredientsText += "\n\n" + trimmed
        }

        if productName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let firstLine = trimmed.components(separatedBy: .newlines).first,
           firstLine.count <= 60,
           !looksNutrition {
            productName = firstLine
        }
    }

    private func submit() {
        guard canSubmit else { return }
        isSubmitting = true

        let contribution = ProductContribution(
            barcode: barcode,
            productName: productName,
            brand: brand.isEmpty ? nil : brand,
            ingredientsText: ingredientsText.isEmpty ? nil : ingredientsText,
            nutritionFactsText: nutritionFactsText.isEmpty ? nil : nutritionFactsText,
            dietaryTags: Array(selectedTags).sorted(),
            notes: notes.isEmpty ? nil : notes,
            photos: productPhotos
        )

        Task {
            do {
                try await ProductSubmissionService.shared.submitProductContribution(contribution)
                await MainActor.run {
                    isSubmitting = false
                    withAnimation {
                        showThankYou = true
                    }
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    alertMessage = error.localizedDescription
                }
            }
        }
    }

    private func skip() {
        onSkip?()
        dismiss()
    }

    private func dismissFlow() {
        onSkip?()
        dismiss()
    }
}
