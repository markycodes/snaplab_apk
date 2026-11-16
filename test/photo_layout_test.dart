import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:photobooth_kiosk/photo_layout.dart';
import 'package:photobooth_kiosk/photo_border.dart' show PhotoBorderStyle;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temporaryDirectory;
  late List<File> photos;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'photobooth-layout-test-',
    );
    final photo = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}photo.jpg',
    );
    await photo.writeAsBytes(await _encodePhoto());
    photos = [photo];
  });

  tearDown(() async {
    await temporaryDirectory.delete(recursive: true);
  });

  test('composes one to five photos into a vertical photobooth strip', () async {
    var previousHeight = 0;
    for (var count = 1; count <= 5; count++) {
      final inputs = <File>[];
      for (var index = 0; index < count; index++) {
        final copy = File(
          '${temporaryDirectory.path}${Platform.pathSeparator}photo-$index.jpg',
        );
        await copy.writeAsBytes(await photos.first.readAsBytes());
        inputs.add(copy);
      }

      final strip = await composePhotoStrip(inputs);
      final codec = await ui.instantiateImageCodec(await strip.readAsBytes());
      try {
        final image = (await codec.getNextFrame()).image;
        expect(image.width, 4);
        expect(image.height, greaterThan(previousHeight));
        previousHeight = image.height;
        image.dispose();
      } finally {
        codec.dispose();
      }
    }
  });

  test('composition cache key includes every photo input', () async {
    final otherPhoto = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}other-photo.jpg',
    );
    await otherPhoto.writeAsBytes(await photos.first.readAsBytes());

    final first = await composePhotoStrip([photos.first, photos.first]);
    final second = await composePhotoStrip([photos.first, otherPhoto]);

    expect(second.path, isNot(first.path));
  });

  test('rejects a strip outside the supported 1–5 photo range', () async {
    expect(composePhotoStrip([]), throwsArgumentError);
    expect(
      composePhotoStrip(List<File>.filled(6, photos.first)),
      throwsArgumentError,
    );
  });

  test(
    'keeps built-in photo borders visible on all four sides after crop',
    () async {
      final largePhoto = File(
        '${temporaryDirectory.path}${Platform.pathSeparator}border-test.png',
      );
      await largePhoto.writeAsBytes(
        await _encodePhoto(width: 400, height: 300),
      );

      final composed = await composePhotoStrip([
        largePhoto,
      ], photoBorderStyle: PhotoBorderStyle.wedding);
      final codec = await ui.instantiateImageCodec(
        await composed.readAsBytes(),
      );
      try {
        final image = (await codec.getNextFrame()).image;
        final pixels = await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        expect(pixels, isNotNull);

        bool hasWeddingGold(int left, int top, int right, int bottom) {
          for (var y = top; y <= bottom; y++) {
            for (var x = left; x <= right; x++) {
              final offset = (y * image.width + x) * 4;
              if ((pixels!.getUint8(offset) - 0xC8).abs() < 12 &&
                  (pixels.getUint8(offset + 1) - 0xA8).abs() < 12 &&
                  (pixels.getUint8(offset + 2) - 0x6B).abs() < 12) {
                return true;
              }
            }
          }
          return false;
        }

        bool hasWeddingFooter(int left, int top, int right, int bottom) {
          for (var y = top; y <= bottom; y++) {
            for (var x = left; x <= right; x++) {
              final offset = (y * image.width + x) * 4;
              if ((pixels!.getUint8(offset) - 0xF9).abs() < 12 &&
                  (pixels.getUint8(offset + 1) - 0xF5).abs() < 12 &&
                  (pixels.getUint8(offset + 2) - 0xEC).abs() < 12) {
                return true;
              }
            }
          }
          return false;
        }

        expect(hasWeddingGold(100, 80, 300, 100), isTrue, reason: 'top border');
        expect(hasWeddingGold(20, 150, 40, 260), isTrue, reason: 'left border');
        expect(
          hasWeddingGold(image.width - 40, 150, image.width - 20, 260),
          isTrue,
          reason: 'right border',
        );
        expect(
          hasWeddingFooter(100, image.height - 110, 300, image.height - 75),
          isTrue,
          reason: 'bottom border',
        );
        image.dispose();
      } finally {
        codec.dispose();
      }
    },
  );

  test('photo hit regions follow the selected template slots', () {
    final template = photoFrameTemplateById('classical-music-three')!;
    expect(
      photoSlotBounds(
        3,
        layout: PhotoLayout.verticalStrip,
        frameTemplate: template,
      ),
      template.photoSlots,
    );
  });

  test(
    'classic photo layouts define a distinct frame for each photo count',
    () {
      for (var count = 1; count <= 5; count++) {
        final template = photoFrameTemplateById('classic-$count')!;
        expect(template.id, 'classic-$count');
        expect(template.classicStyle, isTrue);
        expect(template.photoSlots, hasLength(count));
        expect(
          photoSlotBounds(
            count,
            layout: PhotoLayout.verticalStrip,
            frameTemplate: template,
          ),
          template.photoSlots,
        );
      }
    },
  );

  test('classic session choices show one layout for each photo count', () {
    for (final landscape in [false, true]) {
      final choices = classicPhotoFrameTemplates
          .where(
            (template) =>
                template.landscape == landscape &&
                template.id != 'classic-staggered-4',
          )
          .toList(growable: false);

      expect(choices.map((template) => template.photoCount), [1, 2, 3, 4, 5]);
      expect(
        choices.where((template) => template.photoCount == 4),
        hasLength(1),
      );
      expect(choices.every((template) => template.classicStyle), isTrue);
    }
  });

  test('classic 2- and 3-photo layouts use taller photo boxes', () {
    final twoPhotoTemplate = photoFrameTemplateById('classic-2')!;
    final threePhotoTemplate = photoFrameTemplateById('classic-3')!;

    expect(twoPhotoTemplate.photoSlots.map((slot) => slot.height), [
      closeTo(0.33, 0.001),
      closeTo(0.33, 0.001),
    ]);
    expect(threePhotoTemplate.photoSlots.map((slot) => slot.height), [
      closeTo(0.23, 0.001),
      closeTo(0.23, 0.001),
      closeTo(0.23, 0.001),
    ]);
    expect(threePhotoTemplate.photoSlots.map((slot) => slot.width), [
      closeTo(0.66, 0.001),
      closeTo(0.66, 0.001),
      closeTo(0.66, 0.001),
    ]);
  });

  test('classic photo layouts compose without image frame assets', () async {
    for (var count = 1; count <= 5; count++) {
      final template = photoFrameTemplateById('classic-$count')!;
      final classic = await composePhotoStrip(
        List<File>.filled(count, photos.first),
        frameTemplate: template,
      );
      final image = await _decode(classic);
      try {
        expect(image.width, 4);
        expect(image.height, 6);
      } finally {
        image.dispose();
      }
    }
  });

  test('frame picker returns only templates matching device orientation', () {
    for (var count = 1; count <= 5; count++) {
      final landscape = frameTemplatesForOrientation(count, landscape: true);
      final portrait = frameTemplatesForOrientation(count, landscape: false);
      expect(landscape, isNotEmpty);
      expect(portrait, isNotEmpty);
      expect(landscape.every((template) => template.landscape), isTrue);
      expect(portrait.every((template) => !template.landscape), isTrue);
      expect(
        landscape.firstWhere((template) => template.classicStyle).id,
        'classic-landscape-$count',
      );
    }
  });

  test('landscape gallery includes four designed variants per photo count', () {
    for (var count = 1; count <= 5; count++) {
      final templates = frameTemplatesForOrientation(count, landscape: true);
      final designed = templates
          .where((template) => template.landscapeDesign != null)
          .toList();
      expect(designed, hasLength(LandscapeFrameDesign.values.length));
      expect(
        designed.map((template) => template.label).toSet(),
        hasLength(LandscapeFrameDesign.values.length),
      );
      expect(
        designed
            .map(
              (template) => template.photoSlots
                  .map(
                    (slot) =>
                        '${slot.left.toStringAsFixed(3)},${slot.top.toStringAsFixed(3)},${slot.right.toStringAsFixed(3)},${slot.bottom.toStringAsFixed(3)}',
                  )
                  .join('|'),
            )
            .toSet(),
        hasLength(LandscapeFrameDesign.values.length),
      );
      expect(
        designed.every(
          (template) =>
              template.classicStyle &&
              template.containPhotos &&
              template.photoSlots.length == count,
        ),
        isTrue,
      );
      for (final template in designed) {
        for (var first = 0; first < template.photoSlots.length; first++) {
          final slot = template.photoSlots[first];
          expect(slot.left, greaterThanOrEqualTo(0));
          expect(slot.top, greaterThanOrEqualTo(0));
          expect(slot.right, lessThanOrEqualTo(1));
          expect(slot.bottom, lessThanOrEqualTo(1));
          for (
            var second = first + 1;
            second < template.photoSlots.length;
            second++
          ) {
            expect(
              slot.overlaps(template.photoSlots[second]),
              isFalse,
              reason: '${template.label} photo boxes should not overlap',
            );
          }
        }
      }
    }
  });

  test('landscape frame designs render visibly different prints', () async {
    final largePhoto = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}designed-frame.png',
    );
    await largePhoto.writeAsBytes(await _encodePhoto(width: 400, height: 300));

    final outputs = <List<int>>[];
    for (final design in LandscapeFrameDesign.values) {
      final template = frameTemplatesForOrientation(
        1,
        landscape: true,
      ).firstWhere((frame) => frame.landscapeDesign == design);
      final image = await _decode(
        await composePhotoStrip([largePhoto], frameTemplate: template),
      );
      try {
        expect(image.width / image.height, closeTo(1.5, 0.01));
        final bytes = await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        outputs.add(bytes!.buffer.asUint8List().toList(growable: false));
      } finally {
        image.dispose();
      }
    }
    expect(outputs.map(Object.hashAll).toSet(), hasLength(4));
  });

  test('landscape frame fills its photo box without white space', () async {
    final stripedPhoto = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}landscape-striped.png',
    );
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawColor(const ui.Color(0xFF20C040), ui.BlendMode.src);
    canvas.drawRect(
      const ui.Rect.fromLTWH(0, 0, 400, 45),
      Paint()..color = const ui.Color(0xFFE02020),
    );
    canvas.drawRect(
      const ui.Rect.fromLTWH(0, 255, 400, 45),
      Paint()..color = const ui.Color(0xFF2040E0),
    );
    final source = await recorder.endRecording().toImage(400, 300);
    try {
      final data = await source.toByteData(format: ui.ImageByteFormat.png);
      await stripedPhoto.writeAsBytes(
        data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
    } finally {
      source.dispose();
    }

    final template = photoFrameTemplateById('classic-landscape-1')!;
    final composed = await composePhotoStrip([
      stripedPhoto,
    ], frameTemplate: template);
    final image = await _decode(composed);
    try {
      expect(image.width / image.height, closeTo(1.5, 0.01));
      final photoBoxTop = (image.height * 0.20).round();
      final photoBoxBottom = (image.height * 0.82).round();
      for (final y in [photoBoxTop + 1, photoBoxBottom - 1]) {
        final pixel = await _pixelAt(image, image.width ~/ 2, y);
        expect(pixel, isNot([0xFF, 0xFF, 0xFF]));
        expect(pixel[1], greaterThan(pixel[0]));
        expect(pixel[1], greaterThan(pixel[2]));
      }
      expect(await _pixelAt(image, 4, image.height ~/ 2), [0xFF, 0xFF, 0xFF]);
    } finally {
      image.dispose();
    }
  });

  test(
    'landscape photo drag changes the horizontal crop in the frame',
    () async {
      final widePhoto = File(
        '${temporaryDirectory.path}${Platform.pathSeparator}landscape-pan.png',
      );
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawColor(const ui.Color(0xFF2040E0), ui.BlendMode.src);
      canvas.drawRect(
        const ui.Rect.fromLTWH(170, 0, 60, 100),
        Paint()..color = const ui.Color(0xFF20C040),
      );
      final source = await recorder.endRecording().toImage(400, 100);
      try {
        final data = await source.toByteData(format: ui.ImageByteFormat.png);
        await widePhoto.writeAsBytes(
          data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        );
      } finally {
        source.dispose();
      }

      final template = photoFrameTemplateById('classic-landscape-1')!;
      final centered = await composePhotoStrip([
        widePhoto,
      ], frameTemplate: template);
      final dragged = await composePhotoStrip(
        [widePhoto],
        frameTemplate: template,
        photoTransforms: const [PhotoCropTransform(pan: ui.Offset(0.5, 0))],
      );
      final centeredImage = await _decode(centered);
      final draggedImage = await _decode(dragged);
      try {
        final sampleY = (centeredImage.height * 0.51).round();
        final centeredPixel = await _pixelAt(
          centeredImage,
          centeredImage.width ~/ 2,
          sampleY,
        );
        final draggedPixel = await _pixelAt(
          draggedImage,
          draggedImage.width ~/ 2,
          sampleY,
        );
        expect(centeredPixel[1], greaterThan(centeredPixel[2]));
        expect(draggedPixel[2], greaterThan(draggedPixel[1]));
      } finally {
        centeredImage.dispose();
        draggedImage.dispose();
      }
    },
  );

  test('classic staggered layout matches the four-photo reference', () async {
    final template = photoFrameTemplateById('classic-staggered-4')!;
    expect(template.photoCount, 4);
    expect(template.classicStyle, isTrue);
    expect(template.classicHasBranding, isTrue);
    expect(template.classicAspectRatio, closeTo(0.953, 0.001));
    expect(template.photoSlots[0].center.dx, lessThan(0.5));
    expect(template.photoSlots[1].center.dx, lessThan(0.5));
    expect(template.photoSlots[2].center.dx, greaterThan(0.5));
    expect(template.photoSlots[3].center.dx, greaterThan(0.5));
    expect(template.photoSlots[0].top, lessThan(template.photoSlots[2].top));
    expect(template.photoSlots[1].top, lessThan(template.photoSlots[3].top));
    expect(template.photoSlots[0].top, greaterThan(0.12));

    final largePhoto = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}staggered-photo.png',
    );
    await largePhoto.writeAsBytes(await _encodePhoto(width: 64, height: 48));
    final image = await _decode(
      await composePhotoStrip(
        List<File>.filled(4, largePhoto),
        frameTemplate: template,
      ),
    );
    try {
      expect(image.width / image.height, closeTo(0.953, 0.01));
    } finally {
      image.dispose();
    }
  });

  test('classic branding is kept above every photo opening', () {
    for (final template in classicPhotoFrameTemplates) {
      final logoBounds = classicFrameLogoBounds(
        Size(400, 400 / template.classicAspectRatio),
        template,
      );
      final firstPhotoTop =
          template.photoSlots.map((slot) => slot.top).reduce(math.min) *
          (400 / template.classicAspectRatio);

      expect(
        logoBounds.bottom,
        lessThan(firstPhotoTop),
        reason: '${template.label} should leave the SnapLab logo unobstructed',
      );
    }
  });

  test('classic frame footer stays clear of text over the photos', () async {
    final template = photoFrameTemplateById('classic-staggered-4')!;
    final largePhoto = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}classic-footer-photo.png',
    );
    await largePhoto.writeAsBytes(await _encodePhoto(width: 320, height: 240));
    final composed = await composePhotoStrip(
      List<File>.filled(4, largePhoto),
      frameTemplate: template,
    );
    final image = await _decode(composed);
    try {
      expect(
        await _pixelAt(image, image.width ~/ 2, (image.height * 0.88).round()),
        [255, 255, 255],
      );
    } finally {
      image.dispose();
    }
  });

  test('photo hit regions map strip images in their visible order', () {
    final slots = photoSlotBounds(3, layout: PhotoLayout.verticalStrip);
    expect(slots, hasLength(3));
    expect(slots[0].center.dy, lessThan(slots[1].center.dy));
    expect(slots[1].center.dy, lessThan(slots[2].center.dy));
    expect(slots[0].contains(slots[0].center), isTrue);
  });

  test('photo hit regions map collage slots to each photo', () {
    final slots = photoSlotBounds(3, layout: PhotoLayout.collage);
    expect(slots, hasLength(3));
    expect(slots[0].center.dx, lessThan(slots[1].center.dx));
    expect(slots[2].center.dy, greaterThan(slots[0].center.dy));
  });

  test('identifies when a photo layout uses a single column', () {
    expect(
      photoLayoutUsesSingleColumn(3, layout: PhotoLayout.verticalStrip),
      isTrue,
    );
    expect(
      photoLayoutUsesSingleColumn(3, layout: PhotoLayout.collage),
      isFalse,
    );
    expect(photoLayoutUsesSingleColumn(1, layout: PhotoLayout.collage), isTrue);
  });

  test('collage lays photos out in a shorter two-column print', () async {
    final largePhoto = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}large-photo.png',
    );
    await largePhoto.writeAsBytes(await _encodePhoto(width: 64, height: 48));
    final pair = [largePhoto, largePhoto];
    final strip = await composePhotoStrip(pair);
    final collage = await composePhotoStrip(pair, layout: PhotoLayout.collage);
    final stripImage = await _decode(strip);
    final collageImage = await _decode(collage);
    expect(collageImage.width, stripImage.width);
    expect(collageImage.height, lessThan(stripImage.height));
    stripImage.dispose();
    collageImage.dispose();
  });

  test(
    'no-frame layout refreshes its frame when the selected color changes',
    () async {
      final photo = File(
        '${temporaryDirectory.path}${Platform.pathSeparator}large-photo.png',
      );
      await photo.writeAsBytes(await _encodePhoto(width: 64, height: 48));
      const borderColor = Color(0xFF47667D);
      const alternateBorderColor = Color(0xFFC59AD8);

      final result = await composePhotoStrip([photo], borderColor: borderColor);
      final alternateResult = await composePhotoStrip([
        photo,
      ], borderColor: alternateBorderColor);
      final image = await _decode(result);
      final alternateImage = await _decode(alternateResult);
      try {
        expect(alternateResult.path, isNot(result.path));
        expect(await _pixelAt(image, 0, 0), [0x47, 0x66, 0x7D]);
        expect(await _pixelAt(alternateImage, 0, 0), [0xC5, 0x9A, 0xD8]);
      } finally {
        image.dispose();
        alternateImage.dispose();
      }
    },
  );

  test(
    'photo crop transforms create a separately rendered adjusted layout',
    () async {
      final original = await composePhotoStrip(photos);
      final adjusted = await composePhotoStrip(
        photos,
        photoTransforms: const [
          PhotoCropTransform(zoom: 1.5, pan: ui.Offset(0.12, -0.08)),
        ],
      );

      expect(adjusted.path, isNot(original.path));
      expect(await adjusted.exists(), isTrue);
      final originalImage = await _decode(original);
      final adjustedImage = await _decode(adjusted);
      expect(adjustedImage.width, originalImage.width);
      expect(adjustedImage.height, originalImage.height);
      originalImage.dispose();
      adjustedImage.dispose();
    },
  );

  test(
    'built-in photo sticker choices include 50 decorations and expressions',
    () {
      expect(photoStickerChoices, hasLength(50));
      expect(
        photoStickerChoices.map((sticker) => sticker.label),
        containsAll(['Happy', 'Laughing', 'Sad', 'Scared', 'Ghost']),
      );
    },
  );

  test('photo stickers are burned into the exported image', () async {
    final squarePhoto = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}square-photo.png',
    );
    await squarePhoto.writeAsBytes(await _encodePhoto(width: 128, height: 128));
    final decorated = await applyPhotoStickers(squarePhoto, const [
      PhotoSticker(
        label: 'Star',
        icon: Icons.star_rounded,
        position: ui.Offset(0.5, 0.5),
      ),
    ]);
    final sourceImage = await _decode(squarePhoto);
    final decoratedImage = await _decode(decorated);
    try {
      expect(decorated.path, isNot(squarePhoto.path));
      expect(decoratedImage.width, sourceImage.width);
      expect(decoratedImage.height, sourceImage.height);
      expect(
        await _pixelAt(decoratedImage, 64, 64),
        isNot(await _pixelAt(sourceImage, 64, 64)),
      );
    } finally {
      sourceImage.dispose();
      decoratedImage.dispose();
    }
  });

  test(
    'sticker geometry preserves normalized position and size at any resolution',
    () {
      const sticker = PhotoSticker(
        label: 'Uploaded sticker',
        imagePath: 'sticker.png',
        position: ui.Offset(0.75, 0.25),
        scale: 2,
      );
      final previewGeometry = PhotoStickerGeometry.forSize(
        sticker,
        const ui.Size(320, 960),
      );
      final exportGeometry = PhotoStickerGeometry.forSize(
        sticker,
        const ui.Size(1600, 4800),
      );

      expect(previewGeometry.center, const ui.Offset(240, 240));
      expect(exportGeometry.center / 5, previewGeometry.center);
      expect(previewGeometry.boxSize, closeTo(179.2, 0.001));
      expect(
        exportGeometry.boxSize / 5,
        closeTo(previewGeometry.boxSize, 0.001),
      );
    },
  );

  test('new selected decorations start at a larger size', () {
    const size = ui.Size(320, 960);
    const uploadedSticker = PhotoSticker(
      label: 'Uploaded sticker',
      imagePath: 'sticker.png',
    );
    const builtInSticker = PhotoSticker(
      label: 'Star',
      icon: Icons.star_rounded,
    );

    final uploaded = PhotoStickerGeometry.forSize(
      photoStickerForCanvas(uploadedSticker),
      size,
    );
    final builtIn = PhotoStickerGeometry.forSize(
      photoStickerForCanvas(builtInSticker),
      size,
    );

    expect(uploaded.boxSize, closeTo(120.96, 0.001));
    expect(builtIn.glyphSize, closeTo(51.2, 0.001));
  });

  test(
    'sticker drag keeps the same normalized position at any preview size',
    () {
      const position = ui.Offset(0.45, 0.6);
      const startPoint = ui.Offset(180, 400);
      const drag = ui.Offset(80, -120);

      final previewPosition = photoStickerPositionAfterDrag(
        startPosition: position,
        startFocalPoint: startPoint,
        currentFocalPoint: startPoint + drag,
        canvasSize: const ui.Size(800, 1200),
      );
      final doubledPosition = photoStickerPositionAfterDrag(
        startPosition: position,
        startFocalPoint: startPoint * 2,
        currentFocalPoint: (startPoint + drag) * 2,
        canvasSize: const ui.Size(1600, 2400),
      );

      expect(previewPosition, const ui.Offset(0.55, 0.5));
      expect(doubledPosition, previewPosition);
    },
  );

  test('photo stickers keep their selected vertical position on export', () async {
    final squarePhoto = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}positioned-sticker-photo.png',
    );
    await squarePhoto.writeAsBytes(await _encodePhoto(width: 128, height: 128));
    final decorated = await applyPhotoStickers(squarePhoto, const [
      PhotoSticker(
        label: 'Star',
        icon: Icons.star_rounded,
        position: ui.Offset(0.75, 0.25),
      ),
    ]);
    final sourceImage = await _decode(squarePhoto);
    final image = await _decode(decorated);
    try {
      final sourceCenter = await _pixelAt(sourceImage, 96, 32);
      final decoratedCenter = await _pixelAt(image, 96, 32);
      expect(decoratedCenter, isNot(sourceCenter));
      final sourceAbove = await _pixelAt(sourceImage, 96, 14);
      final decoratedAbove = await _pixelAt(image, 96, 14);
      for (var channel = 0; channel < 3; channel++) {
        expect(
          (decoratedAbove[channel] - sourceAbove[channel]).abs(),
          lessThan(8),
        );
      }
    } finally {
      sourceImage.dispose();
      image.dispose();
    }
  });

  test('rotated decorations are reflected in the exported image', () async {
    final squarePhoto = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}rotated-sticker-photo.png',
    );
    await squarePhoto.writeAsBytes(await _encodePhoto(width: 128, height: 128));
    final original = await applyPhotoStickers(squarePhoto, const [
      PhotoSticker(label: 'Arrow', icon: Icons.arrow_forward_rounded),
    ]);
    final rotated = await applyPhotoStickers(squarePhoto, const [
      PhotoSticker(
        label: 'Arrow',
        icon: Icons.arrow_forward_rounded,
        rotation: math.pi / 2,
      ),
    ]);

    expect(await original.readAsBytes(), isNot(await rotated.readAsBytes()));
  });

  test('custom image stickers preserve their position and scale on export', () async {
    final squarePhoto = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}custom-sticker-photo.png',
    );
    final stickerImage = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}custom-sticker.png',
    );
    await squarePhoto.writeAsBytes(await _encodePhoto(width: 128, height: 128));
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawColor(const ui.Color(0xFFFF0000), ui.BlendMode.src);
    final redImage = await recorder.endRecording().toImage(16, 16);
    try {
      final data = await redImage.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('Test sticker could not be encoded.');
      await stickerImage.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
    } finally {
      redImage.dispose();
    }

    final decorated = await applyPhotoStickers(squarePhoto, [
      PhotoSticker(
        label: 'Uploaded sticker',
        imagePath: stickerImage.path,
        position: const ui.Offset(0.75, 0.25),
        scale: 4.5,
      ),
    ]);
    final decoratedImage = await _decode(decorated);
    try {
      expect(decoratedImage.width, 128);
      expect(decoratedImage.height, 128);
      expect(await _pixelAt(decoratedImage, 96, 32), [255, 0, 0]);
      expect(await _pixelAt(decoratedImage, 5, 125), [32, 64, 128]);
    } finally {
      decoratedImage.dispose();
    }
  });

  test('non-square image stickers keep their preview aspect ratio and center', () async {
    final photo = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}non-square-sticker-photo.png',
    );
    final stickerImage = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}non-square-sticker.png',
    );
    await photo.writeAsBytes(await _encodePhoto(width: 128, height: 128));
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawColor(const ui.Color(0xFFFF0000), ui.BlendMode.src);
    final redImage = await recorder.endRecording().toImage(16, 8);
    try {
      final data = await redImage.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('Test sticker could not be encoded.');
      await stickerImage.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
    } finally {
      redImage.dispose();
    }

    final decorated = await applyPhotoStickers(photo, [
      PhotoSticker(
        label: 'Wide uploaded sticker',
        imagePath: stickerImage.path,
        position: const ui.Offset(0.5, 0.5),
      ),
    ]);
    final image = await _decode(decorated);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) {
        throw StateError('Test image pixels could not be read.');
      }
      var left = image.width;
      var right = -1;
      var top = image.height;
      var bottom = -1;
      for (var y = 0; y < image.height; y++) {
        for (var x = 0; x < image.width; x++) {
          final offset = (y * image.width + x) * 4;
          if (data.getUint8(offset) == 255 &&
              data.getUint8(offset + 1) == 0 &&
              data.getUint8(offset + 2) == 0) {
            left = math.min(left, x);
            right = math.max(right, x);
            top = math.min(top, y);
            bottom = math.max(bottom, y);
          }
        }
      }

      expect((left + right) / 2, closeTo(64, 1));
      expect((top + bottom) / 2, closeTo(64, 1));
      expect((right - left + 1) / (bottom - top + 1), closeTo(2, 0.25));
    } finally {
      image.dispose();
    }
  });

  test(
    'mirrors photo slots without flipping the frame or layout text',
    () async {
      final splitPhoto = File(
        '${temporaryDirectory.path}${Platform.pathSeparator}split-photo.png',
      );
      await splitPhoto.writeAsBytes(await _encodeSplitPhoto());
      final original = await composePhotoStrip([splitPhoto]);
      final mirrored = await composePhotoStrip([
        splitPhoto,
      ], mirrorPhotos: true);
      final originalImage = await _decode(original);
      final mirroredImage = await _decode(mirrored);
      try {
        expect(mirrored.path, endsWith('.strip-mirrored.png'));
        expect(await _pixelAt(originalImage, 25, 50), _isRed);
        expect(await _pixelAt(originalImage, 75, 50), _isBlue);
        expect(await _pixelAt(mirroredImage, 25, 50), _isBlue);
        expect(await _pixelAt(mirroredImage, 75, 50), _isRed);
      } finally {
        originalImage.dispose();
        mirroredImage.dispose();
      }
    },
  );

  test('composites a customer PNG frame over the chosen layout', () async {
    final overlay = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}frame.png',
    );
    await overlay.writeAsBytes(await _encodeFrame(const ui.Color(0xFFFF0000)));

    final framed = await composePhotoStrip([
      photos.first,
    ], framePath: overlay.path);
    expect(await framed.exists(), isTrue);
    expect(framed.path, endsWith('.strip.png'));
  });

  test('uses the SnapLab logo in generated layouts', () async {
    final photo = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}logo-photo.png',
    );
    await photo.writeAsBytes(await _encodePhoto(width: 400, height: 300));
    final output = await composePhotoStrip([photo]);
    final image = await _decode(output);
    try {
      final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      expect(pixels, isNotNull);
      var hasDarkLogoPixel = false;
      for (var y = 18; y < 58 && !hasDarkLogoPixel; y++) {
        for (var x = 30; x < image.width - 30; x++) {
          final offset = (y * image.width + x) * 4;
          if (pixels!.getUint8(offset) < 80 &&
              pixels.getUint8(offset + 1) < 80 &&
              pixels.getUint8(offset + 2) < 80) {
            hasDarkLogoPixel = true;
            break;
          }
        }
      }
      expect(hasDarkLogoPixel, isTrue);
    } finally {
      image.dispose();
    }
  });

  test(
    'customer PNG frame aspect ratio is preserved in the final layout',
    () async {
      final frame = File(
        '${temporaryDirectory.path}${Platform.pathSeparator}portrait-frame.png',
      );
      await frame.writeAsBytes(await _encodePortraitFrame());

      final framed = await composePhotoStrip([
        photos.first,
      ], framePath: frame.path);
      final image = await _decode(framed);
      try {
        final headerHeight = _frameHeaderHeight(image);
        expect(image.height - headerHeight, 16);
        expect(await _pixelAt(image, 0, headerHeight), _isRed);
        expect(await _pixelAt(image, 0, headerHeight + 2), _isRed);
        expect(await _pixelAt(image, 0, headerHeight + 12), _isBlue);
      } finally {
        image.dispose();
      }
    },
  );

  test('detects uploaded frame photo counts and composes into its openings', () async {
    final logo = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}uploaded-frame-logo.png',
    );
    await logo.writeAsBytes(await _encodeFrame(const ui.Color(0xFFFF0000)));
    for (var count = 1; count <= 5; count++) {
      final frame = File(
        '${temporaryDirectory.path}${Platform.pathSeparator}layout-$count.png',
      );
      await frame.writeAsBytes(await _encodeLayoutFrame(count));

      final template = await customerPhotoFrameTemplate(frame.path);
      expect(template.photoCount, count);
      expect(template.photoSlots, hasLength(count));
      for (var index = 1; index < count; index++) {
        expect(
          template.photoSlots[index].center.dy,
          greaterThan(template.photoSlots[index - 1].center.dy),
        );
      }

      if (count == 3) {
        final largePhoto = File(
          '${temporaryDirectory.path}${Platform.pathSeparator}uploaded-frame-photo.png',
        );
        await largePhoto.writeAsBytes(
          await _encodePhoto(width: 400, height: 300),
        );
        final output = await composePhotoStrip(
          List<File>.filled(count, largePhoto),
          frameTemplate: template,
          brandLogoPath: logo.path,
        );
        final image = await _decode(output);
        try {
          final headerHeight = _frameHeaderHeight(image);
          expect(image.height - headerHeight, image.width * 3 ~/ 2);
          expect(
            await _pixelAt(image, image.width ~/ 2, headerHeight ~/ 2),
            _isRed,
          );
        } finally {
          image.dispose();
        }
      }
    }
  });

  test(
    'phone-uploaded portrait frames keep their aspect ratio on photo layouts',
    () async {
      final frame = File(
        '${temporaryDirectory.path}${Platform.pathSeparator}phone-frame.png',
      );
      await frame.writeAsBytes(await _encodePhonePortraitFrame());

      final template = await customerPhotoFrameTemplate(frame.path);
      expect(template.photoCount, 3);
      final output = await composePhotoStrip(
        List<File>.filled(3, photos.first),
        frameTemplate: template,
      );
      final image = await _decode(output);
      try {
        final frameHeight = image.height - _frameHeaderHeight(image);
        expect(image.width / frameHeight, closeTo(643 / 2048, 0.01));
      } finally {
        image.dispose();
      }
    },
  );

  test(
    'oversized uploaded frames retain their original aspect ratio',
    () async {
      final frame = File(
        '${temporaryDirectory.path}${Platform.pathSeparator}wide-frame.png',
      );
      await frame.writeAsBytes(await _encodeWideLayoutFrame());

      final template = await customerPhotoFrameTemplate(frame.path);
      final output = await composePhotoStrip(
        List<File>.filled(3, photos.first),
        frameTemplate: template,
      );
      final image = await _decode(output);
      try {
        final frameHeight = image.height - _frameHeaderHeight(image);
        expect(image.width / frameHeight, closeTo(2, 0.01));
        expect(template.photoSlots, hasLength(3));
        expect(template.photoSlots.first.center.dy, lessThan(0.5));
        expect(template.photoSlots.last.center.dy, greaterThan(0.5));
      } finally {
        image.dispose();
      }
    },
  );

  test('uploaded frame decoration stays over photo inside an opening', () async {
    final frame = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}decorated-frame.png',
    );
    await frame.writeAsBytes(
      await _encodeLayoutFrame(3, decorateFirstOpening: true),
    );
    final photo = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}red-photo.png',
    );
    await photo.writeAsBytes(
      await _encodePhoto(
        color: const ui.Color(0xFFFF0000),
        width: 400,
        height: 300,
      ),
    );

    final template = await customerPhotoFrameTemplate(frame.path);
    final output = await composePhotoStrip(
      List<File>.filled(3, photo),
      frameTemplate: template,
    );
    final image = await _decode(output);
    try {
      const height = 300.0;
      const openingHeight = 35.0;
      const gap = 10.0;
      final headerHeight = _frameHeaderHeight(image);
      final frameHeight = image.height - headerHeight;
      final openingStartY = (height - (3 * openingHeight + 2 * gap)) / 2;
      final decoration = await _pixelAt(
        image,
        (0.5 * image.width).round(),
        headerHeight +
            ((openingStartY + openingHeight / 2) / height * frameHeight)
                .round(),
      );
      expect(decoration[1], greaterThan(180));
      expect(decoration[0], lessThan(80));

      final photoPoint = await _pixelAt(
        image,
        (0.35 * image.width).round(),
        headerHeight +
            ((openingStartY + openingHeight / 2) / height * frameHeight)
                .round(),
      );
      expect(photoPoint[0], greaterThan(180));
      expect(photoPoint[1], lessThan(80));
    } finally {
      image.dispose();
    }
  });

  test(
    'rejects uploaded frames without detected transparent openings',
    () async {
      final frame = File(
        '${temporaryDirectory.path}${Platform.pathSeparator}opaque-frame.png',
      );
      await frame.writeAsBytes(await _encodeFrame(const ui.Color(0xFFFF0000)));

      expect(customerPhotoFrameTemplate(frame.path), throwsFormatException);
    },
  );

  test('uses the captured date in the output filename', () async {
    final largePhoto = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}date-photo.png',
    );
    await largePhoto.writeAsBytes(await _encodePhoto(width: 400, height: 300));
    final firstDate = await composePhotoStrip([
      largePhoto,
    ], captureDate: DateTime(2026, 6, 8));
    final nextDate = await composePhotoStrip([
      largePhoto,
    ], captureDate: DateTime(2026, 6, 9));
    final withoutDate = await composePhotoStrip([largePhoto]);
    final firstImage = await _decode(firstDate);
    final nextImage = await _decode(nextDate);
    final imageWithoutDate = await _decode(withoutDate);
    try {
      expect(firstDate.path, contains('-date-20260608.png'));
      expect(nextDate.path, contains('-date-20260609.png'));
      expect(firstImage.width, imageWithoutDate.width);
      expect(firstImage.height, imageWithoutDate.height);
      expect(firstDate.path, isNot(nextDate.path));
    } finally {
      firstImage.dispose();
      nextImage.dispose();
      imageWithoutDate.dispose();
    }
  });

  test('capture date appears below the logo in the branded photo header', () async {
    final photo = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}dated-header-photo.png',
    );
    await photo.writeAsBytes(await _encodePhoto(width: 400, height: 300));
    final withoutDate = await composePhotoStrip([photo]);
    final withDate = await composePhotoStrip([
      photo,
    ], captureDate: DateTime(2026, 6, 8));
    final baseImage = await _decode(withoutDate);
    final datedImage = await _decode(withDate);
    try {
      expect(datedImage.width, baseImage.width);
      expect(datedImage.height, baseImage.height);
      final basePixels = await baseImage.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      final datedPixels = await datedImage.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      expect(basePixels, isNotNull);
      expect(datedPixels, isNotNull);
      final firstHeaderRow = (baseImage.width * 0.15).round();
      final lastHeaderRow = (baseImage.width * 0.205).round();
      var changedHeaderPixel = false;
      for (var y = firstHeaderRow; y < lastHeaderRow; y++) {
        for (var x = 0; x < datedImage.width; x++) {
          final offset = (y * datedImage.width + x) * 4;
          for (var channel = 0; channel < 3; channel++) {
            if (basePixels!.getUint8(offset + channel) !=
                datedPixels!.getUint8(offset + channel)) {
              changedHeaderPixel = true;
              break;
            }
          }
          if (changedHeaderPixel) break;
        }
        if (changedHeaderPixel) break;
      }
      expect(changedHeaderPixel, isTrue);
    } finally {
      baseImage.dispose();
      datedImage.dispose();
    }
  });

  test('classic frames add a date footer when the header has no room', () async {
    final photo = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}classic-date-photo.png',
    );
    await photo.writeAsBytes(await _encodePhoto(width: 400, height: 300));
    for (final template in classicPhotoFrameTemplates) {
      final photos = List<File>.filled(template.photoCount, photo);
      final withoutDate = await composePhotoStrip(
        photos,
        frameTemplate: template,
      );
      final withDate = await composePhotoStrip(
        photos,
        frameTemplate: template,
        captureDate: DateTime(2026, 6, 8),
      );
      final baseImage = await _decode(withoutDate);
      final datedImage = await _decode(withDate);
      try {
        expect(
          datedImage.height,
          greaterThan(baseImage.height),
          reason: 'Classic frame ${template.id} should show its capture date.',
        );
      } finally {
        baseImage.dispose();
        datedImage.dispose();
      }
    }
  });

  test('capture date footer stays below bundled frame artwork', () async {
    final photo = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}dated-frame-photo.png',
    );
    await photo.writeAsBytes(await _encodePhoto(width: 400, height: 300));
    final template = photoFrameTemplateById(
      'snaplab-good-vibes-long-one-photo',
    )!;
    const dateFooterColor = ui.Color(0xFFF8E0B2);
    final withoutDate = await composePhotoStrip(
      [photo],
      frameTemplate: template,
      borderColor: dateFooterColor,
    );
    final withDate = await composePhotoStrip(
      [photo],
      frameTemplate: template,
      borderColor: dateFooterColor,
      captureDate: DateTime(2026, 6, 8),
    );
    final baseImage = await _decode(withoutDate);
    final datedImage = await _decode(withDate);
    try {
      expect(datedImage.width, baseImage.width);
      expect(datedImage.height, greaterThan(baseImage.height));
      for (final x in [0, baseImage.width ~/ 2, baseImage.width - 1]) {
        final basePixel = await _pixelAt(baseImage, x, baseImage.height - 1);
        final datedPixel = await _pixelAt(datedImage, x, baseImage.height - 1);
        for (var channel = 0; channel < 3; channel++) {
          expect(datedPixel[channel], closeTo(basePixel[channel], 16));
        }
      }
      final footerPixel = await _pixelAt(
        datedImage,
        2,
        baseImage.height + (datedImage.height - baseImage.height) ~/ 2,
      );
      expect(footerPixel[0], closeTo(0xF8, 16));
      expect(footerPixel[1], closeTo(0xE0, 16));
      expect(footerPixel[2], closeTo(0xB2, 16));
    } finally {
      baseImage.dispose();
      datedImage.dispose();
    }
  });

  test(
    'custom photo border covers the full crop without a dark outline',
    () async {
      final largePhoto = File(
        '${temporaryDirectory.path}${Platform.pathSeparator}border-photo.png',
      );
      final border = File(
        '${temporaryDirectory.path}${Platform.pathSeparator}photo-border.png',
      );
      await largePhoto.writeAsBytes(
        await _encodePhoto(width: 100, height: 100),
      );
      await border.writeAsBytes(await _encodePhotoBorder());

      final composed = await composePhotoStrip([
        largePhoto,
      ], photoBorderOverlayPath: border.path);
      final image = await _decode(composed);
      try {
        expect(await _pixelAt(image, 50, 22), _isRed);
        expect(await _pixelAt(image, 50, 24), _isRed);
        expect(await _pixelAt(image, 50, 50), _isPhotoColor);
        final outsideEdge = await _pixelAt(image, 4, 50);
        expect(outsideEdge.every((channel) => channel > 150), isTrue);
      } finally {
        image.dispose();
      }
    },
  );

  test(
    'each bundled frame fills every photo window with a captured photo',
    () async {
      final largePhoto = File(
        '${temporaryDirectory.path}${Platform.pathSeparator}template-photo.png',
      );
      final logo = File(
        '${temporaryDirectory.path}${Platform.pathSeparator}template-logo.png',
      );
      await largePhoto.writeAsBytes(
        await _encodePhoto(width: 400, height: 300),
      );
      await logo.writeAsBytes(await _encodeFrame(const ui.Color(0xFFFF0000)));
      for (final template in photoFrameTemplates) {
        final framed = await composePhotoStrip(
          List<File>.filled(template.photoCount, largePhoto),
          frameTemplate: template,
          brandLogoPath: logo.path,
        );
        final image = await _decode(framed);
        try {
          final headerHeight = _frameHeaderHeight(image);
          final frameHeight = image.height - headerHeight;
          expect(
            await _pixelAt(image, image.width ~/ 2, headerHeight ~/ 2),
            _isRed,
            reason: '${template.label} should show the brand logo at the top',
          );
          expect(
            image.width / frameHeight,
            closeTo(await _frameAspectRatio(template.assetPath), 0.002),
            reason: template.label,
          );
          final pixels = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          expect(pixels, isNotNull);
          for (
            var slotIndex = 0;
            slotIndex < template.photoSlots.length;
            slotIndex++
          ) {
            final slot = template.photoSlots[slotIndex];
            final rotation = template.rotationForSlot(slotIndex);
            final center = Offset(
              slot.left + slot.width / 2,
              slot.top + slot.height / 2,
            );
            Offset rotatePoint(Offset point) {
              final dx = point.dx - center.dx;
              final dy = point.dy - center.dy;
              return Offset(
                center.dx + dx * math.cos(rotation) - dy * math.sin(rotation),
                center.dy + dx * math.sin(rotation) + dy * math.cos(rotation),
              );
            }

            final photoSamplePoints = template.foregroundArtwork
                ? [
                    rotatePoint(
                      ui.Offset(
                        slot.left + slot.width / 2,
                        slot.top + slot.height / 2,
                      ),
                    ),
                  ]
                : [
                    rotatePoint(
                      ui.Offset(
                        slot.left + slot.width * 0.10,
                        slot.top + slot.height / 2,
                      ),
                    ),
                    rotatePoint(
                      ui.Offset(
                        slot.right - slot.width * 0.10,
                        slot.top + slot.height / 2,
                      ),
                    ),
                    rotatePoint(
                      ui.Offset(
                        slot.left + slot.width / 2,
                        slot.top + slot.height * 0.10,
                      ),
                    ),
                    rotatePoint(
                      ui.Offset(
                        slot.left + slot.width / 2,
                        slot.bottom - slot.height * 0.10,
                      ),
                    ),
                  ];
            for (final point in photoSamplePoints) {
              final x = (point.dx * image.width).floor();
              final y = headerHeight + (point.dy * frameHeight).floor();
              final offset = (y * image.width + x) * 4;
              expect(
                pixels!.getUint8(offset),
                closeTo(32, 12),
                reason: template.label,
              );
              expect(
                pixels.getUint8(offset + 1),
                closeTo(64, 12),
                reason: template.label,
              );
              expect(
                pixels.getUint8(offset + 2),
                closeTo(128, 12),
                reason: template.label,
              );
            }
            final outsideWindowPoints = [
              rotatePoint(
                ui.Offset(
                  slot.left - slot.width * 0.01,
                  slot.top + slot.height / 2,
                ),
              ),
              rotatePoint(
                ui.Offset(
                  slot.right + slot.width * 0.01,
                  slot.top + slot.height / 2,
                ),
              ),
              rotatePoint(
                ui.Offset(
                  slot.left + slot.width / 2,
                  slot.top - slot.height * 0.01,
                ),
              ),
              rotatePoint(
                ui.Offset(
                  slot.left + slot.width / 2,
                  slot.bottom + slot.height * 0.01,
                ),
              ),
            ];
            for (final point in outsideWindowPoints) {
              if (point.dx < 0 ||
                  point.dx >= 1 ||
                  point.dy < 0 ||
                  point.dy >= 1 ||
                  template.photoSlots.asMap().entries.any(
                    (entry) =>
                        entry.key != slotIndex && entry.value.contains(point),
                  )) {
                continue;
              }
              final pixel = await _pixelAt(
                image,
                (point.dx * image.width).floor(),
                headerHeight + (point.dy * frameHeight).floor(),
              );
              expect(
                pixel,
                isNot(_isPhotoColor),
                reason: '${template.label} photo overflow at $point',
              );
            }
          }
        } finally {
          image.dispose();
        }
      }
    },
  );

  test('bundled frame artwork overlays photo edges', () async {
    final template = photoFrameTemplates.first;
    final framed = await composePhotoStrip(
      List<File>.filled(template.photoCount, photos.first),
      frameTemplate: template,
    );
    final image = await _decode(framed);
    try {
      final slot = template.photoSlots.first;
      final headerHeight = _frameHeaderHeight(image);
      final frameHeight = image.height - headerHeight;
      final artworkEdge = await _pixelAt(
        image,
        ((slot.left + slot.width * 0.01) * image.width).floor(),
        headerHeight + ((slot.top + slot.height / 2) * frameHeight).floor(),
      );
      final photoCenter = await _pixelAt(
        image,
        ((slot.left + slot.width / 2) * image.width).floor(),
        headerHeight + ((slot.top + slot.height / 2) * frameHeight).floor(),
      );

      expect(artworkEdge, isNot([32, 64, 128]));
      expect(photoCenter[2], greaterThan(photoCenter[0]));
      expect(photoCenter[2], greaterThan(100));
    } finally {
      image.dispose();
    }
  });

  test(
    'blue beige camera and butterfly artwork stay in front of photos',
    () async {
      final template = photoFrameTemplateById('blue-beige-playful-three')!;
      final framed = await composePhotoStrip(
        List<File>.filled(template.photoCount, photos.first),
        frameTemplate: template,
      );
      final image = await _decode(framed);
      try {
        final point = await _findForegroundArtworkPoint(
          'blue-beige-playful-three',
        );
        expect(
          await _pixelAt(
            image,
            (point.dx * image.width).round(),
            _frameHeaderHeight(image) +
                (point.dy * (image.height - _frameHeaderHeight(image))).round(),
          ),
          isNot(_isPhotoColor),
          reason: 'Decorative frame artwork was covered at $point',
        );
      } finally {
        image.dispose();
      }
    },
  );

  test('green polaroid borders stay above overlapping photos', () async {
    final template = photoFrameTemplateById('green-polaroid-three')!;
    final framed = await composePhotoStrip(
      List<File>.filled(template.photoCount, photos.first),
      frameTemplate: template,
    );
    final image = await _decode(framed);
    try {
      final point = await _findForegroundArtworkPoint('green-polaroid-three');
      expect(
        await _pixelAt(
          image,
          (point.dx * image.width).round(),
          _frameHeaderHeight(image) +
              (point.dy * (image.height - _frameHeaderHeight(image))).round(),
        ),
        isNot(_isPhotoColor),
        reason: 'Overlapping polaroid border was covered at $point',
      );
    } finally {
      image.dispose();
    }
  });

  test('green polaroid photos stay inside their transparent windows', () async {
    final template = photoFrameTemplateById('green-polaroid-three')!;
    final colors = [
      const ui.Color(0xFFFF0000),
      const ui.Color(0xFF00FF00),
      const ui.Color(0xFF0000FF),
    ];
    final outputs = <File>[];
    for (var index = 0; index < colors.length; index++) {
      final photo = File(
        '${temporaryDirectory.path}${Platform.pathSeparator}window-$index.png',
      );
      await photo.writeAsBytes(
        await _encodePhoto(color: colors[index], width: 120, height: 90),
      );
      outputs.add(
        await composePhotoStrip(
          List<File>.filled(template.photoCount, photo),
          frameTemplate: template,
        ),
      );
    }

    final images = await Future.wait(outputs.map(_decode));
    try {
      final headerHeight = _frameHeaderHeight(images.first);
      for (final point in [const Offset(61, 61), const Offset(87, 110)]) {
        final reference = await _pixelAt(
          images.first,
          point.dx.round(),
          headerHeight + point.dy.round(),
        );
        for (final image in images.skip(1)) {
          final pixel = await _pixelAt(
            image,
            point.dx.round(),
            _frameHeaderHeight(image) + point.dy.round(),
          );
          for (var channel = 0; channel < 3; channel++) {
            expect(
              (pixel[channel] - reference[channel]).abs(),
              lessThanOrEqualTo(3),
              reason: 'Photo content leaked into frame artwork at $point',
            );
          }
        }
      }
    } finally {
      for (final image in images) {
        image.dispose();
      }
    }
  });

  test('green polaroid photos stay in their assigned windows', () async {
    final template = photoFrameTemplateById('green-polaroid-three')!;
    final photoColors = [
      const ui.Color(0xFFFF0000),
      const ui.Color(0xFF00FF00),
      const ui.Color(0xFF0000FF),
    ];
    final coloredPhotos = <File>[];
    for (var index = 0; index < photoColors.length; index++) {
      final photo = File(
        '${temporaryDirectory.path}${Platform.pathSeparator}layer-$index.png',
      );
      await photo.writeAsBytes(
        await _encodePhoto(color: photoColors[index], width: 120, height: 90),
      );
      coloredPhotos.add(photo);
    }

    final framed = await composePhotoStrip(
      coloredPhotos,
      frameTemplate: template,
    );
    final image = await _decode(framed);
    try {
      expect(
        await _pixelAt(
          image,
          (image.width * 0.5).round(),
          _frameHeaderHeight(image) +
              ((image.height - _frameHeaderHeight(image)) * 0.18).round(),
        ),
        _isRed,
      );
      expect(
        await _pixelAt(
          image,
          (image.width * 0.45).round(),
          _frameHeaderHeight(image) +
              ((image.height - _frameHeaderHeight(image)) * 0.48).round(),
        ),
        _isGreen,
      );
      expect(
        await _pixelAt(
          image,
          (image.width * 0.55).round(),
          _frameHeaderHeight(image) +
              ((image.height - _frameHeaderHeight(image)) * 0.81).round(),
        ),
        _isBlue,
      );
    } finally {
      image.dispose();
    }
  });

  test('capture date is printed outside custom frame artwork', () async {
    final overlay = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}colored-frame.png',
    );
    final largePhoto = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}colored-frame-photo.png',
    );
    await overlay.writeAsBytes(await _encodeFrame(const ui.Color(0xFFB03020)));
    await largePhoto.writeAsBytes(await _encodePhoto(width: 400, height: 300));
    final framed = await composePhotoStrip(
      [largePhoto],
      framePath: overlay.path,
      captureDate: DateTime(2026, 6, 8),
    );
    final image = await _decode(framed);
    try {
      final dateFooter = await _pixelAt(
        image,
        (image.width * 0.35).round(),
        image.height - 11,
      );
      expect(dateFooter, [255, 255, 255]);
    } finally {
      image.dispose();
    }
  });

  test('keeps custom frame below the logo when composing the saved photo', () async {
    final overlay = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}logo-frame.png',
    );
    await overlay.writeAsBytes(await _encodeFrame(const ui.Color(0xFF204080)));
    final logo = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}custom-brand.png',
    );
    final largePhoto = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}custom-frame-photo.png',
    );
    await logo.writeAsBytes(await _encodeFrame(const ui.Color(0xFFFF0000)));
    await largePhoto.writeAsBytes(await _encodePhoto(width: 400, height: 300));

    final framed = await composePhotoStrip(
      [largePhoto],
      framePath: overlay.path,
      brandLogoPath: logo.path,
    );
    final image = await _decode(framed);
    try {
      expect(image.width, 400);
      final headerHeight = _frameHeaderHeight(image);
      expect(image.height - headerHeight, 300);
      expect(
        await _pixelAt(image, image.width ~/ 2, headerHeight ~/ 2),
        _isRed,
      );
      expect(await _pixelAt(image, 0, headerHeight + 10), [0x20, 0x40, 0x80]);
    } finally {
      image.dispose();
    }
  });

  test(
    'rejects a photo count that does not match the selected frame',
    () async {
      final fourPhotoFrame = photoFrameTemplates.first;
      await expectLater(
        composePhotoStrip([photos.first], frameTemplate: fourPhotoFrame),
        throwsArgumentError,
      );
    },
  );

  test('bundled frames require the number of photos in their openings', () {
    expect(photoFrameTemplates.map((template) => template.photoCount), [
      4,
      4,
      4,
      3,
      3,
      4,
      5,
      4,
      3,
      3,
      3,
      2,
      3,
      4,
      2,
      3,
      2,
      1,
      2,
      3,
      4,
      5,
      3,
      3,
      3,
      3,
      1,
      3,
      2,
      3,
      2,
      1,
      2,
      3,
      4,
      5,
      1,
      2,
      3,
      4,
      5,
    ]);
    expect(photoFrameTemplateById('cream-maroon-strip-four')?.photoCount, 4);
    expect(photoFrameTemplateById('beige-collage-five')?.photoCount, 5);
    expect(
      photoFrameTemplateById('snaplab-travel-receipt-5-photo')?.photoCount,
      5,
    );
    expect(
      photoFrameTemplateById('green-polaroid-three')?.photoSlotRotations,
      hasLength(3),
    );
  });
}

