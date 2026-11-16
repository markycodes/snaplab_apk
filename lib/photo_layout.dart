import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'photo_border.dart'
    show PhotoBorderPainter, PhotoBorderStyle, prepareCustomPhotoBorderPng;

import 'package:flutter/services.dart';

enum PhotoLayout { verticalStrip, collage }

const _photoTextFontFamily = 'RobotoMono';

@immutable
class PhotoCropTransform {
  const PhotoCropTransform({this.zoom = 1, this.pan = Offset.zero});

  final double zoom;
  final Offset pan;
}

@immutable
class PhotoSticker {
  const PhotoSticker({
    required this.label,
    this.emoji,
    this.icon,
    this.imagePath,
    this.position = const Offset(0.5, 0.5),
    this.scale = 1,
    this.rotation = 0,
  }) : assert(
         (emoji != null ? 1 : 0) +
                 (icon != null ? 1 : 0) +
                 (imagePath != null ? 1 : 0) ==
             1,
       );

  final String label;
  final String? emoji;
  final IconData? icon;
  final String? imagePath;
  final Offset position;
  final double scale;
  final double rotation;

  PhotoSticker copyWith({Offset? position, double? scale, double? rotation}) =>
      PhotoSticker(
        label: label,
        emoji: emoji,
        icon: icon,
        imagePath: imagePath,
        position: position ?? this.position,
        scale: scale ?? this.scale,
        rotation: rotation ?? this.rotation,
      );
}

PhotoSticker photoStickerForCanvas(PhotoSticker sticker) => sticker.copyWith(
  scale: sticker.scale * (sticker.imagePath == null ? 2 : 1.35),
);

const photoStickerChoices = <PhotoSticker>[
  PhotoSticker(label: 'Heart', emoji: '❤️'),
  PhotoSticker(label: 'Sparkles', emoji: '✨'),
  PhotoSticker(label: 'Smile', emoji: '😊'),
  PhotoSticker(label: 'Star', emoji: '⭐'),
  PhotoSticker(label: 'Party', emoji: '🎉'),
  PhotoSticker(label: 'Flower', emoji: '🌸'),
  PhotoSticker(label: 'Rainbow', emoji: '🌈'),
  PhotoSticker(label: 'Butterfly', emoji: '🦋'),
  PhotoSticker(label: 'Strawberry', emoji: '🍓'),
  PhotoSticker(label: 'Cherries', emoji: '🍒'),
  PhotoSticker(label: 'Watermelon', emoji: '🍉'),
  PhotoSticker(label: 'Milk tea', emoji: '🧋'),
  PhotoSticker(label: 'Teddy bear', emoji: '🧸'),
  PhotoSticker(label: 'Bunny', emoji: '🐰'),
  PhotoSticker(label: 'Crown', emoji: '👑'),
  PhotoSticker(label: 'Gem', emoji: '💎'),
  PhotoSticker(label: 'Sparkling heart', emoji: '💖'),
  PhotoSticker(label: 'Sun', emoji: '☀️'),
  PhotoSticker(label: 'Moon', emoji: '🌙'),
  PhotoSticker(label: 'Balloon', emoji: '🎈'),
  PhotoSticker(label: 'Cake', emoji: '🎂'),
  PhotoSticker(label: 'Bow', emoji: '🎀'),
  PhotoSticker(label: 'Sunglasses', emoji: '🕶️'),
  PhotoSticker(label: 'Camera icon', icon: Icons.camera_alt_rounded),
  PhotoSticker(label: 'Favorite icon', icon: Icons.favorite_rounded),
  PhotoSticker(label: 'Star icon', icon: Icons.star_rounded),
  PhotoSticker(label: 'Celebration icon', icon: Icons.celebration_rounded),
  PhotoSticker(label: 'Music icon', icon: Icons.music_note_rounded),
  PhotoSticker(label: 'Pets icon', icon: Icons.pets_rounded),
  PhotoSticker(label: 'Coffee icon', icon: Icons.local_cafe_rounded),
  PhotoSticker(label: 'Cake icon', icon: Icons.cake_rounded),
  PhotoSticker(label: 'Sun icon', icon: Icons.wb_sunny_rounded),
  PhotoSticker(label: 'Laughing', emoji: '😂'),
  PhotoSticker(label: 'Rolling with laughter', emoji: '🤣'),
  PhotoSticker(label: 'Happy', emoji: '😄'),
  PhotoSticker(label: 'Loved-up', emoji: '🥰'),
  PhotoSticker(label: 'Winking', emoji: '😉'),
  PhotoSticker(label: 'Silly', emoji: '😜'),
  PhotoSticker(label: 'Blowing a kiss', emoji: '😘'),
  PhotoSticker(label: 'Crying', emoji: '😢'),
  PhotoSticker(label: 'Sobbing', emoji: '😭'),
  PhotoSticker(label: 'Sad', emoji: '🙁'),
  PhotoSticker(label: 'Shocked', emoji: '😱'),
  PhotoSticker(label: 'Scared', emoji: '😨'),
  PhotoSticker(label: 'Ghost', emoji: '👻'),
  PhotoSticker(label: 'Monster', emoji: '👹'),
  PhotoSticker(label: 'Angry', emoji: '😡'),
  PhotoSticker(label: 'Nervous', emoji: '😬'),
  PhotoSticker(label: 'Sleepy', emoji: '😴'),
  PhotoSticker(label: 'Clown', emoji: '🤡'),
];

@immutable
class PhotoStickerGeometry {
  const PhotoStickerGeometry._({
    required this.center,
    required this.boxSize,
    required this.glyphSize,
  });

  factory PhotoStickerGeometry.forSize(PhotoSticker sticker, Size imageSize) {
    final center = Offset(
      sticker.position.dx.clamp(0.0, 1.0).toDouble() * imageSize.width,
      sticker.position.dy.clamp(0.0, 1.0).toDouble() * imageSize.height,
    );
    final baseSize = sticker.imagePath != null ? 0.28 : 0.1;
    return PhotoStickerGeometry._(
      center: center,
      boxSize: imageSize.width * baseSize * sticker.scale,
      glyphSize: imageSize.width * 0.1 * sticker.scale * 0.8,
    );
  }

  final Offset center;
  final double boxSize;
  final double glyphSize;
}

Offset photoStickerPositionAfterDrag({
  required Offset startPosition,
  required Offset startFocalPoint,
  required Offset currentFocalPoint,
  required Size canvasSize,
}) {
  if (canvasSize.width <= 0 || canvasSize.height <= 0) {
    throw ArgumentError.value(canvasSize, 'canvasSize');
  }
  final drag = currentFocalPoint - startFocalPoint;
  return Offset(
    (startPosition.dx + drag.dx / canvasSize.width)
        .clamp(0.05, 0.95)
        .toDouble(),
    (startPosition.dy + drag.dy / canvasSize.height)
        .clamp(0.05, 0.95)
        .toDouble(),
  );
}

