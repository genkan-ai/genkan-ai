// Copyright (c) 2026 Shion Oba, Rui Yokokura. All Rights Reserved.
// Viewing and evaluation only. Unauthorized use, copying, modification, or distribution is prohibited.

import Foundation

enum AIConversationState: Equatable {
    case idle
    case connecting
    case listening
    case thinking
    case speaking
    case failed(String)

    var label: String {
        switch self {
        case .idle: "待機中"
        case .connecting: "OpenRouterを準備中"
        case .listening: "お話しください"
        case .thinking: "考えています…"
        case .speaking: "AIが応答中"
        case .failed(let message): message
        }
    }
}

struct ConversationTranscript: Identifiable, Equatable {
    enum Speaker {
        case visitor
        case assistant
    }

    let id = UUID()
    let speaker: Speaker
    let text: String
}
