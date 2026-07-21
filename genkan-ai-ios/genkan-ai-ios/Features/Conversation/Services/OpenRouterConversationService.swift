// Copyright (c) 2026 Shion Oba, Rui Yokokura. All Rights Reserved.
// Viewing and evaluation only. Unauthorized use, copying, modification, or distribution is prohibited.

import AVFAudio
import Combine
import Foundation
import Speech

enum ConversationAudioError: LocalizedError {
    case openRouterAPIKeyMissing
    case speechRecognitionUnavailable
    case speechPermissionDenied
    case audioInputUnavailable

    var errorDescription: String? {
        switch self {
        case .openRouterAPIKeyMissing: "設定からOpenRouter APIキーを登録してください"
        case .speechRecognitionUnavailable: "日本語のローカル音声認識を開始できませんでした"
        case .speechPermissionDenied: "音声認識の使用を許可してください"
        case .audioInputUnavailable: "iPhoneの対話用マイクを開始できませんでした"
        }
    }
}

@MainActor
protocol ConversationAudioControlling: AnyObject {
    var microphoneLevelPublisher: AnyPublisher<Double, Never> { get }
    var statePublisher: AnyPublisher<AIConversationState, Never> { get }
    var transcriptsPublisher: AnyPublisher<[ConversationTranscript], Never> { get }
    var liveTranscriptPublisher: AnyPublisher<String, Never> { get }

    func startSession() async throws
    func speakSpeakerTest()
    func submitCurrentUtterance()
    func stopSession()
}

private struct OpenRouterMessage: Codable {
    let role: String
    let content: String
}

private struct OpenRouterRequest: Encodable {
    let model: String
    let messages: [OpenRouterMessage]
    let temperature: Double
    let maxTokens: Int

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature
        case maxTokens = "max_tokens"
    }
}

private struct OpenRouterResponse: Decodable {
    struct Choice: Decodable {
        let message: OpenRouterMessage
    }
    let choices: [Choice]
}

private struct OpenRouterErrorResponse: Decodable {
    struct APIError: Decodable { let message: String }
    let error: APIError
}

@MainActor
final class OpenRouterConversationService: NSObject, ObservableObject, ConversationAudioControlling {
    @Published private(set) var microphoneLevel: Double = 0
    @Published private(set) var state: AIConversationState = .idle
    @Published private(set) var transcripts: [ConversationTranscript] = []
    @Published private(set) var liveTranscript = ""

    var microphoneLevelPublisher: AnyPublisher<Double, Never> { $microphoneLevel.eraseToAnyPublisher() }
    var statePublisher: AnyPublisher<AIConversationState, Never> { $state.eraseToAnyPublisher() }
    var transcriptsPublisher: AnyPublisher<[ConversationTranscript], Never> { $transcripts.eraseToAnyPublisher() }
    var liveTranscriptPublisher: AnyPublisher<String, Never> { $liveTranscript.eraseToAnyPublisher() }

    private let audioEngine = AVAudioEngine()
    private let synthesizer = AVSpeechSynthesizer()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP"))
    private let urlSession: URLSession
    private var messages: [OpenRouterMessage] = []
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var responseTask: Task<Void, Never>?
    private var speechDebounceTask: Task<Void, Never>?
    private var isRunning = false
    private var isTapInstalled = false
    private var shouldListenAfterSpeech = false
    private var isProcessingVisitorTurn = false

