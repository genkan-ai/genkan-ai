// Copyright (c) 2026 Shion Oba, Rui Yokokura. All Rights Reserved.
// Viewing and evaluation only. Unauthorized use, copying, modification, or distribution is prohibited.

import SwiftUI

struct DoorbellHeroCard: View {
    let phase: DoorbellSessionPhase
    let detectionConfidence: Double

    var body: some View {
        VStack(spacing: 22) {
            ZStack {
                // Ambient Glow Rings
                Circle()
                    .fill(phase.tint.opacity(0.15))
                    .frame(width: 140, height: 140)
                    .blur(radius: 10)
                
                if phase == .monitoring {
                    Circle()
                        .stroke(phase.tint.opacity(0.3), lineWidth: 2)
                        .frame(width: 120, height: 120)
                        .scaleEffect(1.05)
                        .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: phase)
                }

                Image(systemName: phase.symbolName)
                    .font(.system(size: 46, weight: .bold))
                    .foregroundStyle(phase.tint)
                    .symbolEffect(.pulse, options: .repeating, isActive: phase == .monitoring)
                    .frame(width: 96, height: 96)
                    .background(
                        Circle()
                            .fill(phase.tint.opacity(0.16))
                            .overlay(Circle().stroke(phase.tint.opacity(0.4), lineWidth: 1.5))
                    )
            }
            .padding(.top, 8)

            VStack(spacing: 8) {
                Text(phase.title)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                
                Text(phase.detail)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }

            if phase == .monitoring {
                VStack(spacing: 6) {
                    HStack {
                        Text("チャイムAI検知感度")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(detectionConfidence * 100))%")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(GenkanTheme.activeGreen)
                    }
                    
                    ProgressView(value: detectionConfidence)
                        .tint(GenkanTheme.activeGreen)
                }
                .padding(.horizontal, 24)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 20)
        .signageGlassCard(cornerRadius: 28)
    }
}

#Preview {
    ZStack {
        GenkanTheme.oledBackground.ignoresSafeArea()
        DoorbellHeroCard(phase: .monitoring, detectionConfidence: 0.75)
            .padding()
    }
}
