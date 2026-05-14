//
//  VoiceGuidanceService.swift
//  Ethica
//
//  Text-to-speech voice guidance for AR mode
//

import Foundation
import AVFAudio
import AVFoundation
import Combine

class VoiceGuidanceService: ObservableObject {
    private let synthesizer = AVSpeechSynthesizer()
    private var lastSpeakTime: Date?
    private let speakThrottle: TimeInterval = 3.0  // Minimum 3 seconds between announcements
    
    @Published var isSpeaking = false
    
    init() {
        setupAudioSession()
    }
    
    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: .duckOthers)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            AppLogger.error("❌ Failed to setup audio session: \(error)")
        }
    }
    
    func speak(_ text: String, priority: Priority = .normal) {
        // Throttle announcements
        if let lastTime = lastSpeakTime, Date().timeIntervalSince(lastTime) < speakThrottle {
            if priority != .high {
                return
            }
        }
        
        // Stop current speech if new high priority message
        if priority == .high && synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        
        DispatchQueue.main.async {
            self.isSpeaking = true
        }
        
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.5  // Normal speed
        utterance.pitchMultiplier = 1.0
        utterance.volume = 0.8
        
        synthesizer.speak(utterance)
        lastSpeakTime = Date()
        
        AppLogger.debug("🔊 Voice: \(text)")
        
        // Update speaking state when done
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(text.count) * 0.05) {
            self.isSpeaking = false
        }
    }
    
    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }
    
    enum Priority {
        case normal
        case high
    }
}
