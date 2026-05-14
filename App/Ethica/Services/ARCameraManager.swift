//
//  ARCameraManager.swift
//  Ethica
//
//  Camera session manager for AR product scanning
//

import Foundation
import AVFoundation
import UIKit
import Combine

class ARCameraManager: NSObject, ObservableObject {
    let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "com.ethica.camera")
    
    @Published var isAuthorized = false
    @Published var isSessionRunning = false
    
    private let recognitionService = ProductRecognitionService.shared
    
    override init() {
        super.init()
        checkAuthorization()
    }
    
    func checkAuthorization() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isAuthorized = true
            setupCaptureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.isAuthorized = granted
                    if granted {
                        self?.setupCaptureSession()
                    }
                }
            }
        case .denied, .restricted:
            isAuthorized = false
        @unknown default:
            isAuthorized = false
        }
    }
    
    private func setupCaptureSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.captureSession.beginConfiguration()
            self.captureSession.sessionPreset = .high
            
            // Add video input
            guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let videoInput = try? AVCaptureDeviceInput(device: videoDevice),
                  self.captureSession.canAddInput(videoInput) else {
                AppLogger.error("❌ Failed to add video input")
                self.captureSession.commitConfiguration()
                return
            }
            
            self.captureSession.addInput(videoInput)
            
            // Configure video output
            self.videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            self.videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "com.ethica.videoOutput"))
            
            guard self.captureSession.canAddOutput(self.videoOutput) else {
                AppLogger.error("❌ Failed to add video output")
                self.captureSession.commitConfiguration()
                return
            }
            
            self.captureSession.addOutput(self.videoOutput)
            
            // Optimize connection
            if let connection = self.videoOutput.connection(with: .video) {
                connection.videoOrientation = .portrait
                if connection.isVideoStabilizationSupported {
                    connection.preferredVideoStabilizationMode = .auto
                }
            }
            
            self.captureSession.commitConfiguration()
            
            AppLogger.debug("✅ Camera session configured successfully")
        }
    }
    
    func startSession() {
        sessionQueue.async { [weak self] in
            guard let self = self, !self.isSessionRunning else { return }
            self.captureSession.startRunning()
            DispatchQueue.main.async {
                self.isSessionRunning = true
                AppLogger.debug("✅ Camera session started")
            }
        }
    }
    
    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self = self, self.isSessionRunning else { return }
            self.captureSession.stopRunning()
            DispatchQueue.main.async {
                self.isSessionRunning = false
                AppLogger.debug("⏸️ Camera session stopped")
            }
        }
    }
}

// MARK: - Video Output Delegate
extension ARCameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        // Determine orientation
        let orientation: CGImagePropertyOrientation
        switch UIDevice.current.orientation {
        case .portrait:
            orientation = .right
        case .portraitUpsideDown:
            orientation = .left
        case .landscapeLeft:
            orientation = .up
        case .landscapeRight:
            orientation = .down
        default:
            orientation = .right
        }
        
        // Send frame to recognition service
        recognitionService.processFrame(pixelBuffer, orientation: orientation)
    }
}
