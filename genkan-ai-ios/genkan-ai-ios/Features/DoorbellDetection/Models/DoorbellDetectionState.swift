// Copyright (c) 2026 Shion Oba, Rui Yokokura. All Rights Reserved.
// Viewing and evaluation only. Unauthorized use, copying, modification, or distribution is prohibited.

import Foundation

enum DoorbellDetectionState: Equatable {
    case idle
    case requestingPermission
    case monitoring
    case permissionDenied
    case unsupported
    case failed(String)
}

struct DoorbellDetectionEvent: Equatable {
    let date: Date
    let confidence: Double
}

enum DoorbellDetectionError: LocalizedError {
    case microphonePermissionDenied
    case classifierUnavailable
    case doorbellClassificationUnavailable
    case audioInputUnavailable

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            "マイクの使用が許可されていません"
        case .classifierUnavailable:
            "音響分類器を開始できませんでした"
        case .doorbellClassificationUnavailable:
            "この端末の音響分類器はドアベル音に対応していません"
        case .audioInputUnavailable:
            "iPhoneのマイク入力を開始できませんでした"
        }
    }
}
