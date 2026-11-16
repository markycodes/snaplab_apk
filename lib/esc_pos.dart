import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

enum EscPosCutMode {
  full(0),
  partial(1);

  const EscPosCutMode(this.commandValue);

  final int commandValue;

  static EscPosCutMode fromName(String? name) => values.firstWhere(
    (mode) => mode.name == name,
    orElse: () => EscPosCutMode.full,
  );
}

Future<Uint8List> encodeEscPosRaster(
  File photo, {
  int widthDots = 576,
  int threshold = 128,
  double shadowLightening = 0.35,
  EscPosCutMode cutMode = EscPosCutMode.full,
}) async {
  if (widthDots < 8 || widthDots > 576 || widthDots % 8 != 0) {
    throw ArgumentError.value(
      widthDots,
      'widthDots',
      'Must be a multiple of 8 between 8 and 576.',
    );
  }
  if (threshold < 0 || threshold > 255) {
    throw ArgumentError.value(threshold, 'threshold', 'Must be 0 to 255.');
  }
  if (shadowLightening < 0 || shadowLightening > 0.5) {
    throw ArgumentError.value(
      shadowLightening,
      'shadowLightening',
      'Must be between 0 and 0.5.',
    );
  }

  final codec = await ui.instantiateImageCodec(
    await photo.readAsBytes(),
    targetWidth: widthDots,
  );
  ui.Image? image;
  try {
    image = (await codec.getNextFrame()).image;
    final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (pixels == null) {
      throw StateError('Could not read photo pixels for printing.');
    }

    if (image.height == 0 || image.height > 65535) {
      throw RangeError.range(
        image.height,
        1,
        65535,
        'photoHeight',
        'ESC/POS raster height must fit in an unsigned 16-bit value.',
      );
    }
    final monochrome = Uint8List(widthDots * image.height);
    var currentError = Float32List(widthDots + 2);
    var nextError = Float32List(widthDots + 2);
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < widthDots; x++) {
        final offset = (y * widthDots + x) * 4;
        final alpha = pixels.getUint8(offset + 3);
        final sourceLuminance =
            (pixels.getUint8(offset) * 299 +
                pixels.getUint8(offset + 1) * 587 +
                pixels.getUint8(offset + 2) * 114) /
            1000;
        final lightenedLuminance =
            255 - (255 - sourceLuminance) * (1 - shadowLightening);
        final luminance =
            (lightenedLuminance * alpha + 255 * (255 - alpha)) / 255;
        final adjusted = (luminance + currentError[x + 1]).clamp(0, 255);
        final isBlack = adjusted < threshold;
        monochrome[y * widthDots + x] = isBlack ? 1 : 0;
        final quantizationError = adjusted - (isBlack ? 0 : 255);
        currentError[x + 2] += quantizationError * (7 / 16);
        nextError[x] += quantizationError * (3 / 16);
        nextError[x + 1] += quantizationError * (5 / 16);
        nextError[x + 2] += quantizationError * (1 / 16);
      }
      currentError = nextError;
      nextError = Float32List(widthDots + 2);
    }

    final widthBytes = widthDots ~/ 8;
    final raster = Uint8List(widthBytes * image.height);
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < widthDots; x++) {
        if (monochrome[y * widthDots + x] == 1) {
          raster[y * widthBytes + x ~/ 8] |= 0x80 >> (x & 7);
        }
      }
    }

    final output = BytesBuilder(copy: false)
      ..add(const [0x1B, 0x40, 0x1B, 0x61, 0x01]);
    for (var startY = 0; startY < image.height; startY += 255) {
      final remainingRows = image.height - startY;
      final bandHeight = remainingRows < 255 ? remainingRows : 255;
      final startByte = startY * widthBytes;
      final endByte = startByte + bandHeight * widthBytes;
      output
        ..add([
          0x1D,
          0x76,
          0x30,
          0x00,
          widthBytes & 0xFF,
          (widthBytes >> 8) & 0xFF,
          bandHeight,
          0x00,
        ])
        ..add(raster.sublist(startByte, endByte));
    }
    output.add([0x1B, 0x64, 12, 0x1D, 0x56, cutMode.commandValue]);
    return output.takeBytes();
  } finally {
    image?.dispose();
    codec.dispose();
  }
}
