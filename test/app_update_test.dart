import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth_kiosk/app_update.dart';

void main() {
  group('parseAppUpdateManifest', () {
    test('parses update details and compares numeric version codes', () {
      final manifest = parseAppUpdateManifest('''
{
  "version": "1.2.0",
  "versionCode": 12,
  "apkUrl": "https://updates.example.com/photobooth-1.2.0.apk",
  "releaseNotes": "New frame designs"
}
''');

      expect(manifest.version, '1.2.0');
      expect(manifest.versionCode, 12);
      expect(manifest.apkUri.scheme, 'https');
      expect(manifest.releaseNotes, 'New frame designs');
      expect(
        manifest.downloadUri,
        Uri.parse('https://updates.example.com/photobooth-1.2.0.apk'),
      );
      expect(manifest.isNewerThan(11), isTrue);
      expect(manifest.isNewerThan(12), isFalse);
    });

    test('converts Google Drive share links to direct download URLs', () {
      final fileLink = parseAppUpdateManifest('''
{
  "version": "1.2.0",
  "versionCode": 12,
  "apkUrl": "https://drive.google.com/file/d/abc123/view?usp=sharing"
}
''');
      final queryLink = parseAppUpdateManifest('''
{
  "version": "1.2.0",
  "versionCode": 12,
  "apkUrl": "https://drive.google.com/open?id=abc123"
}
''');

      expect(
        fileLink.downloadUri,
        Uri.https('drive.usercontent.google.com', '/download', {
          'export': 'download',
          'confirm': 't',
          'id': 'abc123',
        }),
      );
      expect(queryLink.downloadUri, fileLink.downloadUri);
    });

    test('rejects malformed manifests and non-HTTPS APK links', () {
      expect(() => parseAppUpdateManifest('invalid'), throwsFormatException);
      expect(
        () => parseAppUpdateManifest('''
{"version":"1.2.0","versionCode":12,"apkUrl":"http://updates.example.com/app.apk"}
'''),
        throwsFormatException,
      );
      expect(
        () => parseAppUpdateManifest('''
{"version":"1.2.0","versionCode":0,"apkUrl":"https://updates.example.com/app.apk"}
'''),
        throwsFormatException,
      );
    });
  });
}
