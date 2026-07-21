// Copyright (c) 2026 Shion Oba, Rui Yokokura. All Rights Reserved.
// Viewing and evaluation only. Unauthorized use, copying, modification, or distribution is prohibited.

import SwiftUI

enum DoorbellSessionPhase: Equatable {
    case preparing
    case ready
    case monitoring
    case detected
    case answering
    case conversation
    case cooldown
    case failed(String)

    var title: String {
        switch self {
        case .preparing: "準備しています"
        case .ready: "監視を開始できます"
        case .monitoring: "ピンポンを待っています"
        case .detected: "ピンポンを検出しました"
        case .answering: "インターホンに応答中"
        case .conversation: "対話中"
        case .cooldown: "監視を再開します"
        case .failed: "確認が必要です"
        }
    }

    var detail: String {
        switch self {
        case .preparing: "ESP32へ接続してください"
        case .ready: "iPhoneのマイクでチャイム音を監視します"
        case .monitoring: "アプリを開いたままにしてください"
        case .detected: "ESP32へ押下指示を送ります"
        case .answering: "サーボの完了を待っています"
        case .conversation: "iPhoneをインターホンの近くに置いてください"
        case .cooldown: "重複検出を防止しています"
        case .failed(let message): message
        }
    }

    var symbolName: String {
        switch self {
        case .preparing: "antenna.radiowaves.left.and.right"
        case .ready: "doorbell"
        case .monitoring: "waveform.badge.mic"
        case .detected: "bell.badge.fill"
        case .answering: "hand.tap.fill"
        case .conversation: "waveform.circle.fill"
        case .cooldown: "clock.arrow.circlepath"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .ready: .blue
        case .monitoring: .green
        case .detected, .answering: .orange
        case .conversation: .indigo
        case .failed: .red
        default: .secondary
        }
    }
}
