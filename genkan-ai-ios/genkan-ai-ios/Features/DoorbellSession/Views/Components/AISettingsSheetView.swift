// Copyright (c) 2026 Shion Oba, Rui Yokokura. All Rights Reserved.
// Viewing and evaluation only. Unauthorized use, copying, modification, or distribution is prohibited.

import SwiftUI

struct AISettingsSheetView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                GenkanTheme.oledBackground.ignoresSafeArea()
                
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("音声AI設定", systemImage: "sparkles")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(GenkanTheme.aiIndigo)

                        Text("この試作版は、iPhone上のApple Intelligenceを使って応答を生成します。APIキーやトークンの設定は不要です。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Label("Apple Intelligence対応・有効化済みのiPhoneが必要です", systemImage: "iphone.gen3")
                        Label("初回はマイク・音声認識の許可が必要です", systemImage: "mic.badge.plus")
                        Label("会話は端末内モデルで処理します", systemImage: "lock.shield")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        dismiss()
                    } label: {
                        Text("閉じる")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(GenkanTheme.aiIndigo)
                }
                .padding(24)
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    AISettingsSheetView()
}
