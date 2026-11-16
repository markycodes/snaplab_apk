import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:photobooth_kiosk/ai_cartoon_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('uses the built-in secure AI cartoon endpoint', () {
    expect(defaultAiCartoonEndpoint, 'https://snaplabbooth.com/pb_cartoon.php');
  });

  group('AiCartoonService.validateEndpoint', () {
    test('accepts a secure HTTPS endpoint', () {
      expect(
        AiCartoonService.validateEndpoint(
          'https://snaplabbooth.com/photobooth/pb_cartoon.php',
        ),
        Uri.parse('https://snaplabbooth.com/photobooth/pb_cartoon.php'),
      );
    });

    test('rejects insecure, credentialed, or parameterized endpoints', () {
      for (final endpoint in [
        'http://snaplabbooth.com/pb_cartoon.php',
        'snaplabbooth.com/pb_cartoon.php',
        'https:///pb_cartoon',
        'https://user@snaplabbooth.com/pb_cartoon.php',
        'https://snaplabbooth.com/pb_cartoon.php?token=secret',
      ]) {
        expect(
          () => AiCartoonService.validateEndpoint(endpoint),
          throwsFormatException,
        );
      }
    });
  });

  test(
    'authorizes and uploads the compressed photo with the bearer token',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'photobooth-ai-cartoon-test',
      );
      final photo = File('${directory.path}\\photo.png');
      final image = img.Image(width: 8, height: 8);
      image.setPixelRgb(0, 0, 255, 0, 0);
      final jpegBytes = img.encodeJpg(image);
      await photo.writeAsBytes(img.encodePng(image));
      final seenRequests = <http.BaseRequest>[];
      final client = MockClient((request) async {
        seenRequests.add(request);
        if (request.url.path.endsWith('/pb_auth')) {
          expect(jsonDecode(request.body), {
            'deviceId': 'device-12345678',
            'activationCode': 'A' * 86,
          });
          return http.Response(
            jsonEncode({'accessToken': 'payload.signature'}),
            HttpStatus.ok,
          );
        }

        expect(request.url.path, '/pb_cartoon.php');
        expect(
          request.headers.entries
              .firstWhere((entry) => entry.key.toLowerCase() == 'authorization')
              .value,
          'Bearer payload.signature',
        );
        expect(
          utf8.decode(request.bodyBytes, allowMalformed: true),
          contains('portrait.jpg'),
        );
        expect(
          utf8.decode(request.bodyBytes, allowMalformed: true),
          contains('name="style"\r\n\r\nanime\r\n'),
        );
        return http.Response.bytes(
          jpegBytes,
          HttpStatus.ok,
          headers: const {
            'content-type': 'image/jpeg',
            'x-snaplab-ai-style': 'anime',
          },
        );
      });

      try {
        final result = await AiCartoonService(client: client).generate(
          photo: photo,
          endpoint: defaultAiCartoonEndpoint,
          deviceId: 'device-12345678',
          activationCode: 'A' * 86,
          style: AiPhotoStyle.anime,
        );
        expect(result.path, '${photo.path}.ai-cartoon.jpg');
        expect(await result.readAsBytes(), jpegBytes);
        expect(seenRequests.map((request) => request.url.path), [
          '/pb_auth',
          '/pb_cartoon.php',
        ]);
      } finally {
        client.close();
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'rejects an AI server that does not confirm the requested style',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'photobooth-ai-style-test',
      );
      final photo = File('${directory.path}\\photo.png');
      final image = img.Image(width: 8, height: 8);
      await photo.writeAsBytes(img.encodePng(image));
      var generationRequest = false;
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/pb_auth')) {
          return http.Response(
            jsonEncode({'accessToken': 'payload.signature'}),
            HttpStatus.ok,
          );
        }
        generationRequest = true;
        return http.Response.bytes(
          img.encodeJpg(image),
          HttpStatus.ok,
          headers: const {'content-type': 'image/jpeg'},
        );
      });

      try {
        await expectLater(
          AiCartoonService(client: client).generate(
            photo: photo,
            endpoint: defaultAiCartoonEndpoint,
            deviceId: 'device-12345678',
            activationCode: 'A' * 86,
            style: AiPhotoStyle.anime,
          ),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('did not confirm the selected photo style'),
            ),
          ),
        );
        expect(generationRequest, isTrue);
      } finally {
        client.close();
        await directory.delete(recursive: true);
      }
    },
  );

  test('preserves facial-detail resolution up to 2048 pixels', () async {
    final directory = await Directory.systemTemp.createTemp(
      'photobooth-ai-resolution-test',
    );
    final photo = File('${directory.path}\\photo.png');
    final source = img.Image(width: 1200, height: 600);
    await photo.writeAsBytes(img.encodePng(source));
    List<int>? uploadedJpeg;
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/pb_auth')) {
        return http.Response(
          jsonEncode({'accessToken': 'payload.signature'}),
          HttpStatus.ok,
        );
      }

      final body = request.bodyBytes;
      var start = -1;
      var end = -1;
      for (var index = 0; index < body.length - 1; index++) {
        if (body[index] == 0xff && body[index + 1] == 0xd8) {
          start = index;
          break;
        }
      }
      if (start >= 0) {
        for (var index = start + 2; index < body.length - 1; index++) {
          if (body[index] == 0xff && body[index + 1] == 0xd9) {
            end = index + 2;
            break;
          }
        }
      }
      expect(start, greaterThanOrEqualTo(0));
      expect(end, greaterThan(start));
      uploadedJpeg = body.sublist(start, end);
      return http.Response.bytes(
        img.encodeJpg(img.Image(width: 8, height: 8)),
        HttpStatus.ok,
        headers: const {
          'content-type': 'image/jpeg',
          'x-snaplab-ai-style': 'anime',
        },
      );
    });

    try {
      await AiCartoonService(client: client).generate(
        photo: photo,
        endpoint: defaultAiCartoonEndpoint,
        deviceId: 'device-12345678',
        activationCode: 'A' * 86,
        style: AiPhotoStyle.anime,
      );
      final uploadedImage = img.decodeJpg(Uint8List.fromList(uploadedJpeg!));
      expect(uploadedImage?.width, 1200);
      expect(uploadedImage?.height, 600);
    } finally {
      client.close();
      await directory.delete(recursive: true);
    }
  });

  test(
    'generates multi-photo AI batches sequentially in photo order',
    () async {
      final photos = [
        File('photo-1.jpg'),
        File('photo-2.jpg'),
        File('photo-3.jpg'),
        File('photo-4.jpg'),
        File('photo-5.jpg'),
      ];
      final completed = <String>[];
      final completedPhotos = <String, File>{};
      var activeGenerations = 0;
      var maximumActiveGenerations = 0;

      final generated = await generateAiPhotoBatch(
        photos: photos,
        completedPhotos: completedPhotos,
        transformPhoto: (photo) async {
          activeGenerations++;
          if (activeGenerations > maximumActiveGenerations) {
            maximumActiveGenerations = activeGenerations;
          }
          await Future<void>.delayed(const Duration(milliseconds: 2));
          completed.add(photo.path);
          activeGenerations--;
          return File('${photo.path}.generated');
        },
      );

      expect(maximumActiveGenerations, 1);
      expect(completed, photos.map((photo) => photo.path));
      expect(
        generated.map((photo) => photo.path),
        photos.map((photo) => '${photo.path}.generated'),
      );
    },
  );

  test('identifies the photo that failed in an AI batch', () async {
    await expectLater(
      generateAiPhotoBatch(
        photos: [File('photo-1.jpg'), File('photo-2.jpg')],
        completedPhotos: {},
        transformPhoto: (photo) async {
          if (photo.path == 'photo-2.jpg') {
            throw StateError('server unavailable');
          }
          return File('${photo.path}.generated');
        },
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('photo 2 of 2'),
        ),
      ),
    );
  });

  test('retry resumes from the first photo that previously failed', () async {
    final directory = await Directory.systemTemp.createTemp(
      'photobooth-ai-batch-retry-test',
    );
    final photos = [
      for (var index = 1; index <= 5; index++)
        File('${directory.path}\\photo-$index.jpg'),
    ];
    final completedPhotos = <String, File>{};
    final attempted = <String>[];
    var shouldFailFourthPhoto = true;

    Future<File> transform(File photo) async {
      attempted.add(photo.path);
      if (photo == photos[3] && shouldFailFourthPhoto) {
        throw StateError('replicate_prediction_failed');
      }
      final generated = File('${photo.path}.generated');
      await generated.writeAsBytes([1, 2, 3]);
      return generated;
    }

    try {
      await expectLater(
        generateAiPhotoBatch(
          photos: photos,
          completedPhotos: completedPhotos,
          transformPhoto: transform,
        ),
        throwsA(isA<StateError>()),
      );
      expect(attempted, photos.take(4).map((photo) => photo.path));
      expect(completedPhotos, hasLength(3));

      shouldFailFourthPhoto = false;
      final generated = await generateAiPhotoBatch(
        photos: photos,
        completedPhotos: completedPhotos,
        transformPhoto: transform,
      );

      expect(attempted.sublist(4), [photos[3].path, photos[4].path]);
      expect(attempted.where((path) => path == photos[0].path), hasLength(1));
      expect(attempted.where((path) => path == photos[1].path), hasLength(1));
      expect(attempted.where((path) => path == photos[2].path), hasLength(1));
      expect(generated, hasLength(5));
      expect(completedPhotos, hasLength(5));
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
