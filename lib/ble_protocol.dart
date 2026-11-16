import 'dart:convert';

class BleCreditRequest {
  const BleCreditRequest._();

  static List<int> readCredits() => utf8.encode(jsonEncode({'op': 'credits'}));

  static List<int> reportBattery({
    required int percent,
    required int startPercent,
    required int stopPercent,
  }) {
    if (percent < 0 || percent > 100) {
      throw ArgumentError.value(percent, 'percent', 'Must be from 0 to 100.');
    }
    if (startPercent < 0 ||
        startPercent > 99 ||
        stopPercent < 1 ||
        stopPercent > 100 ||
        startPercent >= stopPercent) {
      throw ArgumentError(
        'Charge thresholds must be from 0 to 100 and start must be below stop.',
      );
    }
    return utf8.encode(
      jsonEncode({
        'op': 'battery',
        'percent': percent,
        'startPercent': startPercent,
        'stopPercent': stopPercent,
      }),
    );
  }

  static List<int> consumeCredits(int amount) {
    if (amount <= 0) {
      throw ArgumentError.value(amount, 'amount', 'Must be positive.');
    }
    return utf8.encode(jsonEncode({'op': 'consume', 'amount': amount}));
  }
}

class BleCreditResponse {
  const BleCreditResponse({
    required this.credits,
    required this.consumed,
    this.error,
  });

  final int credits;
  final bool consumed;
  final String? error;

  factory BleCreditResponse.fromBytes(List<int> value) {
    final decoded = jsonDecode(utf8.decode(value));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('ESP32 BLE response must be a JSON object.');
    }

    final credits = decoded['credits'];
    final consumed = decoded['consumed'];
    final error = decoded['error'];
    if (credits is! int ||
        credits < 0 ||
        consumed is! bool ||
        error != null && error is! String) {
      throw const FormatException(
        'ESP32 BLE response has invalid credit fields.',
      );
    }

    return BleCreditResponse(
      credits: credits,
      consumed: consumed,
      error: error is String ? error : null,
    );
  }
}
