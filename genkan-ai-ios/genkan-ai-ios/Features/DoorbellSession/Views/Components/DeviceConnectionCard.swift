// Copyright (c) 2026 Shion Oba, Rui Yokokura. All Rights Reserved.
// Viewing and evaluation only. Unauthorized use, copying, modification, or distribution is prohibited.

import SwiftUI

struct DeviceConnectionCard: View {
    let devices: [BLEServoDevice]
    let onScan: () -> Void
    let onConnect: (BLEServoDevice) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("ESP32を接続", systemImage: "cpu")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.primary)
                Spacer()
                Button("再検索") { onScan() }
                    .font(.subheadline.weight(.medium))
                    .buttonStyle(.bordered)
                    .tint(GenkanTheme.liveBlue)
            }

            if devices.isEmpty {
                HStack(spacing: 12) {
                    ProgressView()
                        .tint(GenkanTheme.liveBlue)
                    Text("GenkanAIデバイスを探しています…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 8) {
                    ForEach(devices) { device in
                        Button {
                            onConnect(device)
                        } label: {
                            HStack {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                    .foregroundStyle(GenkanTheme.liveBlue)
                                Text(device.name)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(GenkanTheme.cardBackground)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .stroke(GenkanTheme.cardBorder, lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(18)
        .signageGlassCard(cornerRadius: 22)
    }
}
