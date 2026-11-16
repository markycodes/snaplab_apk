import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photobooth_kiosk/session_gif.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'photobooth-gif-test-',
    );
  });

  tearDown(() async {
    await temporaryDirectory.delete(recursive: true);
  });

  test('encodes capture photos as a looping animated GIF', () async {
    final first = await writePng(
      temporaryDirectory,
      'first.png',
      800,
      600,
      0xFFFF0000,
    );
    final second = await writePng(
      temporaryDirectory,
      'second.png',
      600,
      800,
      0xFF0000FF,
    );

    final gif = await createSessionGif([first, second]);

    expect(gif.path, endsWith('.gif'));
    expect(await gif.exists(), isTrue);
    final decoded = img.decodeGif(await gif.readAsBytes());
    expect(decoded, isNotNull);
    expect(decoded!.numFrames, 3);
    expect(decoded.width, lessThanOrEqualTo(480));
    expect(decoded.height, lessThanOrEqualTo(480));
  });

  test(
    'animates only the five captured photos without a framed final photo',
    () async {
      final photos = <File>[];
      for (var index = 0; index < 5; index++) {
        photos.add(
          await writePng(
            temporaryDirectory,
            'session-$index.png',
            60,
            40,
            0xFF000000 + (index + 1) * 0x00010101,
          ),
        );
      }

      final gif = await createSessionGif(photos);
      final decoded = img.decodeGif(await gif.readAsBytes());

      expect(decoded, isNotNull);
      expect(decoded!.numFrames, 8);
    },
  );

  test('rejects empty and oversized photo sets', () async {
    await expectLater(createSessionGif([]), throwsArgumentError);
    final photos = <File>[];
    for (var index = 0; index < 7; index++) {
      photos.add(
        await writePng(
          temporaryDirectory,
          'photo-$index.png',
          20,
          20,
          0xFF000000 + index,
        ),
      );
    }
    await expectLater(createSessionGif(photos), throwsArgumentError);
  });
}

Future<File> writePng(
  Directory directory,
  String name,
  int width,
  int height,
  int color,
) async {
  final image = img.Image(width: width, height: height);
  img.fill(
    image,
    color: img.ColorRgba8(
      (color >> 16) & 0xFF,
      (color >> 8) & 0xFF,
      color & 0xFF,
      (color >> 24) & 0xFF,
    ),
  );
  final file = File('${directory.path}${Platform.pathSeparator}$name');
  await file.writeAsBytes(img.encodePng(image));
  return file;
}
