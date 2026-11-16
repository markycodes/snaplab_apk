import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth_kiosk/photo_effects.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temporaryDirectory;
  late File sourcePhoto;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'photobooth-effect-test-',
    );
    sourcePhoto = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}photo.png',
    );
    await sourcePhoto.writeAsBytes(await _encodeImage());
  });

  tearDown(() async {
    await temporaryDirectory.delete(recursive: true);
  });

  test('Original keeps the source photo unchanged', () async {
    expect(
      await applyPhotoEffect(sourcePhoto, PhotoEffect.original),
      sourcePhoto,
    );
  });

  test('color effects produce readable PNG images', () async {
    for (final effect in PhotoEffect.values.where(
      (effect) => effect != PhotoEffect.original,
    )) {
      final output = await applyPhotoEffect(sourcePhoto, effect, maxWidth: 4);
      expect(await output.exists(), isTrue, reason: effect.label);
      final codec = await ui.instantiateImageCodec(await output.readAsBytes());
      try {
        final image = (await codec.getNextFrame()).image;
        expect(image.width, greaterThan(0), reason: effect.label);
        expect(image.height, greaterThan(0), reason: effect.label);
        image.dispose();
      } finally {
        codec.dispose();
      }
    }
  });

  test('each filter preview has its own output file', () async {
    final effects = PhotoEffect.values
        .where((effect) => effect != PhotoEffect.original)
        .toList();
    final previews = <File>[];
    for (final effect in effects) {
      previews.add(await applyPhotoEffect(sourcePhoto, effect, maxWidth: 240));
    }
    expect(
      previews.map((file) => file.path).toSet(),
      hasLength(effects.length),
    );
  });

  test('black-and-white effect produces equal color channels', () async {
    final output = await applyPhotoEffect(
      sourcePhoto,
      PhotoEffect.monochrome,
      maxWidth: 4,
    );
    final codec = await ui.instantiateImageCodec(await output.readAsBytes());
    try {
      final image = (await codec.getNextFrame()).image;
      final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      expect(pixels, isNotNull);
      expect(pixels!.getUint8(0), pixels.getUint8(1));
      expect(pixels.getUint8(1), pixels.getUint8(2));
      image.dispose();
    } finally {
      codec.dispose();
    }
  });

  test('cartoon effect posterizes color and outlines strong edges', () async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawColor(const ui.Color(0xFFE6D2B4), ui.BlendMode.src);
    canvas.drawRect(
      const ui.Rect.fromLTWH(8, 4, 4, 8),
      ui.Paint()..color = const ui.Color(0xFF1E3250),
    );
    final image = await recorder.endRecording().toImage(16, 16);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('Test image could not be encoded.');
      await sourcePhoto.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
    } finally {
      image.dispose();
    }

    final output = await applyPhotoEffect(
      sourcePhoto,
      PhotoEffect.cartoon,
      maxWidth: 16,
    );
    final codec = await ui.instantiateImageCodec(await output.readAsBytes());
    try {
      final result = (await codec.getNextFrame()).image;
      final pixels = await result.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      expect(pixels, isNotNull);
      int channel(int x, int y, int index) =>
          pixels!.getUint8((y * result.width + x) * 4 + index);
      expect(
        [channel(10, 8, 0), channel(10, 8, 1), channel(10, 8, 2)],
        [0, 64, 64],
      );
      expect(
        [channel(7, 8, 0), channel(7, 8, 1), channel(7, 8, 2)],
        [24, 20, 32],
      );
      result.dispose();
    } finally {
      codec.dispose();
    }
  });
}

Future<Uint8List> _encodeImage() async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawColor(const ui.Color(0xFF204080), ui.BlendMode.src);
  canvas.drawRect(
    const ui.Rect.fromLTWH(0, 0, 2, 3),
    ui.Paint()..color = const ui.Color(0xFFFFC080),
  );
  final image = await recorder.endRecording().toImage(4, 3);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('Test photo could not be encoded.');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image.dispose();
  }
}
