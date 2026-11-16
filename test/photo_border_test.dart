import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth_kiosk/photo_border.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temporaryDirectory;
  late File sourcePhoto;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'photobooth-border-test-',
    );
    sourcePhoto = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}photo.jpg',
    );
    await sourcePhoto.writeAsBytes(
      await _encodeImage((canvas) {
        canvas.drawColor(const ui.Color(0xFF204080), ui.BlendMode.src);
      }),
    );
  });

  tearDown(() async {
    await temporaryDirectory.delete(recursive: true);
  });

  test('no border keeps the captured photo unchanged', () async {
    final result = await applyPhotoBorder(
      sourcePhoto,
      style: PhotoBorderStyle.none,
    );

    expect(result.path, sourcePhoto.path);
    expect(await File('${sourcePhoto.path}.bordered.png').exists(), isFalse);
  });

  test(
    'built-in border produces a valid PNG at the photo dimensions',
    () async {
      final result = await applyPhotoBorder(
        sourcePhoto,
        style: PhotoBorderStyle.classic,
      );

      expect(result.path, endsWith('.bordered.png'));
      final image = await _decodeImage(await result.readAsBytes());
      expect(image.width, 4);
      expect(image.height, 3);
      image.dispose();
    },
  );

  test(
    'every built-in celebration frame renders at the photo dimensions',
    () async {
      final styles = PhotoBorderStyle.values.where(
        (style) =>
            style != PhotoBorderStyle.none && style != PhotoBorderStyle.custom,
      );

      for (final style in styles) {
        final result = await applyPhotoBorder(sourcePhoto, style: style);
        final image = await _decodeImage(await result.readAsBytes());
        expect(image.width, 4, reason: '${style.label} frame width');
        expect(image.height, 3, reason: '${style.label} frame height');
        image.dispose();
      }
    },
  );

  test(
    'custom transparent PNG is composited over the captured photo',
    () async {
      final overlayFile = File(
        '${temporaryDirectory.path}${Platform.pathSeparator}border.png',
      );
      await overlayFile.writeAsBytes(
        await _encodeImage((canvas) {
          canvas.drawRect(
            const ui.Rect.fromLTWH(0, 0, 4, 1),
            ui.Paint()..color = const ui.Color(0xFFFF0000),
          );
        }),
      );

      final result = await applyPhotoBorder(
        sourcePhoto,
        style: PhotoBorderStyle.custom,
        customOverlayPath: overlayFile.path,
      );
      final image = await _decodeImage(await result.readAsBytes());
      final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);

      expect(pixels, isNotNull);
      expect(pixels!.getUint8(0), greaterThan(200));
      expect(pixels.getUint8(1), lessThan(20));
      final lowerPixelOffset = (2 * 4) * 4;
      expect(pixels.getUint8(lowerPixelOffset), 32);
      expect(pixels.getUint8(lowerPixelOffset + 1), 64);
      expect(pixels.getUint8(lowerPixelOffset + 2), 128);
      image.dispose();
    },
  );

  test(
    'large custom PNGs are resized while keeping transparent openings',
    () async {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder)..scale(6);
      canvas.drawColor(const ui.Color(0xFF204080), ui.BlendMode.src);
      canvas.drawRect(
        const ui.Rect.fromLTWH(40, 100, 120, 80),
        ui.Paint()..blendMode = ui.BlendMode.clear,
      );
      final source = await recorder.endRecording().toImage(1200, 1800);
      final encoded = await source.toByteData(format: ui.ImageByteFormat.png);
      source.dispose();
      expect(encoded, isNotNull);

      final normalized = await prepareCustomPhotoBorderPng(
        encoded!.buffer.asUint8List(
          encoded.offsetInBytes,
          encoded.lengthInBytes,
        ),
      );
      final image = await _decodeImage(normalized);
      try {
        expect(image.width, customPhotoImageMaxWidth);
        expect(image.height, customPhotoImageMaxHeight);
        final pixels = await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        expect(pixels, isNotNull);
        final openingCenter = (750 * image.width + 500) * 4;
        expect(pixels!.getUint8(openingCenter + 3), 0);
      } finally {
        image.dispose();
      }
    },
  );

  test(
    'large custom PNGs keep their original aspect ratio when resized',
    () async {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder)..scale(2);
      canvas.drawColor(const ui.Color(0xFF204080), ui.BlendMode.src);
      final source = await recorder.endRecording().toImage(1800, 900);
      final encoded = await source.toByteData(format: ui.ImageByteFormat.png);
      source.dispose();
      expect(encoded, isNotNull);

      final normalized = await prepareCustomPhotoBorderPng(
        encoded!.buffer.asUint8List(
          encoded.offsetInBytes,
          encoded.lengthInBytes,
        ),
      );
      final image = await _decodeImage(normalized);
      try {
        expect(image.width, 1000);
        expect(image.height, 500);
        expect(image.width / image.height, closeTo(2, 0.01));
      } finally {
        image.dispose();
      }
    },
  );
}

Future<Uint8List> _encodeImage(void Function(ui.Canvas canvas) draw) async {
  final recorder = ui.PictureRecorder();
  draw(ui.Canvas(recorder));
  final image = await recorder.endRecording().toImage(4, 3);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('Test image could not be encoded.');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image.dispose();
  }
}

Future<ui.Image> _decodeImage(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  try {
    return (await codec.getNextFrame()).image;
  } finally {
    codec.dispose();
  }
}
