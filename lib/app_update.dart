import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class AppUpdateManifest {
  const AppUpdateManifest({
    required this.version,
    required this.versionCode,
    required this.apkUri,
    required this.releaseNotes,
  });

  final String version;
  final int versionCode;
  final Uri apkUri;
  final String releaseNotes;

  Uri get downloadUri {
    if (apkUri.host != 'drive.google.com') return apkUri;
    final pathSegments = apkUri.pathSegments;
    final fileIndex = pathSegments.indexOf('d');
    final fileId = fileIndex >= 0 && fileIndex + 1 < pathSegments.length
        ? pathSegments[fileIndex + 1]
        : apkUri.queryParameters['id'];
    if (fileId == null || fileId.isEmpty) return apkUri;
    return Uri.https('drive.usercontent.google.com', '/download', {
      'export': 'download',
      'confirm': 't',
      'id': fileId,
    });
  }

  bool isNewerThan(int installedVersionCode) =>
      versionCode > installedVersionCode;
}

AppUpdateManifest parseAppUpdateManifest(String source) {
  final Object? decoded;
  try {
    decoded = jsonDecode(source);
  } on FormatException {
    throw const FormatException('The update manifest is not valid JSON.');
  }
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('The update manifest must be a JSON object.');
  }

  final version = decoded['version'];
  final versionCode = decoded['versionCode'];
  final apkUrl = decoded['apkUrl'];
  final releaseNotes = decoded['releaseNotes'] ?? '';
  if (version is! String ||
      version.trim().isEmpty ||
      versionCode is! int ||
      versionCode < 1 ||
      apkUrl is! String ||
      releaseNotes is! String) {
    throw const FormatException('The update manifest is missing valid fields.');
  }

  final apkUri = Uri.tryParse(apkUrl);
  if (apkUri == null || apkUri.scheme != 'https' || apkUri.host.isEmpty) {
    throw const FormatException('The APK download link must use HTTPS.');
  }

  return AppUpdateManifest(
    version: version.trim(),
    versionCode: versionCode,
    apkUri: apkUri,
    releaseNotes: releaseNotes.trim(),
  );
}

Future<AppUpdateManifest> fetchAppUpdateManifest(Uri manifestUri) async {
  if (manifestUri.scheme != 'https' || manifestUri.host.isEmpty) {
    throw const FormatException('The update manifest link must use HTTPS.');
  }

  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    final request = await client
        .getUrl(manifestUri)
        .timeout(const Duration(seconds: 20));
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final response = await request.close().timeout(const Duration(seconds: 20));
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'The update server returned HTTP ${response.statusCode}.',
        uri: manifestUri,
      );
    }
    final bytes = await response.fold<BytesBuilder>(BytesBuilder(copy: false), (
      builder,
      chunk,
    ) {
      if (builder.length + chunk.length > 64 * 1024) {
        throw const FormatException('The update manifest is too large.');
      }
      builder.add(chunk);
      return builder;
    });
    return parseAppUpdateManifest(utf8.decode(bytes.takeBytes()));
  } finally {
    client.close(force: true);
  }
}
