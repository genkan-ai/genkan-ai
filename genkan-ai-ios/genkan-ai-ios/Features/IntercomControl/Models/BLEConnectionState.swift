// Copyright (c) 2026 Shion Oba, Rui Yokokura. All Rights Reserved.
// Viewing and evaluation only. Unauthorized use, copying, modification, or distribution is prohibited.

import Foundation

enum BLEConnectionState: Equatable {
    case bluetoothUnavailable(String)
    case scanning
    case connecting(String)
    case connected(String)
    case disconnected
}
