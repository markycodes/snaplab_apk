import 'dart:io';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum KioskPermissionId { camera, storage, bluetooth, network }

enum KioskPermissionImportance { critical, optional }

class KioskPermissionConfig {
  const KioskPermissionConfig({
    required this.id,
    required this.importance,
    required this.feature,
    required this.rationale,
    required this.fallback,
  });

  final KioskPermissionId id;
  final KioskPermissionImportance importance;
  final String feature;
  final String rationale;
  final String fallback;
}

const kioskPermissions = <KioskPermissionConfig>[
  KioskPermissionConfig(
    id: KioskPermissionId.camera,
    importance: KioskPermissionImportance.critical,
    feature: 'Photo capture',
    rationale: 'Camera access is used only to take booth photos.',
    fallback: 'The booth stays unavailable until camera access is restored.',
  ),
  KioskPermissionConfig(
    id: KioskPermissionId.storage,
    importance: KioskPermissionImportance.critical,
    feature: 'Save and print',
    rationale:
        'Photos are saved to the booth app and Pictures/Photobooth. '
        'Scoped storage is used where available.',
    fallback: 'The booth stays unavailable if it cannot save photos.',
  ),
  KioskPermissionConfig(
    id: KioskPermissionId.bluetooth,
    importance: KioskPermissionImportance.optional,
    feature: 'Coin slot and Bluetooth printer',
    rationale:
        'Bluetooth access is used to communicate with paired booth hardware. '
        'The app does not request location; legacy Android may limit BLE scanning.',
    fallback: 'Coin-slot and printing features may be unavailable.',
  ),
  KioskPermissionConfig(
    id: KioskPermissionId.network,
    importance: KioskPermissionImportance.optional,
    feature: 'Photo upload and QR sharing',
    rationale:
        'Network access uses the normal internet connection and does not '
        'require an Android runtime permission.',
    fallback: 'Photos remain saved locally; online sharing is unavailable.',
  ),
];

enum KioskPermissionState {
  granted,
  denied,
  permanentlyDenied,
  limited,
  notDetermined,
  notRequired,
}

class KioskPermissionSnapshot {
  const KioskPermissionSnapshot(this.states);

  final Map<KioskPermissionId, KioskPermissionState> states;

  bool get criticalPermissionsGranted =>
      const [KioskPermissionId.camera, KioskPermissionId.storage].every(
        (id) =>
            states[id] == KioskPermissionState.granted ||
            states[id] == KioskPermissionState.limited ||
            states[id] == KioskPermissionState.notRequired,
      );
}

class KioskPermissionService {
  KioskPermissionService({
    this._deviceChannel = const MethodChannel('photobooth/device'),
  });

  final MethodChannel _deviceChannel;

  Future<int> _androidSdkInt() async {
    if (!Platform.isAndroid) return 0;
    final sdk = await _deviceChannel.invokeMethod<int>('androidSdkInt');
    if (sdk == null) {
      throw StateError('Could not determine the Android version.');
    }
    return sdk;
  }

  Future<List<Permission>> _permissionsToCheck() async {
    if (Platform.isAndroid) {
      final sdk = await _androidSdkInt();
      return [
        Permission.camera,
        if (sdk <= 28) Permission.storage,
        if (sdk >= 31) Permission.bluetoothScan,
        if (sdk >= 31) Permission.bluetoothConnect,
      ];
    }
    if (Platform.isIOS) {
      return [Permission.camera, Permission.photosAddOnly];
    }
    return [Permission.camera];
  }

  Future<KioskPermissionSnapshot> refresh() async {
    final permissions = await _permissionsToCheck();
    final statuses = <Permission, PermissionStatus>{};
    for (final permission in permissions) {
      statuses[permission] = await permission.status;
    }
    return _snapshot(statuses);
  }

  Future<KioskPermissionSnapshot> requestDuringSetup({
    required bool setupMode,
    required bool kioskLive,
  }) async {
    assert(setupMode && !kioskLive, 'Permission prompts are admin setup only.');
    if (!setupMode || kioskLive) {
      throw StateError('Permissions can only be requested during admin setup.');
    }

    final permissions = await _permissionsToCheck();
    final preferences = await SharedPreferences.getInstance();
    for (final permission in permissions) {
      await preferences.setBool(
        'kiosk_permission_requested_${permission.value}',
        true,
      );
    }
    final statuses = await permissions.request();
    return _snapshot(statuses);
  }

  Future<KioskPermissionSnapshot> _snapshot(
    Map<Permission, PermissionStatus> statuses,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    final states = <KioskPermissionId, KioskPermissionState>{
      KioskPermissionId.camera: _state(
        statuses[Permission.camera],
        preferences.getBool(
              'kiosk_permission_requested_${Permission.camera.value}',
            ) ??
            false,
      ),
      KioskPermissionId.storage: Platform.isAndroid
          ? (statuses[Permission.storage] == null
                ? KioskPermissionState.notRequired
                : _state(
                    statuses[Permission.storage],
                    preferences.getBool(
                          'kiosk_permission_requested_${Permission.storage.value}',
                        ) ??
                        false,
                  ))
          : Platform.isIOS
          ? _state(
              statuses[Permission.photosAddOnly],
              preferences.getBool(
                    'kiosk_permission_requested_${Permission.photosAddOnly.value}',
                  ) ??
                  false,
            )
          : KioskPermissionState.notRequired,
      KioskPermissionId.bluetooth: Platform.isAndroid
          ? (statuses.containsKey(Permission.bluetoothScan) ||
                    statuses.containsKey(Permission.bluetoothConnect)
                ? _combineBluetooth(
                    statuses[Permission.bluetoothScan],
                    statuses[Permission.bluetoothConnect],
                    preferences.getBool(
                          'kiosk_permission_requested_${Permission.bluetoothScan.value}',
                        ) ??
                        false,
                    preferences.getBool(
                          'kiosk_permission_requested_${Permission.bluetoothConnect.value}',
                        ) ??
                        false,
                  )
                : KioskPermissionState.notRequired)
          : KioskPermissionState.notRequired,
      KioskPermissionId.network: KioskPermissionState.notRequired,
    };
    return KioskPermissionSnapshot(states);
  }

  KioskPermissionState _combineBluetooth(
    PermissionStatus? scan,
    PermissionStatus? connect,
    bool scanRequested,
    bool connectRequested,
  ) {
    final values = [scan, connect].whereType<PermissionStatus>().toList();
    if (values.any(
      (status) => status.isPermanentlyDenied || status.isRestricted,
    )) {
      return KioskPermissionState.permanentlyDenied;
    }
    if (values.every((status) => status.isGranted || status.isLimited)) {
      return KioskPermissionState.granted;
    }
    if (values.any((status) => status.isDenied)) {
      final deniedNotRequested =
          scan?.isDenied == true && !scanRequested ||
          connect?.isDenied == true && !connectRequested;
      return deniedNotRequested
          ? KioskPermissionState.notDetermined
          : KioskPermissionState.denied;
    }
    return KioskPermissionState.notDetermined;
  }

  KioskPermissionState _state(PermissionStatus? status, bool requested) {
    if (status == null) return KioskPermissionState.notRequired;
    if (status.isGranted) return KioskPermissionState.granted;
    if (status.isLimited) return KioskPermissionState.limited;
    if (status.isPermanentlyDenied || status.isRestricted) {
      return KioskPermissionState.permanentlyDenied;
    }
    if (status.isDenied) {
      return requested
          ? KioskPermissionState.denied
          : KioskPermissionState.notDetermined;
    }
    return KioskPermissionState.notDetermined;
  }

  Future<bool> openSettings() => openAppSettings();
}