Future<File> applyPhotoStickers(
  File photo,
  List<PhotoSticker> stickers, {
  DateTime? captureDate,
}) async {
  if (stickers.isEmpty && captureDate == null) return photo;

  final bytes = await photo.readAsBytes();
  final codec = await ui.instantiateImageCodec(bytes);
  ui.Image? image;
  try {
    image = (await codec.getNextFrame()).image;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImage(image, Offset.zero, Paint());
    for (final sticker in stickers) {
      if (sticker.imagePath case final imagePath?) {
        final stickerCodec = await ui.instantiateImageCodec(
          await File(imagePath).readAsBytes(),
        );
        ui.Image? stickerImage;
        try {
          stickerImage = (await stickerCodec.getNextFrame()).image;
          final geometry = PhotoStickerGeometry.forSize(
            sticker,
            Size(image.width.toDouble(), image.height.toDouble()),
          );
          final fittedSize = applyBoxFit(
            BoxFit.contain,
            Size(stickerImage.width.toDouble(), stickerImage.height.toDouble()),
            Size.square(geometry.boxSize),
          ).destination;
          canvas.save();
          canvas.translate(geometry.center.dx, geometry.center.dy);
          canvas.rotate(sticker.rotation);
          canvas.drawImageRect(
            stickerImage,
            Rect.fromLTWH(
              0,
              0,
              stickerImage.width.toDouble(),
              stickerImage.height.toDouble(),
            ),
            Rect.fromCenter(
              center: Offset.zero,
              width: fittedSize.width,
              height: fittedSize.height,
            ),
            Paint()..filterQuality = FilterQuality.high,
          );
          canvas.restore();
        } finally {
          stickerImage?.dispose();
          stickerCodec.dispose();
        }
        continue;
      }
      final geometry = PhotoStickerGeometry.forSize(
        sticker,
        Size(image.width.toDouble(), image.height.toDouble()),
      );
      final style = TextStyle(
        color: Colors.white,
        fontSize: geometry.glyphSize,
        fontFamily: sticker.icon?.fontFamily,
        fontFamilyFallback: sticker.icon?.fontFamilyFallback,
        package: sticker.icon?.fontPackage,
        shadows: const [
          Shadow(color: Color(0x99000000), blurRadius: 8),
          Shadow(color: Color(0x99000000), blurRadius: 2),
        ],
      );
      final painter = TextPainter(
        text: TextSpan(
          text: sticker.emoji ?? String.fromCharCode(sticker.icon!.codePoint),
          style: style,
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      canvas.save();
      canvas.translate(geometry.center.dx, geometry.center.dy);
      canvas.rotate(sticker.rotation);
      painter.paint(canvas, Offset(-painter.width / 2, -painter.height / 2));
      canvas.restore();
    }
    if (captureDate != null) {
      final backgroundColor = await _captureDateBackgroundColor(
        image,
        image.width.toDouble(),
        image.height.toDouble(),
      );
      _drawCaptureDate(
        canvas,
        image.width.toDouble(),
        image.height.toDouble(),
        captureDate,
        backgroundColor,
      );
    }
    final picture = recorder.endRecording();
    ui.Image? output;
    try {
      output = await picture.toImage(image.width, image.height);
      final png = await output.toByteData(format: ui.ImageByteFormat.png);
      if (png == null) throw StateError('Could not encode photo decorations.');
      final suffix = Object.hashAll(
        stickers.map(
          (sticker) => Object.hash(
            sticker.emoji,
            sticker.icon?.codePoint,
            sticker.imagePath,
            sticker.position.dx,
            sticker.position.dy,
            sticker.scale,
            sticker.rotation,
          ),
        ),
      ).toRadixString(16);
      final captureDateSuffix = captureDate == null
          ? ''
          : '-date-${captureDate.year.toString().padLeft(4, '0')}'
                '${captureDate.month.toString().padLeft(2, '0')}'
                '${captureDate.day.toString().padLeft(2, '0')}';
      final result = File(
        '${photo.path}.stickers-$suffix$captureDateSuffix.png',
      );
      await result.writeAsBytes(
        png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
        flush: true,
      );
      return result;
    } finally {
      output?.dispose();
      picture.dispose();
    }
  } finally {
    image?.dispose();
    codec.dispose();
  }
}

extension PhotoLayoutLabel on PhotoLayout {
  String get label => switch (this) {
    PhotoLayout.verticalStrip => 'Photo strip',
    PhotoLayout.collage => 'Collage',
  };
}

List<Rect> photoSlotBounds(
  int photoCount, {
  required PhotoLayout layout,
  PhotoFrameTemplate? frameTemplate,
}) {
  if (photoCount < 1 || photoCount > 5) {
    throw ArgumentError.value(
      photoCount,
      'photoCount',
      'Choose 1 to 5 photos.',
    );
  }
  if (frameTemplate != null) {
    if (frameTemplate.photoCount != photoCount) {
      throw ArgumentError.value(
        photoCount,
        'photoCount',
        'The selected frame requires ${frameTemplate.photoCount} photos.',
      );
    }
    return frameTemplate.photoSlots;
  }

  const margin = 0.045;
  const gap = 0.025;
  const headerHeight = 0.105;
  const footerHeight = 0.13;
  final columns = layout == PhotoLayout.collage && photoCount > 1 ? 2 : 1;
  final rows = (photoCount + columns - 1) ~/ columns;
  final photoWidth = 1 - margin * 2;
  final cellWidth = (photoWidth - gap * (columns - 1)) / columns;
  final cellHeight = cellWidth * 0.78;
  final totalHeight =
      margin * 2 +
      headerHeight +
      footerHeight +
      cellHeight * rows +
      gap * (rows - 1);
  return List<Rect>.generate(photoCount, (index) {
    final row = index ~/ columns;
    final rowStart = row * columns;
    final rowCount = math.min(columns, photoCount - rowStart);
    final column = index % columns + (columns - rowCount) ~/ 2;
    final centeredOffset = columns == 2 && rowCount == 1
        ? (cellWidth + gap) / 2
        : 0.0;
    final left = margin + column * (cellWidth + gap) + centeredOffset;
    final top = margin + headerHeight + row * (cellHeight + gap);
    return Rect.fromLTRB(
      left,
      top / totalHeight,
      left + cellWidth,
      (top + cellHeight) / totalHeight,
    );
  }, growable: false);
}

const classicPhotoFrameTemplates = <PhotoFrameTemplate>[
  PhotoFrameTemplate(
    id: 'classic-landscape-1',
    label: 'Landscape 1 photo',
    assetPath: '',
    classicStyle: true,
    classicAspectRatio: 1.5,
    landscape: true,
    containPhotos: true,
    photoSlots: [Rect.fromLTRB(0.045, 0.20, 0.955, 0.82)],
  ),
  PhotoFrameTemplate(
    id: 'classic-landscape-2',
    label: 'Landscape 2 photos',
    assetPath: '',
    classicStyle: true,
    classicAspectRatio: 1.5,
    landscape: true,
    containPhotos: true,
    photoSlots: [
      Rect.fromLTRB(0.045, 0.20, 0.475, 0.82),
      Rect.fromLTRB(0.525, 0.20, 0.955, 0.82),
    ],
  ),
  PhotoFrameTemplate(
    id: 'classic-landscape-3',
    label: 'Landscape 3 photos',
    assetPath: '',
    classicStyle: true,
    classicAspectRatio: 1.5,
    landscape: true,
    containPhotos: true,
    photoSlots: [
      Rect.fromLTRB(0.04, 0.22, 0.32, 0.80),
      Rect.fromLTRB(0.36, 0.22, 0.64, 0.80),
      Rect.fromLTRB(0.68, 0.22, 0.96, 0.80),
    ],
  ),
  PhotoFrameTemplate(
    id: 'classic-landscape-4',
    label: 'Landscape 4 photos',
    assetPath: '',
    classicStyle: true,
    classicAspectRatio: 1.5,
    landscape: true,
    containPhotos: true,
    photoSlots: [
      Rect.fromLTRB(0.05, 0.20, 0.475, 0.48),
      Rect.fromLTRB(0.525, 0.20, 0.95, 0.48),
      Rect.fromLTRB(0.05, 0.54, 0.475, 0.82),
      Rect.fromLTRB(0.525, 0.54, 0.95, 0.82),
    ],
  ),
  PhotoFrameTemplate(
    id: 'classic-landscape-5',
    label: 'Landscape 5 photos',
    assetPath: '',
    classicStyle: true,
    classicAspectRatio: 1.5,
    landscape: true,
    containPhotos: true,
    photoSlots: [
      Rect.fromLTRB(0.035, 0.21, 0.31, 0.48),
      Rect.fromLTRB(0.3625, 0.21, 0.6375, 0.48),
      Rect.fromLTRB(0.69, 0.21, 0.965, 0.48),
      Rect.fromLTRB(0.20, 0.54, 0.475, 0.81),
      Rect.fromLTRB(0.525, 0.54, 0.80, 0.81),
    ],
  ),
  PhotoFrameTemplate(
    id: 'classic-1',
    label: 'Classic',
    assetPath: '',
    classicStyle: true,
    photoSlots: [Rect.fromLTRB(0.10, 0.205, 0.90, 0.755)],
  ),
  PhotoFrameTemplate(
    id: 'classic-2',
    label: 'Classic',
    assetPath: '',
    classicStyle: true,
    photoSlots: [
      Rect.fromLTRB(0.10, 0.16, 0.90, 0.49),
      Rect.fromLTRB(0.10, 0.51, 0.90, 0.84),
    ],
  ),
  PhotoFrameTemplate(
    id: 'classic-3',
    label: 'Classic',
    assetPath: '',
    classicStyle: true,
    photoSlots: [
      Rect.fromLTRB(0.17, 0.13, 0.83, 0.36),
      Rect.fromLTRB(0.17, 0.385, 0.83, 0.615),
      Rect.fromLTRB(0.17, 0.64, 0.83, 0.87),
    ],
  ),
  PhotoFrameTemplate(
    id: 'classic-4',
    label: 'Classic',
    assetPath: '',
    classicStyle: true,
    photoSlots: [
      Rect.fromLTRB(0.09, 0.195, 0.475, 0.465),
      Rect.fromLTRB(0.525, 0.195, 0.91, 0.465),
      Rect.fromLTRB(0.09, 0.515, 0.475, 0.785),
      Rect.fromLTRB(0.525, 0.515, 0.91, 0.785),
    ],
  ),
  PhotoFrameTemplate(
    id: 'classic-staggered-4',
    label: 'Classic staggered',
    assetPath: '',
    classicStyle: true,
    classicAspectRatio: 0.953,
    photoSlots: [
      Rect.fromLTRB(0.147, 0.143, 0.484, 0.474),
      Rect.fromLTRB(0.152, 0.508, 0.483, 0.827),
      Rect.fromLTRB(0.505, 0.217, 0.862, 0.560),
      Rect.fromLTRB(0.509, 0.602, 0.860, 0.950),
    ],
  ),
  PhotoFrameTemplate(
    id: 'classic-5',
    label: 'Classic',
    assetPath: '',
    classicStyle: true,
    photoSlots: [
      Rect.fromLTRB(0.10, 0.175, 0.475, 0.455),
      Rect.fromLTRB(0.525, 0.175, 0.90, 0.455),
      Rect.fromLTRB(0.10, 0.505, 0.355, 0.785),
      Rect.fromLTRB(0.3725, 0.505, 0.6275, 0.785),
      Rect.fromLTRB(0.645, 0.505, 0.90, 0.785),
    ],
  ),
];

enum LandscapeFrameDesign { coffee, floral, celebration, geometric }

const _landscapePhotoSlots = <int, List<Rect>>{
  1: [Rect.fromLTRB(0.045, 0.20, 0.955, 0.82)],
  2: [
    Rect.fromLTRB(0.045, 0.20, 0.475, 0.82),
    Rect.fromLTRB(0.525, 0.20, 0.955, 0.82),
  ],
  3: [
    Rect.fromLTRB(0.04, 0.22, 0.32, 0.80),
    Rect.fromLTRB(0.36, 0.22, 0.64, 0.80),
    Rect.fromLTRB(0.68, 0.22, 0.96, 0.80),
  ],
  4: [
    Rect.fromLTRB(0.05, 0.20, 0.475, 0.48),
    Rect.fromLTRB(0.525, 0.20, 0.95, 0.48),
    Rect.fromLTRB(0.05, 0.54, 0.475, 0.82),
    Rect.fromLTRB(0.525, 0.54, 0.95, 0.82),
  ],
  5: [
    Rect.fromLTRB(0.035, 0.21, 0.31, 0.48),
    Rect.fromLTRB(0.3625, 0.21, 0.6375, 0.48),
    Rect.fromLTRB(0.69, 0.21, 0.965, 0.48),
    Rect.fromLTRB(0.20, 0.54, 0.475, 0.81),
    Rect.fromLTRB(0.525, 0.54, 0.80, 0.81),
  ],
};

const _landscapeDesignLabels = <LandscapeFrameDesign, String>{
  LandscapeFrameDesign.coffee: 'Coffee',
  LandscapeFrameDesign.floral: 'Floral',
  LandscapeFrameDesign.celebration: 'Celebration',
  LandscapeFrameDesign.geometric: 'Geometric',
};

const _floralLandscapePhotoSlots = <int, List<Rect>>{
  1: [Rect.fromLTRB(0.16, 0.19, 0.84, 0.81)],
  2: [
    Rect.fromLTRB(0.16, 0.17, 0.84, 0.46),
    Rect.fromLTRB(0.16, 0.54, 0.84, 0.83),
  ],
  3: [
    Rect.fromLTRB(0.055, 0.18, 0.57, 0.82),
    Rect.fromLTRB(0.62, 0.18, 0.945, 0.48),
    Rect.fromLTRB(0.62, 0.52, 0.945, 0.82),
  ],
  4: [
    Rect.fromLTRB(0.045, 0.17, 0.30, 0.83),
    Rect.fromLTRB(0.35, 0.17, 0.60, 0.83),
    Rect.fromLTRB(0.65, 0.17, 0.955, 0.48),
    Rect.fromLTRB(0.65, 0.52, 0.955, 0.83),
  ],
  5: [
    Rect.fromLTRB(0.055, 0.18, 0.47, 0.48),
    Rect.fromLTRB(0.055, 0.52, 0.47, 0.82),
    Rect.fromLTRB(0.53, 0.18, 0.945, 0.48),
    Rect.fromLTRB(0.53, 0.52, 0.72, 0.82),
    Rect.fromLTRB(0.755, 0.52, 0.945, 0.82),
  ],
};

const _celebrationLandscapePhotoSlots = <int, List<Rect>>{
  1: [Rect.fromLTRB(0.09, 0.16, 0.91, 0.84)],
  2: [
    Rect.fromLTRB(0.07, 0.20, 0.58, 0.80),
    Rect.fromLTRB(0.64, 0.20, 0.93, 0.80),
  ],
  3: [
    Rect.fromLTRB(0.055, 0.18, 0.38, 0.48),
    Rect.fromLTRB(0.405, 0.18, 0.945, 0.48),
    Rect.fromLTRB(0.20, 0.53, 0.80, 0.82),
  ],
  4: [
    Rect.fromLTRB(0.075, 0.18, 0.46, 0.47),
    Rect.fromLTRB(0.54, 0.18, 0.925, 0.47),
    Rect.fromLTRB(0.075, 0.53, 0.46, 0.82),
    Rect.fromLTRB(0.54, 0.53, 0.925, 0.82),
  ],
  5: [
    Rect.fromLTRB(0.04, 0.18, 0.30, 0.48),
    Rect.fromLTRB(0.37, 0.18, 0.63, 0.48),
    Rect.fromLTRB(0.70, 0.18, 0.96, 0.48),
    Rect.fromLTRB(0.19, 0.53, 0.45, 0.82),
    Rect.fromLTRB(0.55, 0.53, 0.81, 0.82),
  ],
};

const _geometricLandscapePhotoSlots = <int, List<Rect>>{
  1: [Rect.fromLTRB(0.24, 0.17, 0.76, 0.83)],
  2: [
    Rect.fromLTRB(0.08, 0.18, 0.45, 0.82),
    Rect.fromLTRB(0.55, 0.18, 0.92, 0.82),
  ],
  3: [
    Rect.fromLTRB(0.055, 0.20, 0.34, 0.80),
    Rect.fromLTRB(0.36, 0.16, 0.64, 0.84),
    Rect.fromLTRB(0.66, 0.20, 0.945, 0.80),
  ],
  4: [
    Rect.fromLTRB(0.06, 0.18, 0.38, 0.48),
    Rect.fromLTRB(0.42, 0.18, 0.94, 0.48),
    Rect.fromLTRB(0.06, 0.53, 0.58, 0.82),
    Rect.fromLTRB(0.62, 0.53, 0.94, 0.82),
  ],
  5: [
    Rect.fromLTRB(0.045, 0.18, 0.43, 0.82),
    Rect.fromLTRB(0.49, 0.18, 0.70, 0.48),
    Rect.fromLTRB(0.74, 0.18, 0.955, 0.48),
    Rect.fromLTRB(0.49, 0.53, 0.70, 0.82),
    Rect.fromLTRB(0.74, 0.53, 0.955, 0.82),
  ],
};

List<Rect> _landscapeSlotsFor(LandscapeFrameDesign design, int photoCount) =>
    switch (design) {
      LandscapeFrameDesign.coffee => _landscapePhotoSlots[photoCount]!,
      LandscapeFrameDesign.floral => _floralLandscapePhotoSlots[photoCount]!,
      LandscapeFrameDesign.celebration =>
        _celebrationLandscapePhotoSlots[photoCount]!,
      LandscapeFrameDesign.geometric =>
        _geometricLandscapePhotoSlots[photoCount]!,
    };

List<PhotoFrameTemplate> _createLandscapeDesignTemplates() => [
  for (final design in LandscapeFrameDesign.values)
    for (var photoCount = 1; photoCount <= 5; photoCount++)
      PhotoFrameTemplate(
        id: 'landscape-${design.name}-$photoCount',
        label:
            '${_landscapeDesignLabels[design]} $photoCount photo'
            '${photoCount == 1 ? '' : 's'}',
        assetPath: '',
        classicStyle: true,
        classicAspectRatio: 1.5,
        landscape: true,
        containPhotos: true,
        landscapeDesign: design,
        photoSlots: _landscapeSlotsFor(design, photoCount),
      ),
];

final landscapePhotoFrameTemplates = _createLandscapeDesignTemplates();

bool photoLayoutUsesSingleColumn(
  int photoCount, {
  required PhotoLayout layout,
  PhotoFrameTemplate? frameTemplate,
}) {
  final slots = photoSlotBounds(
    photoCount,
    layout: layout,
    frameTemplate: frameTemplate,
  );
  if (slots.length < 2) return true;
  final centers = slots.map((slot) => slot.center.dx);
  return centers.reduce(math.max) - centers.reduce(math.min) <= 0.08;
}

class PhotoFrameTemplate {
  const PhotoFrameTemplate({
    required this.id,
    required this.label,
    required this.assetPath,
    required this.photoSlots,
    this.filePath,
    this.photoSlotRotations = const [],
    this.foregroundArtwork = false,
    this.photoPaintOrder = const [],
    this.photoWindowsFromTransparency = false,
    this.transparencyWindowPaths,
    this.classicStyle = false,
    this.classicHasBranding = true,
    this.classicAspectRatio = 2 / 3,
    this.landscape = false,
    this.containPhotos = false,
    this.landscapeDesign,
  });

  const PhotoFrameTemplate.transparentAsset({
    required String id,
    required String label,
    required String assetPath,
    required List<Rect> photoSlots,
  }) : this(
         id: id,
         label: label,
         assetPath: assetPath,
         photoSlots: photoSlots,
         photoWindowsFromTransparency: true,
       );

  final String id;
  final String label;
  final String assetPath;
  final String? filePath;
  final List<Rect> photoSlots;
  final List<double> photoSlotRotations;
  final bool foregroundArtwork;
  final List<int> photoPaintOrder;
  final bool photoWindowsFromTransparency;
  final List<Path>? transparencyWindowPaths;
  final bool classicStyle;
  final bool classicHasBranding;
  final double classicAspectRatio;
  final bool landscape;
  final bool containPhotos;
  final LandscapeFrameDesign? landscapeDesign;

  int get photoCount => photoSlots.length;

  double rotationForSlot(int index) =>
      index < photoSlotRotations.length ? photoSlotRotations[index] : 0;
}

Rect classicFrameLogoBounds(Size size, PhotoFrameTemplate template) {
  final firstPhotoTop = template.photoSlots
      .map((slot) => slot.top)
      .reduce(math.min);
  final top = size.height * 0.01;
  final bottom = math.max(top, size.height * (firstPhotoTop - 0.01));
  return Rect.fromLTRB(size.width * 0.19, top, size.width * 0.81, bottom);
}

final Map<String, Future<PhotoFrameTemplate>> _customerPhotoFrameTemplates = {};

Future<PhotoFrameTemplate> customerPhotoFrameTemplate(String filePath) =>
    _customerPhotoFrameTemplates.putIfAbsent(
      filePath,
      () => _loadCustomerPhotoFrameTemplate(filePath),
    );

Future<PhotoFrameTemplate> _loadCustomerPhotoFrameTemplate(
  String filePath,
) async {
  final bytes = await prepareCustomPhotoBorderPng(
    await File(filePath).readAsBytes(),
  );
  final codec = await ui.instantiateImageCodec(bytes);
  ui.Image? image;
  try {
    image = (await codec.getNextFrame()).image;
    final pixelData = await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    if (pixelData == null) {
      throw StateError('Could not inspect the uploaded frame transparency.');
    }

    final width = image.width;
    final height = image.height;
    final totalPixels = width * height;
    final componentAt = Int32List(totalPixels)..fillRange(0, totalPixels, -1);
    final queue = Int32List(totalPixels);
    final transparentWindows = <(int, Rect)>[];
    var component = 0;

    for (var start = 0; start < totalPixels; start++) {
      if (componentAt[start] != -1 || pixelData.getUint8(start * 4 + 3) > 32) {
        continue;
      }

      var head = 0;
      var tail = 0;
      var pixelCount = 0;
      var minX = width;
      var maxX = -1;
      var minY = height;
      var maxY = -1;
      var touchesEdge = false;
      componentAt[start] = component;
      queue[tail++] = start;

      while (head < tail) {
        final current = queue[head++];
        final x = current % width;
        final y = current ~/ width;
        pixelCount++;
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
        if (x == 0 || x == width - 1 || y == 0 || y == height - 1) {
          touchesEdge = true;
        }

        void visit(int neighbor) {
          if (componentAt[neighbor] == -1 &&
              pixelData.getUint8(neighbor * 4 + 3) <= 32) {
            componentAt[neighbor] = component;
            queue[tail++] = neighbor;
          }
        }

        if (x > 0) visit(current - 1);
        if (x + 1 < width) visit(current + 1);
        if (y > 0) visit(current - width);
        if (y + 1 < height) visit(current + width);
      }

      final boxWidth = maxX - minX + 1;
      final boxHeight = maxY - minY + 1;
      final boxArea = boxWidth * boxHeight;
      final aspectRatio = boxWidth / boxHeight;
      if (!touchesEdge &&
          pixelCount >= totalPixels * 0.003 &&
          boxArea >= totalPixels * 0.008 &&
          boxWidth >= width * 0.04 &&
          boxHeight >= height * 0.04 &&
          aspectRatio >= 0.18 &&
          aspectRatio <= 5.5) {
        const inset = 2.0;
        final left = (minX + inset).clamp(0, width).toDouble() / width;
        final top = (minY + inset).clamp(0, height).toDouble() / height;
        final right = (maxX + 1 - inset).clamp(0, width).toDouble() / width;
        final bottom = (maxY + 1 - inset).clamp(0, height).toDouble() / height;
        if (right > left && bottom > top) {
          transparentWindows.add((
            component,
            Rect.fromLTRB(left, top, right, bottom),
          ));
        }
      }
      component++;
    }

    if (transparentWindows.isEmpty || transparentWindows.length > 5) {
      throw const FormatException(
        'Frame must have 1 to 5 enclosed transparent photo openings. '
        'Upload a transparent PNG with one opening per photo.',
      );
    }

    transparentWindows.sort((a, b) {
      final verticalOrder = a.$2.center.dy.compareTo(b.$2.center.dy);
      return verticalOrder != 0
          ? verticalOrder
          : a.$2.center.dx.compareTo(b.$2.center.dx);
    });
    final normalizedWindowPaths = <Path>[];
    for (final (windowComponent, _) in transparentWindows) {
      final path = Path();
      for (var y = 0; y < height; y++) {
        var x = 0;
        while (x < width) {
          if (componentAt[y * width + x] != windowComponent) {
            x++;
            continue;
          }
          final startX = x;
          while (x < width && componentAt[y * width + x] == windowComponent) {
            x++;
          }
          path.addRect(
            Rect.fromLTRB(
              startX / width,
              y / height,
              x / width,
              (y + 1) / height,
            ),
          );
        }
      }
      normalizedWindowPaths.add(path);
    }
    final filename = File(filePath).uri.pathSegments.last;
    return PhotoFrameTemplate(
      id: 'customer-${filePath.hashCode.toRadixString(16)}',
      label: filename
          .replaceFirst(RegExp(r'\.[^.]+$'), '')
          .replaceFirst(RegExp(r'^photo_frame_\d+'), 'Frame'),
      assetPath: '',
      filePath: filePath,
      photoSlots: List<Rect>.unmodifiable(
        transparentWindows.map((window) => window.$2),
      ),
      photoWindowsFromTransparency: true,
      landscape: width > height,
      containPhotos: width > height,
      transparencyWindowPaths: List<Path>.unmodifiable(normalizedWindowPaths),
    );
  } finally {
    image?.dispose();
    codec.dispose();
  }
}

const photoFrameTemplates = <PhotoFrameTemplate>[
  PhotoFrameTemplate(
    id: 'newsprint-four',
    label: 'Newsprint',
    assetPath: 'assets/frames/newsprint.png',
    photoSlots: [
      Rect.fromLTRB(0.107, 0.011, 0.921, 0.236),
      Rect.fromLTRB(0.103, 0.249, 0.913, 0.471),
      Rect.fromLTRB(0.099, 0.486, 0.909, 0.710),
      Rect.fromLTRB(0.095, 0.731, 0.905, 0.955),
    ],
  ),
  PhotoFrameTemplate(
    id: 'golden-film-four',
    label: 'Golden film',
    assetPath: 'assets/frames/golden_film_four.png',
    photoSlots: [
      Rect.fromLTRB(0.248, 0.039, 0.711, 0.237),
      Rect.fromLTRB(0.252, 0.273, 0.715, 0.479),
      Rect.fromLTRB(0.256, 0.515, 0.723, 0.721),
      Rect.fromLTRB(0.269, 0.755, 0.731, 0.952),
    ],
  ),
  PhotoFrameTemplate(
    id: 'silver-wedding-four',
    label: 'Silver wedding',
    assetPath: 'assets/frames/silver_wedding_four.png',
    photoSlots: [
      Rect.fromLTRB(0.140, 0.055, 0.849, 0.219),
      Rect.fromLTRB(0.140, 0.257, 0.849, 0.421),
      Rect.fromLTRB(0.140, 0.459, 0.849, 0.623),
      Rect.fromLTRB(0.140, 0.660, 0.849, 0.825),
    ],
  ),
  PhotoFrameTemplate(
    id: 'classical-music-three',
    label: 'Classical music',
    assetPath: 'assets/frames/classical_music_three.png',
    photoSlots: [
      Rect.fromLTRB(0.119, 0.214, 0.781, 0.394),
      Rect.fromLTRB(0.119, 0.428, 0.781, 0.608),
      Rect.fromLTRB(0.114, 0.642, 0.776, 0.822),
    ],
  ),
  PhotoFrameTemplate(
    id: 'memories-three',
    label: 'Memories',
    assetPath: 'assets/frames/memories_three.png',
    photoSlots: [
      Rect.fromLTRB(0.236, 0.095, 0.769, 0.279),
      Rect.fromLTRB(0.236, 0.315, 0.769, 0.490),
      Rect.fromLTRB(0.236, 0.526, 0.765, 0.696),
    ],
  ),
  PhotoFrameTemplate(
    id: 'film-negative-four',
    label: 'Film negative',
    assetPath: 'assets/frames/film_negative_four.png',
    photoSlots: [
      Rect.fromLTRB(0.162, 0.033, 0.845, 0.245),
      Rect.fromLTRB(0.166, 0.273, 0.845, 0.486),
      Rect.fromLTRB(0.162, 0.514, 0.841, 0.728),
      Rect.fromLTRB(0.162, 0.756, 0.841, 0.969),
    ],
  ),
  PhotoFrameTemplate(
    id: 'beige-collage-five',
    label: 'Beige collage',
    assetPath: 'assets/frames/beige_collage_five.png',
    photoSlots: [
      Rect.fromLTRB(0.018, 0.014, 0.571, 0.652),
      Rect.fromLTRB(0.596, 0.014, 0.982, 0.275),
      Rect.fromLTRB(0.596, 0.288, 0.982, 0.662),
      Rect.fromLTRB(0.016, 0.678, 0.399, 0.986),
      Rect.fromLTRB(0.412, 0.673, 0.998, 0.988),
    ],
  ),
  PhotoFrameTemplate(
    id: 'cream-maroon-strip-four',
    label: 'Cream and maroon',
    assetPath: 'assets/frames/cream_maroon_strip_four.png',
    photoSlots: [
      Rect.fromLTRB(0.163, 0.188, 0.844, 0.341),
      Rect.fromLTRB(0.163, 0.357, 0.844, 0.510),
      Rect.fromLTRB(0.163, 0.521, 0.844, 0.674),
      Rect.fromLTRB(0.163, 0.688, 0.844, 0.841),
    ],
  ),
  PhotoFrameTemplate(
    id: 'green-polaroid-three',
    label: 'Green polaroid',
    assetPath: 'assets/frames/green_polaroid_three.png',
    foregroundArtwork: true,
    photoSlots: [
      Rect.fromLTRB(0.200, 0.000, 0.880, 0.365),
      Rect.fromLTRB(0.130, 0.294, 0.825, 0.666),
      Rect.fromLTRB(0.190, 0.630, 0.900, 0.980),
    ],
    photoSlotRotations: [-0.14, 0.14, -0.14],
    photoPaintOrder: [2, 1, 0],
    photoWindowsFromTransparency: true,
  ),
  PhotoFrameTemplate(
    id: 'blue-beige-playful-three',
    label: 'Blue and beige',
    assetPath: 'assets/frames/blue_beige_playful_three.png',
    foregroundArtwork: true,
    photoSlots: [
      Rect.fromLTRB(0.321, 0.071, 0.678, 0.332),
      Rect.fromLTRB(0.321, 0.346, 0.678, 0.610),
      Rect.fromLTRB(0.321, 0.623, 0.678, 0.888),
    ],
  ),
  PhotoFrameTemplate.transparentAsset(
    id: 'friendship-editorial-three-photo',
    label: 'Friendship editorial (3 photos)',
    assetPath: 'assets/frames/friendship-editorial-three-photo.png',
    photoSlots: [
      Rect.fromLTRB(0.118, 0.233, 0.492, 0.445),
      Rect.fromLTRB(0.509, 0.233, 0.883, 0.445),
      Rect.fromLTRB(0.193, 0.465, 0.809, 0.724),
    ],
  ),
  PhotoFrameTemplate.transparentAsset(
    id: 'friendship-editorial-two-photo',
    label: 'Friendship editorial (2 photos)',
    assetPath: 'assets/frames/friendship-editorial-two-photo.png',
    photoSlots: [
      Rect.fromLTRB(0.118, 0.244, 0.492, 0.563),
      Rect.fromLTRB(0.509, 0.376, 0.883, 0.695),
    ],
  ),
  PhotoFrameTemplate.transparentAsset(
    id: 'friendship-frame-three-photo',
    label: 'Friendship frame (3 photos)',
    assetPath: 'assets/frames/friendship-frame-three-photo.png',
    photoSlots: [
      Rect.fromLTRB(0.147, 0.136, 0.527, 0.440),
      Rect.fromLTRB(0.547, 0.136, 0.854, 0.309),
      Rect.fromLTRB(0.547, 0.319, 0.854, 0.492),
    ],
  ),
  PhotoFrameTemplate.transparentAsset(
    id: 'friendship-frame-transparent',
    label: 'Friendship collage (4 photos)',
    assetPath: 'assets/frames/friendship-frame-transparent.png',
    photoSlots: [
      Rect.fromLTRB(0.155, 0.137, 0.569, 0.373),
      Rect.fromLTRB(0.591, 0.137, 0.859, 0.290),
      Rect.fromLTRB(0.590, 0.298, 0.859, 0.449),
      Rect.fromLTRB(0.155, 0.386, 0.423, 0.539),
    ],
  ),
  PhotoFrameTemplate.transparentAsset(
    id: 'friendship-frame-two-photo',
    label: 'Friendship frame (2 photos)',
    assetPath: 'assets/frames/friendship-frame-two-photo.png',
    photoSlots: [
      Rect.fromLTRB(0.147, 0.136, 0.508, 0.440),
      Rect.fromLTRB(0.530, 0.136, 0.854, 0.440),
    ],
  ),
  PhotoFrameTemplate.transparentAsset(
    id: 'minimal-friendship-frame-three-photo',
    label: 'Minimal friendship (3 photos)',
    assetPath: 'assets/frames/minimal-friendship-frame-three-photo.png',
    photoSlots: [
      Rect.fromLTRB(0.135, 0.108, 0.540, 0.461),
      Rect.fromLTRB(0.568, 0.108, 0.866, 0.278),
      Rect.fromLTRB(0.568, 0.291, 0.866, 0.461),
    ],
  ),
  PhotoFrameTemplate.transparentAsset(
    id: 'minimal-friendship-frame-two-photo',
    label: 'Minimal friendship (2 photos)',
    assetPath: 'assets/frames/minimal-friendship-frame-two-photo.png',
    photoSlots: [
      Rect.fromLTRB(0.135, 0.108, 0.474, 0.461),
      Rect.fromLTRB(0.527, 0.108, 0.866, 0.461),
    ],
  ),
  PhotoFrameTemplate.transparentAsset(
    id: 'receipt-friendship-frame-1',
    label: 'Friendship receipt (1 photo)',
    assetPath: 'assets/frames/receipt-friendship-frame-1.png',
    photoSlots: [Rect.fromLTRB(0.151, 0.234, 0.850, 0.661)],
  ),
  PhotoFrameTemplate.transparentAsset(
    id: 'receipt-friendship-frame-2',
    label: 'Friendship receipt (2 photos)',
    assetPath: 'assets/frames/receipt-friendship-frame-2.png',
    photoSlots: [
      Rect.fromLTRB(0.148, 0.237, 0.499, 0.613),
      Rect.fromLTRB(0.529, 0.285, 0.853, 0.662),
    ],
  ),
  PhotoFrameTemplate.transparentAsset(
    id: 'receipt-friendship-frame-3',
    label: 'Friendship receipt (3 photos)',
    assetPath: 'assets/frames/receipt-friendship-frame-3.png',
    photoSlots: [
      Rect.fromLTRB(0.146, 0.237, 0.551, 0.588),
      Rect.fromLTRB(0.581, 0.237, 0.853, 0.402),
      Rect.fromLTRB(0.581, 0.421, 0.853, 0.588),
    ],
  ),
  PhotoFrameTemplate.transparentAsset(
    id: 'receipt-friendship-frame-4',
    label: 'Friendship receipt (4 photos)',
    assetPath: 'assets/frames/receipt-friendship-frame-4.png',
    photoSlots: [
      Rect.fromLTRB(0.146, 0.237, 0.484, 0.399),
      Rect.fromLTRB(0.514, 0.237, 0.853, 0.399),
      Rect.fromLTRB(0.146, 0.417, 0.484, 0.579),
      Rect.fromLTRB(0.514, 0.417, 0.853, 0.579),
    ],
  ),
  PhotoFrameTemplate.transparentAsset(
    id: 'receipt-friendship-frame-5',
    label: 'Friendship receipt (5 photos)',
    assetPath: 'assets/frames/receipt-friendship-frame-5.png',
    photoSlots: [
      Rect.fromLTRB(0.146, 0.237, 0.361, 0.396),
      Rect.fromLTRB(0.392, 0.237, 0.607, 0.396),
      Rect.fromLTRB(0.638, 0.237, 0.853, 0.396),
      Rect.fromLTRB(0.194, 0.414, 0.484, 0.589),
      Rect.fromLTRB(0.514, 0.414, 0.805, 0.589),
    ],
  ),
  PhotoFrameTemplate.transparentAsset(
    id: 'snaplab-empty-editorial',
    label: 'Editorial receipt',
    assetPath: 'assets/frames/snaplab-empty-editorial-frame.png',
    photoSlots: [
      Rect.fromLTRB(0.107, 0.190, 0.895, 0.368),
      Rect.fromLTRB(0.107, 0.387, 0.895, 0.565),
      Rect.fromLTRB(0.107, 0.652, 0.895, 0.831),
    ],
  ),
  PhotoFrameTemplate.transparentAsset(
    id: 'snaplab-empty-editorial-three-photo',
    label: 'Editorial (3 photos)',
    assetPath: 'assets/frames/snaplab-empty-editorial-three-photo-frame.png',
    photoSlots: [
      Rect.fromLTRB(0.107, 0.189, 0.895, 0.357),
      Rect.fromLTRB(0.107, 0.386, 0.895, 0.553),
      Rect.fromLTRB(0.107, 0.649, 0.895, 0.817),
    ],
  ),
  PhotoFrameTemplate.transparentAsset(
    id: 'snaplab-empty-memory-receipt',
    label: 'Memory receipt',
    assetPath: 'assets/frames/snaplab-empty-memory-receipt-frame.png',
    photoSlots: [
      Rect.fromLTRB(0.107, 0.211, 0.895, 0.390),
      Rect.fromLTRB(0.107, 0.417, 0.895, 0.597),
      Rect.fromLTRB(0.107, 0.624, 0.895, 0.803),
    ],
  ),
  PhotoFrameTemplate.transparentAsset(
    id: 'snaplab-empty-photo-receipt',
    label: 'Photo receipt',
    assetPath: 'assets/frames/snaplab-empty-photo-receipt-frame.png',
    photoSlots: [
      Rect.fromLTRB(0.107, 0.202, 0.895, 0.398),
      Rect.fromLTRB(0.107, 0.424, 0.895, 0.621),
      Rect.fromLTRB(0.107, 0.647, 0.895, 0.843),
    ],
  ),
  PhotoFrameTemplate.transparentAsset(
    id: 'snaplab-good-vibes-long-one-photo',
    label: 'Good vibes',
    assetPath: 'assets/frames/snaplab-good-vibes-long-one-photo.png',
    photoSlots: [Rect.fromLTRB(0.111, 0.126, 0.891, 0.601)],
  ),
  PhotoFrameTemplate.transparentAsset(
    id: 'snaplab-love-three-photo',
    label: 'Love (3 photos)',
    assetPath: 'assets/frames/snaplab-love-three-photo.png',
    photoSlots: [
      Rect.fromLTRB(0.126, 0.163, 0.486, 0.776),
      Rect.fromLTRB(0.516, 0.163, 0.875, 0.460),
      Rect.fromLTRB(0.516, 0.478, 0.875, 0.776),
    ],
  ),
  PhotoFrameTemplate.transparentAsset(
    id: 'snaplab-love-two-photo',
    label: 'Love (2 photos)',
    assetPath: 'assets/frames/snaplab-love-two-photo.png',
    photoSlots: [
      Rect.fromLTRB(0.126, 0.163, 0.486, 0.776),
      Rect.fromLTRB(0.516, 0.163, 0.875, 0.776),
    ],
  ),
  PhotoFrameTemplate.transparentAsset(
    id: 'snaplab-minimal-three-photo',
    label: 'Minimal (3 photos)',
    assetPath: 'assets/frames/snaplab-minimal-three-photo.png',
    photoSlots: [
      Rect.fromLTRB(0.126, 0.141, 0.486, 0.793),
      Rect.fromLTRB(0.516, 0.141, 0.875, 0.457),
      Rect.fromLTRB(0.516, 0.477, 0.875, 0.793),
    ],
  ),
  PhotoFrameTemplate.transparentAsset(
    id: 'snaplab-minimal-two-photo',
    label: 'Minimal (2 photos)',
    assetPath: 'assets/frames/snaplab-minimal-two-photo.png',
    photoSlots: [
      Rect.fromLTRB(0.126, 0.141, 0.486, 0.793),
      Rect.fromLTRB(0.516, 0.141, 0.875, 0.793),
    ],
  ),
  PhotoFrameTemplate.transparentAsset(
    id: 'snaplab-theme-1-photo',
    label: 'SnapLab theme 1',
    assetPath: 'assets/frames/snaplab-theme-1-photo.png',
    photoSlots: [Rect.fromLTRB(0.292, 0.308, 0.710, 0.589)],
  ),
  PhotoFrameTemplate.transparentAsset(
    id: 'snaplab-theme-2-photo',
    label: 'SnapLab theme 2',
    assetPath: 'assets/frames/snaplab-theme-2-photo.png',
    photoSlots: [
      Rect.fromLTRB(0.126, 0.308, 0.419, 0.589),
      Rect.fromLTRB(0.582, 0.308, 0.875, 0.589),
    ],
  ),
  PhotoFrameTemplate.transparentAsset(
    id: 'snaplab-theme-3-photo',
    label: 'SnapLab theme 3',
    assetPath: 'assets/frames/snaplab-theme-3-photo.png',
    photoSlots: [
      Rect.fromLTRB(0.126, 0.308, 0.507, 0.589),
      Rect.fromLTRB(0.543, 0.308, 0.875, 0.439),
      Rect.fromLTRB(0.543, 0.458, 0.875, 0.589),
    ],
  ),
  PhotoFrameTemplate.transparentAsset(
    id: 'snaplab-theme-4-photo',
    label: 'SnapLab theme 4',
    assetPath: 'assets/frames/snaplab-theme-4-photo.png',
    photoSlots: [
      Rect.fromLTRB(0.126, 0.308, 0.419, 0.437),
      Rect.fromLTRB(0.582, 0.308, 0.875, 0.437),
      Rect.fromLTRB(0.126, 0.456, 0.419, 0.589),
      Rect.fromLTRB(0.582, 0.456, 0.875, 0.589),
    ],
  ),
  PhotoFrameTemplate.transparentAsset(
    id: 'snaplab-theme-5-photo',
    label: 'SnapLab theme 5',
    assetPath: 'assets/frames/snaplab-theme-5-photo.png',
    photoSlots: [
      Rect.fromLTRB(0.126, 0.308, 0.457, 0.589),
      Rect.fromLTRB(0.495, 0.308, 0.673, 0.437),
      Rect.fromLTRB(0.697, 0.308, 0.875, 0.437),
      Rect.fromLTRB(0.495, 0.456, 0.673, 0.589),
      Rect.fromLTRB(0.697, 0.456, 0.875, 0.589),
    ],
  ),
  PhotoFrameTemplate.transparentAsset(
    id: 'snaplab-travel-receipt-1-photo',
    label: 'Travel receipt (1 photo)',
    assetPath: 'assets/frames/snaplab-travel-receipt-1-photo.png',
    photoSlots: [Rect.fromLTRB(0.292, 0.309, 0.710, 0.589)],
  ),
  PhotoFrameTemplate.transparentAsset(
    id: 'snaplab-travel-receipt-2-photo',
    label: 'Travel receipt (2 photos)',
    assetPath: 'assets/frames/snaplab-travel-receipt-2-photo.png',
    photoSlots: [
      Rect.fromLTRB(0.126, 0.309, 0.419, 0.589),
      Rect.fromLTRB(0.582, 0.309, 0.875, 0.589),
    ],
  ),
  PhotoFrameTemplate.transparentAsset(
    id: 'snaplab-travel-receipt-3-photo',
    label: 'Travel receipt (3 photos)',
    assetPath: 'assets/frames/snaplab-travel-receipt-3-photo.png',
    photoSlots: [
      Rect.fromLTRB(0.126, 0.309, 0.507, 0.589),
      Rect.fromLTRB(0.543, 0.309, 0.875, 0.439),
      Rect.fromLTRB(0.543, 0.458, 0.875, 0.589),
    ],
  ),
  PhotoFrameTemplate.transparentAsset(
    id: 'snaplab-travel-receipt-4-photo',
    label: 'Travel receipt (4 photos)',
    assetPath: 'assets/frames/snaplab-travel-receipt-4-photo.png',
    photoSlots: [
      Rect.fromLTRB(0.126, 0.309, 0.419, 0.439),
      Rect.fromLTRB(0.582, 0.309, 0.875, 0.439),
      Rect.fromLTRB(0.126, 0.458, 0.419, 0.589),
      Rect.fromLTRB(0.582, 0.458, 0.875, 0.589),
    ],
  ),
  PhotoFrameTemplate.transparentAsset(
    id: 'snaplab-travel-receipt-5-photo',
    label: 'Travel receipt (5 photos)',
    assetPath: 'assets/frames/snaplab-travel-receipt-5-photo.png',
    photoSlots: [
      Rect.fromLTRB(0.126, 0.309, 0.457, 0.589),
      Rect.fromLTRB(0.495, 0.309, 0.673, 0.439),
      Rect.fromLTRB(0.697, 0.309, 0.875, 0.439),
      Rect.fromLTRB(0.495, 0.458, 0.673, 0.589),
      Rect.fromLTRB(0.697, 0.458, 0.875, 0.589),
    ],
  ),
];

List<PhotoFrameTemplate> frameTemplatesForOrientation(
  int photoCount, {
  required bool landscape,
  Iterable<PhotoFrameTemplate> customerTemplates = const [],
}) =>
    <PhotoFrameTemplate>[
          ...classicPhotoFrameTemplates,
          ...landscapePhotoFrameTemplates,
          ...photoFrameTemplates,
          ...customerTemplates,
        ]
        .where(
          (template) =>
              template.photoCount == photoCount &&
              template.landscape == landscape,
        )
        .toList(growable: false);

PhotoFrameTemplate? photoFrameTemplateById(String? id) {
  if (id == null) return null;
  for (final template in classicPhotoFrameTemplates) {
    if (template.id == id) return template;
  }
  for (final template in landscapePhotoFrameTemplates) {
    if (template.id == id) return template;
  }
  for (final template in photoFrameTemplates) {
    if (template.id == id) return template;
  }
  return null;
}

final Map<String, Future<List<Path>>> _photoWindowPaths = {};

Color landscapeFrameAccent(LandscapeFrameDesign design) => switch (design) {
  LandscapeFrameDesign.coffee => const Color(0xFF8A5738),
  LandscapeFrameDesign.floral => const Color(0xFFB85C77),
  LandscapeFrameDesign.celebration => const Color(0xFF327A73),
  LandscapeFrameDesign.geometric => const Color(0xFF426AA3),
};

void paintLandscapeFrameDesign(
  Canvas canvas,
  Size size,
  PhotoFrameTemplate template,
) {
  final design = template.landscapeDesign;
  if (design == null) return;
  final accent = landscapeFrameAccent(design);
  final outerPaint = Paint()
    ..color = accent
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(2, size.width * 0.009);
  final bounds = Offset.zero & size;
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      bounds.deflate(size.width * 0.018),
      Radius.circular(
        design == LandscapeFrameDesign.geometric ? 0 : size.width * 0.025,
      ),
    ),
    outerPaint,
  );
  for (final slot in template.photoSlots) {
    final photoBounds = Rect.fromLTRB(
      slot.left * size.width,
      slot.top * size.height,
      slot.right * size.width,
      slot.bottom * size.height,
    );
    final frameBounds = photoBounds.inflate(size.width * 0.012);
    final framePaint = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2, size.width * 0.006);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        frameBounds,
        Radius.circular(
          design == LandscapeFrameDesign.coffee ? size.width * 0.018 : 0,
        ),
      ),
      framePaint,
    );

    if (design == LandscapeFrameDesign.floral ||
        design == LandscapeFrameDesign.celebration) {
      final dotPaint = Paint()
        ..color = design == LandscapeFrameDesign.floral
            ? const Color(0xFFE4A9B9)
            : const Color(0xFFE4B65D);
      final radius = math.max(2, size.width * 0.009).toDouble();
      for (final corner in [
        frameBounds.topLeft,
        frameBounds.topRight,
        frameBounds.bottomLeft,
        frameBounds.bottomRight,
      ]) {
        canvas.drawCircle(corner, radius, dotPaint);
      }
    } else if (design == LandscapeFrameDesign.coffee) {
      final beanPaint = Paint()
        ..color = const Color(0xFFB9825B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, size.width * 0.003);
      for (final corner in [frameBounds.topLeft, frameBounds.bottomRight]) {
        final bean = Rect.fromCenter(
          center: corner,
          width: size.width * 0.026,
          height: size.width * 0.014,
        );
        canvas.drawOval(bean, beanPaint);
        canvas.drawLine(
          Offset(bean.left + bean.width * 0.25, bean.bottom),
          Offset(bean.right - bean.width * 0.25, bean.top),
          beanPaint,
        );
      }
    }
  }
}