Future<ui.Image> _decodeBytes(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  try {
    return (await codec.getNextFrame()).image;
  } finally {
    codec.dispose();
  }
}

Future<double> _frameAspectRatio(String assetPath) async {
  final data = await rootBundle.load(assetPath);
  final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
  try {
    final image = (await codec.getNextFrame()).image;
    try {
      return image.width / image.height;
    } finally {
      image.dispose();
    }
  } finally {
    codec.dispose();
  }
}

Future<Uint8List> _encodePhoto({
  int width = 4,
  int height = 3,
  ui.Color color = const ui.Color(0xFF204080),
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawColor(color, ui.BlendMode.src);
  final image = await recorder.endRecording().toImage(width, height);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('Test photo could not be encoded.');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image.dispose();
  }
}

Future<Offset> _findForegroundArtworkPoint(String frameId) async {
  final template = photoFrameTemplateById(frameId)!;
  final data = await rootBundle.load(template.assetPath);
  final frame = await _decodeBytes(data.buffer.asUint8List());
  try {
    final pixels = await frame.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (pixels == null) {
      throw StateError('Could not read $frameId artwork pixels');
    }

    for (var y = 0; y < frame.height; y += 6) {
      for (var x = 0; x < frame.width; x += 6) {
        final offset = (y * frame.width + x) * 4;
        final alpha = pixels.getUint8(offset + 3);
        if (alpha <= 16) continue;
        final point = Offset(x / frame.width, y / frame.height);
        final isInsidePhotoSlot = template.photoSlots.any(
          (slot) => slot.contains(point),
        );
        if (!isInsidePhotoSlot) {
          return point;
        }
      }
    }
    throw StateError('No foreground artwork point found for $frameId.');
  } finally {
    frame.dispose();
  }
}

