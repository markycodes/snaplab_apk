import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:photobooth_kiosk/ganap_payment.dart';

void main() {
  group('GanapPaymentClient', () {
    test('creates a checkout with the signed-in booth details', () async {
      final client = _FakeClient(
        (request, body) => http.Response(
          jsonEncode({
            'referenceNumber': 'GN-12345',
            'qrType': 'checkout_url',
            'qrContent': 'https://checkout.ganap.net/pay/GN-12345',
          }),
          200,
        ),
      );
      final payments = GanapPaymentClient(
        client: client,
        backend: Uri.parse('https://booth.example.test'),
      );

      final checkout = await payments.createCheckout(
        deviceId: 'device-12345678',
        activationCode: '${'a' * 86}==\n',
        idempotencyKey: 'a' * 32,
      );

      expect(checkout.referenceNumber, 'GN-12345');
      expect(checkout.qrType, GanapQrType.checkoutUrl);
      expect(checkout.qrContent, 'https://checkout.ganap.net/pay/GN-12345');
      expect(client.lastRequest!.url.path, '/ganap_checkout');
      expect(client.lastBody!['activationCode'], 'a' * 86);
    });

    test('accepts a raw QR Ph payload without treating it as a URL', () async {
      final client = _FakeClient(
        (_, _) => http.Response(
          jsonEncode({
            'referenceNumber': 'GN-QR-1',
            'qrType': 'payload',
            'qrContent': '00020101021229370016A000000677010111',
          }),
          200,
        ),
      );
      final payments = GanapPaymentClient(
        client: client,
        backend: Uri.parse('https://booth.example.test'),
      );

      final checkout = await payments.createCheckout(
        deviceId: 'device-12345678',
        activationCode: 'a' * 86,
        idempotencyKey: 'e' * 32,
      );

      expect(checkout.qrType, GanapQrType.payload);
      expect(checkout.qrContent, startsWith('0002'));
    });

    test('accepts inline QR images and HTTPS image URLs', () async {
      final inlineClient = _FakeClient(
        (_, _) => http.Response(
          jsonEncode({
            'referenceNumber': 'GN-IMAGE-1',
            'qrType': 'image_data',
            'qrContent': 'data:image/png;base64,aGVsbG8=',
          }),
          200,
        ),
      );
      final inlinePayments = GanapPaymentClient(
        client: inlineClient,
        backend: Uri.parse('https://booth.example.test'),
      );
      final inlineCheckout = await inlinePayments.createCheckout(
        deviceId: 'device-12345678',
        activationCode: 'a' * 86,
        idempotencyKey: 'f' * 32,
      );

      expect(inlineCheckout.qrType, GanapQrType.imageData);
      expect(inlineCheckout.imageBytes, [104, 101, 108, 108, 111]);

      final imageUrlClient = _FakeClient(
        (_, _) => http.Response(
          jsonEncode({
            'referenceNumber': 'GN-IMAGE-2',
            'qrType': 'image_url',
            'qrContent': 'https://cdn.ganap.net/payments/qr.png',
          }),
          200,
        ),
      );
      final imageUrlPayments = GanapPaymentClient(
        client: imageUrlClient,
        backend: Uri.parse('https://booth.example.test'),
      );
      final imageUrlCheckout = await imageUrlPayments.createCheckout(
        deviceId: 'device-12345678',
        activationCode: 'a' * 86,
        idempotencyKey: '1' * 32,
      );

      expect(imageUrlCheckout.qrType, GanapQrType.imageUrl);
      expect(imageUrlCheckout.qrContent, contains('cdn.ganap.net'));
    });

    test('returns only recognized payment states', () async {
      final client = _FakeClient(
        (_, _) => http.Response(jsonEncode({'status': 'paid'}), 200),
      );
      final payments = GanapPaymentClient(
        client: client,
        backend: Uri.parse('https://booth.example.test'),
      );

      final status = await payments.getStatus(
        deviceId: 'device-12345678',
        activationCode: 'activation-token',
        idempotencyKey: 'b' * 32,
      );

      expect(status, 'paid');
      expect(client.lastRequest!.url.path, '/ganap_status');
    });

    test('reports the safe Ganap rejection status and error code', () async {
      final client = _FakeClient(
        (_, _) => http.Response(
          jsonEncode({
            'error': 'ganap_checkout_rejected',
            'ganapStatus': 401,
            'providerCode': 'invalid_signature',
            'providerField': 'projectUuid',
            'providerMessage': 'Project UUID was not found.',
          }),
          502,
        ),
      );
      final payments = GanapPaymentClient(
        client: client,
        backend: Uri.parse('https://booth.example.test'),
      );

      await expectLater(
        payments.createCheckout(
          deviceId: 'device-12345678',
          activationCode: 'a' * 86,
          idempotencyKey: 'c' * 32,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains(
              'HTTP 401: field: projectUuid — code: invalid_signature — Project UUID was not found.',
            ),
          ),
        ),
      );
    });

    test(
      'explains when Ganap minimum exceeds the booth session price',
      () async {
        final client = _FakeClient(
          (_, _) => http.Response(
            jsonEncode({
              'error': 'ganap_minimum_exceeds_session_price',
              'minimumAmount': 200,
              'sessionPrice': 20,
            }),
            503,
          ),
        );
        final payments = GanapPaymentClient(
          client: client,
          backend: Uri.parse('https://booth.example.test'),
        );

        await expectLater(
          payments.createCheckout(
            deviceId: 'device-12345678',
            activationCode: 'a' * 86,
            idempotencyKey: '2' * 32,
          ),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('minimum payment of ₱200'),
            ),
          ),
        );
      },
    );

    test('explains safe checkout response shape failures', () async {
      final client = _FakeClient(
        (_, _) => http.Response(
          jsonEncode({
            'error': 'invalid_ganap_checkout_response',
            'endpointVersion': '20261021-url-diagnostics-10',
            'responseProblem': 'checkout_url_scheme_not_https',
            'responseKeys': ['data', 'referenceNumber', 'checkoutPage'],
            'checkoutScheme': null,
            'checkoutHost': null,
            'checkoutUrlShape': 'relative_path',
            'checkoutUrlMatchCount': 1,
            'checkoutCandidateHosts': ['checkout.ganap.net'],
          }),
          502,
        ),
      );
      final payments = GanapPaymentClient(
        client: client,
        backend: Uri.parse('https://booth.example.test'),
      );

      await expectLater(
        payments.createCheckout(
          deviceId: 'device-12345678',
          activationCode: 'a' * 86,
          idempotencyKey: 'd' * 32,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains(
              'checkout_url_scheme_not_https; fields: data, referenceNumber, checkoutPage; checkout scheme: missing; backend version: 20261021-url-diagnostics-10; checkout URL format: relative_path; HTTPS URL candidates: 1; candidate hosts: checkout.ganap.net',
            ),
          ),
        ),
      );
    });

    test('creates a 128-bit hexadecimal idempotency key', () {
      final key = GanapPaymentClient.createIdempotencyKey();

      expect(key, matches(RegExp(r'^[a-f0-9]{32}$')));
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