Future<List<Path>> photoWindowPathsForTemplate(PhotoFrameTemplate template) {
  if (!template.photoWindowsFromTransparency) {
    throw ArgumentError.value(
      template.id,
      'template',
      'This frame does not use transparency-defined photo windows.',
    );
  }
  if (template.transparencyWindowPaths case final paths?) {
    return Future<List<Path>>.value(paths);
  }
  return _photoWindowPaths.putIfAbsent(
    template.assetPath,
    () => _loadPhotoWindowPaths(template),
  );
}

Future<List<Path>> _loadPhotoWindowPaths(PhotoFrameTemplate template) async {
  final data = await rootBundle.load(template.assetPath);
  final codec = await ui.instantiateImageCodec(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
  );
  ui.Image? image;
  try {
    image = (await codec.getNextFrame()).image;
    final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (pixels == null) {
      throw StateError('Could not read ${template.label} frame transparency.');
    }
    final width = image.width;
    final height = image.height;
    final labels = Int32List(width * height)..fillRange(0, width * height, -1);
    final componentSizes = <int>[];
    final componentCenters = <Offset>[];
    final queue = <int>[];

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final start = y * width + x;
        if (labels[start] != -1 || pixels.getUint8(start * 4 + 3) != 0) {
          continue;
        }
        final component = componentSizes.length;
        var count = 0;
        var sumX = 0.0;
        var sumY = 0.0;
        queue
          ..clear()
          ..add(start);
        labels[start] = component;
        while (queue.isNotEmpty) {
          final current = queue.removeLast();
          final currentX = current % width;
          final currentY = current ~/ width;
          count++;
          sumX += currentX;
          sumY += currentY;

          void visit(int neighbor) {
            if (labels[neighbor] == -1 &&
                pixels.getUint8(neighbor * 4 + 3) == 0) {
              labels[neighbor] = component;
              queue.add(neighbor);
            }
          }

          if (currentX > 0) visit(current - 1);
          if (currentX + 1 < width) visit(current + 1);
          if (currentY > 0) visit(current - width);
          if (currentY + 1 < height) visit(current + width);
        }
        componentSizes.add(count);
        componentCenters.add(
          Offset(sumX / count / width, sumY / count / height),
        );
      }
    }

    final componentToWindow = <int, int>{};
    for (var component = 0; component < componentSizes.length; component++) {
      if (componentSizes[component] < 2000) continue;
      final center = componentCenters[component];
      var nearestWindow = 0;
      var nearestDistance = double.infinity;
      for (var index = 0; index < template.photoSlots.length; index++) {
        final distance = (template.photoSlots[index].center - center).distance;
        if (distance < nearestDistance) {
          nearestDistance = distance;
          nearestWindow = index;
        }
      }
      componentToWindow[component] = nearestWindow;
    }

    final paths = List<Path>.generate(
      template.photoSlots.length,
      (_) => Path(),
    );
    for (var y = 0; y < height; y++) {
      var x = 0;
      while (x < width) {
        final component = labels[y * width + x];
        final window = componentToWindow[component];
        if (window == null ||
            !_isPhotoWindowInterior(labels, width, height, x, y, component)) {
          x++;
          continue;
        }
        final startX = x;
        while (x < width &&
            componentToWindow[labels[y * width + x]] == window &&
            _isPhotoWindowInterior(labels, width, height, x, y, component)) {
          x++;
        }
        paths[window].addRect(
          Rect.fromLTRB(
            startX / width,
            y / height,
            x / width,
            (y + 1) / height,
          ),
        );
      }
    }
    return List<Path>.unmodifiable(paths);
  } finally {
    image?.dispose();
    codec.dispose();
  }
}

