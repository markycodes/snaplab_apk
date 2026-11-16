import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:photobooth_kiosk/soft_copy_service.dart';

void main() {
  test('uses the built-in secure upload endpoint', () {
    expect(defaultSoftCopyUploadEndpoint, 'https://snaplabbooth.com/pb_upload');
  });

  group('SoftCopyService.validateUploadEndpoint', () {
    test('accepts an HTTPS upload endpoint', () {
      expect(
        SoftCopyService.validateUploadEndpoint(
          'https://learn.snaplabbooth.com/photobooth/upload.php',
        ),
        Uri.parse('https://learn.snaplabbooth.com/photobooth/upload.php'),
      );
    });

    test('rejects insecure or incomplete endpoints', () {
      for (final endpoint in [
        'http://learn.snaplabbooth.com/upload.php',
        'learn.snaplabbooth.com/upload.php',
        'https:///upload.php',
      ]) {
        expect(
          () => SoftCopyService.validateUploadEndpoint(endpoint),
          throwsFormatException,
        );
      }
    });

    test('rejects endpoints with embedded credentials or query parameters', () {
      for (final endpoint in [
        '******learn.snaplabbooth.com/upload.php',
        'https://learn.snaplabbooth.com/upload.php?token=secret',
      ]) {
        expect(
          () => SoftCopyService.validateUploadEndpoint(endpoint),
          throwsFormatException,
        );
      }
    });
  });

  test('uses the temporary bearer token to upload the photo', () async {
    final directory = await Directory.systemTemp.createTemp('photobooth-test');
    final photo = File('${directory.path}\\photo.png');
    await photo.writeAsBytes([1, 2, 3]);
    final seenRequests = <http.BaseRequest>[];
    final client = MockClient((request) async {
      seenRequests.add(request);
      if (request.url.path.endsWith('/pb_auth')) {
        final body = jsonDecode(request.body);
        expect(body, {
          'deviceId': 'device-12345678',
          'activationCode': 'A' * 86,
        });

        return http.Response(
          jsonEncode({'accessToken': 'payload.signature'}),
          HttpStatus.ok,
        );
      }

      final authorizationHeader = request.headers.entries
          .firstWhere((entry) => entry.key.toLowerCase() == 'authorization')
          .value;
      expect(authorizationHeader, ['Bearer', 'payload.signature'].join(' '));
      return http.Response(
        jsonEncode({
          'downloadUrl': 'https://snaplabbooth.com/pb_download?id=123',
        }),
        HttpStatus.ok,
      );
    });

    try {
      final result = await SoftCopyService(client: client).uploadPhoto(
        photo: photo,
        endpoint: defaultSoftCopyUploadEndpoint,
        deviceId: 'device-12345678',
        activationCode: '${'A' * 86}==',
      );

      expect(result.host, 'snaplabbooth.com');
      expect(seenRequests, hasLength(2));
      expect(seenRequests.first.url.path, '/pb_auth');
      expect(seenRequests.last.url.path, '/pb_upload');
    } finally {
      client.close();
      await directory.delete(recursive: true);
    }
  });

  test('compresses oversized photos before uploading them', () async {
    final directory = await Directory.systemTemp.createTemp(
      'photobooth-large-photo-test',
    );
    final photo = File('${directory.path}\\photo.png');
    final image = img.Image(width: 2, height: 2);
    image.setPixelRgb(0, 0, 255, 0, 0);
    image.setPixelRgb(1, 0, 0, 255, 0);
    image.setPixelRgb(0, 1, 0, 0, 255);
    image.setPixelRgb(1, 1, 255, 255, 255);
    await photo.writeAsBytes(img.encodePng(image));
    final padding = await photo.open(mode: FileMode.append);
    await padding.writeFrom(List<int>.filled(18 * 1024 * 1024, 0));
    await padding.close();
    final client = _InspectingClient((request) {
      if (request.url.path.endsWith('/pb_auth')) {
        return http.Response(
          jsonEncode({'accessToken': 'payload.signature'}),
          HttpStatus.ok,
        );
      }

      expect(request, isA<http.MultipartRequest>());
      final upload = request as http.MultipartRequest;
      expect(upload.files.single.filename, 'photo.jpg');
      expect(upload.files.single.length, lessThan(18 * 1024 * 1024));
      return http.Response(
        jsonEncode({
          'downloadUrl': 'https://snaplabbooth.com/pb_download?id=123',
        }),
        HttpStatus.ok,
      );
    });

    try {
      final result = await SoftCopyService(client: client).uploadPhoto(
        photo: photo,
        endpoint: defaultSoftCopyUploadEndpoint,
        deviceId: 'device-12345678',
        activationCode: 'A' * 86,
      );
      expect(result.host, 'snaplabbooth.com');
    } finally {
      client.close();
      await directory.delete(recursive: true);
    }
  });

  test('authorizes uploads with compact activation codes', () async {
    final directory = await Directory.systemTemp.createTemp(
      'photobooth-compact-activation-test',
    );
    final photo = File('${directory.path}\\photo.png');
    await photo.writeAsBytes([1, 2, 3]);
    final compactCode = '33${List.filled(86, 'A').join()}';
    Map<String, dynamic>? authorizationBody;
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/pb_auth')) {
        authorizationBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({'accessToken': 'payload.signature'}),
          HttpStatus.ok,
        );
      }

      return http.Response(
        jsonEncode({
          'downloadUrl': 'https://snaplabbooth.com/pb_download?id=123',
        }),
        HttpStatus.ok,
      );
    });

    try {
      await SoftCopyService(client: client).uploadPhoto(
        photo: photo,
        endpoint: defaultSoftCopyUploadEndpoint,
        deviceId: 'device-12345678',
        activationCode: compactCode,
      );
      expect(authorizationBody?['activationCode'], compactCode);
    } finally {
      client.close();
      await directory.delete(recursive: true);
    }
  });

  test(
    'follows a same-origin temporary redirect during authorization',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'photobooth-test',
      );
      final photo = File('${directory.path}\\photo.png');
      await photo.writeAsBytes([1, 2, 3]);
      final authorizationRequests = <http.BaseRequest>[];
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/pb_auth')) {
          authorizationRequests.add(request);
          return http.Response(
            '',
            HttpStatus.temporaryRedirect,
            headers: {'location': '/pb_auth.php'},
          );
        }

        if (request.url.path.endsWith('/pb_auth.php')) {
          authorizationRequests.add(request);
          expect(request.method, 'POST');
          expect(jsonDecode(request.body), {
            'deviceId': 'device-12345678',
            'activationCode': 'A' * 86,
          });
          return http.Response(
            jsonEncode({'accessToken': 'payload.signature'}),
            HttpStatus.ok,
          );
        }
        return http.Response(
          jsonEncode({
            'downloadUrl': 'https://snaplabbooth.com/pb_download?id=123',
          }),
          HttpStatus.ok,
        );
      });

      try {
        final result = await SoftCopyService(client: client).uploadPhoto(
          photo: photo,
          endpoint: defaultSoftCopyUploadEndpoint,
          deviceId: 'device-12345678',
          activationCode: 'A' * 86,
        );
        expect(result.host, 'snaplabbooth.com');
        expect(authorizationRequests.map((request) => request.url.path), [
          '/pb_auth',
          '/pb_auth.php',
        ]);
      } finally {
        client.close();
        await directory.delete(recursive: true);
      }
    },
  );

  test('rejects cross-origin authorization redirects', () async {
    final directory = await Directory.systemTemp.createTemp('photobooth-test');
    final photo = File('${directory.path}\\photo.png');
    await photo.writeAsBytes([1, 2, 3]);
    final client = MockClient(
      (request) async => http.Response(
        '',
        HttpStatus.temporaryRedirect,
        headers: {'location': 'https://attacker.example/pb_auth'},
      ),
    );

    try {
      await expectLater(
        SoftCopyService(client: client).uploadPhoto(
          photo: photo,
          endpoint: defaultSoftCopyUploadEndpoint,
          deviceId: 'device-12345678',
          activationCode: 'A' * 86,
        ),
        throwsA(isA<HttpException>()),
      );
    } finally {
      client.close();
      await directory.delete(recursive: true);
    }
  });

  test(
    'reports the authorization URL when the server rejects authorization',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'photobooth-test',
      );
      final photo = File('${directory.path}\\photo.png');
      await photo.writeAsBytes([1, 2, 3]);
      final client = MockClient(
        (request) async => http.Response(
          jsonEncode({'error': 'activation_required'}),
          HttpStatus.badRequest,
        ),
      );

      try {
        await expectLater(
          SoftCopyService(client: client).uploadPhoto(
            photo: photo,
            endpoint: defaultSoftCopyUploadEndpoint,
            deviceId: 'device-12345678',
            activationCode: 'A' * 86,
          ),
          throwsA(
            isA<HttpException>().having(
              (error) => error.uri,
              'uri',
              Uri.parse('https://snaplabbooth.com/pb_auth'),
            ),
          ),
        );
      } finally {
        client.close();
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'authorizes feature-enabled activation codes for photo uploads',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'photobooth-test',
      );
      final photo = File('${directory.path}\\photo.png');
      await photo.writeAsBytes([1, 2, 3]);
      final payload = base64Url
          .encode(
            utf8.encode(
              jsonEncode({
                'version': 2,
                'deviceId': 'device-12345678',
                'features': ['paymongo_qrph'],
              }),
            ),
          )
          .replaceAll('=', '');
      final activationCode = '$payload.${'A' * 86}';
      var authorizationRequested = false;
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/pb_auth')) {
          authorizationRequested = true;
          expect(jsonDecode(request.body), {
            'deviceId': 'device-12345678',
            'activationCode': activationCode,
          });
          return http.Response(
            jsonEncode({'accessToken': 'payload.signature'}),
            HttpStatus.ok,
          );
        }
        return http.Response(
          jsonEncode({
            'downloadUrl': 'https://snaplabbooth.com/pb_download?id=123',
          }),
          HttpStatus.ok,
        );
      });

      try {
        final result = await SoftCopyService(client: client).uploadPhoto(
          photo: photo,
          endpoint: defaultSoftCopyUploadEndpoint,
          deviceId: 'device-12345678',
          activationCode: activationCode,
        );
        expect(authorizationRequested, isTrue);
        expect(result.host, 'snaplabbooth.com');
      } finally {
        client.close();
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'uploads photo and GIF separately and reports each result immediately',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'photobooth-test',
      );
      final photo = File('${directory.path}\\photo.png');
      final gif = File('${directory.path}\\animation.gif');
      await photo.writeAsBytes([1, 2, 3]);
      await gif.writeAsBytes([4, 5, 6]);
      var authorizationCount = 0;
      var uploadCount = 0;
      final gifUploadStarted = Completer<void>();
      final releaseUploads = Completer<void>();
      final progress = <(SoftCopyUploadResult, bool)>[];
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/pb_auth')) {
          authorizationCount++;
          return http.Response(
            jsonEncode({'accessToken': 'payload.signature'}),
            HttpStatus.ok,
          );
        }

        final uploadIndex = ++uploadCount;
        final authorizationHeader = request.headers.entries
            .firstWhere((entry) => entry.key.toLowerCase() == 'authorization')
            .value;
        expect(authorizationHeader, ['Bearer', 'payload.signature'].join(' '));
        if (uploadIndex == 1) {
          return http.Response(
            jsonEncode({
              'downloadUrl': 'https://snaplabbooth.com/pb_download?id=photo',
            }),
            HttpStatus.ok,
          );
        }
        gifUploadStarted.complete();
        await releaseUploads.future;
        return http.Response(
          jsonEncode({'error': 'gif_size_not_supported'}),
          HttpStatus.requestEntityTooLarge,
        );
      });

      try {
        final uploads = SoftCopyService(client: client).uploadPhotos(
          photo: photo,
          gif: gif,
          endpoint: defaultSoftCopyUploadEndpoint,
          deviceId: 'device-12345678',
          activationCode: 'A' * 86,
          onProgress: (result, isComplete) {
            progress.add((result, isComplete));
          },
        );
        await gifUploadStarted.future.timeout(const Duration(seconds: 2));
        expect(progress, hasLength(1));
        expect(progress.first.$1.photoUrl?.queryParameters['id'], 'photo');
        expect(progress.first.$1.gifUrl, isNull);
        expect(progress.first.$2, isFalse);
        releaseUploads.complete();
        final result = await uploads;

        expect(authorizationCount, 1);
        expect(uploadCount, 2);
        expect(result.photoUrl?.queryParameters['id'], 'photo');
        expect(result.gifUrl, isNull);
        expect(result.gifError, contains('413'));
        expect(progress, hasLength(2));
        expect(progress.last.$2, isTrue);
      } finally {
        if (!releaseUploads.isCompleted) releaseUploads.complete();
        client.close();
        await directory.delete(recursive: true);
      }
    },
  );

  test('uploads the moving photo MP4 with its own download URL', () async {
    final directory = await Directory.systemTemp.createTemp(
      'photobooth-video-upload-test',
    );
    final photo = File('${directory.path}\\photo.png');
    final video = File('${directory.path}\\moving-photo.mp4');
    await photo.writeAsBytes([1, 2, 3]);
    await video.writeAsBytes([0, 0, 0, 24, 102, 116, 121, 112]);
    final uploadFiles = <String>[];
    final client = _InspectingClient((request) {
      if (request.url.path.endsWith('/pb_auth')) {
        return http.Response(
          jsonEncode({'accessToken': 'payload.signature'}),
          HttpStatus.ok,
        );
      }

      expect(request, isA<http.MultipartRequest>());
      final upload = request as http.MultipartRequest;
      uploadFiles.add(upload.files.single.filename ?? '');
      return http.Response(
        jsonEncode({
          'downloadUrl': 'https://snaplabbooth.com/pb_download?id=video',
        }),
        HttpStatus.ok,
      );
    });

    try {
      final result = await SoftCopyService(client: client).uploadPhotos(
        photo: photo,
        video: video,
        endpoint: defaultSoftCopyUploadEndpoint,
        deviceId: 'device-12345678',
        activationCode: 'A' * 86,
      );

      expect(uploadFiles, ['photo.png', 'moving-photo.mp4']);
      expect(result.videoUrl?.queryParameters['id'], 'video');
      expect(result.videoError, isNull);
    } finally {
      client.close();
      await directory.delete(recursive: true);
    }
  });
}

class _InspectingClient extends http.BaseClient {
  _InspectingClient(this.onRequest);

  final http.Response Function(http.BaseRequest request) onRequest;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = onRequest(request);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }
}
