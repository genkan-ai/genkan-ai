// Copyright (c) 2026 Shion Oba, Rui Yokokura. All Rights Reserved.
// Viewing and evaluation only. Unauthorized use, copying, modification, or distribution is prohibited.

import SwiftUI

struct DoorbellSessionView: View {
    @StateObject private var viewModel = DoorbellSessionViewModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var isSettingsPresented = false

    var body: some View {
        NavigationStack {
            ZStack {
                // Background ambient gradient
                GenkanTheme.backgroundGradient(for: viewModel.phase.tint)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Signage Digital Clock & Status Header
                    SignageHeaderView(
                        isSettingsPresented: $isSettingsPresented,
                        isAIActive: viewModel.isAIConfigured
                    )

                    ZStack {
                        if viewModel.phase == .conversation {
                            conversationContent
                                .transition(.opacity.combined(with: .scale(scale: 0.97)))
                        } else {
                            signageDashboardContent
                                .transition(.opacity)
                        }
                    }
                }
            }
            .navigationBarHidden(true)
            .animation(.smooth(duration: 0.35), value: viewModel.phase)
            .sensoryFeedback(.impact(weight: .medium), trigger: viewModel.feedbackToken)
            .onChange(of: scenePhase) { oldPhase, newPhase in
                if newPhase != .active {
                    viewModel.suspendForBackground()
                }
            }
            .sheet(isPresented: $isSettingsPresented) {
                AISettingsSheetView()
            }
        }
    }

    // MARK: - Signage Dashboard Content
    private var signageDashboardContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                // Main Ambient Hero Card
                DoorbellHeroCard(
                    phase: viewModel.phase,
                    detectionConfidence: viewModel.detectionConfidence
                )

                // Device & Mic Status Indicators
                statusRow

                // Device Scanner (When Disconnected)
                if !viewModel.isConnected {
                    DeviceConnectionCard(
                        devices: viewModel.devices,
                        onScan: { viewModel.scan() },
                        onConnect: { device in viewModel.connect(to: device) }
                    )
                }

                // Primary Prominent Actions
                controlsCard

                // Recent Activity Summary
                activityCard
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Status Indicators Row
    private var statusRow: some View {
        HStack(spacing: 12) {
            StatusChip(
                title: "ESP32",
                value: viewModel.connectionLabel,
                symbol: "dot.radiowaves.left.and.right",
                isActive: viewModel.isConnected
            )
            
            Spacer()
            
            StatusChip(
                title: "マイク",
                value: viewModel.microphoneLabel,
                symbol: "mic.fill",
                isActive: viewModel.detectionState == .monitoring
            )
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Controls Card (Large Signage Buttons)
    private var controlsCard: some View {
        VStack(spacing: 14) {
            Button {
                viewModel.toggleMonitoring()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: viewModel.phase == .monitoring ? "stop.fill" : "ear.badge.waveform")
                        .font(.title3.weight(.bold))
                    Text(viewModel.primaryActionTitle)
                        .font(.title3.weight(.bold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .tint(viewModel.phase == .monitoring ? GenkanTheme.errorRed : GenkanTheme.liveBlue)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .disabled(viewModel.phase != .monitoring && !viewModel.canStartMonitoring)
            .shadow(color: (viewModel.phase == .monitoring ? GenkanTheme.errorRed : GenkanTheme.liveBlue).opacity(0.4), radius: 10, x: 0, y: 4)

            Button {
                viewModel.pressManually()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "hand.tap.fill")
                        .font(.headline)
                    Text("手動で応答ボタンを押す")
                        .font(.headline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.bordered)
            .tint(.primary)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .disabled(!viewModel.canManuallyPress)

            if viewModel.isConnected {
                Button("ESP32との接続を解除", role: .destructive) {
                    viewModel.disconnect()
                }
                .font(.footnote.weight(.medium))
                .padding(.top, 4)
            }
        }
        .padding(20)
        .signageGlassCard(cornerRadius: 24)
    }

    // MARK: - Activity Summary Card
    private var activityCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("動作状況")
                .font(.headline.weight(.bold))
                .foregroundStyle(.primary)

            HStack {
                Text("サーボモータ")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(servoStatusLabel)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
            }

            Divider()
                .overlay(GenkanTheme.cardBorder)

            HStack {
                Text("最終ピンポン検知")
                    .foregroundStyle(.secondary)
                Spacer()
                if let event = viewModel.lastDetection {
                    Text(event.date, style: .time)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(GenkanTheme.activeGreen)
                } else {
                    Text("記録なし")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .font(.subheadline)
        .padding(20)
        .signageGlassCard(cornerRadius: 24)
    }

    // MARK: - Active Conversation Screen
    private var conversationContent: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(GenkanTheme.aiIndigo.opacity(0.25))
                    .frame(width: 130, height: 130)
                    .blur(radius: 12)

                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 84, weight: .bold))
                    .foregroundStyle(GenkanTheme.aiIndigo)
                    .symbolEffect(.variableColor.iterative, isActive: true)
            }

            VStack(spacing: 8) {
                Text("Apple Intelligence受付中")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                
                Text(viewModel.conversationState.label)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(GenkanTheme.aiIndigo)
                    .multilineTextAlignment(.center)
            }

            // Live Audio Waveform
            MicrophoneLevelView(level: viewModel.microphoneLevel)
                .signageGlassCard(cornerRadius: 22)
                .padding(.horizontal, 20)

            // Transcripts Bubble Stream
            if !viewModel.transcripts.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(viewModel.transcripts) { item in
                                TranscriptBubbleView(transcript: item)
                                    .id(item.id)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .frame(maxHeight: 220)
                    .padding(.horizontal, 20)
                    .onChange(of: viewModel.transcripts.count) { _, _ in
                        if let last = viewModel.transcripts.last {
                            withAnimation {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }

            Spacer()

            VStack(spacing: 10) {
                Button {
                    viewModel.testSpeaker()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "speaker.wave.3.fill")
                        Text("スピーカーをテスト")
                    }
                    .font(.headline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.bordered)

                Button(role: .destructive) {
                    viewModel.endConversation()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "phone.down.fill")
                        Text("対話を終了")
                    }
                    .font(.headline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
                .tint(GenkanTheme.errorRed)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }

    private var servoStatusLabel: String {
        switch viewModel.servoStatus {
        case "ready": "準備完了"
        case "pressing": "押しています"
        default: viewModel.servoStatus
        }
    }
}

#Preview {
    DoorbellSessionView()
}