bool _isPhotoWindowInterior(
  Int32List labels,
  int width,
  int height,
  int x,
  int y,
  int component,
) {
  const inset = 5;
  for (var offsetY = -inset; offsetY <= inset; offsetY++) {
    final neighborY = y + offsetY;
    if (neighborY < 0 || neighborY >= height) return false;
    for (var offsetX = -inset; offsetX <= inset; offsetX++) {
      final neighborX = x + offsetX;
      if (neighborX < 0 ||
          neighborX >= width ||
          labels[neighborY * width + neighborX] != component) {
        return false;
      }
    }
  }
  return true;
}

class PhotoWindowClipper extends CustomClipper<Path> {
  const PhotoWindowClipper(this.normalizedPath);

  final Path normalizedPath;

  @override
  Path getClip(Size size) {
    final transform = Float64List(16);
    transform[0] = size.width;
    transform[5] = size.height;
    transform[10] = 1;
    transform[15] = 1;
    return normalizedPath.transform(transform);
  }

  @override
  bool shouldReclip(covariant PhotoWindowClipper oldClipper) =>
      !identical(normalizedPath, oldClipper.normalizedPath);
}

Future<File> composePhotoStrip(
  List<File> photos, {
  PhotoLayout layout = PhotoLayout.verticalStrip,
  Color borderColor = const Color(0xFFFFFFFF),
  String? framePath,
  PhotoFrameTemplate? frameTemplate,
  String? brandLogoPath,
  PhotoBorderStyle photoBorderStyle = PhotoBorderStyle.none,
  String? photoBorderOverlayPath,
  DateTime? captureDate,
  bool mirrorPhotos = false,
  List<PhotoCropTransform> photoTransforms = const [],
}) async {
  if (photos.isEmpty || photos.length > 5) {
    throw ArgumentError.value(photos.length, 'photos', 'Choose 1 to 5 photos.');
  }
  if (framePath != null && frameTemplate != null) {
    throw ArgumentError(
      'Choose either a custom frame or a photo-slot frame template.',
    );
  }
  if (frameTemplate != null && photos.length != frameTemplate.photoCount) {
    throw ArgumentError.value(
      photos.length,
      'photos',
      'The selected frame requires ${frameTemplate.photoCount} photos.',
    );
  }
  if (photoTransforms.isNotEmpty && photoTransforms.length != photos.length) {
    throw ArgumentError.value(
      photoTransforms.length,
      'photoTransforms',
      'Provide one crop transform per photo.',
    );
  }

  final codecs = <ui.Codec>[];
  final images = <ui.Image>[];
  ui.Codec? templateCodec;
  ui.Image? templateImage;
  ui.Codec? brandLogoCodec;
  ui.Image? brandLogoImage;
  ui.Codec? framePathCodec;
  ui.Image? framePathImage;
  ui.Codec? photoBorderCodec;
  ui.Image? photoBorderImage;
  List<Path>? windowPaths;
  var captureDateRenderedInHeader = false;
  try {
    for (final photo in photos) {
      final codec = await ui.instantiateImageCodec(await photo.readAsBytes());
      codecs.add(codec);
      images.add((await codec.getNextFrame()).image);
    }

    if (frameTemplate != null && !frameTemplate.classicStyle) {
      if (frameTemplate.filePath case final filePath?) {
        templateCodec = await ui.instantiateImageCodec(
          await File(filePath).readAsBytes(),
        );
      } else {
        final frameData = await rootBundle.load(frameTemplate.assetPath);
        templateCodec = await ui.instantiateImageCodec(
          frameData.buffer.asUint8List(
            frameData.offsetInBytes,
            frameData.lengthInBytes,
          ),
        );
      }
      templateImage = (await templateCodec.getNextFrame()).image;
      if (frameTemplate.photoWindowsFromTransparency) {
        windowPaths = await photoWindowPathsForTemplate(frameTemplate);
      }
    }

    if (framePath != null) {
      final frameFile = File(framePath);
      if (!await frameFile.exists()) {
        throw StateError('The selected customer PNG frame could not be found.');
      }
      final frameBytes = await prepareCustomPhotoBorderPng(
        await frameFile.readAsBytes(),
      );
      framePathCodec = await ui.instantiateImageCodec(frameBytes);
      framePathImage = (await framePathCodec.getNextFrame()).image;
    }
    final needsExternalFrameHeader =
        framePath != null ||
        frameTemplate != null &&
            (!frameTemplate.classicStyle || !frameTemplate.classicHasBranding);
    final needsBrandLogo =
        frameTemplate == null ||
        needsExternalFrameHeader ||
        frameTemplate.classicStyle && frameTemplate.classicHasBranding;
    if (needsBrandLogo) {
      if (brandLogoPath != null) {
        final logoFile = File(brandLogoPath);
        if (!await logoFile.exists()) {
          throw StateError('The selected brand logo could not be found.');
        }
        brandLogoCodec = await ui.instantiateImageCodec(
          await logoFile.readAsBytes(),
        );
      } else {
        final logoData = await rootBundle.load('assets/photobooth_logo.png');
        brandLogoCodec = await ui.instantiateImageCodec(
          logoData.buffer.asUint8List(
            logoData.offsetInBytes,
            logoData.lengthInBytes,
          ),
        );
      }
      brandLogoImage = (await brandLogoCodec.getNextFrame()).image;
    }

    final width = images.first.width;
    final margin = width * 0.045;
    final gap = width * 0.025;
    final headerHeight = width * 0.16;
    final footerHeight = width * 0.13;
    final photoWidth = width - margin * 2;
    final columns = layout == PhotoLayout.collage && photos.length > 1 ? 2 : 1;
    final rows = (photos.length + columns - 1) ~/ columns;
    final cellWidth = (photoWidth - gap * (columns - 1)) / columns;
    final cellHeight = cellWidth * 0.78;
    final selectedFrameImage = templateImage ?? framePathImage;
    final height = frameTemplate?.classicStyle == true
        ? (width / frameTemplate!.classicAspectRatio).round()
        : selectedFrameImage == null
        ? (margin * 2 +
                  headerHeight +
                  footerHeight +
                  cellHeight * rows +
                  gap * (rows - 1))
              .ceil()
        : (width * selectedFrameImage.height / selectedFrameImage.width)
              .round();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final bounds = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
    final photoDestinations = List<Rect>.filled(images.length, Rect.zero);
    canvas.drawRect(bounds, Paint()..color = borderColor);

    if (frameTemplate != null && frameTemplate.classicStyle) {
      final classicTemplate = frameTemplate;
      if (classicTemplate.classicHasBranding) {
        final logo = brandLogoImage!;
        final logoBounds = classicFrameLogoBounds(
          Size(width.toDouble(), height.toDouble()),
          classicTemplate,
        );
        final logoSize = Size(logo.width.toDouble(), logo.height.toDouble());
        final logoFit = applyBoxFit(BoxFit.contain, logoSize, logoBounds.size);
        canvas.drawImageRect(
          logo,
          Offset.zero & logoSize,
          Alignment.center.inscribe(logoFit.destination, logoBounds),
          Paint()..filterQuality = FilterQuality.high,
        );
        if (captureDate != null) {
          final firstPhotoTop =
              classicTemplate.photoSlots
                  .map((slot) => slot.top)
                  .reduce(math.min) *
              height;
          final dateTop = logoBounds.bottom + height * 0.006;
          captureDateRenderedInHeader =
              framePath == null &&
              _drawCaptureDateHeader(
                canvas,
                width.toDouble(),
                dateTop,
                math.max(0, firstPhotoTop - dateTop - height * 0.004),
                captureDate,
                borderColor,
                width * 0.026,
              );
        }
      }
      for (var index = 0; index < images.length; index++) {
        final slot = classicTemplate.photoSlots[index];
        final destination = Rect.fromLTRB(
          slot.left * width,
          slot.top * height,
          slot.right * width,
          slot.bottom * height,
        );
        photoDestinations[index] = destination;
        canvas.drawRect(
          destination.inflate(width * 0.009),
          Paint()..color = borderColor,
        );
        _drawImageCover(
          canvas,
          images[index],
          destination,
          mirror: mirrorPhotos,
          transform: _photoTransformAt(photoTransforms, index),
        );
        canvas.drawRect(
          destination,
          Paint()
            ..color = const Color(0xFF17212B)
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1, width * 0.003),
        );
      }
      if (classicTemplate.landscapeDesign != null) {
        paintLandscapeFrameDesign(
          canvas,
          Size(width.toDouble(), height.toDouble()),
          classicTemplate,
        );
      }
    } else if (frameTemplate != null && templateImage != null) {
      final photoPaintOrder = frameTemplate.photoPaintOrder.isEmpty
          ? List<int>.generate(images.length, (index) => index)
          : frameTemplate.photoPaintOrder;
      for (final index in photoPaintOrder) {
        final normalizedSlot = frameTemplate.photoSlots[index];
        final destination = Rect.fromLTRB(
          normalizedSlot.left * width,
          normalizedSlot.top * height,
          normalizedSlot.right * width,
          normalizedSlot.bottom * height,
        );
        photoDestinations[index] = destination;
        final rotation = frameTemplate.rotationForSlot(index);
        canvas.save();
        if (windowPaths != null) {
          final clipper = PhotoWindowClipper(windowPaths[index]);
          canvas.clipPath(
            clipper.getClip(Size(width.toDouble(), height.toDouble())),
          );
        }
        if (rotation != 0) {
          canvas.translate(destination.center.dx, destination.center.dy);
          canvas.rotate(rotation);
          canvas.translate(-destination.center.dx, -destination.center.dy);
        }
        canvas.clipRect(destination);
        _drawImageCover(
          canvas,
          images[index],
          destination,
          mirror: mirrorPhotos,
          transform: _photoTransformAt(photoTransforms, index),
        );
        canvas.restore();
      }
    } else {
      if (!needsExternalFrameHeader) {
        final logo = brandLogoImage!;
        final logoBounds = Rect.fromLTWH(
          width * 0.05,
          margin,
          width * 0.90,
          headerHeight * 0.76,
        );
        final logoSize = Size(logo.width.toDouble(), logo.height.toDouble());
        final logoFit = applyBoxFit(BoxFit.contain, logoSize, logoBounds.size);
        final logoDestination = Alignment.center.inscribe(
          logoFit.destination,
          logoBounds,
        );
        canvas.drawImageRect(
          logo,
          Offset.zero & logoSize,
          logoDestination,
          Paint()..filterQuality = FilterQuality.high,
        );
        if (captureDate != null) {
          final dateTop = logoBounds.bottom + width * 0.008;
          captureDateRenderedInHeader =
              framePath == null &&
              _drawCaptureDateHeader(
                canvas,
                width.toDouble(),
                dateTop,
                math.max(0, margin + headerHeight - dateTop),
                captureDate,
                borderColor,
                width * 0.032,
              );
        }
      }
      var top = margin + headerHeight;
      for (var index = 0; index < images.length; index++) {
        final image = images[index];
        final row = index ~/ columns;
        final rowStart = row * columns;
        final rowCount = math.min(columns, images.length - rowStart);
        final column = index % columns + (columns - rowCount) ~/ 2;
        final centeredOffset = columns == 2 && rowCount == 1
            ? (cellWidth + gap) / 2
            : 0.0;
        final destination = Rect.fromLTWH(
          margin + column * (cellWidth + gap) + centeredOffset,
          top + row * (cellHeight + gap),
          cellWidth,
          cellHeight,
        );
        photoDestinations[index] = destination;
        if (photoBorderOverlayPath == null) {
          canvas.drawRect(
            destination.inflate(width * 0.006),
            Paint()..color = borderColor,
          );
        }
        _drawImageCover(
          canvas,
          image,
          destination,
          mirror: mirrorPhotos,
          transform: _photoTransformAt(photoTransforms, index),
        );
      }
    }

    final picture = recorder.endRecording();
    ui.Image? output;
    ui.Image? frameImage;
    try {
      output = await picture.toImage(width, height);
      if (templateImage != null) {
        frameImage = templateImage;
      } else if (framePath != null) {
        frameImage = framePathImage;
      }
      if (frameImage != null) {
        final framedRecorder = ui.PictureRecorder();
        final framedCanvas = Canvas(framedRecorder);
        framedCanvas.drawImageRect(
          output,
          bounds,
          bounds,
          Paint()..filterQuality = FilterQuality.high,
        );
        if (frameTemplate != null &&
            !frameTemplate.foregroundArtwork &&
            !frameTemplate.photoWindowsFromTransparency) {
          const photoWindowInset = 0.025;
          final openings = Path();
          for (final slot in frameTemplate.photoSlots) {
            final insetX = slot.width * photoWindowInset;
            final insetY = slot.height * photoWindowInset;
            openings.addRect(
              Rect.fromLTRB(
                (slot.left + insetX) * width,
                (slot.top + insetY) * height,
                (slot.right - insetX) * width,
                (slot.bottom - insetY) * height,
              ),
            );
          }
          final frameArea = Path()..addRect(bounds);
          final overlayArea = Path.combine(
            PathOperation.difference,
            frameArea,
            openings,
          );
          framedCanvas.save();
          framedCanvas.clipPath(overlayArea);
        }
        final frameSource = Rect.fromLTWH(
          0,
          0,
          frameImage.width.toDouble(),
          frameImage.height.toDouble(),
        );
        final frameFit = applyBoxFit(
          BoxFit.contain,
          frameSource.size,
          bounds.size,
        );
        framedCanvas.drawImageRect(
          frameImage,
          frameSource,
          Alignment.center.inscribe(frameFit.destination, bounds),
          Paint()..filterQuality = FilterQuality.high,
        );
        if (frameTemplate != null &&
            !frameTemplate.foregroundArtwork &&
            !frameTemplate.photoWindowsFromTransparency) {
          framedCanvas.restore();
        }
        final framedPicture = framedRecorder.endRecording();
        output.dispose();
        output = await framedPicture.toImage(width, height);
        framedPicture.dispose();
      }
      if (photoBorderStyle != PhotoBorderStyle.none &&
          photoBorderStyle != PhotoBorderStyle.custom) {
        final currentOutput = output;
        final borderedRecorder = ui.PictureRecorder();
        final borderedCanvas = Canvas(borderedRecorder);
        borderedCanvas.drawImageRect(
          currentOutput,
          bounds,
          bounds,
          Paint()..filterQuality = FilterQuality.high,
        );
        for (var index = 0; index < photoDestinations.length; index++) {
          final destination = photoDestinations[index];
          final rotation = frameTemplate?.rotationForSlot(index) ?? 0;
          borderedCanvas.save();
          if (rotation != 0) {
            borderedCanvas.translate(
              destination.center.dx,
              destination.center.dy,
            );
            borderedCanvas.rotate(rotation);
            borderedCanvas.translate(
              -destination.center.dx,
              -destination.center.dy,
            );
          }
          borderedCanvas.clipRect(destination);
          borderedCanvas.save();
          borderedCanvas.translate(destination.left, destination.top);
          PhotoBorderPainter(photoBorderStyle)
              .paint(borderedCanvas, destination.size);
          borderedCanvas.restore();
          borderedCanvas.restore();
        }
        final borderedPicture = borderedRecorder.endRecording();
        try {
          output = await borderedPicture.toImage(width, height);
        } finally {
          currentOutput.dispose();
          borderedPicture.dispose();
        }
      }
      if (photoBorderOverlayPath != null) {
        final borderFile = File(photoBorderOverlayPath);
        if (!await borderFile.exists()) {
          throw StateError(
            'The selected custom PNG border could not be found.',
          );
        }
        photoBorderCodec = await ui.instantiateImageCodec(
          await borderFile.readAsBytes(),
        );
        final borderImage = (await photoBorderCodec.getNextFrame()).image;
        photoBorderImage = borderImage;
        final currentOutput = output;
        final borderedRecorder = ui.PictureRecorder();
        final borderedCanvas = Canvas(borderedRecorder);
        borderedCanvas.drawImageRect(
          currentOutput,
          bounds,
          bounds,
          Paint()..filterQuality = FilterQuality.high,
        );
        for (var index = 0; index < photoDestinations.length; index++) {
          final destination = photoDestinations[index];
          final rotation = frameTemplate?.rotationForSlot(index) ?? 0;
          borderedCanvas.save();
          if (rotation != 0) {
            borderedCanvas.translate(
              destination.center.dx,
              destination.center.dy,
            );
            borderedCanvas.rotate(rotation);
            borderedCanvas.translate(
              -destination.center.dx,
              -destination.center.dy,
            );
          }
          borderedCanvas.clipRect(destination);
          borderedCanvas.drawImageRect(
            borderImage,
            Rect.fromLTWH(
              0,
              0,
              borderImage.width.toDouble(),
              borderImage.height.toDouble(),
            ),
            destination,
            Paint()..filterQuality = FilterQuality.high,
          );
          borderedCanvas.restore();
        }
        final borderedPicture = borderedRecorder.endRecording();
        try {
          output = await borderedPicture.toImage(width, height);
        } finally {
          currentOutput.dispose();
          borderedPicture.dispose();
        }
      }
      if (needsExternalFrameHeader) {
        final currentOutput = output;
        output = await _prependFrameLogoHeader(currentOutput, brandLogoImage!);
        currentOutput.dispose();
      }
      if (captureDate != null && !captureDateRenderedInHeader) {
        final currentOutput = output;
        output = await _appendCaptureDateFooter(
          currentOutput,
          captureDate,
          borderColor,
        );
        currentOutput.dispose();
      }
    } finally {
      picture.dispose();
    }
    try {
      final bytes = await output.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw StateError('Could not create the photo strip.');
      final suffix = switch (layout) {
        PhotoLayout.verticalStrip => 'strip',
        PhotoLayout.collage => 'collage',
      };
      final frameSuffix = frameTemplate != null
          ? '-${frameTemplate.id}'
          : framePath == null
          ? ''
          : '-custom-${framePath.hashCode.toRadixString(16)}';
      final mirrorSuffix = mirrorPhotos ? '-mirrored' : '';
      final borderColorSuffix =
          '-border-${borderColor.toARGB32().toRadixString(16)}';
      final cropSuffix =
          photoTransforms.isEmpty ||
              photoTransforms.every(
                (transform) =>
                    transform.zoom == 1 && transform.pan == Offset.zero,
              )
          ? ''
          : '-crop-${Object.hashAll(photoTransforms).toRadixString(16)}';
      final photoBorderSuffix = photoBorderOverlayPath == null
          ? ''
          : '-photo-border-${photoBorderOverlayPath.hashCode.toRadixString(16)}';
      final logoSuffix = brandLogoPath == null
          ? ''
          : '-logo-${brandLogoPath.hashCode.toRadixString(16)}';
      final inputSuffix = Object.hashAll(photos.map((photo) => photo.path))
          .toRadixString(16);
      final captureDateSuffix = captureDate == null
          ? ''
          : '-date-${captureDate.year.toString().padLeft(4, '0')}'
                '${captureDate.month.toString().padLeft(2, '0')}'
                '${captureDate.day.toString().padLeft(2, '0')}';
      final result = File(
        '${photos.first.path}$borderColorSuffix-$inputSuffix-'
        '${width}x${output.height}$frameSuffix.$suffix'
        '$mirrorSuffix$cropSuffix$photoBorderSuffix$logoSuffix'
        '$captureDateSuffix.png',
      );
      await result.writeAsBytes(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        flush: true,
      );
      return result;
    } finally {
      output.dispose();
    }
  } finally {
    templateImage?.dispose();
    templateCodec?.dispose();
    brandLogoImage?.dispose();
    brandLogoCodec?.dispose();
    framePathImage?.dispose();
    framePathCodec?.dispose();
    photoBorderImage?.dispose();
    photoBorderCodec?.dispose();
    for (final image in images) {
      image.dispose();
    }
    for (final codec in codecs) {
      codec.dispose();
    }
  }
}

