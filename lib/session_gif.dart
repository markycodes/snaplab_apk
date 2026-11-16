import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

Future<File> createSessionGif(List<File> photos) async {
  if (photos.isEmpty || photos.length > 6) {
    throw ArgumentError.value(photos.length, 'photos', 'Choose 1 to 6 frames.');
  }
  final frames = await Future.wait(photos.map((photo) => photo.readAsBytes()));
  final encoded = await compute(_encodeSessionGif, frames);
  final output = File('${photos.first.path}.session.gif');
  await output.writeAsBytes(encoded, flush: true);
  return output;
}

Uint8List _encodeSessionGif(List<Uint8List> frames) {
  const maxDimension = 480;
  final (width, height) = _gifCanvasSize(frames.first, maxDimension);
  final fittedFrames = <img.Image>[];
  for (final bytes in frames) {
    final image = img.decodeImage(bytes);
    if (image == null) {
      throw const FormatException('A captured photo could not be decoded.');
    }
    final oriented = img.bakeOrientation(image);
    fittedFrames.add(
      img.copyResize(
        oriented,
        width: width,
        height: height,
        maintainAspect: true,
        backgroundColor: img.ColorRgb8(0, 0, 0),
        interpolation: img.Interpolation.average,
      ),
    );
  }
  final encoder = img.GifEncoder(repeat: 0, delay: 55);
  final sequence = switch (fittedFrames.length) {
    1 => <img.Image>[fittedFrames.first, fittedFrames.first],
    2 => <img.Image>[fittedFrames.first, fittedFrames.last, fittedFrames.first],
    _ => <img.Image>[
      ...fittedFrames,
      ...fittedFrames.reversed.skip(1).take(fittedFrames.length - 2),
    ],
  };

  for (final frame in sequence) {
    encoder.addFrame(frame, duration: 55);
  }

  final bytes = encoder.finish();
  if (bytes == null || bytes.isEmpty) {
    throw StateError('Could not encode the session GIF.');
  }
  return bytes;
}

(int, int) _gifCanvasSize(Uint8List firstFrame, int maxDimension) {
  final firstImage = img.decodeImage(firstFrame);
  if (firstImage == null) {
    throw const FormatException('A captured photo could not be decoded.');
  }
  final orientedFirst = img.bakeOrientation(firstImage);
  final scale = (maxDimension / orientedFirst.width)
      .clamp(0.0, maxDimension / orientedFirst.height)
      .clamp(0.0, 1.0);
  final width = (orientedFirst.width * scale)
      .round()
      .clamp(1, maxDimension)
      .toInt();
  final height = (orientedFirst.height * scale)
      .round()
      .clamp(1, maxDimension)
      .toInt();
  return (width, height);
}
