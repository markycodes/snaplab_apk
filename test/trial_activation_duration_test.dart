import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth_kiosk/trial_activation_duration.dart';

void main() {
  group('parseTrialDuration', () {
    test('accepts minute, hour, and day units', () {
      expect(parseTrialDuration('30m'), const Duration(minutes: 30));
      expect(parseTrialDuration('2h'), const Duration(hours: 2));
      expect(parseTrialDuration('14d'), const Duration(days: 14));
    });

    test('keeps bare day values compatible', () {
      expect(parseTrialDuration('14'), const Duration(days: 14));
      expect(parseTrialDuration('1'), const Duration(days: 1));
    });

    test('accepts uppercase units', () {
      expect(parseTrialDuration('5M'), const Duration(minutes: 5));
      expect(parseTrialDuration('3H'), const Duration(hours: 3));
      expect(parseTrialDuration('7D'), const Duration(days: 7));
    });

    test('limits trial duration to one minute through 365 days', () {
      expect(parseTrialDuration('1m'), const Duration(minutes: 1));
      expect(parseTrialDuration('365d'), const Duration(days: 365));
      expect(() => parseTrialDuration('0m'), throwsFormatException);
      expect(() => parseTrialDuration('366d'), throwsFormatException);
      expect(() => parseTrialDuration('1m '), throwsFormatException);
    });
  });
}
