import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

enum PhotoBorderStyle {
  none,
  classic,
  party,
  elegant,
  christmas,
  valentinesDay,
  halloween,
  newYear,
  birthday,
  wedding,
  easter,
  summer,
  graduation,
  mothersDay,
  lunarNewYear,
  diwali,
  babyShower,
  anniversary,
  custom,
}

const customPhotoImageMaxWidth = 1000;
const customPhotoImageMaxHeight = 1500;

({int width, int height}) customPhotoImageDecodeSize(Uint8List bytes) {
  const pngSignature = <int>[137, 80, 78, 71, 13, 10, 26, 10];
  if (bytes.length < 24) {
    throw const FormatException('Choose a valid PNG border image.');
  }
  for (var index = 0; index < pngSignature.length; index++) {
    if (bytes[index] != pngSignature[index]) {
      throw const FormatException('Choose a valid PNG border image.');
    }
  }
  final pngHeader = ByteData.sublistView(bytes, 16, 24);
  final sourceWidth = pngHeader.getUint32(0, Endian.big);
  final sourceHeight = pngHeader.getUint32(4, Endian.big);
  if (sourceWidth == 0 || sourceHeight == 0) {
    throw const FormatException('Choose a valid PNG border image.');
  }

  final scale = math.min(
    1.0,
    math.min(
      customPhotoImageMaxWidth / sourceWidth,
      customPhotoImageMaxHeight / sourceHeight,
    ),
  );
  return (
    width: math.max(1, (sourceWidth * scale).round()),
    height: math.max(1, (sourceHeight * scale).round()),
  );
}

extension PhotoBorderStyleLabel on PhotoBorderStyle {
  String get label => switch (this) {
    PhotoBorderStyle.none => 'No border',
    PhotoBorderStyle.classic => 'Classic',
    PhotoBorderStyle.party => 'Party',
    PhotoBorderStyle.elegant => 'Elegant',
    PhotoBorderStyle.christmas => 'Christmas',
    PhotoBorderStyle.valentinesDay => "Valentine's Day",
    PhotoBorderStyle.halloween => 'Halloween',
    PhotoBorderStyle.newYear => 'New Year',
    PhotoBorderStyle.birthday => 'Birthday',
    PhotoBorderStyle.wedding => 'Wedding',
    PhotoBorderStyle.easter => 'Easter',
    PhotoBorderStyle.summer => 'Summer',
    PhotoBorderStyle.graduation => 'Graduation',
    PhotoBorderStyle.mothersDay => "Mother's Day",
    PhotoBorderStyle.lunarNewYear => 'Lunar New Year',
    PhotoBorderStyle.diwali => 'Diwali',
    PhotoBorderStyle.babyShower => 'Baby Shower',
    PhotoBorderStyle.anniversary => 'Anniversary',
    PhotoBorderStyle.custom => 'Custom PNG',
  };
}

class PhotoBorderPainter extends CustomPainter {
  const PhotoBorderPainter(this.style);

  final PhotoBorderStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    final unit = math.min(size.width, size.height);
    final bounds = Offset.zero & size;

