// Copyright (c) 2026 Shion Oba, Rui Yokokura. All Rights Reserved.
// Viewing and evaluation only. Unauthorized use, copying, modification, or distribution is prohibited.

import Combine
import Foundation

@MainActor
final class DoorbellSessionViewModel: ObservableObject {
    @Published private(set) var phase: DoorbellSessionPhase = .preparing
    @Published private(set) var devices: [BLEServoDevice] = []
    @Published private(set) var connectionState: BLEConnectionState = .disconnected
    @Published private(set) var servoStatus = "未接続"
    @Published private(set) var detectionState: DoorbellDetectionState = .idle
    @Published private(set) var detectionConfidence: Double = 0
    @Published private(set) var microphoneLevel: Double = 0
    @Published private(set) var conversationState: AIConversationState = .idle
    @Published private(set) var transcripts: [ConversationTranscript] = []
    @Published private(set) var lastDetection: DoorbellDetectionEvent?
    @Published private(set) var feedbackToken = 0

    var isAIConfigured: Bool { true }
    var connectionLabel: String {
        switch connectionState {
        case .bluetoothUnavailable(let reason): reason
        case .scanning: "検索中"
        case .connecting: "接続中"
        case .connected: "接続済み"
        case .disconnected: "未接続"
        }
    }

    var microphoneLabel: String {
        switch detectionState {
        case .requestingPermission: "許可を確認中"
        case .monitoring: "監視中"
        case .permissionDenied: "許可が必要"
        case .unsupported: "非対応"
        case .failed: "エラー"
        default: phase == .conversation ? "使用中" : "待機中"
        }
    }

    var primaryActionTitle: String {
        switch phase {
        case .monitoring: "監視を停止"
        case .preparing: "ESP32を接続してください"
        default: "ピンポン監視を開始"
        }
    }

    var canStartMonitoring: Bool {
        canPress && phase != .answering && phase != .conversation && phase != .cooldown
    }

    var canManuallyPress: Bool {
        canPress && phase != .answering && phase != .conversation
    }

    var isConnected: Bool {
        if case .connected = connectionState { return true }
        return false
    }

    private let detector: DoorbellDetecting
    private let intercom: IntercomControlling
    private let conversation: ConversationAudioControlling
    private var cancellables = Set<AnyCancellable>()
    private var cooldownTask: Task<Void, Never>?
    private var canPress = false
    private var observedPressStart = false

    init() {
        detector = DoorbellDetectionService()
        intercom = BLEServoService()
        conversation = FoundationConversationService()
        bindServices()
    }

    init(
        detector: DoorbellDetecting,
        intercom: IntercomControlling,
        conversation: ConversationAudioControlling
    ) {
        self.detector = detector
        self.intercom = intercom
        self.conversation = conversation
        bindServices()
    }

    func toggleMonitoring() {
        if phase == .monitoring {
            detector.stopMonitoring()
            phase = canPress ? .ready : .preparing
        } else {
            startMonitoring()
        }
    }

    func startMonitoring() {
        guard canStartMonitoring else { return }

        Task {
            do {
                try await detector.startMonitoring()
                phase = .monitoring
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    func scan() {
        intercom.scan()
    }

    func connect(to device: BLEServoDevice) {
        intercom.connect(to: device)
    }

    func disconnect() {
        detector.stopMonitoring()
        conversation.stopSession()
        intercom.disconnect()
        phase = .preparing
    }

    func suspendForBackground() {
        cooldownTask?.cancel()
        detector.stopMonitoring()
        conversation.stopSession()

        if phase != .preparing {
            phase = canPress ? .ready : .preparing
        }
    }

    func pressManually() {
        guard canManuallyPress else { return }
        detector.stopMonitoring()
        beginAnswering()
    }

    func endConversation() {
        conversation.stopSession()
        phase = .cooldown
        cooldownTask?.cancel()
        cooldownTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled, let self else { return }
            self.phase = self.canPress ? .ready : .preparing
            if self.canPress {
                self.startMonitoring()
            }
        }
    }

    func testSpeaker() {
        conversation.speakSpeakerTest()
    }

    private func bindServices() {
        intercom.devicesPublisher
            .sink { [weak self] in self?.devices = $0 }
            .store(in: &cancellables)

        intercom.connectionStatePublisher
            .sink { [weak self] state in
                guard let self else { return }
                self.connectionState = state
                if !self.isConnected && self.phase != .conversation {
                    self.phase = .preparing
                }
            }
            .store(in: &cancellables)

        intercom.canPressPublisher
            .sink { [weak self] available in
                guard let self else { return }
                self.canPress = available
                if available && self.phase == .preparing {
                    self.phase = .ready
                }
            }
            .store(in: &cancellables)

        intercom.servoStatusPublisher
            .sink { [weak self] status in
                guard let self else { return }
                self.servoStatus = status
                self.handleServoStatus(status)
            }
            .store(in: &cancellables)

        detector.statePublisher
            .sink { [weak self] in self?.detectionState = $0 }
            .store(in: &cancellables)

        detector.confidencePublisher
            .sink { [weak self] in self?.detectionConfidence = $0 }
            .store(in: &cancellables)

        detector.detectionPublisher
            .sink { [weak self] in self?.handleDetection($0) }
            .store(in: &cancellables)

        conversation.microphoneLevelPublisher
            .sink { [weak self] in self?.microphoneLevel = $0 }
            .store(in: &cancellables)

        conversation.statePublisher
            .sink { [weak self] state in
                self?.conversationState = state
            }
            .store(in: &cancellables)

        conversation.transcriptsPublisher
            .sink { [weak self] in self?.transcripts = $0 }
            .store(in: &cancellables)
    }

    private func handleDetection(_ event: DoorbellDetectionEvent) {
        guard phase == .monitoring else { return }
        lastDetection = event
        feedbackToken += 1
        phase = .detected
        detector.stopMonitoring()
        beginAnswering()
    }

    private func beginAnswering() {
        guard canPress else {
            phase = .failed("ESP32へ押下指示を送れません")
            return
        }

        observedPressStart = false
        phase = .answering
        feedbackToken += 1
        intercom.press()
    }

    private func handleServoStatus(_ status: String) {
        guard phase == .answering else { return }

        if status == "pressing" {
            observedPressStart = true
            return
        }

        if status == "ready", observedPressStart {
            startConversation()
        } else if status.contains("できません") || status.contains("確認できません") {
            phase = .failed(status)
        }
    }

    private func startConversation() {
        phase = .conversation
        feedbackToken += 1
        Task {
            do {
                try await conversation.startSession()
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }
}