Future<ui.Image> _prependFrameLogoHeader(ui.Image image, ui.Image logo) async {
  final width = image.width.toDouble();
  final headerHeight = math.max((image.width * 0.18).round(), 1);
  final outputHeight = image.height + headerHeight;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width, outputHeight.toDouble()),
    Paint()..color = const Color(0xFFFFFFFF),
  );
  final logoBounds = Rect.fromLTWH(
    width * 0.19,
    headerHeight * 0.08,
    width * 0.62,
    headerHeight * 0.84,
  );
  final logoSize = Size(logo.width.toDouble(), logo.height.toDouble());
  final logoFit = applyBoxFit(BoxFit.contain, logoSize, logoBounds.size);
  canvas.drawImageRect(
    logo,
    Offset.zero & logoSize,
    Alignment.center.inscribe(logoFit.destination, logoBounds),
    Paint()..filterQuality = FilterQuality.high,
  );
  canvas.drawImageRect(
    image,
    Rect.fromLTWH(0, 0, width, image.height.toDouble()),
    Rect.fromLTWH(0, headerHeight.toDouble(), width, image.height.toDouble()),
    Paint()..filterQuality = FilterQuality.high,
  );
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(image.width, outputHeight);
  } finally {
    picture.dispose();
  }
}

Future<ui.Image> _appendCaptureDateFooter(
  ui.Image image,
  DateTime date,
  Color backgroundColor,
) async {
  final width = image.width.toDouble();
  final contentHeight = image.height.toDouble();
  final footerHeight = math.max((width * 0.095).round(), 28);
  final outputHeight = image.height + footerHeight;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawImageRect(
    image,
    Rect.fromLTWH(0, 0, width, contentHeight),
    Rect.fromLTWH(0, 0, width, contentHeight),
    Paint()..filterQuality = FilterQuality.high,
  );
  canvas.drawRect(
    Rect.fromLTWH(0, contentHeight, width, footerHeight.toDouble()),
    Paint()..color = backgroundColor,
  );
  canvas.drawLine(
    Offset(0, contentHeight),
    Offset(width, contentHeight),
    Paint()
      ..color = const Color(0xFF30271F).withValues(alpha: 0.14)
      ..strokeWidth = math.max(width * 0.002, 1),
  );

  final dateText =
      '${date.month.toString().padLeft(2, '0')}/'
      '${date.day.toString().padLeft(2, '0')}/'
      '${date.year.toString().padLeft(4, '0')}';
  final backgroundLuminance =
      backgroundColor.r * 0.299 +
      backgroundColor.g * 0.587 +
      backgroundColor.b * 0.114;
  final datePainter = TextPainter(
    text: TextSpan(
      text: dateText,
      style: TextStyle(
        fontFamily: _photoTextFontFamily,
        color: backgroundLuminance > 0.5
            ? const Color(0xFF201B16)
            : const Color(0xFFFFFFFF),
        fontSize: math.max(width * 0.032, 12),
        fontWeight: FontWeight.w700,
      ),
    ),
    textAlign: TextAlign.center,
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: width * 0.9);
  datePainter.paint(
    canvas,
    Offset(
      (width - datePainter.width) / 2,
      contentHeight + (footerHeight - datePainter.height) / 2,
    ),
  );
  datePainter.dispose();

  final picture = recorder.endRecording();
  try {
    return await picture.toImage(image.width, outputHeight);
  } finally {
    picture.dispose();
  }
}