    switch (style) {
      case PhotoBorderStyle.none:
      case PhotoBorderStyle.custom:
        return;
      case PhotoBorderStyle.classic:
        canvas.drawRect(
          bounds.deflate(unit * 0.025),
          Paint()
            ..color = const Color(0xFFFFB547)
            ..style = PaintingStyle.stroke
            ..strokeWidth = unit * 0.018,
        );
        canvas.drawRect(
          Rect.fromLTWH(0, size.height * 0.87, size.width, size.height * 0.13),
          Paint()..color = const Color(0xFFF6EADB),
        );
        canvas.drawRect(
          Rect.fromLTWH(0, size.height * 0.87, size.width, unit * 0.012),
          Paint()..color = const Color(0xFFFFB547),
        );
      case PhotoBorderStyle.party:
        final colors = <Color>[
          const Color(0xFFFFB547),
          const Color(0xFFFF6885),
          const Color(0xFF72D8C2),
          const Color(0xFF9C88FF),
        ];
        for (var index = 0; index < 32; index++) {
          final x = (index * 73 % 101) / 100 * size.width;
          final y = (index * 47 % 101) / 100 * size.height;
          if (x > size.width * 0.12 &&
              x < size.width * 0.88 &&
              y > size.height * 0.12 &&
              y < size.height * 0.84) {
            continue;
          }
          canvas.drawCircle(
            Offset(x, y),
            unit * (0.008 + index % 3 * 0.002),
            Paint()..color = colors[index % colors.length],
          );
        }
        canvas.drawRect(
          Rect.fromLTWH(0, size.height * 0.87, size.width, size.height * 0.13),
          Paint()..color = const Color(0xFFFFB547),
        );
      case PhotoBorderStyle.elegant:
        final inset = unit * 0.035;
        final line = Paint()
          ..color = const Color(0xFFF7F0E5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = unit * 0.009;
        canvas.drawRect(bounds.deflate(inset), line);
        final cornerPaint = Paint()
          ..color = const Color(0xFFFFB547)
          ..style = PaintingStyle.stroke
          ..strokeWidth = unit * 0.014;
        final corner = unit * 0.09;
        for (final x in <double>[inset, size.width - inset]) {
          for (final y in <double>[inset, size.height - inset]) {
            final left = x == inset;
            final top = y == inset;
            final dx = left ? corner : -corner;
            final dy = top ? corner : -corner;
            canvas.drawLine(Offset(x, y), Offset(x + dx, y), cornerPaint);
            canvas.drawLine(Offset(x, y), Offset(x, y + dy), cornerPaint);
          }
        }
        canvas.drawRect(
          Rect.fromLTWH(0, size.height * 0.87, size.width, size.height * 0.13),
          Paint()..color = const Color(0xCC101114),
        );
      case PhotoBorderStyle.christmas:
      case PhotoBorderStyle.valentinesDay:
      case PhotoBorderStyle.halloween:
      case PhotoBorderStyle.newYear:
      case PhotoBorderStyle.birthday:
      case PhotoBorderStyle.wedding:
      case PhotoBorderStyle.easter:
      case PhotoBorderStyle.summer:
      case PhotoBorderStyle.graduation:
      case PhotoBorderStyle.mothersDay:
      case PhotoBorderStyle.lunarNewYear:
      case PhotoBorderStyle.diwali:
      case PhotoBorderStyle.babyShower:
      case PhotoBorderStyle.anniversary:
        _paintCelebrationFrame(canvas, size, style, unit);
    }
  }

  @override
  bool shouldRepaint(PhotoBorderPainter oldDelegate) =>
      oldDelegate.style != style;
}

