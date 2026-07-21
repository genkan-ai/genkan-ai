// Copyright (c) 2026 Shion Oba, Rui Yokokura. All Rights Reserved.
// Viewing and evaluation only. Unauthorized use, copying, modification, or distribution is prohibited.

import SwiftUI

struct StatusChip: View {
    let title: String
    let value: String
    let symbol: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(isActive ? GenkanTheme.activeGreen : Color.secondary.opacity(0.4))
                    .frame(width: 8, height: 8)
                
                if isActive {
                    Circle()
                        .stroke(GenkanTheme.activeGreen.opacity(0.6), lineWidth: 2)
                        .frame(width: 14, height: 14)
                }
            }

            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(isActive ? GenkanTheme.activeGreen : .secondary)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(isActive ? .primary : .secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Capsule(style: .continuous)
                .fill(GenkanTheme.cardBackground.opacity(0.9))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(isActive ? GenkanTheme.activeGreen.opacity(0.3) : GenkanTheme.cardBorder, lineWidth: 1)
                )
        )
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    ZStack {
        GenkanTheme.oledBackground.ignoresSafeArea()
        HStack {
            StatusChip(title: "ESP32", value: "接続済み", symbol: "dot.radiowaves.left.and.right", isActive: true)
            StatusChip(title: "マイク", value: "待機中", symbol: "mic.fill", isActive: false)
        }
    }
}
