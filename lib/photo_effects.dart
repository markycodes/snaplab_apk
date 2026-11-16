import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

enum PhotoEffect {
  original,
  vivid,
  warm,
  monochrome,
  vintage,
  cartoon,
  soft,
  cool,
  rose,
  matte,
  sepia,
  cinematic,
  pastel,
  fade,
}

extension PhotoEffectLabel on PhotoEffect {
  String get label => switch (this) {
    PhotoEffect.original => 'Original',
    PhotoEffect.vivid => 'Vivid',
    PhotoEffect.warm => 'Warm',
    PhotoEffect.monochrome => 'B&W',
    PhotoEffect.vintage => 'Vintage',
    PhotoEffect.cartoon => 'Cartoon',
    PhotoEffect.soft => 'Soft',
    PhotoEffect.cool => 'Cool',
    PhotoEffect.rose => 'Rose',
    PhotoEffect.matte => 'Matte',
    PhotoEffect.sepia => 'Sepia',
    PhotoEffect.cinematic => 'Cinematic',
    PhotoEffect.pastel => 'Pastel',
    PhotoEffect.fade => 'Fade',
  };
}

Future<File> applyPhotoEffect(
  File photo,
  PhotoEffect effect, {
  int maxWidth = 1600,
}) async {
  if (effect == PhotoEffect.original) return photo;
  if (maxWidth < 1) throw ArgumentError.value(maxWidth, 'maxWidth');

  final bytes = await photo.readAsBytes();
  final codec = await ui.instantiateImageCodec(bytes, targetWidth: maxWidth);
  ui.Image? image;
  try {
    image = (await codec.getNextFrame()).image;
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) throw StateError('Could not read photo pixels.');
    final input = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    final output = await compute(
      _transformPixels,
      _EffectPixelRequest(input, image.width, image.height, effect),
    );

    final descriptor = ui.ImageDescriptor.raw(
      await ui.ImmutableBuffer.fromUint8List(output),
      width: image.width,
      height: image.height,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final resultCodec = await descriptor.instantiateCodec();
    ui.Image? resultImage;
    try {
      resultImage = (await resultCodec.getNextFrame()).image;
      final png = await resultImage.toByteData(format: ui.ImageByteFormat.png);
      if (png == null) throw StateError('Could not encode the photo effect.');
      final previewSuffix = maxWidth < 1600 ? '.preview-$maxWidth' : '';
      final outputFile = File(
        '${photo.path}.${effect.name}$previewSuffix.effect.png',
      );
      await outputFile.writeAsBytes(
        png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
        flush: true,
      );
      return outputFile;
    } finally {
      resultImage?.dispose();
      resultCodec.dispose();
      descriptor.dispose();
    }
  } finally {
    image?.dispose();
    codec.dispose();
  }
}

int _clampColor(num value) => value.round().clamp(0, 255);

int _luminance(int red, int green, int blue) =>
    (red * 299 + green * 587 + blue * 114) ~/ 1000;

int _posterize(int value) => (((value + 32) ~/ 64) * 64).clamp(0, 255);

int _sampleLuminance(Uint8List pixels, int width, int height, int x, int y) {
  final sampleX = x.clamp(0, width - 1);
  final sampleY = y.clamp(0, height - 1);
  final offset = (sampleY * width + sampleX) * 4;
  return _luminance(pixels[offset], pixels[offset + 1], pixels[offset + 2]);
}

class _EffectPixelRequest {
  const _EffectPixelRequest(this.input, this.width, this.height, this.effect);

  final Uint8List input;
  final int width;
  final int height;
  final PhotoEffect effect;
}

