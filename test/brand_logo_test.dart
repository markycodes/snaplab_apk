import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photobooth_kiosk/brand_logo.dart';

void main() {
  test(
    'makes connected white background transparent and preserves logo ink',
    () {
      final source = img.Image(width: 5, height: 5, numChannels: 4);
      source.clear(img.ColorRgba8(255, 255, 255, 255));
      source.setPixelRgba(2, 2, 20, 30, 40, 255);

      final output = makeWhiteLogoBackgroundTransparent(
        Uint8List.fromList(img.encodePng(source)),
      );
      final result = img.decodeImage(output)!;

      expect(result.getPixel(0, 0).a, 0);
      expect(result.getPixel(2, 2).a, 255);
      expect(result.getPixel(2, 2).r, 20);
    },
  );

  test('preserves white details enclosed by dark logo ink', () {
    final source = img.Image(width: 5, height: 5, numChannels: 4);
    source.clear(img.ColorRgba8(255, 255, 255, 255));
    for (var y = 1; y <= 3; y++) {
      for (var x = 1; x <= 3; x++) {
        source.setPixelRgba(x, y, 20, 30, 40, 255);
      }
    }
    source.setPixelRgba(2, 2, 255, 255, 255, 255);

    final output = makeWhiteLogoBackgroundTransparent(
      Uint8List.fromList(img.encodePng(source)),
    );
    final result = img.decodeImage(output)!;

    expect(result.getPixel(0, 0).a, 0);
    expect(result.getPixel(2, 2).a, 255);
  });
}
