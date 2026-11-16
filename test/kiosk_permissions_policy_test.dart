import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth_kiosk/kiosk_permissions.dart';

void main() {
  test('kiosk permission config declares critical and optional features', () {
    expect(kioskPermissions, hasLength(4));
    expect(
      kioskPermissions
          .where(
            (permission) =>
                permission.importance == KioskPermissionImportance.critical,
          )
          .map((permission) => permission.id),
      containsAll([KioskPermissionId.camera, KioskPermissionId.storage]),
    );
    expect(
      kioskPermissions
          .where(
            (permission) =>
                permission.importance == KioskPermissionImportance.optional,
          )
          .map((permission) => permission.id),
      containsAll([KioskPermissionId.bluetooth, KioskPermissionId.network]),
    );
  });

  test('runtime permission prompts are guarded to operator setup mode', () {
    expect(
      KioskPermissionService().requestDuringSetup(
        setupMode: false,
        kioskLive: false,
      ),
      throwsA(anything),
    );
    expect(
      KioskPermissionService().requestDuringSetup(
        setupMode: true,
        kioskLive: true,
      ),
      throwsA(anything),
    );
  });

  test('Android declares only the approved kiosk permission set', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    final permissionTags = RegExp(r'<uses-permission(?:-sdk-23)?\b[\s\S]*?/>')
        .allMatches(manifest)
        .map((match) => match.group(0)!);
    final removedTags = permissionTags
        .where((tag) => tag.contains('tools:node="remove"'))
        .toList();
    final permissions = permissionTags
        .where((tag) => !tag.contains('tools:node="remove"'))
        .map(
          (tag) => RegExp(r'android:name="([^"]+)"').firstMatch(tag)!.group(1)!,
        )
        .toSet();
    const allowed = {
      'android.permission.INTERNET',
      'android.permission.CAMERA',
      'android.permission.WRITE_EXTERNAL_STORAGE',
      'android.permission.BLUETOOTH',
      'android.permission.BLUETOOTH_ADMIN',
      'android.permission.BLUETOOTH_SCAN',
      'android.permission.BLUETOOTH_CONNECT',
      'android.permission.RECEIVE_BOOT_COMPLETED',
      'android.permission.ACCESS_COARSE_LOCATION',
      'android.permission.ACCESS_FINE_LOCATION',
      'android.permission.REQUEST_INSTALL_PACKAGES',
    };
    expect(permissions.difference(allowed), isEmpty);
    expect(removedTags.join('\n'), contains('android.permission.RECORD_AUDIO'));
    expect(
      removedTags.join('\n'),
      contains('android.permission.READ_EXTERNAL_STORAGE'),
    );
    expect(manifest, isNot(contains('AccessibilityService')));
    expect(
      permissions,
      isNot(
        containsAll([
          'android.permission.READ_CONTACTS',
          'android.permission.SEND_SMS',
          'android.permission.READ_CALL_LOG',
          'android.permission.RECORD_AUDIO',
        ]),
      ),
    );
  });

  test('no permission request calls exist outside the setup service', () {
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where((file) => !file.path.endsWith('kiosk_permissions.dart'));
    for (final file in files) {
      final source = file.readAsStringSync();
      expect(
        source,
        isNot(matches(RegExp(r'\bPermission\.\w+\.request\s*\('))),
        reason: '${file.path} must not request permissions.',
      );
      expect(
        source,
        isNot(contains('openAppSettings(')),
        reason: '${file.path} must not open system settings from guest flow.',
      );
    }
    final app = File('lib/main.dart').readAsStringSync();
    expect(
      RegExp(r'_showKioskSetup\(dialogContext\)').allMatches(app),
      hasLength(1),
      reason: 'Provisioning must remain behind the authenticated admin UI.',
    );
  });
}
