import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth_kiosk/esc_pos.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temporaryDirectory;
  late File photo;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'photobooth-print-test-',
    );
    photo = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}strip.png',
    );
    await photo.writeAsBytes(await _encodeImage());
  });

  tearDown(() async {
    await temporaryDirectory.delete(recursive: true);
  });

  test('creates an ESC/POS raster packet at the requested width', () async {
    final packet = await encodeEscPosRaster(photo, widthDots: 8);

    expect(packet.sublist(0, 5), [0x1B, 0x40, 0x1B, 0x61, 0x01]);
    expect(packet.sublist(5, 13), [0x1D, 0x76, 0x30, 0, 1, 0, 3, 0]);
    expect(packet.length, 5 + 8 + 8 * 3 ~/ 8 + 6);
    expect(packet.sublist(13, 16), [0xB0, 0xD0, 0x60]);
    expect(packet.sublist(packet.length - 6), [0x1B, 0x64, 12, 0x1D, 0x56, 0]);
  });

  test('supports the standard partial-cut command', () async {
    final packet = await encodeEscPosRaster(
      photo,
      widthDots: 8,
      cutMode: EscPosCutMode.partial,
    );

    expect(packet.sublist(packet.length - 6), [0x1B, 0x64, 12, 0x1D, 0x56, 1]);
  });

  test('rejects invalid printer raster configuration', () async {
    expect(encodeEscPosRaster(photo, widthDots: 10), throwsArgumentError);
    expect(encodeEscPosRaster(photo, threshold: 300), throwsArgumentError);
    expect(
      encodeEscPosRaster(photo, shadowLightening: 0.6),
      throwsArgumentError,
    );
  });

  test('includes all raster rows before feeding and cutting', () async {
    final tallPhoto = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}tall.png',
    );
    await tallPhoto.writeAsBytes(await _encodeSolidImage(8, 32));

    final packet = await encodeEscPosRaster(tallPhoto, widthDots: 8);

    expect(packet.sublist(5, 13), [0x1D, 0x76, 0x30, 0, 1, 0, 32, 0]);
    expect(packet.length, 5 + 8 + 32 + 6);
    expect(packet.sublist(packet.length - 6), [0x1B, 0x64, 12, 0x1D, 0x56, 0]);
  });

  test(
    'splits tall photos into compatible raster bands without losing rows',
    () async {
      final tallPhoto = File(
        '${temporaryDirectory.path}${Platform.pathSeparator}very-tall.png',
      );
      await tallPhoto.writeAsBytes(await _encodeSolidImage(8, 260));

      final packet = await encodeEscPosRaster(tallPhoto, widthDots: 8);

      expect(packet.sublist(5, 13), [0x1D, 0x76, 0x30, 0, 1, 0, 255, 0]);
      final secondBandOffset = 5 + 8 + 255;
      expect(packet.sublist(secondBandOffset, secondBandOffset + 8), [
        0x1D,
        0x76,
        0x30,
        0,
        1,
        0,
        5,
        0,
      ]);
      expect(packet.length, 5 + (8 + 255) + (8 + 5) + 6);
      expect(packet.sublist(packet.length - 6), [
        0x1B,
        0x64,
        12,
        0x1D,
        0x56,
        0,
      ]);
    },
  );

  test('lightens grayscale output while preserving dithering detail', () async {
    final grayscalePhoto = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}grayscale.png',
    );
    await grayscalePhoto.writeAsBytes(await _encodeGrayImage(128, 8, 8));

    final packet = await encodeEscPosRaster(grayscalePhoto, widthDots: 8);
    final printedDots = packet
        .sublist(13, 13 + 8)
        .fold<int>(
          0,
          (total, byte) =>
              total + byte.toRadixString(2).replaceAll('0', '').length,
        );

    expect(printedDots, inInclusiveRange(20, 32));
  });

  test('composites transparent pixels against white paper', () async {
    final transparentPhoto = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}transparent.png',
    );
    await transparentPhoto.writeAsBytes(await _encodeTransparentImage());

    final packet = await encodeEscPosRaster(transparentPhoto, widthDots: 8);

    expect(packet.sublist(13, 13 + 1), everyElement(0));
  });
}

Future<Uint8List> _encodeImage() async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawColor(const ui.Color(0xFFFFFFFF), ui.BlendMode.src);
  canvas.drawRect(
    const ui.Rect.fromLTWH(0, 0, 4, 3),
    ui.Paint()..color = const ui.Color(0xFF000000),
  );
  final image = await recorder.endRecording().toImage(8, 3);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('Test image could not be encoded.');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image.dispose();
  }
}

Future<Uint8List> _encodeGrayImage(int gray, int width, int height) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder)
    ..drawColor(const ui.Color(0xFFFFFFFF), ui.BlendMode.src)
    ..drawColor(ui.Color.fromARGB(255, gray, gray, gray), ui.BlendMode.src);
  final image = await recorder.endRecording().toImage(width, height);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('Test image could not be encoded.');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image.dispose();
  }
}

Future<Uint8List> _encodeTransparentImage() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    const ui.Rect.fromLTWH(0, 0, 8, 1),
    ui.Paint()..color = const ui.Color(0x40000000),
  );
  final image = await recorder.endRecording().toImage(8, 1);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('Test image could not be encoded.');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image.dispose();
  }
}

Future<Uint8List> _encodeSolidImage(int width, int height) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawColor(const ui.Color(0xFF202020), ui.BlendMode.src);
  final image = await recorder.endRecording().toImage(width, height);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('Test image could not be encoded.');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image.dispose();
  }
}
