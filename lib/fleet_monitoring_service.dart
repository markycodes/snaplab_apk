import 'dart:convert';

import 'device_activation.dart';

import 'package:http/http.dart' as http;

const defaultFleetMonitoringEndpoint =
    'https://snaplabbooth.com/pb_fleet_ingest.php';

class FleetMonitoringService {
  const FleetMonitoringService({this.client});

  final http.Client? client;

  static Uri validateEndpoint(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty) {
      throw const FormatException(
        'Fleet monitoring requires a secure HTTPS endpoint.',
      );
    }
    return uri;
  }

  Future<Map<String, Object?>> report({
    required String endpoint,
    required String deviceId,
    required String activationCode,
    required Map<String, Object?> status,
    required Map<String, Object?> sales,
    Map<String, Object?>? commandResult,
  }) async {
    final uri = validateEndpoint(endpoint);
    final normalizedActivationCode = normalizeDeviceActivationCode(
      activationCode,
    );
    if (!RegExp(r'^[A-Za-z0-9._:-]{8,128}$').hasMatch(deviceId) ||
        normalizedActivationCode.length > 512 ||
        !hasSupportedDeviceActivationCodeFormat(normalizedActivationCode)) {
      throw const FormatException(
        'A valid activated device is required for fleet monitoring.',
      );
    }

    final activeClient = client ?? http.Client();
    final ownsClient = client == null;
    try {
      final body = <String, Object?>{
        'deviceId': deviceId,
        'activationCode': normalizedActivationCode,
        'status': status,
        'sales': sales,
        ...?commandResult == null ? null : {'commandResult': commandResult},
      };
      final response = await activeClient
          .post(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        var errorCode = '';
        try {
          final decoded = jsonDecode(response.body);
          if (decoded is Map<String, dynamic> &&
              decoded['error'] is String &&
              RegExp(r'^[a-z0-9_]{1,64}$').hasMatch(decoded['error'] as String)) {
            errorCode = ' (${decoded['error']})';
          }
        } on FormatException {
          // Keep the HTTP status when the server does not return JSON.
        }
        throw StateError(
          'Fleet monitoring endpoint returned HTTP '
          '${response.statusCode}$errorCode.',
        );
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Fleet monitoring returned invalid JSON.');
      }
      return decoded;
    } finally {
      if (ownsClient) activeClient.close();
    }
  }
}