void _drawCaptureDate(
  Canvas canvas,
  double width,
  double height,
  DateTime date,
  Color backgroundColor,
) {
  final dateText =
      '${date.month.toString().padLeft(2, '0')}/'
      '${date.day.toString().padLeft(2, '0')}/'
      '${date.year.toString().padLeft(4, '0')}';
  final fontSize = math.max(height * 0.02, width * 0.018);
  final datePainter = TextPainter(
    text: TextSpan(
      text: dateText,
      style: TextStyle(
        fontFamily: _photoTextFontFamily,
        color: const Color(0xFFFFFFFF),
        fontSize: fontSize,
        fontWeight: FontWeight.w600,
      ),
    ),
    textAlign: TextAlign.center,
    textDirection: TextDirection.ltr,
  )..layout();
  final labelHeight = math.max(height * 0.035, width * 0.03);
  final labelWidth = math.min(
    width * 0.58,
    math.max(width * 0.32, datePainter.width + width * 0.06),
  );
  final label = Rect.fromCenter(
    center: Offset(width / 2, height - labelHeight * 0.72),
    width: labelWidth,
    height: labelHeight,
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(label, Radius.circular(labelHeight * 0.22)),
    Paint()..color = backgroundColor,
  );
  final textLuminance =
      (backgroundColor.r * 255).round() * 0.299 +
      (backgroundColor.g * 255).round() * 0.587 +
      (backgroundColor.b * 255).round() * 0.114;
  datePainter.text = TextSpan(
    text: dateText,
    style: TextStyle(
      fontFamily: _photoTextFontFamily,
      color: textLuminance > 145
          ? const Color(0xFF201B16)
          : const Color(0xFFFFFFFF),
      fontSize: fontSize,
      fontWeight: FontWeight.w600,
    ),
  );
  datePainter.layout();
  datePainter.paint(
    canvas,
    Offset(
      (width - datePainter.width) / 2,
      label.top + (labelHeight - datePainter.height) / 2,
    ),
  );
  datePainter.dispose();
}

