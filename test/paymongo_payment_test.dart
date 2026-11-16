import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:photobooth_kiosk/paymongo_payment.dart';

void main() {
  group('PayMongoPaymentClient', () {
    final qrPng = base64Encode([
      0x89,
      0x50,
      0x4e,
      0x47,
      0x0d,
      0x0a,
      0x1a,
      0x0a,
    ]);

    test(
      'creates a QR Ph checkout using the signed-in booth details',
      () async {
        final client = _FakeClient(
          (_, _) => http.Response(
            jsonEncode({
              'referenceNumber': 'pi_12345',
              'qrImageBase64': qrPng,
              'testUrl': 'https://dashboard.paymongo.com/test/123',
              'amountPesos': 20,
            }),
            200,
          ),
        );
        final payments = PayMongoPaymentClient(
          client: client,
          backend: Uri.parse('https://booth.example.test'),
        );

        final checkout = await payments.createCheckout(
          deviceId: 'device-12345678',
          activationCode: '${'a' * 86}==\n',
          idempotencyKey: 'b' * 32,
          amountPesos: 20,
        );

        expect(checkout.referenceNumber, 'pi_12345');
        expect(checkout.amountPesos, 20);
        expect(checkout.testUrl, 'https://dashboard.paymongo.com/test/123');
        expect(checkout.imageBytes, [
          0x89,
          0x50,
          0x4e,
          0x47,
          0x0d,
          0x0a,
          0x1a,
          0x0a,
        ]);
        expect(client.lastRequest!.url.path, '/paymongo_checkout');
        expect(client.lastBody!['activationCode'], 'a' * 86);
        expect(client.lastBody!['amountPesos'], 20);
      },
    );

    test('requests only recognized payment states', () async {
      final client = _FakeClient(
        (_, _) => http.Response(jsonEncode({'status': 'paid'}), 200),
      );
      final payments = PayMongoPaymentClient(
        client: client,
        backend: Uri.parse('https://booth.example.test'),
      );

      final status = await payments.getStatus(
        deviceId: 'device-12345678',
        activationCode: 'activation-token',
        idempotencyKey: 'c' * 32,
      );

      expect(status, 'paid');
      expect(client.lastRequest!.url.path, '/paymongo_status');
    });

    test('surfaces sanitized PayMongo response diagnostics', () async {
      final client = _FakeClient(
        (_, _) => http.Response(
          jsonEncode({
            'error': 'invalid_paymongo_checkout_response',
            'providerStep': 'attach_qr',
            'intentStatus': 'awaiting_next_action',
            'amount': 2000,
            'currency': 'PHP',
            'qrImageKind': 'missing',
            'codeKeys': ['qr_string'],
          }),
          502,
        ),
      );
      final payments = PayMongoPaymentClient(
        client: client,
        backend: Uri.parse('https://booth.example.test'),
      );

      await expectLater(
        payments.createCheckout(
          deviceId: 'device-12345678',
          activationCode: 'activation-token',
          idempotencyKey: 'a' * 32,
          amountPesos: 20,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('step: attach_qr'),
              contains('status: awaiting_next_action'),
              contains('QR fields: qr_string'),
            ),
          ),
        ),
      );
    });

    test('rejects malformed image data and unknown payment statuses', () async {
      final malformedCheckoutClient = _FakeClient(
        (_, _) => http.Response(
          jsonEncode({
            'referenceNumber': 'pi_12345',
            'qrImageBase64': base64Encode([1, 2, 3]),
            'amountPesos': 20,
          }),
          200,
        ),
      );
      final malformedCheckout = PayMongoPaymentClient(
        client: malformedCheckoutClient,
        backend: Uri.parse('https://booth.example.test'),
      );
      await expectLater(
        malformedCheckout.createCheckout(
          deviceId: 'device-12345678',
          activationCode: 'activation-token',
          idempotencyKey: 'd' * 32,
          amountPesos: 20,
        ),
        throwsFormatException,
      );

      final invalidStatusClient = _FakeClient(
        (_, _) => http.Response(jsonEncode({'status': 'success'}), 200),
      );
      final invalidStatus = PayMongoPaymentClient(
        client: invalidStatusClient,
        backend: Uri.parse('https://booth.example.test'),
      );
      await expectLater(
        invalidStatus.getStatus(
          deviceId: 'device-12345678',
          activationCode: 'activation-token',
          idempotencyKey: 'e' * 32,
        ),
        throwsFormatException,
      );
    });

    test('accepts PNG, JPEG, and WebP QR image data', () async {
      final imageSignatures = [
        [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a],
        [0xff, 0xd8, 0xff, 0xe0],
        [
          0x52,
          0x49,
          0x46,
          0x46,
          0x00,
          0x00,
          0x00,
          0x00,
          0x57,
          0x45,
          0x42,
          0x50,
        ],
      ];

      for (final signature in imageSignatures) {
        final client = _FakeClient(
          (_, _) => http.Response(
            jsonEncode({
              'referenceNumber': 'pi_12345',
              'qrImageBase64': base64Encode(signature),
              'amountPesos': 20,
            }),
            200,
          ),
        );
        final payments = PayMongoPaymentClient(
          client: client,
          backend: Uri.parse('https://booth.example.test'),
        );

        await expectLater(
          payments.createCheckout(
            deviceId: 'device-12345678',
            activationCode: 'activation-token',
            idempotencyKey: 'f' * 32,
            amountPesos: 20,
          ),
          completes,
        );
      }
    });

    test('rejects amounts outside the supported whole-peso range', () async {
      final client = _FakeClient((_, _) => http.Response('{}', 200));
      final payments = PayMongoPaymentClient(
        client: client,
        backend: Uri.parse('https://booth.example.test'),
      );

      await expectLater(
        payments.createCheckout(
          deviceId: 'device-12345678',
          activationCode: 'activation-token',
          idempotencyKey: 'g' * 32,
          amountPesos: 0,
        ),
        throwsRangeError,
      );
      await expectLater(
        payments.createCheckout(
          deviceId: 'device-12345678',
          activationCode: 'activation-token',
          idempotencyKey: 'h' * 32,
          amountPesos: 100001,
        ),
        throwsRangeError,
      );
      expect(client.lastRequest, isNull);
    });

    test('rejects a checkout response with a different amount', () async {
      final client = _FakeClient(
        (_, _) => http.Response(
          jsonEncode({
            'referenceNumber': 'pi_12345',
            'qrImageBase64': qrPng,
            'amountPesos': 21,
          }),
          200,
        ),
      );
      final payments = PayMongoPaymentClient(
        client: client,
        backend: Uri.parse('https://booth.example.test'),
      );

      await expectLater(
        payments.createCheckout(
          deviceId: 'device-12345678',
          activationCode: 'activation-token',
          idempotencyKey: 'i' * 32,
          amountPesos: 20,
        ),
        throwsFormatException,
      );
    });
  });
}

class _FakeClient extends http.BaseClient {
  _FakeClient(this.respond);

  final http.Response Function(
    http.BaseRequest request,
    Map<String, dynamic> body,
  )
  respond;
  http.BaseRequest? lastRequest;
  Map<String, dynamic>? lastBody;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    lastRequest = request;
    final bytes = await request.finalize().toBytes();
    lastBody = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    final response = respond(request, lastBody!);
    return http.StreamedResponse(
      Stream<List<int>>.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }
}
