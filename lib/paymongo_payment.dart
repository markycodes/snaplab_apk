import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

const _defaultPayMongoBackend = 'https://snaplabbooth.com';

class PayMongoCheckout {
  const PayMongoCheckout({
    required this.idempotencyKey,
    required this.referenceNumber,
    required this.amountPesos,
    required this.qrImageBase64,
    required this.testUrl,
  });

  final String idempotencyKey;
  final String referenceNumber;
  final int amountPesos;
  final String qrImageBase64;
  final String? testUrl;

  Uint8List get imageBytes => Uint8List.fromList(base64Decode(qrImageBase64));
}

class PayMongoPaymentClient {
  PayMongoPaymentClient({http.Client? client, Uri? backend})
    : _client = client ?? http.Client(),
      _backend = backend ?? Uri.parse(_defaultPayMongoBackend);

  final http.Client _client;
  final Uri _backend;

  static String createIdempotencyKey() {
    final random = Random.secure();
    return List<int>.generate(
      16,
      (_) => random.nextInt(256),
    ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }

  static String _normalizeActivationCode(String code) =>
      code.replaceAll(RegExp(r'\s'), '').replaceFirst(RegExp(r'=+$'), '');

  Future<PayMongoCheckout> createCheckout({
    required String deviceId,
    required String activationCode,
    required String idempotencyKey,
    required int amountPesos,
  }) async {
    if (amountPesos < 1 || amountPesos > 100000) {
      throw RangeError.range(amountPesos, 1, 100000, 'amountPesos');
    }
    final response = await _post('paymongo_checkout', {
      'deviceId': deviceId,
      'activationCode': _normalizeActivationCode(activationCode),
      'idempotencyKey': idempotencyKey,
      'amountPesos': amountPesos,
    });
    final reference = response['referenceNumber'];
    final responseAmount = response['amountPesos'];
    final qrImage = response['qrImageBase64'];
    final testUrlValue = response['testUrl'];
    final testUrl = testUrlValue is String ? testUrlValue : null;
    if (reference is! String ||
        !RegExp(r'^pi_[A-Za-z0-9]+$').hasMatch(reference) ||
        responseAmount != amountPesos ||
        qrImage is! String ||
        !_isValidQrImage(qrImage) ||
        (testUrlValue != null &&
            (testUrl == null || !_isValidTestUrl(testUrl)))) {
      throw const FormatException(
        'PayMongo returned invalid QR Ph checkout details.',
      );
    }
    return PayMongoCheckout(
      idempotencyKey: idempotencyKey,
      referenceNumber: reference,
      amountPesos: amountPesos,
      qrImageBase64: qrImage,
      testUrl: testUrl,
    );
  }

  bool _isValidTestUrl(String content) {
    final uri = Uri.tryParse(content);
    final host = uri?.host.toLowerCase();
    return uri != null &&
        uri.scheme == 'https' &&
        uri.userInfo.isEmpty &&
        host != null &&
        (host == 'paymongo.com' || host.endsWith('.paymongo.com'));
  }

  bool _isValidQrImage(String content) {
    if (content.isEmpty || content.length > 700000) return false;
    try {
      final bytes = base64Decode(content);
      if (bytes.isEmpty || bytes.length > 524288) return false;
      final isPng =
          bytes.length >= 8 &&
          bytes[0] == 0x89 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x4e &&
          bytes[3] == 0x47 &&
          bytes[4] == 0x0d &&
          bytes[5] == 0x0a &&
          bytes[6] == 0x1a &&
          bytes[7] == 0x0a;
      final isJpeg =
          bytes.length >= 3 &&
          bytes[0] == 0xff &&
          bytes[1] == 0xd8 &&
          bytes[2] == 0xff;
      final isWebp =
          bytes.length >= 12 &&
          bytes[0] == 0x52 &&
          bytes[1] == 0x49 &&
          bytes[2] == 0x46 &&
          bytes[3] == 0x46 &&
          bytes[8] == 0x57 &&
          bytes[9] == 0x45 &&
          bytes[10] == 0x42 &&
          bytes[11] == 0x50;
      return isPng || isJpeg || isWebp;
    } on FormatException {
      return false;
    }
  }

  Future<String> getStatus({
    required String deviceId,
    required String activationCode,
    required String idempotencyKey,
  }) async {
    final response = await _post('paymongo_status', {
      'deviceId': deviceId,
      'activationCode': _normalizeActivationCode(activationCode),
      'idempotencyKey': idempotencyKey,
    });
    final status = response['status'];
    if (status is! String ||
        !const {'pending', 'paid', 'expired'}.contains(status)) {
      throw const FormatException(
        'PayMongo returned an invalid payment status.',
      );
    }
    return status;
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, Object?> body,
  ) async {
    final response = await _client
        .post(
          _backend.resolve(path),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 20));
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('The payment server returned invalid data.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = decoded['error'];
      if (error == 'paymongo_disabled') {
        throw StateError(
          'PayMongo payments are disabled in the private server configuration. Verify the test setup before explicitly enabling them.',
        );
      }
      if (error == 'invalid_payment_amount') {
        throw StateError(
          'PayMongo amount must be between ₱${decoded['minimumAmountPesos']} and ₱${decoded['maximumAmountPesos']} in whole pesos.',
        );
      }
      if (error == 'checkout_amount_conflict') {
        throw StateError(
          'This checkout key belongs to a different amount. Cancel and retry to create a fresh payment QR.',
        );
      }
      if (error == 'paymongo_not_configured') {
        final missing = decoded['missing'];
        final details = missing is List
            ? missing.whereType<String>().join(', ')
            : '';
        throw StateError(
          details.isEmpty
              ? 'PayMongo is not configured on the Hostinger server.'
              : 'PayMongo server settings are still needed: $details.',
        );
      }
      if (error == 'paymongo_request_failed') {
        throw StateError(
          'PayMongo rejected the request (HTTP ${decoded['providerStatus'] ?? 'unknown'}). Check the server API keys and PayMongo QR Ph settings.',
        );
      }
      if (error == 'invalid_paymongo_checkout_response') {
        final step = decoded['providerStep'];
        final imageKind = decoded['qrImageKind'];
        final imageLength = decoded['qrImageLength'];
        final intentStatus = decoded['intentStatus'];
        final amount = decoded['amount'];
        final currency = decoded['currency'];
        final codeKeys = decoded['codeKeys'];
        final diagnostics = <String>[
          if (step is String) 'step: $step',
          if (intentStatus is String) 'status: $intentStatus',
          if (amount is num) 'amount: $amount',
          if (currency is String) 'currency: $currency',
          if (imageKind is String) 'QR data: $imageKind',
          if (imageLength is int) 'QR data length: $imageLength',
          if (codeKeys is List && codeKeys.whereType<String>().isNotEmpty)
            'QR fields: ${codeKeys.whereType<String>().join(', ')}',
        ];
        throw StateError(
          diagnostics.isEmpty
              ? 'PayMongo did not return a usable QR Ph image. Check the payment-method and Payment Intent configuration.'
              : 'PayMongo returned unexpected checkout data (${diagnostics.join('; ')}). Verify that the latest paymongo_checkout.php is deployed.',
        );
      }
      if (error == 'invalid_paymongo_test_response') {
        throw StateError(
          'PayMongo test mode did not return the documented test_url. No payment QR was displayed; check the test-key configuration.',
        );
      }
      if (error == 'paymongo_transport_error') {
        throw StateError(
          'The Hostinger server could not connect to PayMongo. Check outbound HTTPS/cURL access.',
        );
      }
      throw StateError(
        'PayMongo payment request failed (${error is String ? error : 'unknown error'}).',
      );
    }
    return decoded;
  }
}
