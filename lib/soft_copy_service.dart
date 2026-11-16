import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

import 'device_activation.dart';

const defaultSoftCopyUploadEndpoint = 'https://snaplabbooth.com/pb_upload';
const _uploadTimeout = Duration(minutes: 3);
const _maxPhotoUploadBytes = 18 * 1024 * 1024;

class SoftCopyUploadResult {
  const SoftCopyUploadResult({
    this.photoUrl,
    this.gifUrl,
    this.videoUrl,
    this.photoError,
    this.gifError,
    this.videoError,
  });

  final Uri? photoUrl;
  final Uri? gifUrl;
  final Uri? videoUrl;
  final String? photoError;
  final String? gifError;
  final String? videoError;
}

class SoftCopyService {
  const SoftCopyService({this._client});

  final http.Client? _client;

  static Uri validateUploadEndpoint(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty) {
      throw const FormatException(
        'Enter a secure HTTPS upload URL without query parameters.',
      );
    }
    return uri;
  }

  Future<Uri> uploadPhoto({
    required File photo,
    required String endpoint,
    required String deviceId,
    required String activationCode,
  }) async {
    final uploadUri = validateUploadEndpoint(endpoint);
    final accessToken = await _authorize(
      uploadUri,
      deviceId: deviceId,
      activationCode: activationCode,
    );
    final preparedPhoto = await _preparePhotoForUpload(photo);
    try {
      return await _uploadAuthorizedPhoto(
        uploadUri,
        accessToken: accessToken,
        photo: preparedPhoto.file,
      );
    } finally {
      await preparedPhoto.temporaryDirectory?.delete(recursive: true);
    }
  }

  Future<SoftCopyUploadResult> uploadPhotos({
    required File photo,
    File? gif,
    File? video,
    required String endpoint,
    required String deviceId,
    required String activationCode,
    void Function(SoftCopyUploadResult result, bool isComplete)? onProgress,
  }) async {
    final uploadUri = validateUploadEndpoint(endpoint);
    final accessToken = await _authorize(
      uploadUri,
      deviceId: deviceId,
      activationCode: activationCode,
    );
    final preparedPhoto = await _preparePhotoForUpload(photo);
    late final ({Uri? url, String? error}) photoResult;
    try {
      final result = await _uploadResult(
        uploadUri,
        'photo',
        preparedPhoto.file,
        accessToken,
      );
      photoResult = (url: result.url, error: result.error);
    } finally {
      await preparedPhoto.temporaryDirectory?.delete(recursive: true);
    }
    var result = SoftCopyUploadResult(
      photoUrl: photoResult.url,
      photoError: photoResult.error,
    );
    if (gif == null && video == null) {
      onProgress?.call(result, true);
      return result;
    }
    onProgress?.call(result, false);
    final ({String type, Uri? url, String? error}) gifResult;
    if (gif == null) {
      gifResult = (type: 'gif', url: null, error: null);
    } else {
      gifResult = await _uploadResult(uploadUri, 'gif', gif, accessToken);
    }
    result = SoftCopyUploadResult(
      photoUrl: photoResult.url,
      photoError: photoResult.error,
      gifUrl: gifResult.url,
      gifError: gifResult.error,
    );
    if (video != null) {
      onProgress?.call(result, false);
      final videoResult = await _uploadResult(
        uploadUri,
        'video',
        video,
        accessToken,
      );
      result = SoftCopyUploadResult(
        photoUrl: photoResult.url,
        photoError: photoResult.error,
        gifUrl: gifResult.url,
        gifError: gifResult.error,
        videoUrl: videoResult.url,
        videoError: videoResult.error,
      );
    }
    onProgress?.call(result, true);
    return result;
  }

  Future<String> _authorize(
    Uri uploadUri, {
    required String deviceId,
    required String activationCode,
  }) async {
    final normalizedActivationCode = normalizeDeviceActivationCode(
      activationCode,
    );
    if (!RegExp(r'^[A-Za-z0-9._:-]{8,128}$').hasMatch(deviceId) ||
        normalizedActivationCode.length > 512 ||
        !hasSupportedDeviceActivationCodeFormat(normalizedActivationCode)) {
      throw const FormatException(
        'A valid activated device is required to upload photos.',
      );
    }

    final authUri = uploadUri.resolve('pb_auth');
    final authorizationResponse = await _postAuthorization(
      authUri,
      jsonEncode({
        'deviceId': deviceId,
        'activationCode': normalizedActivationCode,
      }),
    ).timeout(const Duration(seconds: 15));
    if (authorizationResponse.statusCode != HttpStatus.ok) {
      throw HttpException(
        'Photo upload authorization failed: '
        '${_responseError(authorizationResponse)}.',
        uri: authUri,
      );
    }
    final authorizationBody = jsonDecode(authorizationResponse.body);
    if (authorizationBody is! Map<String, dynamic> ||
        authorizationBody['accessToken'] is! String) {
      throw const FormatException(
        'The photo server returned an invalid upload authorization.',
      );
    }
    final accessToken = authorizationBody['accessToken'] as String;
    if (!RegExp(r'^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$').hasMatch(accessToken)) {
      throw const FormatException(
        'The photo server returned an invalid upload authorization.',
      );
    }
    return accessToken;
  }

  Future<http.Response> _postAuthorization(Uri uri, String body) async {
    var currentUri = uri;
    final visitedUris = <Uri>{};
    for (var redirects = 0; redirects <= 3; redirects++) {
      if (!visitedUris.add(currentUri)) {
        throw HttpException(
          'Photo upload authorization returned a redirect loop.',
          uri: currentUri,
        );
      }
      final request = http.Request('POST', currentUri)
        ..followRedirects = false
        ..headers['Content-Type'] = 'application/json'
        ..body = body;
      final streamedResponse = await (_client == null
          ? request.send()
          : _client.send(request));
      final response = await http.Response.fromStream(streamedResponse);
      if (response.statusCode != HttpStatus.temporaryRedirect &&
          response.statusCode != HttpStatus.permanentRedirect) {
        return response;
      }

      final location = response.headers['location'];
      final redirectedUri = location == null
          ? null
          : currentUri.resolveUri(Uri.parse(location));
      if (redirects == 3 ||
          redirectedUri == null ||
          redirectedUri.scheme != 'https' ||
          redirectedUri.host != currentUri.host ||
          redirectedUri.port != currentUri.port ||
          redirectedUri.userInfo.isNotEmpty) {
        throw HttpException(
          'Photo upload authorization returned an unsafe or unsupported '
          'redirect${location == null ? '' : ' to $location'}.',
          uri: currentUri,
        );
      }
      currentUri = redirectedUri;
    }
    throw HttpException(
      'Photo upload authorization exceeded the redirect limit.',
      uri: uri,
    );
  }

  Future<({String type, Uri? url, String? error})> _uploadResult(
    Uri uploadUri,
    String type,
    File photo,
    String accessToken,
  ) async {
    try {
      final url = await _uploadAuthorizedPhoto(
        uploadUri,
        accessToken: accessToken,
        photo: photo,
      );
      return (type: type, url: url, error: null);
    } on Object catch (error) {
      return (type: type, url: null, error: error.toString());
    }
  }

  Future<Uri> _uploadAuthorizedPhoto(
    Uri uploadUri, {
    required String accessToken,
    required File photo,
  }) async {
    final request = http.MultipartRequest('POST', uploadUri)
      ..headers['Authorization'] = ['Bearer', accessToken].join(' ')
      ..files.add(await http.MultipartFile.fromPath('photo', photo.path));
    final response = await (() async {
      final streamedResponse = await (_client == null
          ? request.send()
          : _client.send(request));
      return http.Response.fromStream(streamedResponse);
    })().timeout(_uploadTimeout);
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'Photo upload failed: ${_responseError(response)}.',
        uri: uploadUri,
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic> || decoded['downloadUrl'] is! String) {
      throw const FormatException(
        'The photo server returned an invalid response.',
      );
    }
    final downloadUri = Uri.tryParse(decoded['downloadUrl'] as String);
    if (downloadUri == null ||
        downloadUri.scheme != 'https' ||
        downloadUri.host != uploadUri.host ||
        downloadUri.userInfo.isNotEmpty) {
      throw const FormatException(
        'The photo server returned an unsafe download URL.',
      );
    }
    return downloadUri;
  }

  Future<({File file, Directory? temporaryDirectory})> _preparePhotoForUpload(
    File photo,
  ) async {
    if (await photo.length() <= _maxPhotoUploadBytes) {
      return (file: photo, temporaryDirectory: null);
    }

    final jpegBytes = await compute(
      _encodePhotoForUpload,
      await photo.readAsBytes(),
    );
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'photobooth-photo-upload-',
    );
    try {
      final compressedPhoto = File(
        '${temporaryDirectory.path}${Platform.pathSeparator}photo.jpg',
      );
      await compressedPhoto.writeAsBytes(jpegBytes, flush: true);
      return (file: compressedPhoto, temporaryDirectory: temporaryDirectory);
    } on Object {
      await temporaryDirectory.delete(recursive: true);
      rethrow;
    }
  }

  String _responseError(http.Response response) {
    try {
      final body = jsonDecode(response.body);
      if (body is Map<String, dynamic> && body['error'] is String) {
        return 'HTTP ${response.statusCode}: ${body['error']}';
      }
    } on FormatException {
      // Non-JSON server responses are reported by status without exposing HTML.
    }
    return 'HTTP ${response.statusCode}';
  }
}

Uint8List _encodePhotoForUpload(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw const FormatException('The photo could not be decoded for upload.');
  }
  final oriented = img.bakeOrientation(decoded);
  const maxWidths = [3600, 3000, 2400, 1920, 1600, 1280, 960, 720];
  const qualities = [90, 84, 78, 72];
  for (final maxWidth in maxWidths) {
    final width = math.min(maxWidth, oriented.width);
    final resized = width == oriented.width
        ? oriented
        : img.copyResize(
            oriented,
            width: width,
            maintainAspect: true,
            interpolation: img.Interpolation.average,
          );
    for (final quality in qualities) {
      final jpegBytes = img.encodeJpg(resized, quality: quality);
      if (jpegBytes.length <= _maxPhotoUploadBytes) return jpegBytes;
    }
  }
  throw StateError('The photo is too large to prepare for online download.');
}
