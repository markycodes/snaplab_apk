import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

const _defaultGanapBackend = 'https://snaplabbooth.com';

enum GanapQrType { checkoutUrl, payload, imageData, imageUrl }

class GanapCheckout {
  const GanapCheckout({
    required this.idempotencyKey,
    required this.referenceNumber,
    required this.qrType,
    required this.qrContent,
  });

  final String idempotencyKey;
  final String referenceNumber;
  final GanapQrType qrType;
  final String qrContent;

  List<int>? get imageBytes {
    if (qrType != GanapQrType.imageData) return null;
    final separator = qrContent.indexOf(',');
    if (separator < 0) return null;
    return base64Decode(qrContent.substring(separator + 1));
  }
}

class GanapPaymentClient {
  GanapPaymentClient({http.Client? client, Uri? backend})
    : _client = client ?? http.Client(),
      _backend = backend ?? Uri.parse(_defaultGanapBackend);

  final http.Client _client;
  final Uri _backend;

  static String _normalizeActivationCode(String code) =>
      code.replaceAll(RegExp(r'\s'), '').replaceFirst(RegExp(r'=+$'), '');

  Future<GanapCheckout> createCheckout({
    required String deviceId,
    required String activationCode,
    required String idempotencyKey,
  }) async {
    final response = await _post('ganap_checkout', {
      'deviceId': deviceId,
      'activationCode': _normalizeActivationCode(activationCode),
      'idempotencyKey': idempotencyKey,
    });
    final reference = response['referenceNumber'];
    final typeValue = response['qrType'];
    final content = response['qrContent'];
    if (reference is! String || reference.isEmpty || content is! String) {
      throw const FormatException('Ganap returned invalid checkout details.');
    }
    final qrType = switch (typeValue) {
      'checkout_url' => GanapQrType.checkoutUrl,
      'payload' => GanapQrType.payload,
      'image_data' => GanapQrType.imageData,
      'image_url' => GanapQrType.imageUrl,
      _ => null,
    };
    if (qrType == null || !_isValidQrContent(qrType, content)) {
      throw const FormatException('Ganap returned invalid checkout details.');
    }
    return GanapCheckout(
      idempotencyKey: idempotencyKey,
      referenceNumber: reference,
      qrType: qrType,
      qrContent: content,
    );
  }

  bool _isValidQrContent(GanapQrType type, String content) {
    if (type == GanapQrType.payload) {
      return content.length <= 4096 &&
          content.isNotEmpty &&
          RegExp(r'^[\x20-\x7E]+$').hasMatch(content);
    }
    if (type == GanapQrType.imageData) {
      final match = RegExp(
        r'^data:image/(png|jpeg|webp);base64,([A-Za-z0-9+/]+={0,2})$',
      ).firstMatch(content);
      if (match == null) return false;
      try {
        final bytes = base64Decode(match.group(2)!);
        return bytes.isNotEmpty && bytes.length <= 524288;
      } on FormatException {
        return false;
      }
    }
    final uri = Uri.tryParse(content);
    final host = uri?.host.toLowerCase();
    return uri != null &&
        uri.scheme == 'https' &&
        uri.userInfo.isEmpty &&
        host != null &&
        (host == 'ganap.net' || host.endsWith('.ganap.net'));
  }

  Future<String> getStatus({
    required String deviceId,
    required String activationCode,
    required String idempotencyKey,
  }) async {
    final response = await _post('ganap_status', {
      'deviceId': deviceId,
      'activationCode': _normalizeActivationCode(activationCode),
      'idempotencyKey': idempotencyKey,
    });
    final status = response['status'];
    if (status is! String ||
        !const {'pending', 'paid', 'expired'}.contains(status)) {
      throw const FormatException('Ganap returned an invalid payment status.');
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
      if (error == 'ganap_not_configured') {
        final missing = decoded['missing'];
        final details = missing is List
            ? missing.whereType<String>().join(', ')
            : '';
        throw StateError(
          details.isEmpty
              ? 'Ganap is not configured on the server. Check the private Hostinger payment settings.'
              : 'Ganap is not configured on the server. Hostinger settings still needed: $details.',
        );
      }
      if (error == 'ganap_minimum_exceeds_session_price') {
        throw StateError(
          'Ganap currently requires a minimum payment of ₱${decoded['minimumAmount']}, above this booth’s ₱${decoded['sessionPrice']} session price. Ganap QRPh is unavailable until its minimum supports ₱20.',
        );
      }
      if (error == 'ganap_checkout_rejected') {
        final ganapStatus = decoded['ganapStatus'];
        final providerCode = decoded['providerCode'];
        final providerField = decoded['providerField'];
        final providerMessage = decoded['providerMessage'];
        final statusText = ganapStatus is int
            ? 'Ganap returned HTTP $ganapStatus'
            : 'Ganap rejected the checkout';
        final diagnostics = <String>[
          if (providerField is String) 'field: $providerField',
          if (providerCode is String) 'code: $providerCode',
        ];
        if (providerMessage is String && providerMessage.isNotEmpty) {
          diagnostics.add(providerMessage);
        }
        throw StateError(
          diagnostics.isEmpty
              ? '$statusText. No explanation was included in Ganap’s response. Check the Ganap project settings and confirm the latest Hostinger ganap_checkout.php is deployed.'
              : '$statusText: ${diagnostics.join(' — ')}',
        );
      }
      if (error == 'ganap_transport_error') {
        throw StateError(
          'Hostinger could not connect to Ganap (cURL error ${decoded['curlCode'] ?? 'unknown'}). Check Hostinger outbound HTTPS/cURL access.',
        );
      }
      if (error == 'invalid_ganap_checkout_response') {
        final problem = decoded['responseProblem'];
        final keys = decoded['responseKeys'];
        final scheme = decoded['checkoutScheme'];
        final host = decoded['checkoutHost'];
        final endpointVersion = decoded['endpointVersion'];
        final urlShape = decoded['checkoutUrlShape'];
        final candidateHosts = decoded['checkoutCandidateHosts'];
        final candidateCount = decoded['checkoutUrlMatchCount'];
        final missingScheme = problem == 'checkout_url_scheme_not_https';
        final missingHost = problem == 'checkout_url_host_missing';
        final details = <String>[
          if (problem is String) problem,
          if (keys is List && keys.whereType<String>().isNotEmpty)
            'fields: ${keys.whereType<String>().join(', ')}',
          if (scheme is String) 'checkout scheme: $scheme',
          if (scheme == null && missingScheme) 'checkout scheme: missing',
          if (host is String) 'checkout host: $host',
          if (host == null && missingHost) 'checkout host: missing',
          if (endpointVersion is String)
            'backend version: $endpointVersion'
          else
            'backend version: unreported',
          if (urlShape is String) 'checkout URL format: $urlShape',
          if (candidateCount is int) 'HTTPS URL candidates: $candidateCount',
          if (candidateHosts is List &&
              candidateHosts.whereType<String>().isNotEmpty)
            'candidate hosts: ${candidateHosts.whereType<String>().join(', ')}',
        ];
        throw StateError(
          details.isEmpty
              ? 'Ganap returned a checkout response the server could not use. Replace ganap_checkout.php on Hostinger with the latest version.'
              : 'Ganap checkout response could not be used (${details.join('; ')}).',
        );
      }
      throw StateError(
        error is String
            ? 'Payment request failed: $error.'
            : 'Payment request failed with HTTP ${response.statusCode}.',
      );
    }
    return decoded;
  }

  static String createIdempotencyKey() {
    final random = Random.secure();
    return List<int>.generate(
      16,
      (_) => random.nextInt(256),
    ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }
}