Future<Color> _captureDateBackgroundColor(
  ui.Image image,
  double width,
  double height,
) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (data == null) {
    throw StateError('Could not sample the photo frame behind the date.');
  }
  final labelHeight = math.max(height * 0.035, width * 0.03);
  final labelWidth = math.min(width * 0.58, width * 0.55);
  final centerX = width / 2;
  final centerY = height - labelHeight * 0.72;
  final colors = <List<int>>[[], [], []];
  for (var row = 0; row < 7; row++) {
    final y = (centerY - labelHeight * 0.35 + labelHeight * 0.7 * row / 6)
        .round()
        .clamp(0, image.height - 1);
    for (var column = 0; column < 11; column++) {
      final x = (centerX - labelWidth * 0.4 + labelWidth * 0.8 * column / 10)
          .round()
          .clamp(0, image.width - 1);
      final offset = (y * image.width + x) * 4;
      for (var channel = 0; channel < 3; channel++) {
        colors[channel].add(data.getUint8(offset + channel));
      }
    }
  }
  for (final channel in colors) {
    channel.sort();
  }
  final median = colors.map((channel) => channel[channel.length ~/ 2]).toList();
  return Color.fromARGB(255, median[0], median[1], median[2]);
}

void _drawImageCover(
  Canvas canvas,
  ui.Image image,
  Rect destination, {
  bool mirror = false,
  PhotoCropTransform transform = const PhotoCropTransform(),
}) {
  final zoom = transform.zoom.clamp(1.0, 3.0);
  final scale = math.max(
    destination.width / image.width,
    destination.height / image.height,
  );
  final sourceWidth = destination.width / scale / zoom;
  final sourceHeight = destination.height / scale / zoom;
  final availableX = math.max(0.0, image.width - sourceWidth);
  final availableY = math.max(0.0, image.height - sourceHeight);
  final panX = mirror ? -transform.pan.dx : transform.pan.dx;
  final source = Rect.fromLTWH(
    (availableX / 2 + panX * availableX).clamp(0, availableX).toDouble(),
    (availableY / 2 + transform.pan.dy * availableY)
        .clamp(0, availableY)
        .toDouble(),
    sourceWidth,
    sourceHeight,
  );
  canvas.save();
  canvas.clipRect(destination);
  if (mirror) {
    canvas.translate(destination.left + destination.right, 0);
    canvas.scale(-1, 1);
  }
  canvas.drawImageRect(
    image,
    source,
    destination,
    Paint()..filterQuality = FilterQuality.high,
  );
  canvas.restore();
}

