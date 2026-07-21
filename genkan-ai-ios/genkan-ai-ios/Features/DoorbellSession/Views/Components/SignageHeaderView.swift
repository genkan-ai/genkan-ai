// Copyright (c) 2026 Shion Oba, Rui Yokokura. All Rights Reserved.
// Viewing and evaluation only. Unauthorized use, copying, modification, or distribution is prohibited.

import Combine
import SwiftUI

struct SignageHeaderView: View {
    @Binding var isSettingsPresented: Bool
    let isAIActive: Bool
    
    @State private var currentTime = Date()
    private let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(currentTime, style: .time)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                
                Text(currentTime.formatted(date: .complete, time: .omitted))
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // AI Status Badge
            HStack(spacing: 6) {
                Circle()
                    .fill(isAIActive ? GenkanTheme.activeGreen : GenkanTheme.alertAmber)
                    .frame(width: 8, height: 8)
                
                Text(isAIActive ? "AI受付中" : "AI準備中")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(isAIActive ? GenkanTheme.activeGreen : GenkanTheme.alertAmber)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill((isAIActive ? GenkanTheme.activeGreen : GenkanTheme.alertAmber).opacity(0.12))
                    .overlay(
                        Capsule()
                            .stroke((isAIActive ? GenkanTheme.activeGreen : GenkanTheme.alertAmber).opacity(0.3), lineWidth: 1)
                    )
            )

            Button {
                isSettingsPresented = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .background(Circle().fill(GenkanTheme.cardBackground))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .onReceive(timer) { input in
            currentTime = input
        }
    }
}

#Preview {
    ZStack {
        GenkanTheme.oledBackground.ignoresSafeArea()
        SignageHeaderView(isSettingsPresented: .constant(false), isAIActive: true)
    }
}