    override init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 45
        urlSession = URLSession(configuration: configuration)
        super.init()
        synthesizer.delegate = self
    }

    func startSession() async throws {
        guard !isRunning else { return }
        guard !KeychainStore.readOpenRouterAPIKey().isEmpty else {
            throw ConversationAudioError.openRouterAPIKeyMissing
        }
        state = .connecting
        transcripts = []
        liveTranscript = ""
        messages = [.init(role: "system", content: ReceptionistAgentDefinition.instructions)]

        do {
            guard recognizer?.isAvailable == true,
                  recognizer?.supportsOnDeviceRecognition == true else {
                throw ConversationAudioError.speechRecognitionUnavailable
            }
            guard await requestSpeechPermission() else {
                throw ConversationAudioError.speechPermissionDenied
            }
            try startAudioEngine()
            isRunning = true
            shouldListenAfterSpeech = true
            speak(ReceptionistAgentDefinition.openingMessage)
        } catch {
            stopSession()
            state = .failed(error.localizedDescription)
            throw error
        }
    }

    func stopSession() {
        isRunning = false
        shouldListenAfterSpeech = false
        stopRecognition()
        responseTask?.cancel()
        responseTask = nil
        speechDebounceTask?.cancel()
        speechDebounceTask = nil
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        if isTapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            isTapInstalled = false
        }
        audioEngine.stop()
        microphoneLevel = 0
        isProcessingVisitorTurn = false
        messages = []
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if case .failed = state { return }
        state = .idle
    }

    func speakSpeakerTest() {
        guard isRunning else { return }
        stopRecognition()
        isProcessingVisitorTurn = false
        shouldListenAfterSpeech = true
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        speak(ReceptionistAgentDefinition.openingMessage)
    }

    func submitCurrentUtterance() {
        let text = liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isProcessingVisitorTurn else { return }
        speechDebounceTask?.cancel()
        isProcessingVisitorTurn = true
        stopRecognition()
        handleVisitorUtterance(text)
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
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw ConversationAudioError.audioInputUnavailable
        }
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
        guard let recognizer, recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            state = .failed(ConversationAudioError.speechRecognitionUnavailable.localizedDescription)
            return
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        recognitionRequest = request
        state = .listening
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self, self.isRunning else { return }
                if let result {
                    let text = result.bestTranscription.formattedString
                    self.liveTranscript = text
                    if result.isFinal {
                        self.speechDebounceTask?.cancel()
                        self.isProcessingVisitorTurn = true
                        self.stopRecognition()
                        self.handleVisitorUtterance(text)
                    } else {
                        self.scheduleResponseAfterPause(for: text)
                    }
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
        liveTranscript = ""
        guard !trimmed.isEmpty else {
            isProcessingVisitorTurn = false
            if isRunning { startListening() }
            return
        }

        transcripts.append(.init(speaker: .visitor, text: trimmed))
        messages.append(.init(role: "user", content: ReceptionistAgentDefinition.prompt(for: trimmed)))
        state = .thinking
        responseTask?.cancel()
        responseTask = Task { [weak self] in
            guard let self else { return }
            do {
                let reply = try await self.requestReply()
                guard self.isRunning, !Task.isCancelled else { return }
                self.finishResponse(reply)
            } catch {
                guard self.isRunning, !Task.isCancelled else { return }
                #if DEBUG
                print("OpenRouter response failed: \(error)")
                #endif
                self.finishResponse(ReceptionistAgentDefinition.fallbackReply(for: trimmed))
            }
        }
    }

    private func requestReply() async throws -> String {
        let apiKey = KeychainStore.readOpenRouterAPIKey()
        guard !apiKey.isEmpty else { throw ConversationAudioError.openRouterAPIKeyMissing }
        guard let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("GenkanAI", forHTTPHeaderField: "X-Title")
        request.httpBody = try JSONEncoder().encode(
            OpenRouterRequest(
                model: "openrouter/free",
                messages: messages,
                temperature: 0.3,
                maxTokens: 160
            )
        )

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200...299).contains(httpResponse.statusCode) else {
            let apiMessage = try? JSONDecoder().decode(OpenRouterErrorResponse.self, from: data).error.message
            throw NSError(
                domain: "OpenRouter",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: apiMessage ?? "OpenRouterとの通信に失敗しました"]
            )
        }

        let responseBody = try JSONDecoder().decode(OpenRouterResponse.self, from: data)
        guard let content = responseBody.choices.first?.message.content else {
            throw URLError(.cannotParseResponse)
        }
        return ReceptionistAgentDefinition.validatedReply(content)
    }

    private func finishResponse(_ reply: String) {
        let validated = ReceptionistAgentDefinition.validatedReply(reply)
        messages.append(.init(role: "assistant", content: validated))
        transcripts.append(.init(speaker: .assistant, text: validated))
        shouldListenAfterSpeech = true
        speak(validated)
    }

    private func speak(_ text: String) {
        try? forceSpeakerOutput()
        state = .speaking
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "ja-JP")
        utterance.rate = 0.48
        utterance.volume = 1
        synthesizer.speak(utterance)
    }

    private func forceSpeakerOutput() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
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

    private func scheduleResponseAfterPause(for text: String) {
        let candidate = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return }
        speechDebounceTask?.cancel()
        speechDebounceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard let self,
                  !Task.isCancelled,
                  self.isRunning,
                  !self.isProcessingVisitorTurn,
                  self.liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines) == candidate else { return }
            self.isProcessingVisitorTurn = true
            self.stopRecognition()
            self.handleVisitorUtterance(candidate)
        }
    }
}

extension OpenRouterConversationService: AVSpeechSynthesizerDelegate {
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