int _frameHeaderHeight(ui.Image image) =>
    math.max((image.width * 0.18).round(), 1).toInt();

Future<Uint8List> _encodeSplitPhoto() async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    const ui.Rect.fromLTWH(0, 0, 50, 100),
    ui.Paint()..color = const ui.Color(0xFFFF0000),
  );
  canvas.drawRect(
    const ui.Rect.fromLTWH(50, 0, 50, 100),
    ui.Paint()..color = const ui.Color(0xFF0000FF),
  );
  final image = await recorder.endRecording().toImage(100, 100);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('Test photo could not be encoded.');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image.dispose();
  }
}

Future<List<int>> _pixelAt(ui.Image image, int x, int y) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (data == null) throw StateError('Test image could not be read.');
  final offset = (y * image.width + x) * 4;
  return [
    data.getUint8(offset),
    data.getUint8(offset + 1),
    data.getUint8(offset + 2),
  ];
}

final _isRed = predicate<List<int>>(
  (pixel) => pixel[0] > 240 && pixel[1] < 10 && pixel[2] < 10,
);
final _isBlue = predicate<List<int>>(
  (pixel) => pixel[0] < 10 && pixel[1] < 10 && pixel[2] > 240,
);
final _isGreen = predicate<List<int>>(
  (pixel) => pixel[0] < 10 && pixel[1] > 240 && pixel[2] < 10,
);
final _isPhotoColor = predicate<List<int>>(
  (pixel) =>
      pixel[2] > pixel[0] + 40 && pixel[2] > pixel[1] + 30 && pixel[2] > 100,
);

