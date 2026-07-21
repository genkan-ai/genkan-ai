// Copyright (c) 2026 Shion Oba, Rui Yokokura. All Rights Reserved.
// Viewing and evaluation only. Unauthorized use, copying, modification, or distribution is prohibited.

#include <BLE2902.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <ESP32Servo.h>

namespace {
constexpr char DEVICE_NAME[] = "GenkanAI";

// Keep these UUIDs in sync with BLEServoService.swift.
// Version 2 UUIDs avoid stale GATT metadata cached by iOS.
constexpr char SERVICE_UUID[] = "2A1F5B70-9B93-4E77-A049-9F2CC3B2A4E0";
constexpr char COMMAND_UUID[] = "2A1F5B71-9B93-4E77-A049-9F2CC3B2A4E0";
constexpr char STATUS_UUID[] = "2A1F5B72-9B93-4E77-A049-9F2CC3B2A4E0";

constexpr int SERVO_PIN = 18;
constexpr int RELEASE_ANGLE = 0;
constexpr int PRESS_ANGLE = 65;
constexpr unsigned long HOLD_TIME_MS = 500;

Servo buttonServo;
BLECharacteristic* statusCharacteristic = nullptr;
volatile bool deviceConnected = false;
volatile bool pressRequested = false;
volatile bool pressInProgress = false;
unsigned long pressStartedAt = 0;

void publishStatus(const char* status) {
  statusCharacteristic->setValue(status);

  if (deviceConnected) {
    statusCharacteristic->notify();
  }
}

class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer*) override {
    deviceConnected = true;
    publishStatus(pressInProgress ? "pressing" : "ready");
  }

  void onDisconnect(BLEServer* server) override {
    deviceConnected = false;
    server->startAdvertising();
  }
};

class CommandCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* characteristic) override {
    const String command = characteristic->getValue();

    if (command == "PRESS") {
      // The BLE callback only queues a request. Servo movement is kept on loop().
      if (!pressInProgress && !pressRequested) {
        pressRequested = true;
      }
    } else {
      publishStatus("error");
    }
  }
};
}  // namespace

void setup() {
  buttonServo.setPeriodHertz(50);
  buttonServo.attach(SERVO_PIN, 500, 2400);
  buttonServo.write(RELEASE_ANGLE);

  BLEDevice::init(DEVICE_NAME);

  BLEServer* server = BLEDevice::createServer();
  server->setCallbacks(new ServerCallbacks());

  BLEService* service = server->createService(SERVICE_UUID);

  BLECharacteristic* commandCharacteristic = service->createCharacteristic(
      COMMAND_UUID,
      BLECharacteristic::PROPERTY_WRITE |
          BLECharacteristic::PROPERTY_WRITE_NR);
  commandCharacteristic->setCallbacks(new CommandCallbacks());

  statusCharacteristic = service->createCharacteristic(
      STATUS_UUID,
      BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
  statusCharacteristic->addDescriptor(new BLE2902());
  statusCharacteristic->setValue("ready");

  service->start();

  BLEAdvertising* advertising = BLEDevice::getAdvertising();
  advertising->addServiceUUID(SERVICE_UUID);
  advertising->setScanResponse(true);
  advertising->start();
}

void loop() {
  if (pressRequested && !pressInProgress) {
    pressRequested = false;
    pressInProgress = true;
    pressStartedAt = millis();
    buttonServo.write(PRESS_ANGLE);
    publishStatus("pressing");
  }

  // Subtraction remains correct even when millis() wraps around.
  if (pressInProgress && millis() - pressStartedAt >= HOLD_TIME_MS) {
    buttonServo.write(RELEASE_ANGLE);
    pressInProgress = false;
    publishStatus("ready");
  }

  delay(1);
}
