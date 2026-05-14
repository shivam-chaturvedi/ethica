//
//  AlternativeProductOverlay.swift
//  Ethica
//
//  Smart alternative visualization for AR mode
//

import SwiftUI

struct AlternativeProductOverlay: View {
    let originalProduct: DetectedProduct
    let alternative: DetectedProduct
    let viewSize: CGSize
    
    @State private var showArrow = false
    @State private var pulseAnimation = false
    
    var body: some View {
        let originalFrame = convertBoundingBox(originalProduct.boundingBox, viewSize: viewSize)
        let alternativeFrame = CGRect(
            x: originalFrame.maxX + 20,
            y: originalFrame.midY - 60,
            width: 120,
            height: 120
        )
        
        ZStack {
            // Ghost image of alternative product
            VStack(spacing: 6) {
                // Product icon/placeholder
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Theme.success.opacity(0.2),
                                    Theme.success.opacity(0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 70, height: 70)
                    
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 28))
                        .foregroundColor(Theme.success)
                }
                .overlay(
                    Circle()
                        .stroke(Theme.success, lineWidth: 2)
                        .scaleEffect(pulseAnimation ? 1.2 : 1.0)
                        .opacity(pulseAnimation ? 0 : 0.6)
                )
                
                // Alternative name
                VStack(spacing: 2) {
                    if let brand = alternative.brand {
                        Text(brand)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    Text(alternative.name)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                .frame(width: 100)
                
                // Savings indicator
                if let origCO2 = originalProduct.co2, let altCO2 = alternative.co2 {
                    let savings = Int(((origCO2 - altCO2) / origCO2) * 100)
                    if savings > 0 {
                        Text("-\(savings)% CO₂")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(Theme.success)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.white)
                            .cornerRadius(8)
                    }
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black.opacity(0.7))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Theme.success,
                                        Theme.success.opacity(0.8)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2
                            )
                    )
            )
            .shadow(color: Theme.success.opacity(0.4), radius: 12)
            .position(x: alternativeFrame.midX, y: alternativeFrame.midY)
            
            // Animated arrow pointing from original to alternative
            Path { path in
                let start = CGPoint(
                    x: originalFrame.maxX,
                    y: originalFrame.midY
                )
                let end = CGPoint(
                    x: alternativeFrame.minX - 10,
                    y: alternativeFrame.midY
                )
                let control1 = CGPoint(
                    x: start.x + 20,
                    y: start.y - 20
                )
                let control2 = CGPoint(
                    x: end.x - 20,
                    y: end.y + 20
                )
                
                path.move(to: start)
                path.addCurve(to: end, control1: control1, control2: control2)
            }
            .trim(from: 0, to: showArrow ? 1 : 0)
            .stroke(
                Theme.success,
                style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [8, 4])
            )
            .shadow(color: Theme.success.opacity(0.5), radius: 4)
            
            // Arrow head
            if showArrow {
                Image(systemName: "arrowtriangle.right.fill")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.success)
                    .position(
                        x: alternativeFrame.minX - 5,
                        y: alternativeFrame.midY
                    )
                    .transition(.opacity)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                showArrow = true
            }
            withAnimation(Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: false)) {
                pulseAnimation = true
            }
        }
    }
    
    private func convertBoundingBox(_ box: CGRect, viewSize: CGSize) -> CGRect {
        let x = box.minX * viewSize.width
        let y = (1 - box.maxY) * viewSize.height
        let width = box.width * viewSize.width
        let height = box.height * viewSize.height
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

// MARK: - Alternative Product Service
extension ProductRecognitionService {
    func fetchAlternative(for product: DetectedProduct) async -> DetectedProduct? {
        // Only suggest alternatives for unsafe/caution products
        guard product.safetyStatus == .danger || product.safetyStatus == .caution else {
            return nil
        }

        // TODO: Call backend /fetch-alternatives endpoint with product info
        // For now, return nil to avoid showing fabricated mock data to users
        AppLogger.debug("AR alternative overlay: no backend integration yet for \(product.name)")
        return nil
    }
}