Future<ui.Image> _decode(File file) async {
  final codec = await ui.instantiateImageCodec(await file.readAsBytes());
  try {
    return (await codec.getNextFrame()).image;
  } finally {
    codec.dispose();
  }
}

Future<Uint8List> _encodeFrame(ui.Color color) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawColor(color, ui.BlendMode.src);
  final image = await recorder.endRecording().toImage(4, 3);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) {
      throw StateError('Frame test image could not be encoded.');
    }
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image.dispose();
  }
}

Future<Uint8List> _encodePortraitFrame() async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    const ui.Rect.fromLTWH(0, 0, 40, 80),
    ui.Paint()..color = const ui.Color(0xFFFF0000),
  );
  canvas.drawRect(
    const ui.Rect.fromLTWH(0, 80, 40, 80),
    ui.Paint()..color = const ui.Color(0xFF0000FF),
  );
  final image = await recorder.endRecording().toImage(40, 160);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) {
      throw StateError('Portrait frame test image could not be encoded.');
    }
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image.dispose();
  }
}

Future<Uint8List> _encodeLayoutFrame(
  int photoCount, {
  bool decorateFirstOpening = false,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawColor(const ui.Color(0xFF47708B), ui.BlendMode.src);
  const width = 200.0;
  const height = 300.0;
  const openingHeight = 35.0;
  const gap = 10.0;
  final totalHeight = photoCount * openingHeight + (photoCount - 1) * gap;
  final startY = (height - totalHeight) / 2;
  final clearPaint = ui.Paint()..blendMode = ui.BlendMode.clear;
  for (var index = 0; index < photoCount; index++) {
    canvas.drawRect(
      ui.Rect.fromLTWH(
        40,
        startY + index * (openingHeight + gap),
        120,
        openingHeight,
      ),
      clearPaint,
    );
  }

  if (decorateFirstOpening) {
    canvas.drawRect(
      ui.Rect.fromLTWH(94, startY + openingHeight / 2 - 6, 12, 12),
      ui.Paint()..color = const ui.Color(0xFF00FF00),
    );
  }
  final image = await recorder.endRecording().toImage(
    width.toInt(),
    height.toInt(),
  );
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) {
      throw StateError('Layout frame test image could not be encoded.');
    }
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image.dispose();
  }
}