void _paintCelebrationFrame(
  Canvas canvas,
  Size size,
  PhotoBorderStyle style,
  double unit,
) {
  final palette = switch (style) {
    PhotoBorderStyle.christmas => (
      primary: const Color(0xFFB32635),
      secondary: const Color(0xFF176B48),
      accent: const Color(0xFFFFD77A),
      footer: const Color(0xFFF8F0DF),
    ),
    PhotoBorderStyle.valentinesDay => (
      primary: const Color(0xFFE84F78),
      secondary: const Color(0xFFFFC4D2),
      accent: const Color(0xFF9C2348),
      footer: const Color(0xFFFFF0F3),
    ),
    PhotoBorderStyle.halloween => (
      primary: const Color(0xFFFF7A24),
      secondary: const Color(0xFF7142A5),
      accent: const Color(0xFF252034),
      footer: const Color(0xFFFFE5C4),
    ),
    PhotoBorderStyle.newYear => (
      primary: const Color(0xFFFFD36B),
      secondary: const Color(0xFFEEEAF8),
      accent: const Color(0xFF28213F),
      footer: const Color(0xFF28213F),
    ),
    PhotoBorderStyle.birthday => (
      primary: const Color(0xFFF35E9B),
      secondary: const Color(0xFF55C8C0),
      accent: const Color(0xFFFFD65C),
      footer: const Color(0xFFFFF1D7),
    ),
    PhotoBorderStyle.wedding => (
      primary: const Color(0xFFC8A86B),
      secondary: const Color(0xFFF7F0E2),
      accent: const Color(0xFF9C8060),
      footer: const Color(0xFFF9F5EC),
    ),
    PhotoBorderStyle.easter => (
      primary: const Color(0xFF9C78D4),
      secondary: const Color(0xFFFFB9C8),
      accent: const Color(0xFF8CCBB4),
      footer: const Color(0xFFFFF2D8),
    ),
    PhotoBorderStyle.summer => (
      primary: const Color(0xFFFFA92F),
      secondary: const Color(0xFF29B7B2),
      accent: const Color(0xFF63B7E8),
      footer: const Color(0xFFFFF1C7),
    ),
    PhotoBorderStyle.graduation => (
      primary: const Color(0xFF28213F),
      secondary: const Color(0xFFFFD36B),
      accent: const Color(0xFFF6F0E5),
      footer: const Color(0xFF28213F),
    ),
    PhotoBorderStyle.mothersDay => (
      primary: const Color(0xFFDF7793),
      secondary: const Color(0xFF7C9E75),
      accent: const Color(0xFFFFE1A8),
      footer: const Color(0xFFFFF3EF),
    ),
    PhotoBorderStyle.lunarNewYear => (
      primary: const Color(0xFFD92D32),
      secondary: const Color(0xFFFFD56A),
      accent: const Color(0xFF8E191F),
      footer: const Color(0xFFFFE7A8),
    ),
    PhotoBorderStyle.diwali => (
      primary: const Color(0xFFFFA62B),
      secondary: const Color(0xFFB13B76),
      accent: const Color(0xFFFFD966),
      footer: const Color(0xFF382252),
    ),
    PhotoBorderStyle.babyShower => (
      primary: const Color(0xFF73BBD2),
      secondary: const Color(0xFFE9A7C0),
      accent: const Color(0xFFFFD980),
      footer: const Color(0xFFF0F8FA),
    ),
    PhotoBorderStyle.anniversary => (
      primary: const Color(0xFFB78B56),
      secondary: const Color(0xFFDA6676),
      accent: const Color(0xFFFFE5B7),
      footer: const Color(0xFFFCF2E7),
    ),
    _ => throw StateError('Not a celebration photo frame: $style'),
  };
  final line = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = unit * 0.014
    ..color = palette.primary;
  canvas.drawRect(boundsOf(size).deflate(unit * 0.025), line);
  canvas.drawRect(
    Rect.fromLTWH(0, size.height * 0.88, size.width, size.height * 0.12),
    Paint()..color = palette.footer,
  );
  canvas.drawRect(
    Rect.fromLTWH(0, size.height * 0.88, size.width, unit * 0.012),
    Paint()..color = palette.primary,
  );

  final positions = <Offset>[
    Offset(size.width * 0.045, size.height * 0.045),
    Offset(size.width * 0.13, size.height * 0.055),
    Offset(size.width * 0.87, size.height * 0.055),
    Offset(size.width * 0.955, size.height * 0.045),
    Offset(size.width * 0.045, size.height * 0.955),
    Offset(size.width * 0.13, size.height * 0.94),
    Offset(size.width * 0.87, size.height * 0.94),
    Offset(size.width * 0.955, size.height * 0.955),
  ];
  for (var index = 0; index < positions.length; index++) {
    _drawCelebrationMotif(
      canvas,
      positions[index],
      unit * (index.isEven ? 0.052 : 0.038),
      style,
      palette.primary,
      palette.secondary,
      palette.accent,
    );
  }

  if (style == PhotoBorderStyle.birthday) {
    final flagPaint = Paint()..color = palette.accent;
    for (var index = 0; index < 9; index++) {
      final x = size.width * (0.21 + index * 0.072);
      final path = Path()
        ..moveTo(x, 0)
        ..lineTo(x + unit * 0.035, 0)
        ..lineTo(x + unit * 0.018, unit * 0.052)
        ..close();
      canvas.drawPath(path, flagPaint);
      if (index.isEven) {
        flagPaint.color = palette.secondary;
      } else {
        flagPaint.color = palette.primary;
      }
    }
  }
}

