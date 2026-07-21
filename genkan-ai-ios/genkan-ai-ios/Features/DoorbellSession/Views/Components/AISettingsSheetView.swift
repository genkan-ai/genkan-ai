// Copyright (c) 2026 Shion Oba, Rui Yokokura. All Rights Reserved.
// Viewing and evaluation only. Unauthorized use, copying, modification, or distribution is prohibited.

import SwiftUI

struct AISettingsSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var apiKey: String
    let message: String?
    let onSave: () -> Void
    let onDelete: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                GenkanTheme.oledBackground.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("OpenRouter設定", systemImage: "sparkles")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(GenkanTheme.aiIndigo)
                            Text("受付の返答生成にOpenRouterの無料モデルルーターを使用します。")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("APIキー")
                                .font(.headline)
                            SecureField("sk-or-v1-...", text: $apiKey)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .textContentType(.password)
                                .padding(14)
                                .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                            Text("キーはこのiPhoneのKeychainに保存され、ソースコードには書き込みません。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Label("音声認識はiPhone内で処理します", systemImage: "iphone.gen3")
                            Label("認識された文章だけをOpenRouterへ送信します", systemImage: "network")
                            Label("無料モデルは混雑や提供状況で応答が不安定な場合があります", systemImage: "exclamationmark.triangle")
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                        if let message {
                            Text(message)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(GenkanTheme.activeGreen)
                        }

                        Button {
                            onSave()
                        } label: {
                            Text("APIキーを保存")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(GenkanTheme.aiIndigo)
                        .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        if !apiKey.isEmpty {
                            Button("保存したAPIキーを削除", role: .destructive) {
                                onDelete()
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(24)
                }
            }
            .navigationTitle("AI設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    AISettingsSheetView(apiKey: .constant(""), message: nil, onSave: {}, onDelete: {})
}
