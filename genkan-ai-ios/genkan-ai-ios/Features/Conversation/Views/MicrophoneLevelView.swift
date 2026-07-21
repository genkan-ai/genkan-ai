// Copyright (c) 2026 Shion Oba, Rui Yokokura. All Rights Reserved.
// Viewing and evaluation only. Unauthorized use, copying, modification, or distribution is prohibited.

import SwiftUI

struct MicrophoneLevelView: View {
    let level: Double
    
    private let barCount = 16

    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .center, spacing: 6) {
                ForEach(0..<barCount, id: \.self) { index in
                    let barHeight = computeBarHeight(for: index)
                    let isActive = index < activeBarCount
                    
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: isActive
                                    ? [GenkanTheme.aiIndigo, GenkanTheme.liveBlue]
                                    : [Color.secondary.opacity(0.2), Color.secondary.opacity(0.1)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 6, height: barHeight)
                        .shadow(
                            color: isActive ? GenkanTheme.liveBlue.opacity(0.5) : Color.clear,
                            radius: 4, x: 0, y: 0
                        )
                }
            }
            .frame(height: 64, alignment: .center)
            .animation(.smooth(duration: 0.15), value: level)

            Text("来客音声を聞き取り中")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 20)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("マイク入力レベル")
        .accessibilityValue("\(Int(level * 100))パーセント")
    }

    private var activeBarCount: Int {
        min(max(Int((level * Double(barCount)).rounded()), 1), barCount)
    }
    
    private func computeBarHeight(for index: Int) -> CGFloat {
        let normalizedIndex = Double(index) / Double(barCount - 1)
        let sineFactor = sin(normalizedIndex * .pi)
        let baseHeight: CGFloat = 12
        let maxHeight: CGFloat = 56
        
        let calculated = baseHeight + CGFloat(level * sineFactor) * (maxHeight - baseHeight)
        return max(baseHeight, min(calculated, maxHeight))
    }
}

#Preview {
    ZStack {
        GenkanTheme.oledBackground.ignoresSafeArea()
        MicrophoneLevelView(level: 0.65)
            .signageGlassCard()
            .padding()
    }
}