Rect boundsOf(Size size) => Offset.zero & size;

void _drawCelebrationMotif(
  Canvas canvas,
  Offset center,
  double radius,
  PhotoBorderStyle style,
  Color primary,
  Color secondary,
  Color accent,
) {
  final fill = Paint()..color = primary;
  final detail = Paint()..color = secondary;
  final line = Paint()
    ..color = accent
    ..style = PaintingStyle.stroke
    ..strokeWidth = radius * 0.18;
  switch (style) {
    case PhotoBorderStyle.christmas:
      canvas.drawCircle(center, radius * 0.72, fill..color = secondary);
      canvas.drawCircle(center, radius * 0.36, detail..color = accent);
      for (var arm = 0; arm < 4; arm++) {
        final angle = arm * math.pi / 4;
        final delta = Offset(math.cos(angle), math.sin(angle)) * radius;
        canvas.drawLine(center - delta, center + delta, line);
      }
    case PhotoBorderStyle.valentinesDay:
    case PhotoBorderStyle.mothersDay:
      final heart = Path()
        ..moveTo(center.dx, center.dy + radius * 0.85)
        ..cubicTo(
          center.dx - radius * 1.35,
          center.dy - radius * 0.05,
          center.dx - radius * 0.8,
          center.dy - radius * 1.2,
          center.dx,
          center.dy - radius * 0.48,
        )
        ..cubicTo(
          center.dx + radius * 0.8,
          center.dy - radius * 1.2,
          center.dx + radius * 1.35,
          center.dy - radius * 0.05,
          center.dx,
          center.dy + radius * 0.85,
        )
        ..close();
      canvas.drawPath(heart, fill);
      if (style == PhotoBorderStyle.mothersDay) {
        canvas.drawCircle(center, radius * 0.2, detail..color = accent);
      }
    case PhotoBorderStyle.halloween:
      canvas.drawOval(
        Rect.fromCenter(
          center: center,
          width: radius * 2,
          height: radius * 1.55,
        ),
        fill,
      );
      canvas.drawLine(
        center.translate(0, -radius * 0.72),
        center.translate(radius * 0.12, -radius * 1.05),
        line,
      );
      final eye = Paint()..color = accent;
      canvas.drawCircle(
        center.translate(-radius * 0.38, 0),
        radius * 0.12,
        eye,
      );
      canvas.drawCircle(center.translate(radius * 0.38, 0), radius * 0.12, eye);
      final mouth = Path()
        ..moveTo(center.dx - radius * 0.35, center.dy + radius * 0.3)
        ..lineTo(center.dx + radius * 0.35, center.dy + radius * 0.3)
        ..lineTo(center.dx, center.dy + radius * 0.62)
        ..close();
      canvas.drawPath(mouth, eye);
    case PhotoBorderStyle.newYear:
    case PhotoBorderStyle.graduation:
      _drawStar(canvas, center, radius, fill);
      canvas.drawCircle(center, radius * 0.2, detail..color = accent);
      if (style == PhotoBorderStyle.graduation) {
        final cap = Path()
          ..moveTo(center.dx - radius, center.dy - radius * 0.25)
          ..lineTo(center.dx, center.dy - radius * 0.7)
          ..lineTo(center.dx + radius, center.dy - radius * 0.25)
          ..lineTo(center.dx, center.dy + radius * 0.2)
          ..close();
        canvas.drawPath(cap, fill..color = primary);
        canvas.drawLine(
          center.translate(radius * 0.68, -radius * 0.12),
          center.translate(radius * 0.68, radius * 0.65),
          line,
        );
      }
    case PhotoBorderStyle.birthday:
      canvas.drawCircle(center, radius * 0.35, fill);
      canvas.drawLine(
        center.translate(0, -radius * 0.3),
        center.translate(radius * 0.3, -radius),
        line,
      );
    case PhotoBorderStyle.wedding:
    case PhotoBorderStyle.anniversary:
      canvas.drawCircle(
        center.translate(-radius * 0.38, 0),
        radius * 0.55,
        line,
      );
      canvas.drawCircle(
        center.translate(radius * 0.38, 0),
        radius * 0.55,
        line,
      );
      canvas.drawCircle(center, radius * 0.18, fill..color = primary);
    case PhotoBorderStyle.easter:
      canvas.drawOval(
        Rect.fromCenter(
          center: center,
          width: radius * 1.35,
          height: radius * 1.9,
        ),
        fill,
      );
      canvas.drawLine(
        center.translate(-radius * 0.5, 0),
        center.translate(radius * 0.5, 0),
        line,
      );
      canvas.drawCircle(
        center.translate(0, radius * 0.38),
        radius * 0.12,
        detail,
      );
    case PhotoBorderStyle.summer:
      canvas.drawCircle(center, radius * 0.38, fill);
      for (var ray = 0; ray < 8; ray++) {
        final angle = ray * math.pi / 4;
        final inner = Offset(math.cos(angle), math.sin(angle)) * radius * 0.58;
        final outer = Offset(math.cos(angle), math.sin(angle)) * radius;
        canvas.drawLine(center + inner, center + outer, line);
      }
    case PhotoBorderStyle.lunarNewYear:
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: center,
            width: radius * 1.4,
            height: radius * 1.6,
          ),
          Radius.circular(radius * 0.3),
        ),
        fill,
      );
      canvas.drawLine(
        center.translate(-radius * 0.8, -radius * 0.82),
        center.translate(radius * 0.8, -radius * 0.82),
        line..color = accent,
      );
      canvas.drawLine(
        center.translate(0, radius * 0.8),
        center.translate(0, radius * 1.3),
        line..color = accent,
      );
      canvas.drawCircle(center, radius * 0.25, detail..color = accent);
    case PhotoBorderStyle.diwali:
      final diya = Path()
        ..moveTo(center.dx - radius, center.dy)
        ..quadraticBezierTo(
          center.dx,
          center.dy + radius * 1.2,
          center.dx + radius,
          center.dy,
        )
        ..close();
      canvas.drawPath(diya, fill);
      final flame = Path()
        ..moveTo(center.dx, center.dy - radius)
        ..cubicTo(
          center.dx - radius * 0.6,
          center.dy - radius * 0.1,
          center.dx + radius * 0.6,
          center.dy - radius * 0.1,
          center.dx,
          center.dy - radius,
        )
        ..close();
      canvas.drawPath(flame, detail..color = accent);
    case PhotoBorderStyle.babyShower:
      canvas.drawOval(
        Rect.fromCenter(
          center: center.translate(0, -radius * 0.15),
          width: radius * 1.2,
          height: radius * 1.5,
        ),
        fill,
      );
      canvas.drawPath(
        Path()
          ..moveTo(center.dx - radius * 0.28, center.dy + radius * 0.5)
          ..lineTo(center.dx + radius * 0.28, center.dy + radius * 0.5)
          ..lineTo(center.dx, center.dy + radius * 0.9)
          ..close(),
        fill,
      );
      canvas.drawLine(
        center.translate(0, radius * 0.9),
        center.translate(radius * 0.12, radius * 1.25),
        line,
      );
    case PhotoBorderStyle.none:
    case PhotoBorderStyle.classic:
    case PhotoBorderStyle.party:
    case PhotoBorderStyle.elegant:
    case PhotoBorderStyle.custom:
      return;
  }
}

