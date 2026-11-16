import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth_kiosk/ble_protocol.dart';

void main() {
  group('BleCreditRequest', () {
    test('uses the shared ESP32 credit request', () {
      expect(utf8.decode(BleCreditRequest.readCredits()), '{"op":"credits"}');
    });

    test('requests a positive configured credit amount', () {
      expect(
        utf8.decode(BleCreditRequest.consumeCredits(4)),
        '{"op":"consume","amount":4}',
      );
    });

    test('reports a valid tablet battery percentage', () {
      expect(
        utf8.decode(
          BleCreditRequest.reportBattery(
            percent: 20,
            startPercent: 20,
            stopPercent: 90,
          ),
        ),
        '{"op":"battery","percent":20,"startPercent":20,"stopPercent":90}',
      );
      expect(
        utf8.decode(
          BleCreditRequest.reportBattery(
            percent: 90,
            startPercent: 15,
            stopPercent: 85,
          ),
        ),
        '{"op":"battery","percent":90,"startPercent":15,"stopPercent":85}',
      );
    });

    test('rejects battery percentages outside 0 to 100', () {
      expect(
        () => BleCreditRequest.reportBattery(
          percent: -1,
          startPercent: 20,
          stopPercent: 90,
        ),
        throwsArgumentError,
      );
      expect(
        () => BleCreditRequest.reportBattery(
          percent: 101,
          startPercent: 20,
          stopPercent: 90,
        ),
        throwsArgumentError,
      );
    });

    test('requires start charging threshold below stop threshold', () {
      expect(
        () => BleCreditRequest.reportBattery(
          percent: 50,
          startPercent: 90,
          stopPercent: 90,
        ),
        throwsArgumentError,
      );
    });

    test('rejects nonpositive payment amounts', () {
      expect(() => BleCreditRequest.consumeCredits(0), throwsArgumentError);
    });
  });

  group('BleCreditResponse', () {
    test('parses the shared ESP32 credit response', () {
      final response = BleCreditResponse.fromBytes(
        utf8.encode('{"credits":3,"consumed":false}'),
      );

      expect(response.credits, 3);
      expect(response.consumed, isFalse);
    });

    test('parses a successful credit deduction', () {
      final response = BleCreditResponse.fromBytes(
        utf8.encode('{"credits":1,"consumed":true}'),
      );

      expect(response.credits, 1);
      expect(response.consumed, isTrue);
    });

    test('parses an ESP32 request error', () {
      final response = BleCreditResponse.fromBytes(
        utf8.encode('{"credits":0,"consumed":false,"error":"invalid_request"}'),
      );

      expect(response.error, 'invalid_request');
    });

    test('rejects invalid or negative balances', () {
      expect(
        () => BleCreditResponse.fromBytes(
          utf8.encode('{"credits":-1,"consumed":false}'),
        ),
        throwsFormatException,
      );
      expect(
        () => BleCreditResponse.fromBytes(utf8.encode('not json')),
        throwsFormatException,
      );
    });
  });
}
