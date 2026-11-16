import 'dart:typed_data';

import 'package:image/image.dart' as img;

Uint8List makeWhiteLogoBackgroundTransparent(Uint8List encodedBytes) {
  final decoded = img.decodeImage(encodedBytes);
  if (decoded == null) {
    throw const FormatException(
      'The selected logo image could not be decoded.',
    );
  }

  var image = img.Image(
    width: decoded.width,
    height: decoded.height,
    numChannels: 4,
  );
  img.compositeImage(image, decoded);
  final longestSide = image.width > image.height ? image.width : image.height;
  if (longestSide > 1800) {
    final scale = 1800 / longestSide;
    image = img.copyResize(
      image,
      width: (image.width * scale).round(),
      height: (image.height * scale).round(),
      interpolation: img.Interpolation.average,
    );
  }

  final pixelCount = image.width * image.height;
  final visited = Uint8List(pixelCount);
  final queue = Int32List(pixelCount);
  var head = 0;
  var tail = 0;

  void enqueue(int index) {
    if (visited[index] != 0) return;
    visited[index] = 1;
    queue[tail++] = index;
  }

  for (var x = 0; x < image.width; x++) {
    enqueue(x);
    enqueue((image.height - 1) * image.width + x);
  }
  for (var y = 1; y < image.height - 1; y++) {
    enqueue(y * image.width);
    enqueue(y * image.width + image.width - 1);
  }

  while (head < tail) {
    final index = queue[head++];
    final x = index % image.width;
    final y = index ~/ image.width;
    final pixel = image.getPixel(x, y);
    final red = pixel.r.toInt();
    final green = pixel.g.toInt();
    final blue = pixel.b.toInt();
    final isTransparent = pixel.a == 0;
    final isNearWhite =
        red >= 232 &&
        green >= 232 &&
        blue >= 232 &&
        (red - green).abs() <= 22 &&
        (green - blue).abs() <= 22 &&
        (blue - red).abs() <= 22;
    if (!isTransparent && !isNearWhite) continue;

    image.setPixelRgba(x, y, 0, 0, 0, 0);
    if (x > 0) enqueue(index - 1);
    if (x + 1 < image.width) enqueue(index + 1);
    if (y > 0) enqueue(index - image.width);
    if (y + 1 < image.height) enqueue(index + image.width);
  }

  return Uint8List.fromList(img.encodePng(image));
}