void _drawStar(Canvas canvas, Offset center, double radius, Paint paint) {
  final path = Path();
  for (var point = 0; point < 10; point++) {
    final angle = -math.pi / 2 + point * math.pi / 5;
    final pointRadius = point.isEven ? radius : radius * 0.42;
    final position =
        center + Offset(math.cos(angle), math.sin(angle)) * pointRadius;
    if (point == 0) {
      path.moveTo(position.dx, position.dy);
    } else {
      path.lineTo(position.dx, position.dy);
    }
  }
  path.close();
  canvas.drawPath(path, paint);
}

Future<void> validateCustomPhotoBorderPng(Uint8List bytes) async {
  await prepareCustomPhotoBorderPng(bytes);
}

Future<Uint8List> prepareCustomPhotoBorderPng(Uint8List bytes) async {
  final targetSize = customPhotoImageDecodeSize(bytes);
  final decoded = img.decodePng(bytes);
  if (decoded == null) {
    throw const FormatException('Choose a valid PNG border image.');
  }
  if (decoded.width == targetSize.width &&
      decoded.height == targetSize.height) {
    return bytes;
  }
  final resized = img.copyResize(
    decoded,
    width: targetSize.width,
    interpolation: img.Interpolation.average,
  );
  return Uint8List.fromList(img.encodePng(resized));
}