Uint8List _transformPixels(_EffectPixelRequest request) {
  final input = request.input;
  final output = Uint8List.fromList(input);
  for (var y = 0; y < request.height; y++) {
    for (var x = 0; x < request.width; x++) {
      final offset = (y * request.width + x) * 4;
      final red = input[offset];
      final green = input[offset + 1];
      final blue = input[offset + 2];
      switch (request.effect) {
        case PhotoEffect.original:
          break;
        case PhotoEffect.vivid:
          output[offset] = _clampColor((red - 128) * 1.25 + 128);
          output[offset + 1] = _clampColor((green - 128) * 1.25 + 128);
          output[offset + 2] = _clampColor((blue - 128) * 1.25 + 128);
        case PhotoEffect.warm:
          output[offset] = _clampColor(red + 22);
          output[offset + 1] = _clampColor(green + 8);
          output[offset + 2] = _clampColor(blue - 18);
        case PhotoEffect.monochrome:
          final gray = _luminance(red, green, blue);
          output[offset] = gray;
          output[offset + 1] = gray;
          output[offset + 2] = gray;
        case PhotoEffect.vintage:
          output[offset] = _clampColor(red * 0.85 + green * 0.1 + 24);
          output[offset + 1] = _clampColor(red * 0.08 + green * 0.82 + 16);
          output[offset + 2] = _clampColor(green * 0.12 + blue * 0.72 + 8);
        case PhotoEffect.cartoon:
          final topLeft = _sampleLuminance(
            input,
            request.width,
            request.height,
            x - 1,
            y - 1,
          );
          final top = _sampleLuminance(
            input,
            request.width,
            request.height,
            x,
            y - 1,
          );
          final topRight = _sampleLuminance(
            input,
            request.width,
            request.height,
            x + 1,
            y - 1,
          );
          final left = _sampleLuminance(
            input,
            request.width,
            request.height,
            x - 1,
            y,
          );
          final right = _sampleLuminance(
            input,
            request.width,
            request.height,
            x + 1,
            y,
          );
          final bottomLeft = _sampleLuminance(
            input,
            request.width,
            request.height,
            x - 1,
            y + 1,
          );
          final bottom = _sampleLuminance(
            input,
            request.width,
            request.height,
            x,
            y + 1,
          );
          final bottomRight = _sampleLuminance(
            input,
            request.width,
            request.height,
            x + 1,
            y + 1,
          );
          final horizontal =
              -topLeft +
              topRight -
              2 * left +
              2 * right -
              bottomLeft +
              bottomRight;
          final vertical =
              -topLeft -
              2 * top -
              topRight +
              bottomLeft +
              2 * bottom +
              bottomRight;
          final edge = horizontal.abs() + vertical.abs() >= 360;
          output[offset] = edge ? 24 : _posterize(red);
          output[offset + 1] = edge ? 20 : _posterize(green);
          output[offset + 2] = edge ? 32 : _posterize(blue);
        case PhotoEffect.soft:
          output[offset] = _clampColor((red - 128) * 0.9 + 128);
          output[offset + 1] = _clampColor((green - 128) * 0.9 + 128);
          output[offset + 2] = _clampColor((blue - 128) * 0.9 + 130);
        case PhotoEffect.cool:
          output[offset] = _clampColor(red - 12);
          output[offset + 1] = _clampColor(green + 2);
          output[offset + 2] = _clampColor(blue + 20);
        case PhotoEffect.rose:
          output[offset] = _clampColor(red + 18);
          output[offset + 1] = _clampColor(green - 4);
          output[offset + 2] = _clampColor(blue + 8);
        case PhotoEffect.matte:
          output[offset] = _clampColor(red * 0.82 + 28);
          output[offset + 1] = _clampColor(green * 0.82 + 28);
          output[offset + 2] = _clampColor(blue * 0.82 + 28);
        case PhotoEffect.sepia:
          output[offset] = _clampColor(
            red * 0.393 + green * 0.769 + blue * 0.189,
          );
          output[offset + 1] = _clampColor(
            red * 0.349 + green * 0.686 + blue * 0.168,
          );
          output[offset + 2] = _clampColor(
            red * 0.272 + green * 0.534 + blue * 0.131,
          );
        case PhotoEffect.cinematic:
          output[offset] = _clampColor((red - 128) * 1.12 + 136);
          output[offset + 1] = _clampColor((green - 128) * 1.08 + 128);
          output[offset + 2] = _clampColor((blue - 128) * 1.12 + 132);
        case PhotoEffect.pastel:
          output[offset] = _clampColor(red * 0.82 + 46);
          output[offset + 1] = _clampColor(green * 0.82 + 46);
          output[offset + 2] = _clampColor(blue * 0.82 + 46);
        case PhotoEffect.fade:
          output[offset] = _clampColor((red - 128) * 0.76 + 34);
          output[offset + 1] = _clampColor((green - 128) * 0.76 + 34);
          output[offset + 2] = _clampColor((blue - 128) * 0.76 + 34);
      }
    }
  }
  return output;
}
