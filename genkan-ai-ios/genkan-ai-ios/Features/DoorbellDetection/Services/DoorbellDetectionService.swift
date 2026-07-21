// Copyright (c) 2026 Shion Oba, Rui Yokokura. All Rights Reserved.
// Viewing and evaluation only. Unauthorized use, copying, modification, or distribution is prohibited.

import AVFAudio
import Combine
import CoreMedia
import Foundation
import SoundAnalysis

@MainActor
protocol DoorbellDetecting: AnyObject {
    var statePublisher: AnyPublisher<DoorbellDetectionState, Never> { get }
    var confidencePublisher: AnyPublisher<Double, Never> { get }
    var detectionPublisher: AnyPublisher<DoorbellDetectionEvent, Never> { get }

    func startMonitoring() async throws
    func stopMonitoring()
}

@MainActor
final class DoorbellDetectionService: NSObject, ObservableObject {
    @Published private(set) var state: DoorbellDetectionState = .idle
    @Published private(set) var confidence: Double = 0

    private let detectionSubject = PassthroughSubject<DoorbellDetectionEvent, Never>()
    private let audioEngine = AVAudioEngine()
    private var analyzer: SNAudioStreamAnalyzer?
    private var classificationRequest: SNClassifySoundRequest?
    private var isTapInstalled = false
    private var consecutiveMatches = 0
    private var lastDetectionDate: Date?

    private let confidenceThreshold = 0.65
    private let requiredConsecutiveMatches = 2
    private let cooldown: TimeInterval = 10

    func startMonitoring() async throws {
        guard state != .monitoring else { return }

        state = .requestingPermission
        guard await requestMicrophonePermission() else {
            state = .permissionDenied
            throw DoorbellDetectionError.microphonePermissionDenied
        }

        do {
            try configureAndStartAudioAnalysis()
            state = .monitoring
        } catch {
            stopMonitoring()
            if let detectionError = error as? DoorbellDetectionError,
               detectionError == .doorbellClassificationUnavailable {
                state = .unsupported
            } else {
                state = .failed(error.localizedDescription)
            }
            throw error
        }
    }

    func stopMonitoring() {
        if isTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            isTapInstalled = false
        }
        audioEngine.stop()
        analyzer?.removeAllRequests()
        analyzer = nil
        classificationRequest = nil
        consecutiveMatches = 0
        confidence = 0

        if state == .monitoring || state == .requestingPermission {
            state = .idle
        }

        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }

    private func requestMicrophonePermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }

    private func configureAndStartAudioAnalysis() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement)
        try session.setActive(true)

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw DoorbellDetectionError.audioInputUnavailable
        }

        let request: SNClassifySoundRequest
        do {
            request = try SNClassifySoundRequest(classifierIdentifier: .version1)
        } catch {
            throw DoorbellDetectionError.classifierUnavailable
        }

        let supportsDoorbell = request.knownClassifications.contains {
            Self.normalizedIdentifier($0).contains("doorbell")
        }
        guard supportsDoorbell else {
            throw DoorbellDetectionError.doorbellClassificationUnavailable
        }

        request.windowDuration = CMTime(seconds: 1.5, preferredTimescale: 48_000)
        request.overlapFactor = 0.75

        let streamAnalyzer = SNAudioStreamAnalyzer(format: format)
        try streamAnalyzer.add(request, withObserver: self)

        inputNode.installTap(
            onBus: 0,
            bufferSize: 8_192,
            format: format
        ) { buffer, time in
            streamAnalyzer.analyze(buffer, atAudioFramePosition: time.sampleTime)
        }
        isTapInstalled = true

        audioEngine.prepare()
        try audioEngine.start()
        analyzer = streamAnalyzer
        classificationRequest = request
    }

    private func handle(result: SNClassificationResult) {
        let match = result.classifications
            .filter { Self.normalizedIdentifier($0.identifier).contains("doorbell") }
            .max { $0.confidence < $1.confidence }

        let currentConfidence = match?.confidence ?? 0
        confidence = currentConfidence

        guard currentConfidence >= confidenceThreshold else {
            consecutiveMatches = 0
            return
        }

        if let lastDetectionDate,
           Date().timeIntervalSince(lastDetectionDate) < cooldown {
            return
        }

        consecutiveMatches += 1
        guard consecutiveMatches >= requiredConsecutiveMatches else { return }

        consecutiveMatches = 0
        let event = DoorbellDetectionEvent(date: Date(), confidence: currentConfidence)
        lastDetectionDate = event.date
        detectionSubject.send(event)
    }

    private static func normalizedIdentifier(_ identifier: String) -> String {
        identifier
            .lowercased()
            .filter(\.isLetter)
    }
}

extension DoorbellDetectionService: DoorbellDetecting {
    var statePublisher: AnyPublisher<DoorbellDetectionState, Never> {
        $state.eraseToAnyPublisher()
    }

    var confidencePublisher: AnyPublisher<Double, Never> {
        $confidence.eraseToAnyPublisher()
    }

    var detectionPublisher: AnyPublisher<DoorbellDetectionEvent, Never> {
        detectionSubject.eraseToAnyPublisher()
    }
}

extension DoorbellDetectionService: SNResultsObserving {
    nonisolated func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let classificationResult = result as? SNClassificationResult else { return }
        Task { @MainActor [weak self] in
            self?.handle(result: classificationResult)
        }
    }

    nonisolated func request(_ request: SNRequest, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            self?.state = .failed(error.localizedDescription)
        }
    }
}
