// Copyright (c) 2026 Shion Oba, Rui Yokokura. All Rights Reserved.
// Viewing and evaluation only. Unauthorized use, copying, modification, or distribution is prohibited.

import Foundation
import Security

enum KeychainStore {
    private static let service = "com.genkanai.openrouter"
    private static let account = "api-key"

    static func readOpenRouterAPIKey() -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8) else { return "" }
        return key
    }

    static func saveOpenRouterAPIKey(_ key: String) throws {
        let value = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return }

        var item = query
        item[kSecValueData as String] = Data(value.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(
                domain: NSOSStatusErrorDomain,
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "APIキーをKeychainへ保存できませんでした"]
            )
        }
    }
}
