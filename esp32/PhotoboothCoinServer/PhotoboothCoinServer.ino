#include <Arduino.h>
#include <ArduinoJson.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <cstring>

constexpr uint8_t COIN_PIN = 15;
// On this board, touching the D32 header pin coincided with charging starting;
// use GPIO 32 as the observed smart-charging control, active-high.
constexpr uint8_t CHARGER_PIN = 32;
constexpr bool CHARGER_ACTIVE_HIGH = true;
constexpr uint32_t DEBOUNCE_MS = 150;
constexpr uint32_t BATTERY_REPORT_TIMEOUT_MS = 90000;
constexpr uint8_t DEFAULT_CHARGE_START_PERCENT = 20;
constexpr uint8_t DEFAULT_CHARGE_STOP_PERCENT = 90;

constexpr char SERVICE_UUID[] = "6f3a1000-9d7b-4c2a-8e51-13b7c0a10000";
constexpr char CHARACTERISTIC_UUID[] = "6f3a1001-9d7b-4c2a-8e51-13b7c0a10000";

volatile uint32_t pendingPulses = 0;
volatile uint32_t lastPulseAt = 0;
uint32_t availableCredits = 0;
uint8_t batteryPercent = 0;
uint8_t chargeStartPercent = DEFAULT_CHARGE_START_PERCENT;
uint8_t chargeStopPercent = DEFAULT_CHARGE_STOP_PERCENT;
uint32_t lastBatteryReportAt = 0;
bool hasBatteryReport = false;
bool chargerOn = false;
portMUX_TYPE stateMux = portMUX_INITIALIZER_UNLOCKED;
BLECharacteristic *creditCharacteristic = nullptr;

void writeChargerState(bool enabled) {
  const bool activeHigh = CHARGER_ACTIVE_HIGH;
  digitalWrite(CHARGER_PIN, enabled == activeHigh ? HIGH : LOW);
}

void updateCharger();

void IRAM_ATTR onCoinPulse() {
  const uint32_t now = millis();
  portENTER_CRITICAL_ISR(&stateMux);
  if (now - lastPulseAt >= DEBOUNCE_MS) {
    ++pendingPulses;
    lastPulseAt = now;
  }
  portEXIT_CRITICAL_ISR(&stateMux);
}

uint32_t currentCredits() {
  portENTER_CRITICAL(&stateMux);
  const uint32_t credits = availableCredits;
  portEXIT_CRITICAL(&stateMux);
  return credits;
}

void reply(bool consumed, const char *error = nullptr) {
  StaticJsonDocument<192> response;
  uint32_t credits = 0;
  uint8_t reportedPercent = 0;
  bool receivedReport = false;
  bool relayOn = false;
  portENTER_CRITICAL(&stateMux);
  credits = availableCredits;
  reportedPercent = batteryPercent;
  receivedReport = hasBatteryReport;
  relayOn = chargerOn;
  portEXIT_CRITICAL(&stateMux);

  response["credits"] = credits;
  response["consumed"] = consumed;
  response["batteryPercent"] = receivedReport ? reportedPercent : -1;
  response["chargerOn"] = relayOn;
  response["chargerPin"] = CHARGER_PIN;
  response["activeHigh"] = CHARGER_ACTIVE_HIGH;
  if (error != nullptr) response["error"] = error;
  String body;
  serializeJson(response, body);
  creditCharacteristic->setValue(body.c_str());
}

class CreditCharacteristicCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *characteristic) override {
    const auto requestText = characteristic->getValue();
    StaticJsonDocument<128> request;
    if (deserializeJson(request, requestText) ||
        !request["op"].is<const char *>()) {
      reply(false, "invalid_request");
      return;
    }

    const char *operation = request["op"];
    if (strcmp(operation, "credits") == 0) {
      reply(false);
      return;
    }

    if (strcmp(operation, "battery") == 0) {
      if (!request["percent"].is<int>() ||
          !request["startPercent"].is<int>() ||
          !request["stopPercent"].is<int>()) {
        reply(false, "invalid_battery_or_threshold");
        return;
      }
      const int percent = request["percent"].as<int>();
      const int startPercent = request["startPercent"].as<int>();
      const int stopPercent = request["stopPercent"].as<int>();
      if (percent < 0 || percent > 100 ||
          startPercent < 0 || startPercent > 99 ||
          stopPercent < 1 || stopPercent > 100 ||
          startPercent >= stopPercent) {
        reply(false, "invalid_battery_or_threshold");
        return;
      }

      portENTER_CRITICAL(&stateMux);
      batteryPercent = static_cast<uint8_t>(percent);
      chargeStartPercent = static_cast<uint8_t>(startPercent);
      chargeStopPercent = static_cast<uint8_t>(stopPercent);
      lastBatteryReportAt = millis();
      hasBatteryReport = true;
      portEXIT_CRITICAL(&stateMux);
      updateCharger();
      reply(false);
      return;
    }

    if (strcmp(operation, "consume") != 0 ||
        !request["amount"].is<uint32_t>() ||
        request["amount"].as<uint32_t>() == 0) {
      reply(false, "invalid_request");
      return;
    }

    const uint32_t amount = request["amount"].as<uint32_t>();
    bool consumed = false;
    portENTER_CRITICAL(&stateMux);
    if (availableCredits >= amount) {
      availableCredits -= amount;
      consumed = true;
    }
    portEXIT_CRITICAL(&stateMux);

    reply(consumed, consumed ? nullptr : "insufficient_credits");
  }
};

void updateCharger() {
  const uint32_t now = millis();
  portENTER_CRITICAL(&stateMux);
  if (hasBatteryReport &&
      now - lastBatteryReportAt > BATTERY_REPORT_TIMEOUT_MS) {
    hasBatteryReport = false;
  }

  if (!hasBatteryReport) {
    chargerOn = false;
  } else if (chargerOn && batteryPercent >= chargeStopPercent) {
    chargerOn = false;
  } else if (!chargerOn && batteryPercent <= chargeStartPercent) {
    chargerOn = true;
  }

  writeChargerState(chargerOn);
  portEXIT_CRITICAL(&stateMux);
}

void setup() {
  Serial.begin(115200);
  pinMode(COIN_PIN, INPUT_PULLDOWN);
  attachInterrupt(digitalPinToInterrupt(COIN_PIN), onCoinPulse, RISING);

  pinMode(CHARGER_PIN, OUTPUT);
  writeChargerState(false);
  Serial.printf("Smart charger ready: pin=%d activeHigh=%d start=%d%% stop=%d%%\n",
                CHARGER_PIN,
                CHARGER_ACTIVE_HIGH ? 1 : 0,
                DEFAULT_CHARGE_START_PERCENT,
                DEFAULT_CHARGE_STOP_PERCENT);

  BLEDevice::init("Photobooth ESP32");
  BLEDevice::setMTU(128);
  BLEServer *server = BLEDevice::createServer();
  BLEService *service = server->createService(SERVICE_UUID);
  creditCharacteristic = service->createCharacteristic(
      CHARACTERISTIC_UUID,
      BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_WRITE);
  creditCharacteristic->setCallbacks(new CreditCharacteristicCallbacks());
  reply(false);
  service->start();

  BLEAdvertising *advertising = BLEDevice::getAdvertising();
  advertising->addServiceUUID(SERVICE_UUID);
  advertising->setScanResponse(true);
  advertising->start();
}

void loop() {
  portENTER_CRITICAL(&stateMux);
  availableCredits += pendingPulses;
  pendingPulses = 0;
  portEXIT_CRITICAL(&stateMux);

  updateCharger();
  delay(10);
}