Future<Uint8List> _encodePhonePortraitFrame() async {
  const width = 643;
  const height = 2048;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawColor(const ui.Color(0xFF159B64), ui.BlendMode.src);
  final clearPaint = ui.Paint()..blendMode = ui.BlendMode.clear;
  for (var index = 0; index < 3; index++) {
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(
        ui.Rect.fromLTWH(72, 170 + index * 600, 500, 500),
        const ui.Radius.circular(36),
      ),
      clearPaint,
    );
  }
  final image = await recorder.endRecording().toImage(width, height);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) {
      throw StateError('Portrait frame test image could not be encoded.');
    }
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image.dispose();
  }
}

Future<Uint8List> _encodeWideLayoutFrame() async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawColor(const ui.Color(0xFF47708B), ui.BlendMode.src);
  final clearPaint = ui.Paint()..blendMode = ui.BlendMode.clear;
  for (var index = 0; index < 3; index++) {
    canvas.drawRect(
      ui.Rect.fromLTWH(550, 100 + index * 250, 700, 150),
      clearPaint,
    );
  }
  final image = await recorder.endRecording().toImage(1800, 900);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) {
      throw StateError('Wide frame test image could not be encoded.');
    }
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image.dispose();
  }
}

Future<Uint8List> _encodePhotoBorder() async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final paint = ui.Paint()..color = const ui.Color(0xFFFF0000);
  canvas.drawRect(const ui.Rect.fromLTWH(0, 0, 100, 10), paint);
  canvas.drawRect(const ui.Rect.fromLTWH(0, 90, 100, 10), paint);
  canvas.drawRect(const ui.Rect.fromLTWH(0, 0, 10, 100), paint);
  canvas.drawRect(const ui.Rect.fromLTWH(90, 0, 10, 100), paint);
  final image = await recorder.endRecording().toImage(100, 100);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) {
      throw StateError('Photo border could not be encoded.');
    }
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image.dispose();
  }
}
