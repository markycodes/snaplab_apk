import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth_kiosk/device_activation.dart';

void main() {
  group('verifyDeviceActivationCode', () {
    late String publicKeyHex;
    late String code;
    late String licensedCode;
    late Map<int, String> compactCodes;
    late String trialCode;
    late DateTime trialExpiresAt;

    setUp(() async {
      final algorithm = Ed25519();
      final keyPair = await algorithm.newKeyPairFromSeed(
        List<int>.generate(32, (index) => index),
      );
      final publicKey = await keyPair.extractPublicKey();
      publicKeyHex = publicKey.bytes
          .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
          .join();
      final signature = await algorithm.sign(
        utf8.encode('photobooth-kiosk-activation-v1:device-12345678'),
        keyPair: keyPair,
      );
      code = base64Url.encode(signature.bytes);
      final payload = base64Url
          .encode(
            utf8.encode(
              jsonEncode({
                'version': 2,
                'deviceId': 'device-12345678',
                'features': ['paymongo_qrph'],
              }),
            ),
          )
          .replaceAll('=', '');
      final licensedSignature = await algorithm.sign(
        utf8.encode('photobooth-kiosk-activation-v2:$payload'),
        keyPair: keyPair,
      );
      licensedCode =
          '$payload.${base64Url.encode(licensedSignature.bytes).replaceAll('=', '')}';
      compactCodes = {};
      for (var featureMask = 0; featureMask <= 3; featureMask++) {
        final compactSignature = await algorithm.sign(
          utf8.encode(
            'photobooth-kiosk-activation-v3:device-12345678:$featureMask',
          ),
          keyPair: keyPair,
        );
        compactCodes[featureMask] =
            '3$featureMask${base64Url.encode(compactSignature.bytes).replaceAll('=', '')}';
      }
      final expirySeconds =
          DateTime.now()
              .toUtc()
              .add(const Duration(days: 14))
              .millisecondsSinceEpoch ~/
          1000;
      trialExpiresAt = DateTime.fromMillisecondsSinceEpoch(
        expirySeconds * 1000,
        isUtc: true,
      );
      final trialSignature = await algorithm.sign(
        utf8.encode(
          'photobooth-kiosk-trial-activation-v1:device-12345678:$expirySeconds',
        ),
        keyPair: keyPair,
      );
      trialCode =
          '4${expirySeconds.toRadixString(16).padLeft(8, '0')}${base64Url.encode(trialSignature.bytes).replaceAll('=', '')}';
    });

    test('accepts a valid code for its device', () async {
      expect(
        await verifyDeviceActivationCode(
          deviceId: 'device-12345678',
          code: code,
          publicKeyHex: publicKeyHex,
        ),
        isTrue,
      );
    });

    test('reads provider features from a signed activation license', () async {
      final activation = await parseDeviceActivationCode(
        deviceId: 'device-12345678',
        code: licensedCode,
        publicKeyHex: publicKeyHex,
      );

      expect(activation?.allows(ActivationFeature.payMongoQrPh), isTrue);
      expect(activation?.allows(ActivationFeature.ganapQrPh), isFalse);
    });

    test(
      'accepts compact codes with all supported feature combinations',
      () async {
        const expectedFeatures = <int, Set<ActivationFeature>>{
          0: {},
          1: {ActivationFeature.payMongoQrPh},
          2: {ActivationFeature.ganapQrPh},
          3: {ActivationFeature.payMongoQrPh, ActivationFeature.ganapQrPh},
        };
        for (final entry in expectedFeatures.entries) {
          final compactCode = compactCodes[entry.key]!;
          expect(compactCode, hasLength(88));
          final activation = await parseDeviceActivationCode(
            deviceId: 'device-12345678',
            code: compactCode,
            publicKeyHex: publicKeyHex,
          );
          expect(activation?.features, entry.value);
        }
      },
    );

    test('recognizes only supported compact activation code shapes', () {
      expect(hasSupportedDeviceActivationCodeFormat(compactCodes[3]!), isTrue);
      expect(hasSupportedDeviceActivationCodeFormat(trialCode), isTrue);
      expect(hasSupportedDeviceActivationCodeFormat('34${'A' * 86}'), isFalse);
      expect(hasSupportedDeviceActivationCodeFormat('32${'A' * 85}'), isFalse);
    });

    test(
      'trial codes are signed, device-specific, and have no QR features',
      () async {
        final activation = await parseDeviceActivationCode(
          deviceId: 'device-12345678',
          code: trialCode,
          publicKeyHex: publicKeyHex,
        );

        expect(activation?.expiresAt, trialExpiresAt);
        expect(activation?.features, isEmpty);
        expect(activation?.isExpiredAt(trialExpiresAt), isTrue);
        expect(
          await parseDeviceActivationCode(
            deviceId: 'device-87654321',
            code: trialCode,
            publicKeyHex: publicKeyHex,
          ),
          isNull,
        );
        expect(
          await parseDeviceActivationCode(
            deviceId: 'device-12345678',
            code:
                '4${trialCode.substring(1, 9)}${compactCodes[0]!.substring(2)}',
            publicKeyHex: publicKeyHex,
          ),
          isNull,
        );
      },
    );

    test('compact codes cannot change device or feature claims', () async {
      final compactCode = compactCodes[1]!;
      expect(
        await parseDeviceActivationCode(
          deviceId: 'device-87654321',
          code: compactCode,
          publicKeyHex: publicKeyHex,
        ),
        isNull,
      );
      expect(
        await parseDeviceActivationCode(
          deviceId: 'device-12345678',
          code: '32${compactCode.substring(2)}',
          publicKeyHex: publicKeyHex,
        ),
        isNull,
      );
    });

    test('accepts whitespace added when copying a compact code', () async {
      final compactCode = compactCodes[3]!;
      expect(
        await verifyDeviceActivationCode(
          deviceId: 'device-12345678',
          code: '${compactCode.substring(0, 44)}\n${compactCode.substring(44)}',
          publicKeyHex: publicKeyHex,
        ),
        isTrue,
      );
    });

    test(
      'keeps legacy activation codes valid without payment features',
      () async {
        final activation = await parseDeviceActivationCode(
          deviceId: 'device-12345678',
          code: code,
          publicKeyHex: publicKeyHex,
        );

        expect(activation, isNotNull);
        expect(activation!.features, isEmpty);
      },
    );

    test('rejects modified feature entitlements', () async {
      final parts = licensedCode.split('.');
      final alteredPayload = base64Url
          .encode(
            utf8.encode(
              jsonEncode({
                'version': 2,
                'deviceId': 'device-12345678',
                'features': ['paymongo_qrph', 'ganap_qrph'],
              }),
            ),
          )
          .replaceAll('=', '');

      expect(
        await verifyDeviceActivationCode(
          deviceId: 'device-12345678',
          code: '$alteredPayload.${parts[1]}',
          publicKeyHex: publicKeyHex,
        ),
        isFalse,
      );
    });

    test('rejects a code signed for another device', () async {
      expect(
        await verifyDeviceActivationCode(
          deviceId: 'device-87654321',
          code: code,
          publicKeyHex: publicKeyHex,
        ),
        isFalse,
      );
    });

    test('rejects malformed codes and public keys', () async {
      expect(
        await verifyDeviceActivationCode(
          deviceId: 'device-12345678',
          code: 'not an activation code',
          publicKeyHex: publicKeyHex,
        ),
        isFalse,
      );
      expect(
        await verifyDeviceActivationCode(
          deviceId: 'device-12345678',
          code: code,
          publicKeyHex: 'invalid',
        ),
        isFalse,
      );
    });

    test('accepts whitespace added when copying a code', () async {
      expect(
        await verifyDeviceActivationCode(
          deviceId: 'device-12345678',
          code: '${code.substring(0, 40)}\n${code.substring(40)}',
          publicKeyHex: publicKeyHex,
        ),
        isTrue,
      );
    });
  });
}
