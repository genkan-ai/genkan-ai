import CoreBluetooth
// Copyright (c) 2026 Shion Oba, Rui Yokokura. All Rights Reserved.
// Viewing and evaluation only. Unauthorized use, copying, modification, or distribution is prohibited.

import Foundation

struct BLEServoDevice: Identifiable {
    let peripheral: CBPeripheral

    var id: UUID { peripheral.identifier }
    var name: String { peripheral.name ?? "GenkanAI" }
}
