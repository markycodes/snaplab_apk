import 'dart:ui' as ui;

import 'package:flutter/animation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth_kiosk/booth_event_theme.dart';
import 'package:photobooth_kiosk/booth_theme_background.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final theme in BoothEventTheme.values) {
    test(
      '$theme artwork is spread across portrait and landscape screens',
      () async {
        for (final size in [
          const ui.Size(600, 1000),
          const ui.Size(1000, 600),
        ]) {
          final recorder = ui.PictureRecorder();
          final canvas = ui.Canvas(recorder);
          final painter = BoothThemeBackgroundPainter(theme: theme);
          painter.paint(canvas, size);
          final picture = recorder.endRecording();
          final image = await picture.toImage(
            size.width.toInt(),
            size.height.toInt(),
          );
          picture.dispose();
          try {
            final pixels = await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            );
            expect(pixels, isNotNull);

            final columns = size.width >= size.height ? 6 : 4;
            final rows = size.width >= size.height ? 4 : 6;
            final cellWidth = size.width ~/ columns;
            final cellHeight = size.height ~/ rows;
            var occupiedCells = 0;
            for (var row = 0; row < rows; row++) {
              for (var column = 0; column < columns; column++) {
                final left = column * cellWidth;
                final top = row * cellHeight;
                var containsArtwork = false;
                for (
                  var y = top;
                  y < top + cellHeight && !containsArtwork;
                  y += 4
                ) {
                  for (var x = left; x < left + cellWidth; x += 4) {
                    final alpha = pixels!.getUint8(
                      (y * size.width.toInt() + x) * 4 + 3,
                    );
                    if (alpha > 0) {
                      containsArtwork = true;
                      break;
                    }
                  }
                }
                if (containsArtwork) occupiedCells++;
              }
            }

            expect(occupiedCells, greaterThanOrEqualTo(columns * rows - 4));
          } finally {
            image.dispose();
          }
        }
      },
    );
  }

  test('theme motifs animate between painter frames', () async {
    for (final theme in BoothEventTheme.values) {
      Future<int> renderAt(double phase) async {
        const size = ui.Size(600, 1000);
        final recorder = ui.PictureRecorder();
        BoothThemeBackgroundPainter(
          theme: theme,
          animation: AlwaysStoppedAnimation<double>(phase),
        ).paint(ui.Canvas(recorder), size);
        final picture = recorder.endRecording();
        final image = await picture.toImage(600, 1000);
        picture.dispose();
        try {
          final bytes = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          return Object.hashAll(bytes!.buffer.asUint8List());
        } finally {
          image.dispose();
        }
      }

      expect(await renderAt(0), isNot(await renderAt(0.25)), reason: '$theme');
    }
  });
}
