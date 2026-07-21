// Copyright (c) 2026 Shion Oba, Rui Yokokura. All Rights Reserved.
// Viewing and evaluation only. Unauthorized use, copying, modification, or distribution is prohibited.

import Combine
import CoreBluetooth
import Foundation

@MainActor
protocol IntercomControlling: AnyObject {
    var devicesPublisher: AnyPublisher<[BLEServoDevice], Never> { get }
    var connectionStatePublisher: AnyPublisher<BLEConnectionState, Never> { get }
    var servoStatusPublisher: AnyPublisher<String, Never> { get }
    var canPressPublisher: AnyPublisher<Bool, Never> { get }
    var canPress: Bool { get }

    func scan()
    func connect(to device: BLEServoDevice)
    func disconnect()
    func press()
}

@MainActor
final class BLEServoService: NSObject, ObservableObject {
    static let serviceUUID = CBUUID(string: "2A1F5B70-9B93-4E77-A049-9F2CC3B2A4E0")
    private static let commandUUID = CBUUID(string: "2A1F5B71-9B93-4E77-A049-9F2CC3B2A4E0")
    private static let statusUUID = CBUUID(string: "2A1F5B72-9B93-4E77-A049-9F2CC3B2A4E0")

    @Published private(set) var devices: [BLEServoDevice] = []
    @Published private(set) var connectionState: BLEConnectionState = .disconnected
    @Published private(set) var servoStatus = "未接続"
    @Published private(set) var canPress = false

    private var central: CBCentralManager!
    private var commandCharacteristic: CBCharacteristic?
    private var statusCharacteristic: CBCharacteristic?
    private var connectedPeripheral: CBPeripheral?
    private var discoveredPeripherals: [UUID: CBPeripheral] = [:]
    private var commandInFlight = false
    private var statusRecoveryTask: Task<Void, Never>?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func scan() {
        guard central.state == .poweredOn else {
            connectionState = .bluetoothUnavailable(Self.bluetoothMessage(for: central.state))
            return
        }

        discoveredPeripherals.removeAll()
        devices = []
        connectionState = .scanning
        central.scanForPeripherals(
            withServices: [Self.serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    func connect(to device: BLEServoDevice) {
        central.stopScan()
        connectionState = .connecting(device.name)
        connectedPeripheral = device.peripheral
        servoStatus = "接続しています…"
        central.connect(device.peripheral)
    }

    func disconnect() {
        guard let connectedPeripheral else { return }
        central.cancelPeripheralConnection(connectedPeripheral)
    }

    func press() {
        guard canPress, let commandCharacteristic, let connectedPeripheral else { return }

        commandInFlight = true
        canPress = false
        servoStatus = "pressing"
        connectedPeripheral.writeValue(
            Data("PRESS".utf8),
            for: commandCharacteristic,
            type: .withResponse
        )
        scheduleStatusRecovery(for: connectedPeripheral)
    }

    private func resetConnection() {
        statusRecoveryTask?.cancel()
        statusRecoveryTask = nil
        commandInFlight = false
        canPress = false
        commandCharacteristic = nil
        statusCharacteristic = nil
        connectedPeripheral = nil
        servoStatus = "未接続"
        connectionState = .disconnected
    }

    private func updatePressAvailability() {
        guard case .connected = connectionState else {
            canPress = false
            return
        }

        let isSettled = servoStatus == "ready"
            || servoStatus == "error"
            || servoStatus.contains("できません")
            || servoStatus.contains("確認できません")

        canPress = commandCharacteristic != nil
            && !commandInFlight
            && isSettled
    }

    private func scheduleStatusRecovery(for peripheral: CBPeripheral) {
        statusRecoveryTask?.cancel()
        statusRecoveryTask = Task { [weak self, weak peripheral] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled,
                  let self,
                  let peripheral,
                  let statusCharacteristic = self.statusCharacteristic else {
                return
            }

            // A read repairs the UI if the final BLE notification was dropped.
            peripheral.readValue(for: statusCharacteristic)

            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled, self.servoStatus == "pressing" else { return }

            self.commandInFlight = false
            self.servoStatus = "応答を確認できませんでした"
            self.updatePressAvailability()
        }
    }

    private static func bluetoothMessage(for state: CBManagerState) -> String {
        switch state {
        case .unauthorized: "Bluetoothの使用を許可してください"
        case .poweredOff: "Bluetoothをオンにしてください"
        case .unsupported: "このiPhoneはBluetooth LEに対応していません"
        case .resetting: "Bluetoothを準備しています…"
        case .unknown: "Bluetoothの状態を確認しています…"
        case .poweredOn: ""
        @unknown default: "Bluetoothを利用できません"
        }
    }
}

extension BLEServoService: IntercomControlling {
    var devicesPublisher: AnyPublisher<[BLEServoDevice], Never> {
        $devices.eraseToAnyPublisher()
    }

    var connectionStatePublisher: AnyPublisher<BLEConnectionState, Never> {
        $connectionState.eraseToAnyPublisher()
    }

    var servoStatusPublisher: AnyPublisher<String, Never> {
        $servoStatus.eraseToAnyPublisher()
    }

    var canPressPublisher: AnyPublisher<Bool, Never> {
        $canPress.eraseToAnyPublisher()
    }
}

extension BLEServoService: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            scan()
        } else {
            resetConnection()
            connectionState = .bluetoothUnavailable(Self.bluetoothMessage(for: central.state))
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        discoveredPeripherals[peripheral.identifier] = peripheral
        devices = discoveredPeripherals.values
            .map(BLEServoDevice.init)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        connectionState = .connected(peripheral.name ?? "GenkanAI")
        servoStatus = "準備中…"
        updatePressAvailability()
        peripheral.discoverServices([Self.serviceUUID])
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        resetConnection()
        servoStatus = "接続できませんでした"
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        resetConnection()
        scan()
    }
}

extension BLEServoService: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let services = peripheral.services else {
            servoStatus = "サービスを取得できませんでした"
            return
        }

        for service in services where service.uuid == Self.serviceUUID {
            peripheral.discoverCharacteristics(
                [Self.commandUUID, Self.statusUUID],
                for: service
            )
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard error == nil, let characteristics = service.characteristics else {
            servoStatus = "操作情報を取得できませんでした"
            return
        }

        for characteristic in characteristics {
            switch characteristic.uuid {
            case Self.commandUUID:
                commandCharacteristic = characteristic
            case Self.statusUUID:
                statusCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
                peripheral.readValue(for: characteristic)
            default:
                break
            }
        }

        updatePressAvailability()
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard characteristic.uuid == Self.commandUUID else { return }

        if error != nil {
            statusRecoveryTask?.cancel()
            commandInFlight = false
            servoStatus = "コマンドを送信できませんでした"
            updatePressAvailability()
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard error == nil,
              characteristic.uuid == Self.statusUUID,
              let value = characteristic.value,
              let status = String(data: value, encoding: .utf8) else {
            return
        }

        let normalizedStatus = status.trimmingCharacters(in: .whitespacesAndNewlines)
        servoStatus = normalizedStatus

        if normalizedStatus == "ready" {
            statusRecoveryTask?.cancel()
            statusRecoveryTask = nil
            commandInFlight = false
        }

        updatePressAvailability()
    }
}