PhotoCropTransform _photoTransformAt(
  List<PhotoCropTransform> transforms,
  int index,
) => transforms.isEmpty ? const PhotoCropTransform() : transforms[index];

bool _drawCaptureDateHeader(
  Canvas canvas,
  double width,
  double top,
  double availableHeight,
  DateTime date,
  Color backgroundColor,
  double maxFontSize,
) {
  if (availableHeight < math.max(8, maxFontSize * 0.65)) return false;
  final dateText =
      '${date.month.toString().padLeft(2, '0')}/'
      '${date.day.toString().padLeft(2, '0')}/'
      '${date.year.toString().padLeft(4, '0')}';
  final luminance =
      backgroundColor.r * 0.299 +
      backgroundColor.g * 0.587 +
      backgroundColor.b * 0.114;
  final painter = TextPainter(
    text: TextSpan(
      text: dateText,
      style: TextStyle(
        color: luminance > 0.5
            ? const Color(0xFF201B16)
            : const Color(0xFFFFFFFF),
        fontFamily: _photoTextFontFamily,
        fontSize: math.min(maxFontSize, availableHeight * 0.72),
        fontWeight: FontWeight.w600,
      ),
    ),
    textAlign: TextAlign.center,
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: width * 0.9);
  painter.paint(
    canvas,
    Offset(
      (width - painter.width) / 2,
      top + (availableHeight - painter.height) / 2,
    ),
  );
  painter.dispose();
  return true;
}
