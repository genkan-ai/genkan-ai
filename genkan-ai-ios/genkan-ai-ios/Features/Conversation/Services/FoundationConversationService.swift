// Copyright (c) 2026 Shion Oba, Rui Yokokura. All Rights Reserved.
// Viewing and evaluation only. Unauthorized use, copying, modification, or distribution is prohibited.

import AVFAudio
import Combine
import Foundation
import FoundationModels
import Speech

enum ConversationAudioError: LocalizedError {
    case appleIntelligenceUnavailable
    case speechRecognitionUnavailable
    case speechPermissionDenied
    case audioInputUnavailable

    var errorDescription: String? {
        switch self {
        case .appleIntelligenceUnavailable:
            "Apple Intelligenceを有効にした対応iPhoneで実行してください"
        case .speechRecognitionUnavailable:
            "日本語の音声認識を開始できませんでした"
        case .speechPermissionDenied:
            "音声認識の使用を許可してください"
        case .audioInputUnavailable:
            "iPhoneの対話用マイクを開始できませんでした"
        }
    }
}

@MainActor
protocol ConversationAudioControlling: AnyObject {
    var microphoneLevelPublisher: AnyPublisher<Double, Never> { get }
    var statePublisher: AnyPublisher<AIConversationState, Never> { get }
    var transcriptsPublisher: AnyPublisher<[ConversationTranscript], Never> { get }

    func startSession() async throws
    func speakSpeakerTest()
    func stopSession()
}

@MainActor
final class FoundationConversationService: NSObject, ObservableObject, ConversationAudioControlling {
    @Published private(set) var microphoneLevel: Double = 0
    @Published private(set) var state: AIConversationState = .idle
    @Published private(set) var transcripts: [ConversationTranscript] = []

    var microphoneLevelPublisher: AnyPublisher<Double, Never> { $microphoneLevel.eraseToAnyPublisher() }
    var statePublisher: AnyPublisher<AIConversationState, Never> { $state.eraseToAnyPublisher() }
    var transcriptsPublisher: AnyPublisher<[ConversationTranscript], Never> { $transcripts.eraseToAnyPublisher() }

    private let audioEngine = AVAudioEngine()
    private let synthesizer = AVSpeechSynthesizer()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP"))
    private let model = SystemLanguageModel.default
    private var languageSession: LanguageModelSession?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var isRunning = false
    private var isTapInstalled = false
    private var shouldListenAfterSpeech = false
    private var isProcessingVisitorTurn = false

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func startSession() async throws {
        guard !isRunning else { return }
        state = .connecting
        transcripts = []

        do {
            try startAudioEngine()
            isRunning = true
            shouldListenAfterSpeech = false
            speak("こんにちは。ご用件をお話しください。")
            Task { [weak self] in
                await self?.prepareLocalAI()
            }
        } catch {
            stopSession()
            state = .failed(error.localizedDescription)
            throw error
        }
    }

    private func prepareLocalAI() async {
        guard isRunning else { return }
        guard model.isAvailable else {
            state = .failed(ConversationAudioError.appleIntelligenceUnavailable.localizedDescription)
            return
        }
        guard recognizer?.isAvailable == true else {
            state = .failed(ConversationAudioError.speechRecognitionUnavailable.localizedDescription)
            return
        }
        guard await requestSpeechPermission() else {
            state = .failed(ConversationAudioError.speechPermissionDenied.localizedDescription)
            return
        }

        languageSession = LanguageModelSession(model: model, instructions: """
        あなたは玄関インターホンの受付AIです。必ず日本語で、明るく簡潔に応答してください。
        訪問者の名前と用件を確認し、必要なら住人に伝えると答えてください。
        住所、家族構成、在宅状況などの個人情報は伝えず、解錠や契約の約束もしないでください。
        """)
        shouldListenAfterSpeech = true
        if !synthesizer.isSpeaking {
            startListening()
        }
    }

    func stopSession() {
        isRunning = false
        shouldListenAfterSpeech = false
        stopRecognition()
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        if isTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            isTapInstalled = false
        }
        audioEngine.stop()
        languageSession = nil
        microphoneLevel = 0
        isProcessingVisitorTurn = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if case .failed = state { return }
        state = .idle
    }

    func speakSpeakerTest() {
        guard isRunning else { return }
        stopRecognition()
        isProcessingVisitorTurn = false
        shouldListenAfterSpeech = true
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        speak("こんにちは。ご用件をお話しください。")
    }

    private func requestSpeechPermission() async -> Bool {
        if SFSpeechRecognizer.authorizationStatus() == .authorized { return true }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    private func startAudioEngine() throws {
        try forceSpeakerOutput()

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw ConversationAudioError.audioInputUnavailable }
        inputNode.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak self] buffer, _ in
            let level = AudioLevelMeter.normalizedLevel(from: buffer)
            Task { @MainActor [weak self] in
                guard let self, self.isRunning else { return }
                self.microphoneLevel = level
                self.recognitionRequest?.append(buffer)
            }
        }
        isTapInstalled = true
        audioEngine.prepare()
        try audioEngine.start()
    }

    private func startListening() {
        guard isRunning, !synthesizer.isSpeaking, recognitionTask == nil, !isProcessingVisitorTurn else { return }
        guard let recognizer, recognizer.isAvailable else {
            state = .failed(ConversationAudioError.speechRecognitionUnavailable.localizedDescription)
            return
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = false
        recognitionRequest = request
        state = .listening
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self, self.isRunning else { return }
                if let result, result.isFinal {
                    let text = result.bestTranscription.formattedString
                    self.isProcessingVisitorTurn = true
                    self.stopRecognition()
                    self.handleVisitorUtterance(text)
                } else if let error, (error as NSError).code != 216 {
                    self.recognitionRequest = nil
                    self.recognitionTask = nil
                    self.retryListening(after: 0.5)
                }
            }
        }
    }

    private func stopRecognition() {
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
    }

    private func handleVisitorUtterance(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let languageSession, !languageSession.isResponding else {
            isProcessingVisitorTurn = false
            if isRunning { startListening() }
            return
        }
        transcripts.append(.init(speaker: .visitor, text: trimmed))
        state = .thinking
        Task { [weak self] in
            do {
                let response = try await languageSession.respond(to: trimmed)
                guard let self, self.isRunning else { return }
                let reply = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                self.transcripts.append(.init(speaker: .assistant, text: reply))
                self.shouldListenAfterSpeech = true
                self.speak(reply)
            } catch {
                self?.state = .failed(error.localizedDescription)
                self?.isProcessingVisitorTurn = false
            }
        }
    }

    private func speak(_ text: String) {
        try? forceSpeakerOutput()
        state = .speaking
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "ja-JP")
        utterance.rate = 0.48
        synthesizer.speak(utterance)
    }

    private func forceSpeakerOutput() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true)
        try session.overrideOutputAudioPort(.speaker)
    }

    private func retryListening(after delay: TimeInterval) {
        guard isRunning else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, self.isRunning else { return }
            self.startListening()
        }
    }
}

extension FoundationConversationService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self, self.shouldListenAfterSpeech else { return }
            self.isProcessingVisitorTurn = false
            self.startListening()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self, self.shouldListenAfterSpeech else { return }
            self.isProcessingVisitorTurn = false
            self.startListening()
        }
    }
}