Future<File> applyPhotoBorder(
  File photo, {
  required PhotoBorderStyle style,
  String? customOverlayPath,
}) async {
  if (style == PhotoBorderStyle.none) return photo;

  final photoCodec = await ui.instantiateImageCodec(await photo.readAsBytes());
  ui.Image? baseImage;
  ui.Image? overlayImage;
  ui.Codec? overlayCodec;
  try {
    baseImage = (await photoCodec.getNextFrame()).image;
    if (style == PhotoBorderStyle.custom) {
      if (customOverlayPath == null) {
        throw StateError('Choose a custom PNG border in admin settings first.');
      }
      final overlay = File(customOverlayPath);
      if (!await overlay.exists()) {
        throw StateError('The selected custom PNG border could not be found.');
      }
      overlayCodec = await ui.instantiateImageCodec(
        await overlay.readAsBytes(),
      );
      overlayImage = (await overlayCodec.getNextFrame()).image;
    }

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final size = Size(baseImage.width.toDouble(), baseImage.height.toDouble());
    final bounds = Offset.zero & size;
    canvas.drawImageRect(
      baseImage,
      Rect.fromLTWH(0, 0, size.width, size.height),
      bounds,
      Paint()..filterQuality = FilterQuality.high,
    );

    final overlay = overlayImage;
    if (overlay != null) {
      canvas.drawImageRect(
        overlay,
        Rect.fromLTWH(
          0,
          0,
          overlay.width.toDouble(),
          overlay.height.toDouble(),
        ),
        bounds,
        Paint()..filterQuality = FilterQuality.high,
      );
    } else {
      PhotoBorderPainter(style).paint(canvas, size);
    }

    final picture = recorder.endRecording();
    late final ui.Image rendered;
    try {
      rendered = await picture.toImage(baseImage.width, baseImage.height);
    } finally {
      picture.dispose();
    }
    try {
      final png = await rendered.toByteData(format: ui.ImageByteFormat.png);
      if (png == null) {
        throw StateError('Could not encode the bordered photo.');
      }
      final output = File('${photo.path}.bordered.png');
      await output.writeAsBytes(
        png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
        flush: true,
      );
      return output;
    } finally {
      rendered.dispose();
    }
  } finally {
    overlayImage?.dispose();
    overlayCodec?.dispose();
    baseImage?.dispose();
    photoCodec.dispose();
  }
}
