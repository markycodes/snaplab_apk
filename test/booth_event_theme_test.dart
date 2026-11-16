import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth_kiosk/booth_event_theme.dart';
import 'package:photobooth_kiosk/photo_border.dart';

void main() {
  test('event presets provide a matching border and welcome text', () {
    expect(BoothEventTheme.classic.borderStyle, PhotoBorderStyle.none);
    expect(BoothEventTheme.birthday.borderStyle, PhotoBorderStyle.birthday);
    expect(BoothEventTheme.wedding.borderStyle, PhotoBorderStyle.wedding);
    expect(BoothEventTheme.graduation.borderStyle, PhotoBorderStyle.graduation);
    expect(BoothEventTheme.holiday.borderStyle, PhotoBorderStyle.christmas);
    expect(BoothEventTheme.summer.borderStyle, PhotoBorderStyle.summer);
    expect(BoothEventTheme.coffeeBeans.borderStyle, PhotoBorderStyle.none);
    expect(BoothEventTheme.coffeeCup.borderStyle, PhotoBorderStyle.none);
    expect(BoothEventTheme.latteArt.borderStyle, PhotoBorderStyle.none);
    expect(BoothEventTheme.valentines.borderStyle, PhotoBorderStyle.wedding);
    expect(BoothEventTheme.classic.welcomeMessage, 'TAKE HOME A MEMORY');
  });

  test('themed attract screens keep a white background', () {
    expect(BoothEventTheme.classic.usesWhiteBackground, isFalse);
    for (final theme in BoothEventTheme.values.skip(1)) {
      expect(theme.usesWhiteBackground, isTrue);
    }
  });

  test('result text colors stay readable on the white result panel', () {
    for (final theme in BoothEventTheme.values) {
      final luminance = theme.resultTextColor.computeLuminance();
      final contrastRatio = 1.05 / (luminance + 0.05);
      expect(
        contrastRatio,
        greaterThanOrEqualTo(4.5),
        reason: '${theme.label} result text should be readable on white',
      );
    }
  });
}
