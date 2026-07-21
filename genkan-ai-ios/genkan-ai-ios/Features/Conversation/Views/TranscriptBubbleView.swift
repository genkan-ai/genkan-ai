// Copyright (c) 2026 Shion Oba, Rui Yokokura. All Rights Reserved.
// Viewing and evaluation only. Unauthorized use, copying, modification, or distribution is prohibited.

import SwiftUI

struct TranscriptBubbleView: View {
    let transcript: ConversationTranscript

    var isAssistant: Bool {
        transcript.speaker == .assistant
    }

    var body: some View {
        HStack {
            if isAssistant { Spacer(minLength: 40) }

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isAssistant ? "sparkles" : "person.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(isAssistant ? Color.white : GenkanTheme.liveBlue)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle().fill(isAssistant ? GenkanTheme.aiIndigo : GenkanTheme.cardBackground)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(isAssistant ? "Genkan AI" : "訪問者")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(isAssistant ? GenkanTheme.aiIndigo : .secondary)

                    Text(transcript.text)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isAssistant ? GenkanTheme.aiIndigo.opacity(0.25) : GenkanTheme.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(isAssistant ? GenkanTheme.aiIndigo.opacity(0.4) : GenkanTheme.cardBorder, lineWidth: 1)
                    )
            )

            if !isAssistant { Spacer(minLength: 40) }
        }
    }
}

#Preview {
    ZStack {
        GenkanTheme.oledBackground.ignoresSafeArea()
        VStack(spacing: 12) {
            TranscriptBubbleView(transcript: ConversationTranscript(speaker: .visitor, text: "こんにちは、宅配便です。"))
            TranscriptBubbleView(transcript: ConversationTranscript(speaker: .assistant, text: "いつもありがとうございます。ドアの前に置いてください。"))
        }
        .padding()
    }
}
