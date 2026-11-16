import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

import 'device_activation.dart';

const defaultAiCartoonEndpoint = 'https://snaplabbooth.com/pb_cartoon.php';
const _maxCartoonUploadBytes = 6 * 1024 * 1024;
const _maxCartoonOutputBytes = 15 * 1024 * 1024;

enum AiPhotoStyle {
  anime('anime', 'Anime'),
  pencilSketch('pencil_sketch', 'Pencil Sketch'),
  cartoon3d('cartoon_3d', '3D Cartoon'),
  chibi('chibi', 'Chibi'),
  popArt('pop_art', 'Pop Art'),
  lineArt('line_art', 'Line Art');

  const AiPhotoStyle(this.key, this.label);

  final String key;
  final String label;

  String get previewAsset => 'assets/ai_style_examples/$key.png';
}

class AiCartoonService {
  const AiCartoonService({this.client});

  final http.Client? client;

  static Uri validateEndpoint(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty) {
      throw const FormatException(
        'AI cartoon conversion requires a secure HTTPS endpoint.',
      );
    }
    return uri;
  }

  Future<File> generate({
    required File photo,
    required String endpoint,
    required String deviceId,
    required String activationCode,
    AiPhotoStyle style = AiPhotoStyle.cartoon3d,
  }) async {
    final uri = validateEndpoint(endpoint);
    final normalizedActivationCode = normalizeDeviceActivationCode(
      activationCode,
    );
    if (!RegExp(r'^[A-Za-z0-9._:-]{8,128}$').hasMatch(deviceId) ||
        normalizedActivationCode.length > 512 ||
        !hasSupportedDeviceActivationCodeFormat(normalizedActivationCode)) {
      throw const FormatException(
        'A valid activated device is required for AI cartoon conversion.',
      );
    }

    final authorizationUri = uri.resolve('pb_auth');
    final activeClient = client ?? http.Client();
    final ownsClient = client == null;
    try {
      final authorizationResponse = await activeClient
          .post(
            authorizationUri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'deviceId': deviceId,
              'activationCode': normalizedActivationCode,
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (authorizationResponse.statusCode != HttpStatus.ok) {
        throw HttpException(
          'AI photo authorization failed with HTTP '
          '${authorizationResponse.statusCode}.',
          uri: authorizationUri,
        );
      }

      final authorizationBody = jsonDecode(authorizationResponse.body);
      if (authorizationBody is! Map<String, dynamic> ||
          authorizationBody['accessToken'] is! String) {
        throw const FormatException(
          'The photo server returned invalid AI authorization.',
        );
      }
      final accessToken = authorizationBody['accessToken'] as String;
      if (!RegExp(r'^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$').hasMatch(accessToken)) {
        throw const FormatException(
          'The photo server returned invalid AI authorization.',
        );
      }

      final jpegBytes = await compute(
        _encodeAiCartoonInput,
        await photo.readAsBytes(),
      );
      if (jpegBytes.length > _maxCartoonUploadBytes) {
        throw StateError('The photo is too large for AI cartoon conversion.');
      }
      final request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer $accessToken'
        ..files.add(
          http.MultipartFile.fromBytes(
            'photo',
            jpegBytes,
            filename: 'portrait.jpg',
          ),
        );
      request.fields['style'] = style.key;
      final streamedResponse = await activeClient
          .send(request)
          .timeout(const Duration(minutes: 2));
      final response = await http.Response.fromStream(streamedResponse);
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'AI cartoon generation failed: ${_responseError(response)}.',
          uri: uri,
        );
      }
      if (response.headers['x-snaplab-ai-style'] != style.key) {
        throw const FormatException(
          'The AI server did not confirm the selected photo style. '
          'Upload the latest pb_cartoon.php to Hostinger and try again.',
        );
      }
      if (response.bodyBytes.isEmpty ||
          response.bodyBytes.length > _maxCartoonOutputBytes ||
          response.headers['content-type']?.toLowerCase().split(';').first !=
              'image/jpeg') {
        throw const FormatException(
          'The AI server returned an invalid cartoon image.',
        );
      }
      final outputFile = File('${photo.path}.ai-cartoon.jpg');
      await outputFile.writeAsBytes(response.bodyBytes, flush: true);
      return outputFile;
    } finally {
      if (ownsClient) activeClient.close();
    }
  }

  String _responseError(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic> && decoded['error'] is String) {
        return 'HTTP ${response.statusCode} (${decoded['error']})';
      }
    } on FormatException {
      // Report status only when the server does not return JSON.
    }
    return 'HTTP ${response.statusCode}';
  }
}

Future<List<File>> generateAiPhotoBatch({
  required List<File> photos,
  required Map<String, File> completedPhotos,
  required Future<File> Function(File photo) transformPhoto,
}) async {
  final transformedPhotos = <File>[];
  for (var index = 0; index < photos.length; index++) {
    final photo = photos[index];
    final cachedPhoto = completedPhotos[photo.path];
    if (cachedPhoto != null && await cachedPhoto.exists()) {
      transformedPhotos.add(cachedPhoto);
      continue;
    }
    try {
      final transformedPhoto = await transformPhoto(photo);
      completedPhotos[photo.path] = transformedPhoto;
      transformedPhotos.add(transformedPhoto);
    } on Object catch (error) {
      throw StateError(
        'AI generation failed for photo ${index + 1} of ${photos.length}: $error',
      );
    }
  }
  return transformedPhotos;
}

Uint8List _encodeAiCartoonInput(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw const FormatException('The photo could not be decoded for AI.');
  }
  final oriented = img.bakeOrientation(decoded);
  final longestSide = math.max(oriented.width, oriented.height);
  final scale = math.min(1.0, 2048 / longestSide);
  final width = (oriented.width * scale).round();
  final height = (oriented.height * scale).round();
  final resized = scale == 1
      ? oriented
      : img.copyResize(
          oriented,
          width: width,
          height: height,
          interpolation: img.Interpolation.average,
        );
  return Uint8List.fromList(img.encodeJpg(resized, quality: 92));
}
