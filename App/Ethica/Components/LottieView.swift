//
//  LottieView.swift
//  Ethica
//
//  SwiftUI wrapper for Lottie animations
//

import Lottie
import SwiftUI

struct LottieView: UIViewRepresentable {
    let animationName: String
    var speed: CGFloat = 1.0
    var loopMode: LottieLoopMode = .loop

    func makeUIView(context: Context) -> LottieAnimationView {
        let view = LottieAnimationView(name: animationName)
        view.loopMode = loopMode
        view.animationSpeed = speed
        view.contentMode = .scaleAspectFit
        view.backgroundBehavior = .pauseAndRestore
        view.play()
        return view
    }

    func updateUIView(_ uiView: LottieAnimationView, context: Context) {}
}
