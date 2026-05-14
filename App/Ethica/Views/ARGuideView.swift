//
//  ARGuideView.swift
//  Ethica
//
//  Tutorial and guide for AR Shelf Scanner
//

import SwiftUI

struct ARGuideView: View {
    @Environment(\.dismiss) var dismiss
    @State private var currentPage = 0
    
    private let pages: [GuidePage] = [
        GuidePage(
            icon: "camera.metering.matrix",
            iconColor: "EC4899",
            title: "Point at Shelf",
            description: "Aim your camera at products on a grocery store shelf",
            tip: "Works best with clear, well-lit shelves"
        ),
        GuidePage(
            icon: "checkmark.circle.fill",
            iconColor: "10B981",
            title: "Green = Safe",
            description: "Products outlined in green are safe for your dietary restrictions",
            tip: "No allergens detected, low environmental impact"
        ),
        GuidePage(
            icon: "exclamationmark.triangle.fill",
            iconColor: "F59E0B",
            title: "Yellow = Caution",
            description: "May contain traces of allergens or have moderate environmental impact",
            tip: "Review details before purchasing"
        ),
        GuidePage(
            icon: "xmark.circle.fill",
            iconColor: "EF4444",
            title: "Red = Danger",
            description: "Contains allergens or violates your dietary restrictions",
            tip: "Avoid these products"
        ),
        GuidePage(
            icon: "hand.tap.fill",
            iconColor: "3B82F6",
            title: "Tap for Details",
            description: "Tap any product overlay to see detailed analysis",
            tip: "View CO₂, water usage, allergens, and alternatives"
        ),
        GuidePage(
            icon: "arrow.triangle.swap",
            iconColor: "10B981",
            title: "Better Alternatives",
            description: "See ghost images of better product options floating nearby",
            tip: "Follow arrows to find eco-friendly swaps"
        )
    ]
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color(hex: "F3F4F6"),
                    Color(hex: "E5E7EB")
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            VStack(spacing: 30) {
                // Close button
                HStack {
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 32, height: 32)
                            .background(Color.white)
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 50)
                
                Spacer()
                
                // Page content
                TabView(selection: $currentPage) {
                    ForEach(0..<pages.count, id: \.self) { index in
                        GuidePageView(page: pages[index])
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))
                .frame(height: 500)
                
                Spacer()
                
                // Action button
                Button(action: {
                    if currentPage < pages.count - 1 {
                        withAnimation {
                            currentPage += 1
                        }
                    } else {
                        dismiss()
                    }
                }) {
                    Text(currentPage < pages.count - 1 ? "Next" : "Start Scanning")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [
                                    Color(hex: "EC4899"),
                                    Color(hex: "DB2777")
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(14)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
    }
}

struct GuidePage {
    let icon: String
    let iconColor: String
    let title: String
    let description: String
    let tip: String
}

struct GuidePageView: View {
    let page: GuidePage
    
    var body: some View {
        VStack(spacing: 24) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color(hex: page.iconColor).opacity(0.15))
                    .frame(width: 120, height: 120)
                
                Image(systemName: page.icon)
                    .font(.system(size: 50))
                    .foregroundColor(Color(hex: page.iconColor))
            }
            
            // Title
            Text(page.title)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
            
            // Description
            Text(page.description)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            // Tip badge
            HStack(spacing: 6) {
                Image(systemName: "lightbulb.fill")
                    .font(.caption)
                    .foregroundColor(Color(hex: "F59E0B"))
                Text(page.tip)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.white)
            .cornerRadius(20)
        }
        .padding(.horizontal, 24)
    }
}

#Preview {
    ARGuideView()
}
