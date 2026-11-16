#include <Arduino.h>
#include <ArduinoJson.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <cstring>

// JUANKIOSK labels its coin input P15 and configures the trigger as active-high.
constexpr uint8_t COIN_PIN = 15;
constexpr uint32_t DEBOUNCE_MS = 150;

constexpr char SERVICE_UUID[] = "6f3a1000-9d7b-4c2a-8e51-13b7c0a10000";
constexpr char CHARACTERISTIC_UUID[] = "6f3a1001-9d7b-4c2a-8e51-13b7c0a10000";

volatile uint32_t pendingPulses = 0;
volatile uint32_t lastPulseAt = 0;
uint32_t availableCredits = 0;
portMUX_TYPE coinMux = portMUX_INITIALIZER_UNLOCKED;
BLECharacteristic *creditCharacteristic = nullptr;

void IRAM_ATTR onCoinPulse() {
  const uint32_t now = millis();
  portENTER_CRITICAL_ISR(&coinMux);
  if (now - lastPulseAt >= DEBOUNCE_MS) {
    ++pendingPulses;
    lastPulseAt = now;
  }
  portEXIT_CRITICAL_ISR(&coinMux);
}

uint32_t currentCredits() {
  portENTER_CRITICAL(&coinMux);
  const uint32_t credits = availableCredits;
  portEXIT_CRITICAL(&coinMux);
  return credits;
}

void reply(bool consumed, const char *error = nullptr) {
  StaticJsonDocument<96> response;
  response["credits"] = currentCredits();
  response["consumed"] = consumed;
  if (error != nullptr) response["error"] = error;
  String body;
  serializeJson(response, body);
  creditCharacteristic->setValue(body.c_str());
}

class CreditCharacteristicCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *characteristic) override {
    const auto requestText = characteristic->getValue();
    StaticJsonDocument<96> request;
    if (deserializeJson(request, requestText) || !request["op"].is<const char *>()) {
      reply(false, "invalid_request");
      return;
    }

    const char *operation = request["op"];
    if (strcmp(operation, "credits") == 0) {
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
    portENTER_CRITICAL(&coinMux);
    if (availableCredits >= amount) {
      availableCredits -= amount;
      consumed = true;
    }
    portEXIT_CRITICAL(&coinMux);

    reply(consumed, consumed ? nullptr : "insufficient_credits");
  }
};

void setup() {
  Serial.begin(115200);
  pinMode(COIN_PIN, INPUT_PULLDOWN);
  attachInterrupt(digitalPinToInterrupt(COIN_PIN), onCoinPulse, RISING);

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
  portENTER_CRITICAL(&coinMux);
  availableCredits += pendingPulses;
  pendingPulses = 0;
  portEXIT_CRITICAL(&coinMux);
  delay(10);
}
