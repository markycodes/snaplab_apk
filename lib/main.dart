import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:android_file_picker/android_file_picker.dart';
import 'package:camera/camera.dart';
import 'package:cryptography/cryptography.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Text;
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

import 'ai_cartoon_service.dart';
import 'app_language.dart';
import 'app_update.dart';
import 'ble_protocol.dart';
import 'brand_logo.dart';
import 'booth_event_theme.dart';
import 'booth_theme_background.dart';
import 'device_activation.dart';
import 'fleet_monitoring_service.dart';
import 'esc_pos.dart';
import 'ganap_payment.dart';
import 'kiosk_mode.dart';
import 'kiosk_permissions.dart';
import 'kiosk_setup_screen.dart';
import 'local_dashboard.dart';
import 'paymongo_payment.dart';
import 'sales_ledger.dart';
import 'photo_border.dart';
import 'photo_effects.dart';
import 'photo_layout.dart';
import 'session_gif.dart';
import 'soft_copy_service.dart';
import 'session_video.dart';

const _ink = Color(0xFF171717);
const _panel = Color(0xFFF7F7F7);
const _accent = Color(0xFF171717);
const _muted = Color(0xFF737373);
const _canvas = Color(0xFFFFFFFF);
const _outline = Color(0xFFE8E8E8);
const _classicPhotoChoiceOrder = [1, 3, 4, 2, 5];
const _serviceUuid = '6f3a1000-9d7b-4c2a-8e51-13b7c0a10000';
const _characteristicUuid = '6f3a1001-9d7b-4c2a-8e51-13b7c0a10000';
const _esp32DeviceName = 'Photobooth ESP32';
const _kioskChannel = MethodChannel('photobooth/kiosk');
const _boothTestMode = kDebugMode && bool.fromEnvironment('BOOTH_TEST_MODE');
const _sessionPricePesos = 20;
const _defaultCoinPricePesos = 20;
const _maxCoinPricePesos = 100000;
const _ganapQrPhMinimumPesos = 200;
const _ganapQrPhAvailable = _sessionPricePesos >= _ganapQrPhMinimumPesos;
const _maxCustomerDecorationCount = 50;
const _updateManifestUrl =
    'https://gist.githubusercontent.com/markycodes/fc8a1509d41f148abc88c8313e8e8b53/raw/update.json';
const _dismissedUpdateVersionCodeKey = 'dismissed_app_update_version_code';
bool _hasPrinted = false;

Future<T> _withKioskFilePicker<T>(Future<T> Function() pickFile) async {
  final restoreKioskAllowlist =
      await _kioskChannel.invokeMethod<bool>('prepareFilePicker') ?? false;
  try {
    return await pickFile();
  } finally {
    if (restoreKioskAllowlist) {
      await _kioskChannel.invokeMethod<void>('finishFilePicker');
    }
  }
}

ColorFilter _liveEffectColorFilter(PhotoEffect effect) {
  final matrix = switch (effect) {
    PhotoEffect.monochrome => const <double>[
      0.299,
      0.587,
      0.114,
      0,
      0,
      0.299,
      0.587,
      0.114,
      0,
      0,
      0.299,
      0.587,
      0.114,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
    ],
    PhotoEffect.warm => const <double>[
      1,
      0,
      0,
      0,
      22,
      0,
      1,
      0,
      0,
      8,
      0,
      0,
      1,
      0,
      -18,
      0,
      0,
      0,
      1,
      0,
    ],
    PhotoEffect.vintage => const <double>[
      0.85,
      0.1,
      0,
      0,
      24,
      0.08,
      0.82,
      0,
      0,
      16,
      0,
      0.12,
      0.72,
      0,
      8,
      0,
      0,
      0,
      1,
      0,
    ],
    PhotoEffect.sepia => const <double>[
      0.393,
      0.769,
      0.189,
      0,
      0,
      0.349,
      0.686,
      0.168,
      0,
      0,
      0.272,
      0.534,
      0.131,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
    ],
    PhotoEffect.cool => const <double>[
      1,
      0,
      0,
      0,
      -12,
      0,
      1,
      0,
      0,
      2,
      0,
      0,
      1,
      0,
      20,
      0,
      0,
      0,
      1,
      0,
    ],
    PhotoEffect.rose => const <double>[
      1,
      0,
      0,
      0,
      18,
      0,
      1,
      0,
      0,
      -4,
      0,
      0,
      1,
      0,
      8,
      0,
      0,
      0,
      1,
      0,
    ],
    PhotoEffect.soft => const <double>[
      0.9,
      0,
      0,
      0,
      12,
      0,
      0.9,
      0,
      0,
      12,
      0,
      0,
      0.9,
      0,
      14.8,
      0,
      0,
      0,
      1,
      0,
    ],
    PhotoEffect.matte => const <double>[
      0.82,
      0,
      0,
      0,
      28,
      0,
      0.82,
      0,
      0,
      28,
      0,
      0,
      0.82,
      0,
      28,
      0,
      0,
      0,
      1,
      0,
    ],
    PhotoEffect.pastel => const <double>[
      0.82,
      0,
      0,
      0,
      46,
      0,
      0.82,
      0,
      0,
      46,
      0,
      0,
      0.82,
      0,
      46,
      0,
      0,
      0,
      1,
      0,
    ],
    PhotoEffect.vivid || PhotoEffect.cartoon => const <double>[
      1.25,
      0,
      0,
      0,
      -32,
      0,
      1.25,
      0,
      0,
      -32,
      0,
      0,
      1.25,
      0,
      -32,
      0,
      0,
      0,
      1,
      0,
    ],
    PhotoEffect.cinematic => const <double>[
      1.12,
      0,
      0,
      0,
      -7.36,
      0,
      1.08,
      0,
      0,
      -10.24,
      0,
      0,
      1.12,
      0,
      -7.36,
      0,
      0,
      0,
      1,
      0,
    ],
    PhotoEffect.fade => const <double>[
      0.76,
      0,
      0,
      0,
      -63.28,
      0,
      0.76,
      0,
      0,
      -63.28,
      0,
      0,
      0.76,
      0,
      -63.28,
      0,
      0,
      0,
      1,
      0,
    ],
    PhotoEffect.original => const <double>[
      1,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
    ],
  };
  return ColorFilter.matrix(matrix);
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PhotoboothApp());
}

class PhotoboothApp extends StatelessWidget {
  const PhotoboothApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Photobooth Kiosk',
      debugShowCheckedModeBanner: false,
      builder: (context, child) => Stack(
        fit: StackFit.expand,
        children: [
          ?child,
          Positioned(
            top: 4,
            left: 10,
            child: SafeArea(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.78),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    child: Text(
                      'POWERED BY SNAPLAB',
                      style: TextStyle(
                        color: _muted,
                        fontSize: 8,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.45,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: _canvas,
        colorScheme: const ColorScheme.light(
          primary: _accent,
          onPrimary: Colors.white,
          secondary: Color(0xFF171717),
          surface: _panel,
          onSurface: _ink,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: _ink,
          surfaceTintColor: Colors.transparent,
        ),
        cardTheme: const CardThemeData(
          color: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 1,
          shadowColor: Color(0x12000000),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(20)),
            side: BorderSide(color: _outline),
          ),
        ),
        dialogTheme: const DialogThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 8,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(22)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          labelStyle: const TextStyle(
            color: _muted,
            fontWeight: FontWeight.w600,
          ),
          floatingLabelStyle: const TextStyle(
            color: _accent,
            fontWeight: FontWeight.w700,
          ),
          helperStyle: const TextStyle(color: _muted),
          hintStyle: const TextStyle(color: _muted),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _outline),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _outline),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: _accent,
            foregroundColor: Colors.white,
            elevation: 0,
            shadowColor: Colors.transparent,
            animationDuration: const Duration(milliseconds: 220),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: _accent,
            foregroundColor: Colors.white,
            elevation: 0,
            shadowColor: Colors.transparent,
            animationDuration: const Duration(milliseconds: 220),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: _ink,
            side: const BorderSide(color: _outline),
            animationDuration: const Duration(milliseconds: 220),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
          ),
        ),
        segmentedButtonTheme: SegmentedButtonThemeData(
          style: ButtonStyle(
            backgroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? _accent
                  : Colors.white,
            ),
            foregroundColor: WidgetStateProperty.resolveWith(
              (states) =>
                  states.contains(WidgetState.selected) ? Colors.white : _ink,
            ),
          ),
        ),
        useMaterial3: true,
      ),
      home: ValueListenableBuilder<AppLanguage>(
        valueListenable: appLanguageNotifier,
        builder: (_, _, _) => BoothScreen(),
      ),
    );
  }
}

class _IdleVideoBackground extends StatefulWidget {
  const _IdleVideoBackground({
    super.key,
    required this.videoPath,
    required this.looping,
    required this.fallbackImagePath,
  });

  final String videoPath;
  final bool looping;
  final String? fallbackImagePath;

  @override
  State<_IdleVideoBackground> createState() => _IdleVideoBackgroundState();
}

class _IdleVideoBackgroundState extends State<_IdleVideoBackground> {
  late final VideoPlayerController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.videoPath));
    unawaited(_initializeVideo());
  }

  Future<void> _initializeVideo() async {
    try {
      await _controller.initialize();
      await _controller.setVolume(0);
      await _controller.setLooping(widget.looping);
      await _controller.play();
      if (mounted) setState(() {});
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = 'Idle video could not play: $error');
      }
    }
  }

  Future<void> _setLooping(bool looping) async {
    try {
      await _controller.setLooping(looping);
    } on Object catch (error) {
      if (mounted) {
        setState(
          () => _error = 'Idle video setting could not be applied: $error',
        );
      }
    }
  }

  @override
  void didUpdateWidget(covariant _IdleVideoBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.looping != widget.looping &&
        _controller.value.isInitialized) {
      unawaited(_setLooping(widget.looping));
    }
  }

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controllerValue = _controller.value;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (widget.fallbackImagePath case final imagePath?)
          Image.file(
            File(imagePath),
            fit: BoxFit.cover,
            errorBuilder: (context, error, stack) =>
                const ColoredBox(color: _ink),
          )
        else
          const ColoredBox(color: _ink),
        if (controllerValue.isInitialized)
          FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: controllerValue.size.width,
              height: controllerValue.size.height,
              child: VideoPlayer(_controller),
            ),
          )
        else if (_error case final error?)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                error,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  shadows: [Shadow(color: Colors.black, blurRadius: 8)],
                ),
              ),
            ),
          )
        else
          const Center(child: CircularProgressIndicator(color: _accent)),
      ],
    );
  }
}

class _SettingsStore {
  static const _saltKey = 'admin_salt';
  static const _hashKey = 'admin_hash';
  static const _appLanguageKey = 'app_language';
  static const _photoBorderKey = 'photo_border_style';
  static const _eventThemeKey = 'booth_event_theme';
  static const _voiceGuidanceKey = 'voice_guidance_enabled';
  static const _liveEffectKey = 'live_camera_effect';
  static const _customPhotoBorderKey = 'custom_photo_border_path';
  static const _customerFrameGalleryKey = 'customer_frame_gallery';
  static const _customerDecorationGalleryKey = 'customer_decoration_gallery';
  static const _pendingCustomerFramePickerKey =
      'pending_customer_frame_picker_started_at';
  static const _autoPrintKey = 'auto_print';
  static const _printerTypeKey = 'printer_type';
  static const _printerAddressKey = 'printer_address';
  static const _receiptWidthDotsKey = 'receipt_width_dots';
  static const _receiptBrightnessKey = 'receipt_brightness';
  static const _receiptCutModeKey = 'receipt_cut_mode';
  static const _printCopiesKey = 'print_copies';
  static const _countdownDurationKey = 'countdown_duration';
  static const _chargeStartPercentKey = 'charge_start_percent';
  static const _chargeStopPercentKey = 'charge_stop_percent';
  static const _previewDurationKey = 'preview_duration';
  static const _idleTimeoutKey = 'kiosk_idle_timeout';
  static const _welcomeMessageKey = 'welcome_message';
  static const _idleImageKey = 'idle_screen_image';
  static const _brandLogoKey = 'brand_logo_path';
  static const _brandLogoAnimationKey = 'brand_logo_animation';
  static const _liveWallpaperEnabledKey = 'live_wallpaper_enabled';
  static const _idleVideoKey = 'idle_screen_video';
  static const _idleVideoLoopKey = 'idle_screen_video_loop';
  static const _testModeKey = 'test_mode_enabled';
  static const _rentModeKey = 'rent_mode_enabled';
  static const _cameraDirectionKey = 'camera_direction';
  static const _activationCodeKey = 'device_activation_code';
  static const _fleetLocationSharingKey = 'fleet_location_sharing';
  static const _fleetPhotoCountsKey = 'fleet_photo_counts';
  static const _fleetLastCommandIdKey = 'fleet_last_command_id';
  static const _fleetCommandResultKey = 'fleet_command_result';
  static const _trialLastSeenKey = 'trial_activation_last_seen_utc_ms';
  static const _walletPaymentEnabledKey = 'wallet_payment_enabled';
  static const _payMongoPaymentsEnabledKey = 'paymongo_payments_enabled';
  static const _payMongoAmountPesosKey = 'paymongo_amount_pesos';
  static const _coinPricePesosKey = 'coin_price_pesos';
  static const _aiStylesEnabledKey = 'ai_styles_enabled';
  static const _aiCoinPaymentEnabledKey = 'ai_coin_payment_enabled';
  static const _aiQrPaymentEnabledKey = 'ai_qr_payment_enabled';
  static const _aiStylePricePesosKey = 'ai_style_price_pesos';
  static const _walletQrPathKey = 'wallet_qr_path';
  static const _legacySoftCopyEndpointKey = 'soft_copy_upload_endpoint';
  static const _legacySoftCopyTokenKey = 'soft_copy_upload_token';
  static const _recentCustomerPhotosKey = 'recent_customer_photos';
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();

  Future<AppLanguage> loadAppLanguage() async {
    final savedLanguage = await _preferences.getString(_appLanguageKey);
    return AppLanguage.values.firstWhere(
      (language) => language.name == savedLanguage,
      orElse: () => AppLanguage.english,
    );
  }

  Future<void> saveAppLanguage(AppLanguage language) =>
      _preferences.setString(_appLanguageKey, language.name);

  Future<PhotoBorderStyle> loadPhotoBorderStyle() async {
    final savedStyle = await _preferences.getString(_photoBorderKey);
    return PhotoBorderStyle.values.firstWhere(
      (style) => style.name == savedStyle,
      orElse: () => PhotoBorderStyle.none,
    );
  }

  Future<BoothEventTheme> loadEventTheme() async {
    final savedTheme = await _preferences.getString(_eventThemeKey);
    return BoothEventTheme.values.firstWhere(
      (theme) => theme.name == savedTheme,
      orElse: () => BoothEventTheme.classic,
    );
  }

  Future<bool> loadVoiceGuidanceEnabled() async =>
      await _preferences.getBool(_voiceGuidanceKey) ?? false;

  Future<PhotoEffect> loadLiveEffect() async {
    final savedEffect = await _preferences.getString(_liveEffectKey);
    return PhotoEffect.values.firstWhere(
      (effect) => effect.name == savedEffect,
      orElse: () => PhotoEffect.original,
    );
  }

  Future<String?> loadCustomPhotoBorderPath() =>
      _preferences.getString(_customPhotoBorderKey);

  Future<List<String>> loadCustomerFrameGallery() async =>
      await _preferences.getStringList(_customerFrameGalleryKey) ?? <String>[];

  Future<void> saveCustomerFrameGallery(List<String> paths) =>
      _preferences.setStringList(_customerFrameGalleryKey, paths);

  Future<void> markCustomerFramePickerPending() => _preferences.setInt(
    _pendingCustomerFramePickerKey,
    DateTime.now().millisecondsSinceEpoch,
  );

  Future<int?> loadPendingCustomerFramePicker() =>
      _preferences.getInt(_pendingCustomerFramePickerKey);

  Future<void> clearPendingCustomerFramePicker() =>
      _preferences.remove(_pendingCustomerFramePickerKey);

  Future<List<String>> loadCustomerDecorationGallery() async =>
      await _preferences.getStringList(_customerDecorationGalleryKey) ??
      <String>[];

  Future<void> saveCustomerDecorationGallery(List<String> paths) =>
      _preferences.setStringList(_customerDecorationGalleryKey, paths);

  Future<void> removeLegacyCustomerFaceMaskGallery() =>
      _preferences.remove('customer_face_mask_gallery');

  Future<List<String>> loadRecentCustomerPhotos() async =>
      await _preferences.getStringList(_recentCustomerPhotosKey) ?? <String>[];

  Future<void> saveRecentCustomerPhotos(List<String> paths) =>
      _preferences.setStringList(_recentCustomerPhotosKey, paths);

  Future<void> savePhotoBorder(
    PhotoBorderStyle style,
    String? customPath,
  ) async {
    await _preferences.setString(_photoBorderKey, style.name);
    if (customPath == null) {
      await _preferences.remove(_customPhotoBorderKey);
    } else {
      await _preferences.setString(_customPhotoBorderKey, customPath);
    }
  }

  Future<bool> loadAutoPrint() async =>
      await _preferences.getBool(_autoPrintKey) ?? false;

  Future<String> loadPrinterType() async =>
      await _preferences.getString(_printerTypeKey) ?? 'receipt';

  Future<void> savePrinterType(String type) =>
      _preferences.setString(_printerTypeKey, type);

  Future<String?> loadPrinterAddress() =>
      _preferences.getString(_printerAddressKey);

  Future<int> loadReceiptWidthDots() async =>
      await _preferences.getInt(_receiptWidthDotsKey) ?? 576;

  Future<void> saveReceiptWidthDots(int widthDots) =>
      _preferences.setInt(_receiptWidthDotsKey, widthDots);

  Future<double> loadReceiptBrightness() async =>
      await _preferences.getDouble(_receiptBrightnessKey) ?? 0.35;

  Future<void> saveReceiptBrightness(double brightness) =>
      _preferences.setDouble(_receiptBrightnessKey, brightness);

  Future<EscPosCutMode> loadReceiptCutMode() async =>
      EscPosCutMode.fromName(await _preferences.getString(_receiptCutModeKey));

  Future<void> saveReceiptCutMode(EscPosCutMode cutMode) =>
      _preferences.setString(_receiptCutModeKey, cutMode.name);

  Future<int> loadPrintCopies() async =>
      await _preferences.getInt(_printCopiesKey) ?? 1;

  Future<int> loadCountdownDuration() async =>
      await _preferences.getInt(_countdownDurationKey) ?? 3;

  Future<int> loadChargeStartPercent() async =>
      await _preferences.getInt(_chargeStartPercentKey) ?? 20;

  Future<int> loadChargeStopPercent() async =>
      await _preferences.getInt(_chargeStopPercentKey) ?? 90;

  Future<void> saveChargeThresholds({
    required int startPercent,
    required int stopPercent,
  }) async {
    await _preferences.setInt(_chargeStartPercentKey, startPercent);
    await _preferences.setInt(_chargeStopPercentKey, stopPercent);
  }

  Future<int> loadPreviewDuration() async =>
      await _preferences.getInt(_previewDurationKey) ?? 5;

  Future<int> loadIdleTimeout() async =>
      await _preferences.getInt(_idleTimeoutKey) ?? 30;

  Future<void> saveIdleTimeout(int seconds) =>
      _preferences.setInt(_idleTimeoutKey, seconds);

  Future<bool> loadFleetLocationSharing() async =>
      await _preferences.getBool(_fleetLocationSharingKey) ?? false;

  Future<void> saveFleetLocationSharing(bool enabled) =>
      _preferences.setBool(_fleetLocationSharingKey, enabled);

  Future<List<int>> loadFleetPhotoCounts() async {
    final saved = await _preferences.getStringList(_fleetPhotoCountsKey);
    final counts = saved?.map(int.tryParse).whereType<int>().toSet().toList();
    if (counts == null ||
        counts.isEmpty ||
        counts.any((count) => count < 1 || count > 5)) {
      return const [1, 2, 3, 4, 5];
    }
    counts.sort();
    return counts;
  }

  Future<void> saveRemoteFleetSettings({
    required BoothEventTheme eventTheme,
    required String welcomeMessage,
    required int idleTimeoutSeconds,
    required List<int> photoCounts,
    required String? printerAddress,
  }) async {
    await _preferences.setString(_eventThemeKey, eventTheme.name);
    await _preferences.setString(_welcomeMessageKey, welcomeMessage);
    await _preferences.setInt(_idleTimeoutKey, idleTimeoutSeconds);
    await _preferences.setStringList(
      _fleetPhotoCountsKey,
      photoCounts.map((count) => count.toString()).toList(),
    );
    if (printerAddress == null) {
      await _preferences.remove(_printerAddressKey);
    } else {
      await _preferences.setString(_printerAddressKey, printerAddress);
    }
  }

  Future<int> loadFleetLastCommandId() async =>
      await _preferences.getInt(_fleetLastCommandIdKey) ?? 0;

  Future<void> saveFleetLastCommandId(int commandId) =>
      _preferences.setInt(_fleetLastCommandIdKey, commandId);

  Future<Map<String, Object?>?> loadFleetCommandResult() async {
    final raw = await _preferences.getString(_fleetCommandResultKey);
    if (raw == null) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Stored fleet command result is invalid.');
    }
    return decoded;
  }

  Future<void> saveFleetCommandResult(
    Map<String, Object?>? commandResult,
  ) async {
    if (commandResult == null) {
      await _preferences.remove(_fleetCommandResultKey);
    } else {
      await _preferences.setString(
        _fleetCommandResultKey,
        jsonEncode(commandResult),
      );
    }
  }

  Future<String> loadWelcomeMessage() async =>
      await _preferences.getString(_welcomeMessageKey) ?? 'TAKE HOME A MEMORY';

  Future<String?> loadIdleScreenImage() =>
      _preferences.getString(_idleImageKey);

  Future<String?> loadBrandLogo() => _preferences.getString(_brandLogoKey);

  Future<bool> loadLiveWallpaperEnabled() async =>
      await _preferences.getBool(_liveWallpaperEnabledKey) ?? false;

  Future<void> saveLiveWallpaperEnabled(bool enabled) =>
      _preferences.setBool(_liveWallpaperEnabledKey, enabled);

  Future<void> saveBrandLogo(String? path) async {
    if (path == null) {
      await _preferences.remove(_brandLogoKey);
    } else {
      await _preferences.setString(_brandLogoKey, path);
    }
  }

  Future<_BrandLogoAnimation> loadBrandLogoAnimation() async {
    final name = await _preferences.getString(_brandLogoAnimationKey);
    return _BrandLogoAnimation.values.firstWhere(
      (animation) => animation.name == name,
      orElse: () => _BrandLogoAnimation.none,
    );
  }

  Future<void> saveBrandLogoAnimation(_BrandLogoAnimation animation) =>
      _preferences.setString(_brandLogoAnimationKey, animation.name);

  Future<String?> loadIdleScreenVideo() =>
      _preferences.getString(_idleVideoKey);

  Future<bool> loadIdleVideoLoop() async =>
      await _preferences.getBool(_idleVideoLoopKey) ?? true;

  Future<bool> loadTestModeEnabled() async =>
      await _preferences.getBool(_testModeKey) ?? false;

  Future<void> saveTestModeEnabled(bool enabled) =>
      _preferences.setBool(_testModeKey, enabled);

  Future<bool> loadRentModeEnabled() async =>
      await _preferences.getBool(_rentModeKey) ?? false;

  Future<void> saveRentModeEnabled(bool enabled) =>
      _preferences.setBool(_rentModeKey, enabled);

  Future<String> loadCameraDirection() async =>
      await _preferences.getString(_cameraDirectionKey) ?? 'back';

  Future<bool> loadWalletPaymentEnabled() async =>
      await _preferences.getBool(_walletPaymentEnabledKey) ?? false;

  Future<void> saveWalletPaymentEnabled(bool enabled) =>
      _preferences.setBool(_walletPaymentEnabledKey, enabled);

  Future<bool> loadPayMongoPaymentsEnabled() async =>
      await _preferences.getBool(_payMongoPaymentsEnabledKey) ?? false;

  Future<void> savePayMongoPaymentsEnabled(bool enabled) =>
      _preferences.setBool(_payMongoPaymentsEnabledKey, enabled);

  Future<int> loadPayMongoAmountPesos() async {
    final amount =
        await _preferences.getInt(_payMongoAmountPesosKey) ??
        _sessionPricePesos;
    return amount >= 1 && amount <= 100000 ? amount : _sessionPricePesos;
  }

  Future<void> savePayMongoAmountPesos(int amount) =>
      _preferences.setInt(_payMongoAmountPesosKey, amount);

  Future<int> loadCoinPricePesos() async {
    final amount =
        await _preferences.getInt(_coinPricePesosKey) ?? _defaultCoinPricePesos;
    return amount >= 1 && amount <= _maxCoinPricePesos
        ? amount
        : _defaultCoinPricePesos;
  }

  Future<void> saveCoinPricePesos(int amount) =>
      _preferences.setInt(_coinPricePesosKey, amount);

  Future<bool> loadAiStylesEnabled() async =>
      await _preferences.getBool(_aiStylesEnabledKey) ?? false;

  Future<void> saveAiStylesEnabled(bool enabled) =>
      _preferences.setBool(_aiStylesEnabledKey, enabled);

  Future<bool> loadAiCoinPaymentEnabled() async =>
      await _preferences.getBool(_aiCoinPaymentEnabledKey) ?? false;

  Future<void> saveAiCoinPaymentEnabled(bool enabled) =>
      _preferences.setBool(_aiCoinPaymentEnabledKey, enabled);

  Future<bool> loadAiQrPaymentEnabled() async =>
      await _preferences.getBool(_aiQrPaymentEnabledKey) ?? false;

  Future<void> saveAiQrPaymentEnabled(bool enabled) =>
      _preferences.setBool(_aiQrPaymentEnabledKey, enabled);

  static String _aiStylePriceKeyForPhotoCount(int photoCount) =>
      'ai_style_price_pesos_$photoCount';

  Future<int> loadAiStylePricePesos() async {
    final amount = await _preferences.getInt(_aiStylePricePesosKey) ?? 20;
    return amount >= 1 && amount <= 100000 ? amount : 20;
  }

  Future<Map<int, int>> loadAiStylePricesPesos() async {
    final legacyAmount = await loadAiStylePricePesos();
    final prices = <int, int>{};
    for (var photoCount = 1; photoCount <= 5; photoCount++) {
      final savedAmount = await _preferences.getInt(
        _aiStylePriceKeyForPhotoCount(photoCount),
      );
      prices[photoCount] =
          savedAmount != null && savedAmount >= 1 && savedAmount <= 100000
          ? savedAmount
          : legacyAmount;
    }
    return prices;
  }

  Future<void> saveAiStylePricesPesos(Map<int, int> prices) async {
    for (var photoCount = 1; photoCount <= 5; photoCount++) {
      final amount = prices[photoCount];
      if (amount == null || amount < 1 || amount > 100000) {
        throw FormatException(
          'AI conversion price for $photoCount photo(s) must be from ₱1 to ₱100,000.',
        );
      }
      await _preferences.setInt(
        _aiStylePriceKeyForPhotoCount(photoCount),
        amount,
      );
    }
    await _preferences.setInt(_aiStylePricePesosKey, prices[1]!);
  }

  Future<String?> loadWalletQrPath() =>
      _preferences.getString(_walletQrPathKey);

  Future<void> removeLegacySoftCopySettings() async {
    await _preferences.remove(_legacySoftCopyEndpointKey);
    await _preferences.remove(_legacySoftCopyTokenKey);
  }

  Future<String?> loadActivationCode() =>
      _preferences.getString(_activationCodeKey);

  Future<void> saveActivationCode(String code) =>
      _preferences.setString(_activationCodeKey, code);

  Future<DateTime> loadEffectiveTrialNow() async {
    final now = DateTime.now().toUtc();
    final savedMilliseconds = await _preferences.getInt(_trialLastSeenKey);
    final saved = savedMilliseconds == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(savedMilliseconds, isUtc: true);
    final effectiveNow = saved != null && saved.isAfter(now) ? saved : now;
    await _preferences.setInt(
      _trialLastSeenKey,
      effectiveNow.millisecondsSinceEpoch,
    );
    return effectiveNow;
  }

  Future<void> saveBoothOptions({
    required bool autoPrint,
    required String? printerAddress,
    required int printCopies,
    required int countdownDuration,
    required int previewDuration,
    required String welcomeMessage,
    required String? idleScreenImage,
    required String? idleScreenVideo,
    required bool idleVideoLoop,
    required bool testModeEnabled,
    required String cameraDirection,
    required bool walletPaymentEnabled,
    required String? walletQrPath,
    required BoothEventTheme eventTheme,
    required bool voiceGuidanceEnabled,
    required PhotoEffect liveEffect,
  }) async {
    if (cameraDirection != CameraLensDirection.front.name &&
        cameraDirection != CameraLensDirection.back.name) {
      throw ArgumentError.value(cameraDirection, 'cameraDirection');
    }
    await _preferences.setBool(_autoPrintKey, autoPrint);
    if (printerAddress == null) {
      await _preferences.remove(_printerAddressKey);
    } else {
      await _preferences.setString(_printerAddressKey, printerAddress);
    }
    await _preferences.setInt(_printCopiesKey, printCopies);
    await _preferences.setInt(_countdownDurationKey, countdownDuration);
    await _preferences.setInt(_previewDurationKey, previewDuration);
    await _preferences.setString(_welcomeMessageKey, welcomeMessage);
    if (idleScreenImage == null) {
      await _preferences.remove(_idleImageKey);
    } else {
      await _preferences.setString(_idleImageKey, idleScreenImage);
    }
    if (idleScreenVideo == null) {
      await _preferences.remove(_idleVideoKey);
    } else {
      await _preferences.setString(_idleVideoKey, idleScreenVideo);
    }
    await _preferences.setBool(_idleVideoLoopKey, idleVideoLoop);
    await _preferences.setBool(_testModeKey, testModeEnabled);
    await _preferences.setString(_cameraDirectionKey, cameraDirection);
    await _preferences.setBool(_walletPaymentEnabledKey, walletPaymentEnabled);
    await _preferences.setString(_eventThemeKey, eventTheme.name);
    await _preferences.setBool(_voiceGuidanceKey, voiceGuidanceEnabled);
    await _preferences.setString(_liveEffectKey, liveEffect.name);
    if (walletQrPath == null) {
      await _preferences.remove(_walletQrPathKey);
    } else {
      await _preferences.setString(_walletQrPathKey, walletQrPath);
    }
  }

  Future<void> verifyAdminSettings(Map<String, Object?> expected) async {
    for (final entry in expected.entries) {
      final key = entry.key;
      final value = entry.value;
      final Object? stored;
      if (value is bool) {
        stored = await _preferences.getBool(key);
      } else if (value is int) {
        stored = await _preferences.getInt(key);
      } else if (value is double) {
        stored = await _preferences.getDouble(key);
      } else if (value is String || value == null) {
        stored = await _preferences.getString(key);
      } else if (value is List<String>) {
        stored = await _preferences.getStringList(key);
      } else {
        throw ArgumentError.value(value, 'expected[$key]');
      }

      final matches = value is List<String>
          ? stored is List<String> && listEquals(stored, value)
          : stored == value;
      if (!matches) {
        throw StateError('The "$key" setting did not persist.');
      }
    }
  }

  Future<bool> hasAdminPassword() async =>
      await _preferences.getString(_hashKey) != null;

  Future<void> createAdminPassword(String password) async {
    final salt = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    final hash = await _derivePasswordHash(password, salt);
    await _preferences.setString(_saltKey, base64UrlEncode(salt));
    await _preferences.setString(_hashKey, base64UrlEncode(hash));
  }

  Future<bool> verifyAdminPassword(String password) async {
    final encodedSalt = await _preferences.getString(_saltKey);
    final encodedHash = await _preferences.getString(_hashKey);
    if (encodedSalt == null || encodedHash == null) return false;

    try {
      final salt = base64Url.decode(encodedSalt);
      final expected = base64Url.decode(encodedHash);
      final actual = await _derivePasswordHash(password, salt);
      if (expected.length != actual.length) return false;

      var difference = 0;
      for (var index = 0; index < expected.length; index++) {
        difference |= expected[index] ^ actual[index];
      }
      return difference == 0;
    } on FormatException {
      return false;
    }
  }

  Future<List<int>> _derivePasswordHash(String password, List<int> salt) async {
    final algorithm = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 120000,
      bits: 256,
    );
    final key = await algorithm.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
    return key.extractBytes();
  }
}

Future<String?> _pickCustomPhotoBorder({bool detectPhotoSlots = false}) async {
  final file = await _withKioskFilePicker(
    () => FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['png'],
    ),
  );
  return _saveCustomPhotoBorder(file, detectPhotoSlots: detectPhotoSlots);
}

Future<String?> _saveCustomPhotoBorder(
  PlatformFile? file, {
  bool detectPhotoSlots = false,
}) async {
  if (file == null) return null;
  final fileLength = await file.length();
  if (fileLength == null) {
    throw StateError('The selected PNG border could not be read.');
  }
  if (fileLength > 12 * 1024 * 1024) {
    throw const FormatException('PNG border images must be 12 MB or smaller.');
  }
  final bytes = await file.readAsBytes();
  final frameBytes = await prepareCustomPhotoBorderPng(bytes);

  final supportDirectory = await getApplicationSupportDirectory();
  final savedFile = File(
    '${supportDirectory.path}${Platform.pathSeparator}'
    '${detectPhotoSlots ? 'photo_frame' : 'photo_border'}_'
    '${DateTime.now().millisecondsSinceEpoch}.png',
  );
  await savedFile.writeAsBytes(frameBytes, flush: true);
  if (detectPhotoSlots) {
    try {
      await customerPhotoFrameTemplate(savedFile.path);
    } on Object {
      await savedFile.delete();
      rethrow;
    }
  }
  return savedFile.path;
}

Future<String?> _pickPhotoDecoration() async {
  final file = await _withKioskFilePicker(
    () => FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['png', 'webp'],
    ),
  );
  if (file == null) return null;
  final length = await file.length();
  if (length == null || length == 0) {
    throw StateError('The selected decoration image could not be read.');
  }
  if (length > 12 * 1024 * 1024) {
    throw const FormatException('Decoration images must be 12 MB or smaller.');
  }
  final extension = file.name.split('.').last.toLowerCase();
  if (!const {'png', 'webp'}.contains(extension)) {
    throw const FormatException('Choose a PNG or WebP decoration image.');
  }
  final bytes = await file.readAsBytes();
  final transparentLogo = makeWhiteLogoBackgroundTransparent(bytes);
  final codec = await ui.instantiateImageCodec(transparentLogo);
  try {
    final frame = await codec.getNextFrame();
    frame.image.dispose();
  } finally {
    codec.dispose();
  }
  final supportDirectory = await getApplicationSupportDirectory();
  final destination = File(
    '${supportDirectory.path}${Platform.pathSeparator}'
    'photo_decoration_${DateTime.now().microsecondsSinceEpoch}.$extension',
  );
  await destination.writeAsBytes(bytes, flush: true);
  return destination.path;
}

Future<String?> _pickIdleScreenImage() async {
  final file = await _withKioskFilePicker(
    () => FilePicker.pickFile(type: FileType.image),
  );
  if (file == null) return null;
  final fileLength = await file.length();
  if (fileLength == null) {
    throw StateError('The selected home screen image could not be read.');
  }
  if (fileLength > 15 * 1024 * 1024) {
    throw const FormatException('Home screen images must be 15 MB or smaller.');
  }

  final bytes = await file.readAsBytes();
  final codec = await ui.instantiateImageCodec(bytes);
  try {
    final frame = await codec.getNextFrame();
    frame.image.dispose();
  } finally {
    codec.dispose();
  }

  final supportDirectory = await getApplicationSupportDirectory();
  final extension = file.name.split('.').last.toLowerCase();
  final safeExtension = RegExp(r'^[a-z0-9]{1,8}$').hasMatch(extension)
      ? extension
      : 'img';
  final savedFile = File(
    '${supportDirectory.path}${Platform.pathSeparator}'
    'idle_screen_${DateTime.now().millisecondsSinceEpoch}.$safeExtension',
  );
  await savedFile.writeAsBytes(bytes, flush: true);
  return savedFile.path;
}

Future<String?> _pickBrandLogo() async {
  final file = await _withKioskFilePicker(
    () => FilePicker.pickFile(type: FileType.image),
  );
  if (file == null) return null;
  final length = await file.length();
  if (length == null || length == 0) {
    throw StateError('The selected logo image could not be read.');
  }
  if (length > 15 * 1024 * 1024) {
    throw const FormatException('Logo images must be 15 MB or smaller.');
  }
  final bytes = await file.readAsBytes();
  final transparentLogo = makeWhiteLogoBackgroundTransparent(bytes);
  final codec = await ui.instantiateImageCodec(transparentLogo);
  try {
    final frame = await codec.getNextFrame();
    frame.image.dispose();
  } finally {
    codec.dispose();
  }

  final supportDirectory = await getApplicationSupportDirectory();
  final savedFile = File(
    '${supportDirectory.path}${Platform.pathSeparator}'
    'brand_logo_${DateTime.now().microsecondsSinceEpoch}.png',
  );
  await savedFile.writeAsBytes(transparentLogo, flush: true);
  return savedFile.path;
}

Future<String?> _pickIdleScreenVideo() async {
  final file = await _withKioskFilePicker(
    () => FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['mp4', 'm4v', 'mov', 'webm'],
    ),
  );
  if (file == null) return null;
  final fileLength = await file.length();
  if (fileLength == null) {
    throw StateError('The selected home screen video could not be read.');
  }
  if (fileLength == 0 || fileLength > 100 * 1024 * 1024) {
    throw const FormatException(
      'Home screen videos must be larger than 0 bytes and 100 MB or smaller.',
    );
  }

  final extension = file.name.split('.').last.toLowerCase();
  if (!const {'mp4', 'm4v', 'mov', 'webm'}.contains(extension)) {
    throw const FormatException(
      'Choose an MP4, M4V, MOV, or WebM home screen video.',
    );
  }

  final supportDirectory = await getApplicationSupportDirectory();
  final sourcePath = file.path;
  if (sourcePath == null || sourcePath.isEmpty) {
    throw StateError('The selected home screen video has no local file path.');
  }
  final savedFile = File(
    '${supportDirectory.path}${Platform.pathSeparator}'
    'idle_screen_${DateTime.now().millisecondsSinceEpoch}.$extension',
  );
  await File(sourcePath).copy(savedFile.path);
  return savedFile.path;
}

class _Esp32PaymentClient {
  final FlutterReactiveBle _ble = FlutterReactiveBle();
  final Uuid _serviceId = Uuid.parse(_serviceUuid);
  final Uuid _characteristicId = Uuid.parse(_characteristicUuid);
  StreamSubscription<ConnectionStateUpdate>? _connection;
  QualifiedCharacteristic? _creditCharacteristic;
  Future<void>? _connecting;
  Future<void> _exchangeTail = Future<void>.value();

  Stream<BleStatus> get statusStream => _ble.statusStream;

  Future<int> readCredits() async {
    final response = await _exchange(BleCreditRequest.readCredits());
    return response.credits;
  }

  Future<BleCreditResponse> consumeCredits(int amount) =>
      _exchange(BleCreditRequest.consumeCredits(amount));

  Future<void> reportBattery(
    int percent, {
    required int startPercent,
    required int stopPercent,
  }) async {
    final response = await _exchange(
      BleCreditRequest.reportBattery(
        percent: percent,
        startPercent: startPercent,
        stopPercent: stopPercent,
      ),
    );
    if (response.error != null) {
      throw StateError('ESP32 rejected battery report: ${response.error}');
    }
  }

  Future<BleCreditResponse> _exchange(List<int> request) {
    final result = _exchangeTail.then((_) => _performExchange(request));
    _exchangeTail = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );
    return result;
  }

  Future<BleCreditResponse> _performExchange(List<int> request) async {
    await _ensureConnected();
    final characteristic = _creditCharacteristic;
    if (characteristic == null) {
      throw StateError('The ESP32 credit characteristic is unavailable.');
    }

    try {
      await _ble
          .writeCharacteristicWithResponse(characteristic, value: request)
          .timeout(const Duration(seconds: 5));
      final response = await _ble
          .readCharacteristic(characteristic)
          .timeout(const Duration(seconds: 5));
      return BleCreditResponse.fromBytes(response);
    } on Object {
      await _disconnect();
      rethrow;
    }
  }

  Future<void> _ensureConnected() async {
    if (_creditCharacteristic != null) return;
    final pendingConnection = _connecting;
    if (pendingConnection != null) {
      await pendingConnection;
      return;
    }

    final connectionAttempt = _connect();
    _connecting = connectionAttempt;
    try {
      await connectionAttempt;
    } finally {
      if (identical(_connecting, connectionAttempt)) _connecting = null;
    }
  }

  Future<void> _connect() async {
    final device = await _ble
        .scanForDevices(
          withServices: const [],
          scanMode: ScanMode.lowLatency,
          requireLocationServicesEnabled: false,
        )
        .where(
          (device) =>
              device.serviceUuids.contains(_serviceId) ||
              device.name == _esp32DeviceName,
        )
        .first
        .timeout(
          const Duration(seconds: 12),
          onTimeout: () => throw TimeoutException(
            'ESP32 not found. Check its power and Bluetooth range.',
          ),
        );

    final connected = Completer<void>();
    final subscription = _ble
        .connectToDevice(
          id: device.id,
          servicesWithCharacteristicsToDiscover: {
            _serviceId: [_characteristicId],
          },
          connectionTimeout: const Duration(seconds: 10),
        )
        .listen(
          (update) {
            if (update.connectionState == DeviceConnectionState.connected) {
              if (!connected.isCompleted) connected.complete();
            } else if (update.connectionState ==
                    DeviceConnectionState.disconnected &&
                !connected.isCompleted) {
              connected.completeError(
                StateError('ESP32 Bluetooth connection was disconnected.'),
              );
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!connected.isCompleted) {
              connected.completeError(error, stackTrace);
            }
          },
        );
    _connection = subscription;

    try {
      await connected.future.timeout(const Duration(seconds: 12));
      final mtu = await _ble
          .requestMtu(deviceId: device.id, mtu: 128)
          .timeout(const Duration(seconds: 8));
      if (mtu < 64) {
        throw StateError(
          'ESP32 negotiated an unsupported Bluetooth data size.',
        );
      }
      _creditCharacteristic = QualifiedCharacteristic(
        deviceId: device.id,
        serviceId: _serviceId,
        characteristicId: _characteristicId,
      );
    } on Object {
      await _disconnect();
      rethrow;
    }
  }

  Future<void> _disconnect() async {
    _creditCharacteristic = null;
    final connection = _connection;
    _connection = null;
    await connection?.cancel();
  }

  Future<void> dispose() => _disconnect();
}

class BoothScreen extends StatefulWidget {
  const BoothScreen({super.key});

  @override
  State<BoothScreen> createState() => _BoothScreenState();
}

String _customerFrameDisplayName(String path) {
  final filename = File(path).uri.pathSegments.last;
  final extensionIndex = filename.lastIndexOf('.');
  final name = extensionIndex > 0
      ? filename.substring(0, extensionIndex)
      : filename;
  return name.replaceFirst(RegExp(r'^photo_(?:border|frame)_\d+'), 'Frame');
}

class _AnimatedStartButton extends StatefulWidget {
  const _AnimatedStartButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  State<_AnimatedStartButton> createState() => _AnimatedStartButtonState();
}

class _AnimatedStartButtonState extends State<_AnimatedStartButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  );
  bool _starting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_starting || widget.onPressed == null) return;
    setState(() => _starting = true);
    await _controller.forward();
    await _controller.reverse();
    if (!mounted) return;
    setState(() => _starting = false);
    widget.onPressed?.call();
  }

  @override
  Widget build(BuildContext context) => ScaleTransition(
    scale: Tween<double>(
      begin: 1,
      end: 0.94,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack)),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SizedBox(
          width: double.infinity,
          height: 60,
          child: FilledButton(
            onPressed: _starting || widget.onPressed == null ? null : _start,
            style: FilledButton.styleFrom(
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(horizontal: 20),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: const Text(
                'Start Photo Session',
                maxLines: 1,
                style: TextStyle(
                  fontFamily: 'DancingScript',
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

enum _PrinterType {
  receipt('Receipt printer'),
  color('Color printer');

  const _PrinterType(this.label);

  final String label;
}

enum _AiPaymentMethod { coins, qrPh }

enum _BrandLogoAnimation {
  none('None'),
  jump('Jump'),
  pump('Pump'),
  sway('Sway'),
  float('Float');

  const _BrandLogoAnimation(this.label);

  final String label;
}

class _PairedPrinter {
  const _PairedPrinter({required this.name, required this.address});

  final String name;
  final String address;

  String get label => '$name ($address)';
}

class _PhotoResultActionButton extends StatelessWidget {
  const _PhotoResultActionButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onPressed,
    required this.foregroundColor,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback? onPressed;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: enabled ? onPressed : null,
    icon: Icon(icon, size: 17),
    label: Text(
      label,
      textAlign: TextAlign.center,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
    ),
    style: OutlinedButton.styleFrom(
      alignment: Alignment.center,
      backgroundColor: Colors.white,
      foregroundColor: foregroundColor,
      disabledBackgroundColor: const Color(0xFFF7F8F9),
      disabledForegroundColor: const Color(0xFF8A9098),
      side: const BorderSide(color: Color(0xFFDCE1E6)),
      minimumSize: const Size.fromHeight(44),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
    ),
  );
}

class _PhotoDownloadActionButton extends StatefulWidget {
  const _PhotoDownloadActionButton({
    required this.label,
    required this.enabled,
    required this.onPressed,
    required this.foregroundColor,
    required this.highlighted,
  });

  final String label;
  final bool enabled;
  final VoidCallback? onPressed;
  final Color foregroundColor;
  final bool highlighted;

  @override
  State<_PhotoDownloadActionButton> createState() =>
      _PhotoDownloadActionButtonState();
}

class _PhotoDownloadActionButtonState extends State<_PhotoDownloadActionButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  );

  @override
  void initState() {
    super.initState();
    if (widget.highlighted) _pulseController.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _PhotoDownloadActionButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.highlighted && !oldWidget.highlighted) {
      _pulseController.repeat(reverse: true);
    } else if (!widget.highlighted && oldWidget.highlighted) {
      _pulseController.stop();
      _pulseController.value = 0;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _pulseController,
    builder: (context, child) {
      final borderColor = widget.highlighted
          ? Color.lerp(
              const Color(0xFFB7E4C7),
              const Color(0xFF168A45),
              _pulseController.value,
            )!
          : const Color(0xFFDCE1E6);
      return Padding(
        padding: EdgeInsets.only(top: widget.highlighted ? 9 : 0),
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: widget.enabled ? widget.onPressed : null,
              icon: const Icon(Icons.qr_code_2_rounded, size: 17),
              label: Text(
                widget.label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: OutlinedButton.styleFrom(
                alignment: Alignment.center,
                backgroundColor: Colors.white,
                foregroundColor: widget.foregroundColor,
                disabledBackgroundColor: const Color(0xFFF7F8F9),
                disabledForegroundColor: const Color(0xFF8A9098),
                side: BorderSide(
                  color: borderColor,
                  width: widget.highlighted ? 1.5 + _pulseController.value : 1,
                ),
                minimumSize: const Size.fromHeight(44),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
              ),
            ),
            if (widget.highlighted)
              Positioned(
                top: -9,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                    color: Color(0xFF168A45),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.cloud_download_rounded,
                    color: Colors.white,
                    size: 15,
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}

class _BarcodeWaveTransition extends StatefulWidget {
  const _BarcodeWaveTransition();

  @override
  State<_BarcodeWaveTransition> createState() => _BarcodeWaveTransitionState();
}

class _BarcodeWaveTransitionState extends State<_BarcodeWaveTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.white.withValues(alpha: 0.96),
    child: Center(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          size: const Size(220, 100),
          painter: _BarcodeWavePainter(_controller.value),
        ),
      ),
    ),
  );
}

class _BarcodeWavePainter extends CustomPainter {
  const _BarcodeWavePainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final barPaint = Paint()..color = const Color(0xFF1769AA);
    final centerY = size.height / 2;
    const widths = [3.0, 1.5, 4.0, 2.0, 1.5, 3.5, 2.0, 5.0, 1.5, 3.0];
    var x = 0.0;
    var index = 0;
    while (x < size.width) {
      final phase = (x / size.width * 2 * pi) - (progress * 2 * pi);
      final waveHeight = 24 + (sin(phase) + 1) * 22;
      final width = widths[index % widths.length];
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, centerY - waveHeight / 2, width, waveHeight),
          const Radius.circular(1.5),
        ),
        barPaint,
      );
      x += width + 3;
      index++;
    }
    final baseline = Paint()
      ..color = const Color(0xFF1769AA).withValues(alpha: 0.2)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, centerY), Offset(size.width, centerY), baseline);
  }

  @override
  bool shouldRepaint(covariant _BarcodeWavePainter oldDelegate) =>
      progress != oldDelegate.progress;
}

class _AiGenerationOverlay extends StatefulWidget {
  const _AiGenerationOverlay({required this.styleLabel});

  final String styleLabel;

  @override
  State<_AiGenerationOverlay> createState() => _AiGenerationOverlayState();
}

class _AiGenerationOverlayState extends State<_AiGenerationOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animationController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..repeat();

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Positioned.fill(
    child: IgnorePointer(
      child: AnimatedBuilder(
        animation: _animationController,
        builder: (context, child) => CustomPaint(
          painter: _AiGenerationSparklePainter(_animationController.value),
          child: child,
        ),
        child: Center(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xE61B2732),
              borderRadius: BorderRadius.circular(22),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x55000000),
                  blurRadius: 16,
                  offset: Offset(0, 5),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.auto_awesome_rounded,
                    color: Color(0xFFFFE08A),
                    size: 30,
                  ),
                  const SizedBox(height: 7),
                  Text(
                    'Creating ${widget.styleLabel}…',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const SizedBox(
                    width: 120,
                    child: LinearProgressIndicator(
                      color: Color(0xFFFFE08A),
                      backgroundColor: Color(0x55FFFFFF),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _AiGenerationSparklePainter extends CustomPainter {
  const _AiGenerationSparklePainter(this.progress);

  final double progress;

  static const _positions = <Offset>[
    Offset(0.13, 0.18),
    Offset(0.82, 0.16),
    Offset(0.23, 0.39),
    Offset(0.74, 0.35),
    Offset(0.88, 0.55),
    Offset(0.15, 0.67),
    Offset(0.67, 0.77),
    Offset(0.38, 0.88),
    Offset(0.51, 0.26),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    for (var index = 0; index < _positions.length; index++) {
      final phase = (progress + index * 0.17) % 1;
      final opacity = sin(phase * pi);
      if (opacity < 0.1) continue;

      final center = Offset(
        _positions[index].dx * size.width,
        _positions[index].dy * size.height,
      );
      final radius = 3 + opacity * 7;
      final alpha = (opacity * 220).round().clamp(0, 255);
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = Color.fromARGB(alpha, 255, 231, 141)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
      final sparkle = Path()
        ..moveTo(center.dx, center.dy - radius * 1.8)
        ..quadraticBezierTo(
          center.dx - radius * 0.3,
          center.dy - radius * 0.3,
          center.dx - radius * 1.8,
          center.dy,
        )
        ..quadraticBezierTo(
          center.dx - radius * 0.3,
          center.dy + radius * 0.3,
          center.dx,
          center.dy + radius * 1.8,
        )
        ..quadraticBezierTo(
          center.dx + radius * 0.3,
          center.dy + radius * 0.3,
          center.dx + radius * 1.8,
          center.dy,
        )
        ..quadraticBezierTo(
          center.dx + radius * 0.3,
          center.dy - radius * 0.3,
          center.dx,
          center.dy - radius * 1.8,
        )
        ..close();
      canvas.drawPath(
        sparkle,
        Paint()..color = Color.fromARGB(alpha, 255, 255, 244),
      );
    }
  }

  @override
  bool shouldRepaint(_AiGenerationSparklePainter oldDelegate) =>
      oldDelegate.progress != progress;
}

typedef _AiPhotoTransformer = Future<File> Function(File photo);
typedef _AiPhotoComposer = Future<File> Function(
  _AiPhotoTransformer transformPhoto,
);

class _PhotoCustomization {
  const _PhotoCustomization({
    this.photo,
    this.animatedGif,
    this.gifError,
    this.sessionVideo,
    this.videoError,
    this.aiPhotoComposer,
  }) : retakeRequested = false;

  const _PhotoCustomization.retake()
    : photo = null,
      animatedGif = null,
      gifError = null,
      sessionVideo = null,
      videoError = null,
      aiPhotoComposer = null,
      retakeRequested = true;

  final File? photo;
  final File? animatedGif;
  final String? gifError;
  final File? sessionVideo;
  final String? videoError;
  final _AiPhotoComposer? aiPhotoComposer;
  final bool retakeRequested;
}

class _PhotoCustomizationDialog extends StatefulWidget {
  const _PhotoCustomizationDialog({
    required this.photos,
    required this.captureDate,
    required this.decorationPaths,
    required this.customerFramePaths,
    required this.brandLogoPath,
    required this.borderStyle,
    required this.customBorderPath,
    required this.initialEffect,
    required this.aiGeneratedPhotoCache,
    required this.onFinalizationChanged,
    required this.captureVideoPaths,
    required this.countdownSeconds,
    this.captureVideoError,
    this.canRetake = false,
    this.initialFrameTemplate,
  });

  final List<File> photos;
  final DateTime captureDate;
  final List<String> decorationPaths;
  final List<String> customerFramePaths;
  final String? brandLogoPath;
  final PhotoBorderStyle borderStyle;
  final String? customBorderPath;
  final PhotoEffect initialEffect;
  final Map<String, File> aiGeneratedPhotoCache;
  final ValueChanged<bool> onFinalizationChanged;
  final List<String> captureVideoPaths;
  final int countdownSeconds;
  final String? captureVideoError;
  final bool canRetake;
  final PhotoFrameTemplate? initialFrameTemplate;

  @override
  State<_PhotoCustomizationDialog> createState() =>
      _PhotoCustomizationDialogState();
}

class _PhotoCustomizationDialogState extends State<_PhotoCustomizationDialog> {
  static const _borderColorChoices = <(String, Color)>[
    ('White', Color(0xFFFFFFFF)),
    ('Black', Color(0xFF17212B)),
    ('Blue gray', Color(0xFF47667D)),
    ('Sky blue', Color(0xFF81C7D9)),
    ('Pink', Color(0xFFE7A6B6)),
    ('Purple', Color(0xFFC59AD8)),
    ('Sage green', Color(0xFF8BBF9F)),
    ('Orange', Color(0xFFE6A35A)),
  ];

  int _step = 1;
  PhotoLayout _layout = PhotoLayout.verticalStrip;
  Color _borderColor = Colors.white;
  String? _framePath;
  PhotoFrameTemplate? _frameTemplate;
  late final List<PhotoEffect> _photoEffects;
  bool _mirrored = false;
  bool _isFinalizing = false;
  bool _showFinalPreview = false;
  int _activePhotoIndex = 0;
  int _activeEditorTab = 0;
  bool _photoDragActive = false;
  bool _showLivePhotoLayers = false;
  bool _previewRefreshPending = false;
  int _previewRefreshRevision = 0;
  late final List<PhotoCropTransform> _photoTransforms;
  late final ValueNotifier<PhotoCropTransform> _livePhotoTransform;
  Offset _previewGesturePan = Offset.zero;
  String? _finalizationError;
  File? _finalizedPhoto;
  Future<List<File>>? _processedPreviewPhotos;
  Future<List<Path>>? _liveWindowPaths;
  late Future<File> _selectedPreview;
  List<PhotoFrameTemplate> _customerFrameTemplates = const [];
  bool _customerFrameLoadFailed = false;
  bool _loadingCustomerFrameTemplates = true;
  final Map<String, Future<Size>> _previewSizes = {};
  final List<PhotoSticker> _stickers = [];
  int? _selectedStickerIndex;
  int? _activeStickerGestureIndex;
  Offset _stickerGestureStartPosition = Offset.zero;
  Offset _stickerGestureStartFocalPoint = Offset.zero;
  double _stickerGestureStartScale = 1;
  double _stickerGestureStartRotation = 0;

  PhotoEffect get _activeEffect => _photoEffects[_activePhotoIndex];

  @override
  void initState() {
    super.initState();
    _photoEffects = List<PhotoEffect>.filled(
      widget.photos.length,
      widget.initialEffect,
    );
    _frameTemplate = widget.initialFrameTemplate;
    if (widget.initialFrameTemplate?.photoWindowsFromTransparency == true) {
      _liveWindowPaths = photoWindowPathsForTemplate(
        widget.initialFrameTemplate!,
      );
    }
    _photoTransforms = List<PhotoCropTransform>.filled(
      widget.photos.length,
      const PhotoCropTransform(),
    );
    _livePhotoTransform = ValueNotifier(const PhotoCropTransform());
    _selectedPreview = _renderSelectedPhoto();
    unawaited(_loadCustomerFrameTemplates());
  }

  Future<void> _loadCustomerFrameTemplates() async {
    var loadFailed = false;
    final templates = await Future.wait(
      widget.customerFramePaths.map((path) async {
        try {
          return await customerPhotoFrameTemplate(path);
        } on Object catch (error) {
          loadFailed = true;
          debugPrint('Could not inspect customer frame "$path": $error');
          return null;
        }
      }),
    );
    if (!mounted) return;
    setState(() {
      _customerFrameTemplates = templates
          .whereType<PhotoFrameTemplate>()
          .toList(growable: false);
      _customerFrameLoadFailed = loadFailed;
      _loadingCustomerFrameTemplates = false;
    });
  }

  @override
  void dispose() {
    _livePhotoTransform.dispose();
    super.dispose();
  }

  void _refreshPreview() {
    _selectedPreview = _renderSelectedPhoto();
  }

  void _selectLayout(PhotoLayout layout) {
    if (_layout == layout || _isFinalizing) return;
    setState(() {
      _layout = layout;
      _refreshPreview();
    });
  }

  void _selectFrame({String? path, PhotoFrameTemplate? template}) {
    if (_framePath == path && _frameTemplate == template) return;
    _liveWindowPaths = null;
    if (template?.photoWindowsFromTransparency == true) {
      _liveWindowPaths ??= photoWindowPathsForTemplate(template!);
    }
    setState(() {
      _framePath = path;
      _frameTemplate = template;
      _refreshPreview();
    });
  }

  void _goBackOneStep() {
    if (_isFinalizing) return;
    if (_showFinalPreview) {
      setState(() => _showFinalPreview = false);
      return;
    }
    if (_finalizedPhoto != null) {
      _editFinalizedPhoto();
      return;
    }
    if (_step > 0) setState(() => _step--);
  }

  Future<File> _renderSelectedPhoto({
    int maxWidth = 800,
    bool includeStickers = false,
  }) async {
    final processedPhotos = maxWidth == 800
        ? await (_processedPreviewPhotos ??= _processPhotos(maxWidth))
        : await _processPhotos(maxWidth);
    final composedPhoto = await composePhotoStrip(
      processedPhotos,
      layout: _layout,
      borderColor: _borderColor,
      framePath: _framePath,
      frameTemplate: _frameTemplate,
      brandLogoPath: widget.brandLogoPath,
      photoBorderStyle: widget.borderStyle,
      captureDate: widget.captureDate,
      photoBorderOverlayPath: widget.borderStyle == PhotoBorderStyle.custom
          ? widget.customBorderPath
          : null,
      mirrorPhotos: _mirrored,
      photoTransforms: _photoTransforms,
    );
    return includeStickers && _stickers.isNotEmpty
        ? applyPhotoStickers(composedPhoto, _stickers)
        : composedPhoto;
  }

  Future<List<File>> _processPhotos(int maxWidth) => Future.wait(
    widget.photos.indexed.map((entry) {
      return applyPhotoEffect(
        entry.$2,
        _photoEffects[entry.$1],
        maxWidth: maxWidth,
      );
    }),
  );

  _AiPhotoComposer _createAiPhotoComposer() {
    final photos = List<File>.unmodifiable(widget.photos);
    final effects = List<PhotoEffect>.unmodifiable(_photoEffects);
    final transforms = List<PhotoCropTransform>.unmodifiable(_photoTransforms);
    final stickers = List<PhotoSticker>.unmodifiable(_stickers);
    final layout = _layout;
    final borderColor = _borderColor;
    final framePath = _framePath;
    final frameTemplate = _frameTemplate;
    final photoBorderStyle = widget.borderStyle;
    final photoBorderOverlayPath = widget.borderStyle == PhotoBorderStyle.custom
        ? widget.customBorderPath
        : null;
    final captureDate = widget.captureDate;
    final mirrorPhotos = _mirrored;
    final brandLogoPath = widget.brandLogoPath;

    return (transformPhoto) async {
      final effectedPhotos = await Future.wait(
        photos.indexed.map(
          (entry) =>
              applyPhotoEffect(entry.$2, effects[entry.$1], maxWidth: 1600),
        ),
      );
      final transformedPhotos = await generateAiPhotoBatch(
        photos: effectedPhotos,
        completedPhotos: widget.aiGeneratedPhotoCache,
        transformPhoto: transformPhoto,
      );
      final composedPhoto = await composePhotoStrip(
        transformedPhotos,
        layout: layout,
        borderColor: borderColor,
        framePath: framePath,
        frameTemplate: frameTemplate,
        brandLogoPath: brandLogoPath,
        photoBorderStyle: photoBorderStyle,
        captureDate: captureDate,
        photoBorderOverlayPath: photoBorderOverlayPath,
        mirrorPhotos: mirrorPhotos,
        photoTransforms: transforms,
      );
      return stickers.isEmpty
          ? composedPhoto
          : applyPhotoStickers(composedPhoto, stickers);
    };
  }

  Widget _buildLivePhotoLayers(Size displaySize) {
    Widget buildLayers(
      List<File> photos,
      List<Path>? windowPaths,
      Size frameDisplaySize,
    ) => ValueListenableBuilder<PhotoCropTransform>(
      valueListenable: _livePhotoTransform,
      builder: (context, activeTransform, _) => Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          for (final index
              in _frameTemplate?.photoPaintOrder.isNotEmpty == true
                  ? _frameTemplate!.photoPaintOrder
                  : List<int>.generate(photos.length, (index) => index))
            _buildLivePhotoLayer(
              index: index,
              photo: photos[index],
              displaySize: frameDisplaySize,
              activeTransform: activeTransform,
              windowPath: windowPaths?[index],
            ),
          if (_frameTemplate?.classicStyle == true)
            Positioned.fill(
              child: _ClassicFrameLiveChrome(
                template: _frameTemplate!,
                brandLogoPath: widget.brandLogoPath,
              ),
            ),
          if (_frameTemplate != null && !_frameTemplate!.classicStyle)
            Positioned.fill(
              child: IgnorePointer(
                child: _frameTemplate!.filePath == null
                    ? Image.asset(
                        _frameTemplate!.assetPath,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                      )
                    : Image.file(
                        File(_frameTemplate!.filePath!),
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                      ),
              ),
            ),
          if (_framePath != null)
            Positioned.fill(
              child: IgnorePointer(
                child: Image.file(
                  File(_framePath!),
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                ),
              ),
            ),
        ],
      ),
    );

    Widget buildLayersWithFrameHeader(
      List<File> photos,
      List<Path>? windowPaths,
    ) {
      final template = _frameTemplate;
      final brandLogoPath = widget.brandLogoPath;
      final hasExternalFrameHeader =
          _framePath != null ||
          template != null &&
              (!template.classicStyle || !template.classicHasBranding);
      if (!hasExternalFrameHeader) {
        return buildLayers(photos, windowPaths, displaySize);
      }

      final headerHeight = displaySize.width * 0.18;
      final frameDisplaySize = Size(
        displaySize.width,
        displaySize.height - headerHeight,
      );
      return Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned(
            top: headerHeight,
            left: 0,
            right: 0,
            bottom: 0,
            child: buildLayers(photos, windowPaths, frameDisplaySize),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: headerHeight,
            child: ColoredBox(
              color: Colors.white,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: displaySize.width * 0.19,
                  vertical: headerHeight * 0.08,
                ),
                child: brandLogoPath == null
                    ? Image.asset(
                        'assets/photobooth_logo.png',
                        fit: BoxFit.contain,
                      )
                    : Image.file(File(brandLogoPath), fit: BoxFit.contain),
              ),
            ),
          ),
        ],
      );
    }

    if (_frameTemplate?.photoWindowsFromTransparency == true) {
      final pathsFuture = _liveWindowPaths ??= photoWindowPathsForTemplate(
        _frameTemplate!,
      );
      return FutureBuilder<List<Path>>(
        future: pathsFuture,
        builder: (context, pathsSnapshot) {
          final paths = pathsSnapshot.data;
          if (paths == null) {
            if (pathsSnapshot.hasError) {
              debugPrint(
                'Could not load live photo window masks: '
                '${pathsSnapshot.error}',
              );
            }
            return const SizedBox.expand();
          }
          return _buildProcessedLivePhotoLayers(
            buildLayersWithFrameHeader,
            paths,
          );
        },
      );
    }
    return _buildProcessedLivePhotoLayers(buildLayersWithFrameHeader, null);
  }

  Widget _buildProcessedLivePhotoLayers(
    Widget Function(List<File>, List<Path>?) buildLayers,
    List<Path>? windowPaths,
  ) => FutureBuilder<List<File>>(
    future: _processedPreviewPhotos ??= _processPhotos(800),
    builder: (context, snapshot) {
      final photos = snapshot.data;
      if (photos == null) {
        if (snapshot.hasError) {
          debugPrint(
            'Could not process live photo filter preview: ${snapshot.error}',
          );
        }
        return const SizedBox.expand();
      }
      return buildLayers(photos, windowPaths);
    },
  );

  Widget _buildLivePhotoLayer({
    required int index,
    required File photo,
    required Size displaySize,
    required PhotoCropTransform activeTransform,
    Path? windowPath,
  }) {
    final slots = photoSlotBounds(
      widget.photos.length,
      layout: _layout,
      frameTemplate: _frameTemplate,
    );
    final slot = slots[index];
    final transform = index == _activePhotoIndex
        ? activeTransform
        : _photoTransforms[index];
    final destination = Rect.fromLTRB(
      slot.left * displaySize.width,
      slot.top * displaySize.height,
      slot.right * displaySize.width,
      slot.bottom * displaySize.height,
    );
    final photoLayer = Positioned.fromRect(
      rect: destination,
      child: Transform.rotate(
        angle: _frameTemplate?.rotationForSlot(index) ?? 0,
        child: ClipRect(
          child: Transform.scale(
            scale: transform.zoom,
            alignment: Alignment.center,
            child: Transform.flip(
              flipX: _mirrored,
              child: Image.file(
                photo,
                fit: BoxFit.cover,
                alignment: Alignment(
                  (_mirrored ? -1 : 1) * transform.pan.dx * 2,
                  transform.pan.dy * 2,
                ),
                filterQuality: FilterQuality.high,
                gaplessPlayback: true,
              ),
            ),
          ),
        ),
      ),
    );
    final borderLayer =
        widget.borderStyle != PhotoBorderStyle.none &&
            widget.borderStyle != PhotoBorderStyle.custom
        ? Positioned.fromRect(
            rect: destination,
            child: Transform.rotate(
              angle: _frameTemplate?.rotationForSlot(index) ?? 0,
              child: IgnorePointer(
                child: CustomPaint(
                  painter: PhotoBorderPainter(widget.borderStyle),
                ),
              ),
            ),
          )
        : null;
    final photoAndBorder = borderLayer == null
        ? Stack(children: [photoLayer])
        : Stack(children: [photoLayer, borderLayer]);
    if (windowPath == null) return photoAndBorder;
    return Positioned.fill(
      child: ClipPath(
        clipper: PhotoWindowClipper(windowPath),
        child: photoAndBorder,
      ),
    );
  }

  Future<Size> _readPreviewSize(File photo) async {
    return _previewSizes.putIfAbsent(photo.path, () async {
      final codec = await ui.instantiateImageCodec(await photo.readAsBytes());
      try {
        final frame = await codec.getNextFrame();
        try {
          return Size(
            frame.image.width.toDouble(),
            frame.image.height.toDouble(),
          );
        } finally {
          frame.image.dispose();
        }
      } finally {
        codec.dispose();
      }
    });
  }

  void _addSticker(PhotoSticker sticker) {
    if (_isFinalizing) return;
    setState(() {
      _stickers.add(photoStickerForCanvas(sticker));
      _selectedStickerIndex = _stickers.length - 1;
    });
  }

  PhotoSticker _stickerAt(int index) => index < photoStickerChoices.length
      ? photoStickerChoices[index]
      : PhotoSticker(
          label: File(
            widget.decorationPaths[index - photoStickerChoices.length],
          ).uri.pathSegments.last,
          imagePath: widget.decorationPaths[index - photoStickerChoices.length],
        );

  Widget _workspacePanel({required String title, required Widget child}) =>
      Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: Color(0x120F172A),
              blurRadius: 10,
              offset: Offset(0, 3),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 7, 10, 4),
              child: Text(
                title,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Expanded(child: child),
          ],
        ),
      );

  Widget _buildWorkspaceFilters({
    required bool compact,
    bool tablet = false,
    required double tileWidth,
    required bool vertical,
  }) => _workspacePanel(
    title: 'Looks',
    child: Column(
      children: [
        if (widget.photos.length > 1)
          SizedBox(
            height: compact ? 42 : 50,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              scrollDirection: Axis.horizontal,
              itemCount: widget.photos.length,
              separatorBuilder: (context, index) => const SizedBox(width: 6),
              itemBuilder: (context, index) => Semantics(
                button: true,
                selected: index == _activePhotoIndex,
                label: 'Edit photo ${index + 1}',
                child: InkWell(
                  onTap: () => _selectPhoto(index),
                  borderRadius: BorderRadius.circular(8),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: compact ? 48 : 58,
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: index == _activePhotoIndex
                          ? Border.all(color: _accent, width: 2)
                          : null,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: Image.file(
                        widget.photos[index],
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            scrollDirection: vertical ? Axis.vertical : Axis.horizontal,
            itemCount: PhotoEffect.values.length,
            separatorBuilder: (context, index) =>
                SizedBox(width: vertical ? 0 : 8, height: vertical ? 8 : 0),
            itemBuilder: (context, index) {
              final effect = PhotoEffect.values[index];
              return SizedBox(
                width: vertical ? double.infinity : tileWidth,
                height: vertical ? 86 : null,
                child: _WorkspaceFilterTile(
                  effect: effect,
                  photo: widget.photos[_activePhotoIndex],
                  selected: effect == _activeEffect,
                  tablet: tablet,
                  onTap: _isFinalizing ? null : () => _selectEffect(effect),
                ),
              );
            },
          ),
        ),
      ],
    ),
  );

  Widget _buildWorkspaceStickers({
    bool tablet = false,
    required double tileWidth,
    required bool vertical,
  }) => _workspacePanel(
    title: 'Decor',
    child: Column(
      children: [
        Expanded(
          child: vertical
              ? GridView.builder(
                  padding: const EdgeInsets.fromLTRB(8, 2, 8, 8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    childAspectRatio: 1,
                  ),
                  itemCount:
                      photoStickerChoices.length +
                      widget.decorationPaths.length,
                  itemBuilder: (context, index) {
                    final sticker = _stickerAt(index);
                    return _WorkspaceStickerTile(
                      sticker: sticker,
                      iconSize: 34,
                      onTap: _isFinalizing ? null : () => _addSticker(sticker),
                    );
                  },
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(8, 2, 8, 8),
                  scrollDirection: Axis.horizontal,
                  itemCount:
                      photoStickerChoices.length +
                      widget.decorationPaths.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final sticker = _stickerAt(index);
                    return SizedBox(
                      width: tileWidth,
                      child: _WorkspaceStickerTile(
                        sticker: sticker,
                        iconSize: tileWidth * 0.4,
                        onTap: _isFinalizing
                            ? null
                            : () => _addSticker(sticker),
                      ),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                onPressed: _selectedStickerIndex == null
                    ? null
                    : () => _resizeSelectedSticker(-0.15),
                tooltip: translateAppText(
                  'Make selected sticker smaller',
                  appLanguageNotifier.value,
                ),
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.remove_circle_outline),
              ),
              IconButton(
                onPressed: _selectedStickerIndex == null
                    ? null
                    : () => _resizeSelectedSticker(0.15),
                tooltip: translateAppText(
                  'Make selected sticker larger',
                  appLanguageNotifier.value,
                ),
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.add_circle_outline),
              ),
              IconButton(
                onPressed: _selectedStickerIndex == null
                    ? null
                    : _removeSelectedSticker,
                tooltip: translateAppText(
                  'Remove selected sticker',
                  appLanguageNotifier.value,
                ),
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _buildWorkspaceLayouts({
    required List<PhotoFrameTemplate> templates,
    required List<PhotoFrameTemplate> customerTemplates,
    bool tablet = false,
    required double tileWidth,
    required bool vertical,
  }) => _workspacePanel(
    title: 'Frames',
    child: Column(
      children: [
        if (_frameTemplate == null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Wrap(
              spacing: 4,
              children: [
                for (final layout in PhotoLayout.values)
                  ChoiceChip(
                    visualDensity: VisualDensity.compact,
                    label: Text(layout.label),
                    selected: _layout == layout,
                    selectedColor: _accent,
                    backgroundColor: Colors.white,
                    labelStyle: TextStyle(
                      color: _layout == layout ? Colors.white : _ink,
                      fontWeight: FontWeight.w700,
                    ),
                    onSelected: _isFinalizing
                        ? null
                        : (_) => _selectLayout(layout),
                  ),
              ],
            ),
          ),
        if (widget.borderStyle == PhotoBorderStyle.none &&
            _frameTemplate == null &&
            _framePath == null)
          SizedBox(
            height: 38,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              scrollDirection: Axis.horizontal,
              itemCount: _borderColorChoices.length,
              separatorBuilder: (context, index) => const SizedBox(width: 7),
              itemBuilder: (context, index) {
                final (label, color) = _borderColorChoices[index];
                final selected = _borderColor == color;
                return Tooltip(
                  message: label,
                  child: Semantics(
                    button: true,
                    selected: selected,
                    label: '$label border color',
                    child: InkWell(
                      onTap: _isFinalizing
                          ? null
                          : () => setState(() {
                              _borderColor = color;
                              _refreshPreview();
                            }),
                      customBorder: const CircleBorder(),
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: selected ? _accent : _outline,
                            width: selected ? 3 : 1,
                          ),
                        ),
                        child: selected
                            ? Icon(
                                Icons.check_rounded,
                                size: 16,
                                color: color.computeLuminance() > 0.5
                                    ? _ink
                                    : Colors.white,
                              )
                            : null,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        if (_loadingCustomerFrameTemplates)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        if (_customerFrameLoadFailed)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              'Some uploaded frames could not be loaded.',
              style: TextStyle(color: Color(0xFFB42318), fontSize: 11),
            ),
          ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            scrollDirection: vertical ? Axis.vertical : Axis.horizontal,
            itemCount: 1 + templates.length + customerTemplates.length,
            itemBuilder: (context, index) {
              late final Widget frameCard;
              if (index == 0) {
                frameCard = _FrameChoiceCard(
                  label: 'No frame',
                  selected: _framePath == null && _frameTemplate == null,
                  onTap: () => _selectFrame(),
                  child: const Icon(Icons.block_rounded),
                );
              } else if (index - 1 < templates.length) {
                final templateIndex = index - 1;
                final template = templates[templateIndex];
                frameCard = _FrameChoiceCard(
                  label: template.label,
                  selected: _frameTemplate == template,
                  onTap: () => _selectFrame(template: template),
                  child: template.classicStyle
                      ? _ClassicFramePreview(template: template)
                      : Image.asset(template.assetPath, fit: BoxFit.contain),
                );
              } else {
                final templateIndex = index - 1 - templates.length;
                final customerTemplate = customerTemplates[templateIndex];
                frameCard = _FrameChoiceCard(
                  label: customerTemplate.label,
                  selected: _frameTemplate == customerTemplate,
                  onTap: () => _selectFrame(template: customerTemplate),
                  child: Image.file(
                    File(customerTemplate.filePath!),
                    fit: BoxFit.contain,
                  ),
                );
              }
              return Padding(
                padding: EdgeInsets.only(
                  right: vertical ? 0 : 8,
                  bottom: vertical ? 8 : 0,
                ),
                child: SizedBox(
                  width: vertical ? double.infinity : tileWidth,
                  height: vertical ? 112 : null,
                  child: frameCard,
                ),
              );
            },
          ),
        ),
      ],
    ),
  );

  Widget _buildSimpleEditorOptions({
    required List<PhotoFrameTemplate> templates,
    required List<PhotoFrameTemplate> customerTemplates,
    required bool tablet,
    required double tileWidth,
    required bool vertical,
  }) {
    const categoryOptions = [
      (2, 'Frames', Icons.crop_portrait_rounded),
      (1, 'Decor', Icons.emoji_emotions_outlined),
      (0, 'Filters', Icons.tune_rounded),
    ];
    final optionsContent = AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.025, 0),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: KeyedSubtree(
        key: ValueKey(_activeEditorTab),
        child: switch (_activeEditorTab) {
          0 => _buildWorkspaceFilters(
            compact: !tablet,
            tablet: tablet,
            tileWidth: tileWidth,
            vertical: vertical,
          ),
          1 => _buildWorkspaceStickers(
            tablet: tablet,
            tileWidth: tileWidth,
            vertical: vertical,
          ),
          _ => _buildWorkspaceLayouts(
            templates: templates,
            customerTemplates: customerTemplates,
            tablet: tablet,
            tileWidth: tileWidth,
            vertical: vertical,
          ),
        },
      ),
    );

    Widget categoryButton(
      int index,
      String label,
      IconData icon, {
      required bool rail,
    }) {
      final selected = _activeEditorTab == index;
      return Semantics(
        button: true,
        selected: selected,
        label: label,
        child: SizedBox(
          height: rail ? 42 : null,
          child: rail
              ? OutlinedButton.icon(
                  onPressed: _isFinalizing
                      ? null
                      : () => setState(() => _activeEditorTab = index),
                  icon: Icon(icon, size: 18),
                  label: Text(label.toUpperCase()),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _ink,
                    backgroundColor: selected
                        ? const Color(0xFFF0E8FF)
                        : Colors.white,
                    side: BorderSide(
                      color: selected ? _accent : Colors.black,
                      width: selected ? 2 : 1.5,
                    ),
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    textStyle: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9),
                    ),
                  ),
                )
              : Material(
                  color: selected ? _ink : Colors.white,
                  borderRadius: BorderRadius.circular(13),
                  child: InkWell(
                    onTap: _isFinalizing
                        ? null
                        : () => setState(() => _activeEditorTab = index),
                    borderRadius: BorderRadius.circular(13),
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 44),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 3,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(13),
                        border: selected ? Border.all(color: _ink) : null,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            icon,
                            size: tablet ? 18 : 16,
                            color: selected ? Colors.white : _ink,
                          ),
                          const SizedBox(height: 2),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              label,
                              maxLines: 1,
                              style: TextStyle(
                                color: selected ? Colors.white : _ink,
                                fontSize: tablet ? 10 : 9,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120F172A),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: vertical
          ? Column(
              children: [
                Expanded(child: optionsContent),
                const SizedBox(height: 8),
                for (final (index, label, icon) in categoryOptions) ...[
                  if (index != categoryOptions.first.$1)
                    const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    child: categoryButton(index, label, icon, rail: true),
                  ),
                ],
              ],
            )
          : Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: _isFinalizing
                          ? null
                          : () => setState(
                              () =>
                                  _activeEditorTab = (_activeEditorTab + 2) % 3,
                            ),
                      tooltip: 'Previous editing tool',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.arrow_back_rounded),
                      style: IconButton.styleFrom(
                        foregroundColor: _ink,
                        backgroundColor: Colors.white,
                        side: const BorderSide(color: _outline),
                      ),
                    ),
                    for (final (index, label, icon) in categoryOptions) ...[
                      if (index != categoryOptions.first.$1)
                        const SizedBox(width: 4),
                      Expanded(
                        child: categoryButton(index, label, icon, rail: false),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(child: optionsContent),
              ],
            ),
    );
  }

  void _updateStickerGesture(
    int index,
    ScaleUpdateDetails details,
    Size imageSize,
  ) {
    if (_isFinalizing ||
        index >= _stickers.length ||
        _activeStickerGestureIndex != index) {
      return;
    }
    final current = _stickers[index];
    setState(() {
      _stickers[index] = current.copyWith(
        position: photoStickerPositionAfterDrag(
          startPosition: _stickerGestureStartPosition,
          startFocalPoint: _stickerGestureStartFocalPoint,
          currentFocalPoint: details.localFocalPoint,
          canvasSize: imageSize,
        ),
        scale: max(0.5, _stickerGestureStartScale * details.scale),
        rotation: _stickerGestureStartRotation + details.rotation,
      );
      _selectedStickerIndex = index;
    });
  }

  void _resizeSelectedSticker(double delta) {
    final index = _selectedStickerIndex;
    if (_isFinalizing || index == null || index >= _stickers.length) return;
    final sticker = _stickers[index];
    setState(() {
      _stickers[index] = sticker.copyWith(
        scale: max(0.5, sticker.scale + delta),
      );
    });
  }

  void _removeSelectedSticker() {
    final index = _selectedStickerIndex;
    if (_isFinalizing || index == null || index >= _stickers.length) return;
    setState(() {
      _stickers.removeAt(index);
      _selectedStickerIndex = _stickers.isEmpty
          ? null
          : (index - 1).clamp(0, _stickers.length - 1).toInt();
    });
  }

  void _selectEffect(PhotoEffect effect) {
    if (_activeEffect == effect || _isFinalizing) return;
    setState(() {
      _photoEffects[_activePhotoIndex] = effect;
      _processedPreviewPhotos = null;
      _previewRefreshPending = false;
      _previewRefreshRevision++;
      _showLivePhotoLayers = false;
      _refreshPreview();
    });
  }

  void _selectPhoto(int index) {
    if (index == _activePhotoIndex || _isFinalizing) return;
    setState(() {
      _activePhotoIndex = index;
      _livePhotoTransform.value = _photoTransforms[index];
    });
  }

  void _toggleMirror(bool mirrored) {
    if (_mirrored == mirrored || _isFinalizing) return;
    setState(() {
      _mirrored = mirrored;
      _previewRefreshPending = false;
      _previewRefreshRevision++;
      _showLivePhotoLayers = false;
      _refreshPreview();
    });
  }

  void _onPreviewGestureStart(ScaleStartDetails details, Size previewSize) {
    if (_isFinalizing) return;
    _photoDragActive = false;
    _activeStickerGestureIndex = null;
    _previewGesturePan = Offset.zero;
    final selectedStickerIndex = _selectedStickerIndex;
    if (_step < 2 &&
        selectedStickerIndex != null &&
        selectedStickerIndex < _stickers.length) {
      final sticker = _stickers[selectedStickerIndex];
      final geometry = PhotoStickerGeometry.forSize(sticker, previewSize);
      final touchSize = max(geometry.boxSize * 1.6, previewSize.width * 0.24);
      final stickerTouchTarget = Rect.fromCenter(
        center: geometry.center,
        width: touchSize,
        height: touchSize,
      );
      if (stickerTouchTarget.contains(details.localFocalPoint)) {
        _activeStickerGestureIndex = selectedStickerIndex;
        _stickerGestureStartPosition = sticker.position;
        _stickerGestureStartFocalPoint = details.localFocalPoint;
        _stickerGestureStartScale = sticker.scale;
        _stickerGestureStartRotation = sticker.rotation;
        return;
      }
    }
    final position = Offset(
      details.localFocalPoint.dx / previewSize.width,
      details.localFocalPoint.dy / previewSize.height,
    );
    final slots = photoSlotBounds(
      widget.photos.length,
      layout: _layout,
      frameTemplate: _frameTemplate,
    );
    final index = slots.indexWhere((slot) => slot.contains(position));
    if (index < 0) return;
    _photoDragActive = true;
    _previewRefreshRevision++;
    setState(() {
      _activePhotoIndex = index;
      _livePhotoTransform.value = _photoTransforms[index];
      _previewGesturePan = Offset.zero;
      _showLivePhotoLayers = true;
    });
  }

  void _onPreviewGestureUpdate(ScaleUpdateDetails details, Size previewSize) {
    if (_isFinalizing) return;
    final stickerIndex = _activeStickerGestureIndex;
    if (stickerIndex != null) {
      _updateStickerGesture(stickerIndex, details, previewSize);
      return;
    }
    if (!_photoDragActive) return;
    _previewGesturePan += details.focalPointDelta;
    final current = _photoTransforms[_activePhotoIndex];
    final maxPan =
        (_frameTemplate?.containPhotos == true ? 0.5 : 0.8) / current.zoom;
    final pan =
        current.pan +
        Offset(
          -_previewGesturePan.dx / previewSize.width * 1.1,
          -_previewGesturePan.dy / previewSize.height * 1.1,
        );
    _livePhotoTransform.value = PhotoCropTransform(
      zoom: current.zoom,
      pan: Offset(
        pan.dx.clamp(-maxPan, maxPan).toDouble(),
        pan.dy.clamp(-maxPan, maxPan).toDouble(),
      ),
    );
  }

  void _onPreviewGestureEnd(ScaleEndDetails details, Size previewSize) {
    if (_activeStickerGestureIndex != null) {
      _activeStickerGestureIndex = null;
      return;
    }
    if (_isFinalizing || !_photoDragActive) {
      _photoDragActive = false;
      return;
    }
    _photoDragActive = false;
    if (_previewGesturePan == Offset.zero) {
      if (_showLivePhotoLayers) {
        if (_previewRefreshPending) {
          setState(() {});
        } else {
          setState(() => _showLivePhotoLayers = false);
        }
      }
      return;
    }
    setState(() {
      _photoTransforms[_activePhotoIndex] = _livePhotoTransform.value;
      _previewRefreshPending = true;
      _refreshPreview();
    });
  }

  Future<void> _useSelectedPhoto() async {
    if (_isFinalizing) return;
    setState(() {
      _isFinalizing = true;
      _finalizationError = null;
    });
    widget.onFinalizationChanged(true);
    try {
      final photo = await _renderSelectedPhoto(
        maxWidth: 1600,
        includeStickers: true,
      );
      if (mounted) {
        setState(() {
          _finalizedPhoto = photo;
          _selectedPreview = Future<File>.value(photo);
          _selectedStickerIndex = null;
          _step = 2;
          _showFinalPreview = false;
          _isFinalizing = false;
        });
        widget.onFinalizationChanged(false);
      }
    } on Object catch (error) {
      widget.onFinalizationChanged(false);
      debugPrint('Could not prepare the full-quality photo: $error');
      if (mounted) {
        setState(() {
          _isFinalizing = false;
          _finalizationError = 'Could not prepare the photo. Please try again or ask the attendant.';
        });
      }
    }
  }

  void _editFinalizedPhoto() {
    if (_finalizedPhoto == null || _isFinalizing) return;
    setState(() {
      _finalizedPhoto = null;
      _step = 1;
      _showFinalPreview = false;
      _selectedStickerIndex = _stickers.isEmpty ? null : _stickers.length - 1;
      _selectedPreview = _renderSelectedPhoto();
    });
  }

  void _proceedToFinalPreview() {
    if (_finalizedPhoto == null || _isFinalizing) return;
    setState(() => _showFinalPreview = true);
  }

  Future<void> _confirmFinalizedPhoto() async {
    final photo = _finalizedPhoto;
    if (photo == null || _isFinalizing) return;
    setState(() => _isFinalizing = true);
    widget.onFinalizationChanged(true);
    File? animatedGif;
    String? gifError;
    File? sessionVideo;
    var videoError = widget.captureVideoError;
    try {
      final gifFrames = await Future.wait(
        widget.photos.indexed.map((entry) {
          return applyPhotoEffect(
            entry.$2,
            _photoEffects[entry.$1],
            maxWidth: 480,
          );
        }),
      );
      animatedGif = await createSessionGif(gifFrames);
    } on Object catch (error) {
      gifError = 'Could not prepare the animated GIF: $error';
      debugPrint(gifError);
    }
    if (videoError == null &&
        widget.captureVideoPaths.length == widget.photos.length) {
      try {
        sessionVideo = await composeSessionVideo(
          clips: widget.captureVideoPaths.map(File.new).toList(growable: false),
          posePhoto: photo,
          photoSlots: photoSlotBounds(
            widget.photos.length,
            layout: _layout,
            frameTemplate: _frameTemplate,
          ),
          countdownSeconds: widget.countdownSeconds,
        );
      } on Object catch (error) {
        videoError = 'Could not prepare the framed video: $error';
        debugPrint(videoError);
      }
    } else {
      videoError ??= 'One or more capture videos are unavailable.';
    }
    if (!mounted) return;
    widget.onFinalizationChanged(false);
    Navigator.of(context).pop(
      _PhotoCustomization(
        photo: photo,
        animatedGif: animatedGif,
        gifError: gifError,
        sessionVideo: sessionVideo,
        videoError: videoError,
        aiPhotoComposer: _createAiPhotoComposer(),
      ),
    );
  }

  void _resetWorkspace() {
    if (_isFinalizing || _step == 2) return;
    for (var index = 0; index < _photoTransforms.length; index++) {
      _photoTransforms[index] = const PhotoCropTransform();
    }
    _livePhotoTransform.value = const PhotoCropTransform();
    _liveWindowPaths =
        widget.initialFrameTemplate?.photoWindowsFromTransparency == true
        ? photoWindowPathsForTemplate(widget.initialFrameTemplate!)
        : null;
    setState(() {
      _layout = PhotoLayout.verticalStrip;
      _borderColor = Colors.white;
      _framePath = null;
      _frameTemplate = widget.initialFrameTemplate;
      for (var index = 0; index < _photoEffects.length; index++) {
        _photoEffects[index] = widget.initialEffect;
      }
      _stickers.clear();
      _selectedStickerIndex = null;
      _activePhotoIndex = 0;
      _mirrored = false;
      _showLivePhotoLayers = false;
      _processedPreviewPhotos = null;
      _refreshPreview();
    });
  }

  Widget _buildWorkspaceFooter({
    required bool isCompact,
    bool previewColumn = false,
  }) => FutureBuilder<File>(
    future: _selectedPreview,
    builder: (context, snapshot) {
      final saveButton = SizedBox(
        width: previewColumn
            ? double.infinity
            : isCompact
            ? 180
            : 240,
        child: FilledButton.icon(
          onPressed:
              snapshot.connectionState == ConnectionState.done &&
                  snapshot.hasData &&
                  !_isFinalizing &&
                  !_hasPrinted
              ? _step == 2
                    ? _showFinalPreview
                          ? _confirmFinalizedPhoto
                          : _proceedToFinalPreview
                    : _useSelectedPhoto
              : null,
          icon: _isFinalizing
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Icon(
                  _step == 2 && _showFinalPreview
                      ? Icons.check_rounded
                      : _step == 2
                      ? Icons.arrow_forward_rounded
                      : Icons.save_alt_rounded,
                ),
          label: Text(
            _isFinalizing
                ? 'PREPARING PHOTO'
                : _step == 2 && _showFinalPreview
                ? 'USE THIS PHOTO'
                : _step == 2
                ? 'PROCEED'
                : 'SAVE PHOTO',
          ),
          style: FilledButton.styleFrom(
            minimumSize: Size.fromHeight(
              previewColumn
                  ? 44
                  : isCompact
                  ? 48
                  : 56,
            ),
            elevation: 3,
            shadowColor: const Color(0x3347667D),
            textStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.35,
            ),
          ),
        ),
      );
      final resetButton = TextButton.icon(
        onPressed: _step == 2 || _isFinalizing ? null : _resetWorkspace,
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('Reset'),
        style: TextButton.styleFrom(foregroundColor: _ink),
      );
      final retakeButton = widget.canRetake && _step < 2
          ? OutlinedButton.icon(
              onPressed: _isFinalizing || _hasPrinted
                  ? null
                  : () =>
                        Navigator.of(context)
                            .pop(const _PhotoCustomization.retake()),
              icon: const Icon(Icons.camera_alt_outlined, size: 18),
              label: const Text('Retake'),
            )
          : null;

      if (previewColumn) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [resetButton, ?retakeButton],
            ),
            const SizedBox(height: 4),
            saveButton,
          ],
        );
      }

      return Row(
        children: [
          resetButton,
          if (retakeButton != null) ...[const SizedBox(width: 8), retakeButton],
          const Spacer(),
          if (_step == 2) ...[
            IconButton(
              onPressed: _isFinalizing ? null : _goBackOneStep,
              tooltip: translateAppText(
                'Back to editing',
                appLanguageNotifier.value,
              ),
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            const SizedBox(width: 8),
          ],
          saveButton,
        ],
      );
    },
  );

  Widget _buildReviewStep() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      boxShadow: const [
        BoxShadow(
          color: Color(0x100F172A),
          blurRadius: 16,
          offset: Offset(0, 5),
        ),
      ],
    ),
    child: SingleChildScrollView(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _showFinalPreview
            ? [
                const Align(
                  child: SizedBox(
                    width: 58,
                    height: 58,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Color(0xFFE7F5EE),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.check_rounded,
                        color: Color(0xFF23865A),
                        size: 34,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Final preview',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _ink,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Check your finished photo. Go back to change filters, decorations, or framing.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _muted, height: 1.4),
                ),
                const SizedBox(height: 12),
                Text(
                  'Original photo selected',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ]
            : [
                const Text(
                  'Print your original photo first to unlock the paid AI styles.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _muted, height: 1.4),
                ),
                const SizedBox(height: 16),
                const Icon(Icons.lock_outline_rounded, color: _muted, size: 24),
              ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final isCompact = screenSize.height < 700;
    final tabletEditor = screenSize.shortestSide >= 480;
    final landscape = screenSize.width > screenSize.height;
    final matchingTemplates = frameTemplatesForOrientation(
      widget.photos.length,
      landscape: landscape,
    );
    final matchingCustomerTemplates = _customerFrameTemplates
        .where(
          (template) =>
              template.photoCount == widget.photos.length &&
              template.landscape == landscape,
        )
        .toList(growable: false);
    return PopScope(
      canPop: false,
      child: Dialog.fullscreen(
        backgroundColor: _canvas,
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              isCompact ? 10 : 18,
              20,
              isCompact ? 12 : 20,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x120F172A),
                        blurRadius: 14,
                        offset: Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEAF2F8),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.auto_awesome_rounded,
                          color: _accent,
                        ),
                      ),
                      SizedBox(
                        width: tabletEditor ? 12 : 0,
                        height: tabletEditor ? 0 : 12,
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Make it yours',
                              style: TextStyle(
                                color: _ink,
                                fontFamily: 'DancingScript',
                                fontWeight: FontWeight.w700,
                                fontSize: isCompact ? 24 : 28,
                              ),
                            ),
                            Text(
                              _step == 2
                                  ? _showFinalPreview
                                        ? 'Final preview'
                                        : 'Choose your photo style'
                                  : 'Choose looks, decor, and a frame',
                              style: const TextStyle(color: _muted),
                            ),
                          ],
                        ),
                      ),
                      if (_step < 2) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: _panel,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${widget.photos.length} ${widget.photos.length == 1 ? 'photo' : 'photos'}',
                            style: const TextStyle(
                              color: _accent,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.1,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                SizedBox(height: isCompact ? 8 : 14),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, bodyConstraints) {
                      final sideBySide =
                          bodyConstraints.maxWidth >= 480 && _step < 2;
                      final tileWidth =
                          (bodyConstraints.maxWidth *
                                  (sideBySide ? 0.15 : 0.19))
                              .clamp(84.0, 126.0);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: Flex(
                              direction: sideBySide
                                  ? Axis.horizontal
                                  : Axis.vertical,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(
                                  flex: sideBySide
                                      ? 7
                                      : tabletEditor
                                      ? 6
                                      : 7,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Expanded(
                                        child: Flex(
                                          direction: Axis.vertical,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            Expanded(
                                              flex: _step == 2 ? 6 : 9,
                                              child: Container(
                                                width: double.infinity,
                                                alignment: Alignment.center,
                                                decoration: BoxDecoration(
                                                  color: Colors.white,
                                                  borderRadius:
                                                      BorderRadius.circular(20),
                                                  boxShadow: const [
                                                    BoxShadow(
                                                      color: Color(0x100F172A),
                                                      blurRadius: 16,
                                                      offset: Offset(0, 5),
                                                    ),
                                                  ],
                                                ),
                                                clipBehavior: Clip.antiAlias,
                                                child: FutureBuilder<File>(
                                                  future: _selectedPreview,
                                                  builder: (context, snapshot) {
                                                    if (_previewRefreshPending &&
                                                        snapshot.connectionState ==
                                                            ConnectionState
                                                                .done) {
                                                      final revision =
                                                          _previewRefreshRevision;
                                                      WidgetsBinding.instance.addPostFrameCallback((
                                                        _,
                                                      ) {
                                                        if (!mounted ||
                                                            !_previewRefreshPending ||
                                                            _photoDragActive ||
                                                            revision !=
                                                                _previewRefreshRevision) {
                                                          return;
                                                        }
                                                        setState(() {
                                                          _previewRefreshPending =
                                                              false;
                                                          _showLivePhotoLayers =
                                                              false;
                                                        });
                                                      });
                                                    }
                                                    if (snapshot.hasError) {
                                                      debugPrint(
                                                        'Could not create the photo preview: '
                                                        '${snapshot.error}',
                                                      );
                                                      return const Padding(
                                                        padding: EdgeInsets.all(
                                                          20,
                                                        ),
                                                        child: Text(
                                                          'Could not create the photo preview. Please try another look.',
                                                          textAlign:
                                                              TextAlign.center,
                                                          style: TextStyle(
                                                            color: Color(
                                                              0xFFB42318,
                                                            ),
                                                          ),
                                                        ),
                                                      );
                                                    }
                                                    final preview =
                                                        snapshot.data;
                                                    if (preview == null) {
                                                      return const CircularProgressIndicator(
                                                        color: _accent,
                                                      );
                                                    }
                                                    return Column(
                                                      children: [
                                                        Expanded(
                                                          child: LayoutBuilder(
                                                            builder: (context, constraints) {
                                                              final previewSize =
                                                                  Size(
                                                                    constraints
                                                                        .maxWidth,
                                                                    constraints
                                                                        .maxHeight,
                                                                  );
                                                              return Stack(
                                                                alignment:
                                                                    Alignment
                                                                        .center,
                                                                children: [
                                                                  Center(
                                                                    child: FutureBuilder<Size>(
                                                                      future: _readPreviewSize(
                                                                        preview,
                                                                      ),
                                                                      builder: (context, sizeSnapshot) {
                                                                        final imageSize =
                                                                            sizeSnapshot.data;
                                                                        if (imageSize ==
                                                                            null) {
                                                                          return const CircularProgressIndicator(
                                                                            color:
                                                                                _accent,
                                                                          );
                                                                        }
                                                                        final displaySize = applyBoxFit(
                                                                          BoxFit
                                                                              .contain,
                                                                          imageSize,
                                                                          previewSize,
                                                                        ).destination;
                                                                        final stickerGeometries = [
                                                                          for (final sticker
                                                                              in _stickers)
                                                                            PhotoStickerGeometry.forSize(
                                                                              sticker,
                                                                              displaySize,
                                                                            ),
                                                                        ];
                                                                        return SizedBox(
                                                                          width:
                                                                              displaySize.width,
                                                                          height:
                                                                              displaySize.height,
                                                                          child: GestureDetector(
                                                                            behavior:
                                                                                HitTestBehavior.opaque,
                                                                            onScaleStart: (details) => _onPreviewGestureStart(
                                                                              details,
                                                                              displaySize,
                                                                            ),
                                                                            onScaleUpdate: (details) => _onPreviewGestureUpdate(
                                                                              details,
                                                                              displaySize,
                                                                            ),
                                                                            onScaleEnd: (details) => _onPreviewGestureEnd(
                                                                              details,
                                                                              displaySize,
                                                                            ),
                                                                            child: Stack(
                                                                              clipBehavior: Clip.hardEdge,
                                                                              children: [
                                                                                Positioned.fill(
                                                                                  child: Image.file(
                                                                                    preview,
                                                                                    fit: BoxFit.contain,
                                                                                    errorBuilder: (context, error, stack) => const Center(
                                                                                      child: Text(
                                                                                        'Photo preview could not be displayed.',
                                                                                        style: TextStyle(color: _ink),
                                                                                      ),
                                                                                    ),
                                                                                  ),
                                                                                ),
                                                                                if (_showLivePhotoLayers && _finalizedPhoto == null) Positioned.fill(child: _buildLivePhotoLayers(displaySize)),
                                                                                for (var index = 0; _finalizedPhoto == null && index < _stickers.length; index++)
                                                                                  Positioned(
                                                                                    width: stickerGeometries[index].boxSize,
                                                                                    height: stickerGeometries[index].boxSize,
                                                                                    left: stickerGeometries[index].center.dx - stickerGeometries[index].boxSize / 2,
                                                                                    top: stickerGeometries[index].center.dy - stickerGeometries[index].boxSize / 2,
                                                                                    child: Transform.rotate(
                                                                                      angle: _stickers[index].rotation,
                                                                                      child: Listener(
                                                                                        onPointerDown: (_) => setState(() => _selectedStickerIndex = index),
                                                                                        child: DecoratedBox(
                                                                                          decoration: BoxDecoration(
                                                                                            border: _selectedStickerIndex == index
                                                                                                ? Border.all(color: _accent, width: displaySize.width * 0.004)
                                                                                                : null,
                                                                                            borderRadius: BorderRadius.circular(displaySize.width * 0.015),
                                                                                          ),
                                                                                          child: SizedBox(
                                                                                            width: double.infinity,
                                                                                            height: double.infinity,
                                                                                            child: Center(
                                                                                              child: _stickers[index].imagePath != null
                                                                                                  ? Image.file(File(_stickers[index].imagePath!), fit: BoxFit.contain)
                                                                                                  : _stickers[index].icon != null
                                                                                                  ? Icon(
                                                                                                      _stickers[index].icon!,
                                                                                                      size: stickerGeometries[index].glyphSize,
                                                                                                      color: Colors.white,
                                                                                                      shadows: const [Shadow(color: Color(0x99000000), blurRadius: 8)],
                                                                                                    )
                                                                                                  : Text(
                                                                                                      _stickers[index].emoji!,
                                                                                                      style: TextStyle(
                                                                                                        color: Colors.white,
                                                                                                        fontSize: stickerGeometries[index].glyphSize,
                                                                                                        shadows: const [Shadow(color: Color(0x99000000), blurRadius: 8)],
                                                                                                      ),
                                                                                                    ),
                                                                                            ),
                                                                                          ),
                                                                                        ),
                                                                                      ),
                                                                                    ),
                                                                                  ),
                                                                              ],
                                                                            ),
                                                                          ),
                                                                        );
                                                                      },
                                                                    ),
                                                                  ),
                                                                  if (snapshot.connectionState !=
                                                                          ConnectionState
                                                                              .done &&
                                                                      !_showLivePhotoLayers)
                                                                    const Positioned(
                                                                      top: 12,
                                                                      right: 12,
                                                                      child: SizedBox(
                                                                        width:
                                                                            24,
                                                                        height:
                                                                            24,
                                                                        child: CircularProgressIndicator(
                                                                          color:
                                                                              _accent,
                                                                          strokeWidth:
                                                                              2.5,
                                                                        ),
                                                                      ),
                                                                    ),
                                                                ],
                                                              );
                                                            },
                                                          ),
                                                        ),
                                                        if (_step < 2)
                                                          Padding(
                                                            padding:
                                                                const EdgeInsets.only(
                                                                  bottom: 4,
                                                                ),
                                                            child: Text(
                                                              _frameTemplate
                                                                          ?.containPhotos ==
                                                                      true
                                                                  ? 'Drag the photo to adjust its position'
                                                                  : 'Drag the photo to reposition it',
                                                              textAlign:
                                                                  TextAlign
                                                                      .center,
                                                              maxLines: 1,
                                                              overflow:
                                                                  TextOverflow
                                                                      .ellipsis,
                                                              style:
                                                                  Theme.of(
                                                                        context,
                                                                      )
                                                                      .textTheme
                                                                      .labelSmall
                                                                      ?.copyWith(
                                                                        color:
                                                                            _muted,
                                                                      ),
                                                            ),
                                                          ),
                                                        if (_step < 2)
                                                          Padding(
                                                            padding:
                                                                const EdgeInsets.fromLTRB(
                                                                  12,
                                                                  0,
                                                                  12,
                                                                  6,
                                                                ),
                                                            child: Row(
                                                              children: [
                                                                const Icon(
                                                                  Icons
                                                                      .flip_rounded,
                                                                  color: _muted,
                                                                ),
                                                                const SizedBox(
                                                                  width: 8,
                                                                ),
                                                                const Expanded(
                                                                  child: Text(
                                                                    'Mirror captured photos',
                                                                    style: TextStyle(
                                                                      color:
                                                                          _ink,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .w700,
                                                                    ),
                                                                  ),
                                                                ),
                                                                Material(
                                                                  elevation: 2,
                                                                  color: Colors
                                                                      .white,
                                                                  shadowColor:
                                                                      const Color(
                                                                        0x3347667D,
                                                                      ),
                                                                  borderRadius:
                                                                      BorderRadius.circular(
                                                                        20,
                                                                      ),
                                                                  child: Switch(
                                                                    value:
                                                                        _mirrored,
                                                                    activeThumbColor:
                                                                        _accent,
                                                                    onChanged:
                                                                        _toggleMirror,
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                      ],
                                                    );
                                                  },
                                                ),
                                              ),
                                            ),
                                            if (_step == 2) ...[
                                              const SizedBox(height: 10),
                                              Expanded(
                                                flex: 4,
                                                child: _buildReviewStep(),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      if (sideBySide) ...[
                                        const SizedBox(height: 4),
                                        _buildWorkspaceFooter(
                                          isCompact: true,
                                          previewColumn: true,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                if (_step < 2) ...[
                                  if (sideBySide)
                                    const SizedBox(width: 10)
                                  else
                                    const SizedBox(height: 10),
                                  Expanded(
                                    flex: sideBySide
                                        ? 3
                                        : tabletEditor
                                        ? 4
                                        : 3,
                                    child: _buildSimpleEditorOptions(
                                      templates: matchingTemplates,
                                      customerTemplates:
                                          matchingCustomerTemplates,
                                      tablet: tabletEditor,
                                      tileWidth: tileWidth,
                                      vertical: sideBySide,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (_finalizationError != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              _finalizationError!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFFB42318),
                                fontSize: 12,
                              ),
                            ),
                          ],
                          if (_isFinalizing) ...[
                            const SizedBox(height: 6),
                            const Text(
                              'Please wait — your full-quality photo is being prepared.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: _muted,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                          if (!sideBySide)
                            Padding(
                              padding: const EdgeInsets.only(top: 14),
                              child: _buildWorkspaceFooter(
                                isCompact: isCompact,
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ClassicFrameLiveChrome extends StatelessWidget {
  const _ClassicFrameLiveChrome({required this.template, this.brandLogoPath});

  final PhotoFrameTemplate template;
  final String? brandLogoPath;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final height = constraints.maxHeight;
      final hasBranding = template.classicHasBranding;
      final logoPath = brandLogoPath;
      final logoBounds = classicFrameLogoBounds(Size(width, height), template);
      return Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(painter: _ClassicFrameOutlinePainter(template)),
          ),
          if (hasBranding)
            Positioned(
              left: logoBounds.left,
              top: logoBounds.top,
              width: logoBounds.width,
              height: logoBounds.height,
              child: logoPath == null
                  ? Image.asset(
                      'assets/photobooth_logo.png',
                      fit: BoxFit.contain,
                    )
                  : Image.file(File(logoPath), fit: BoxFit.contain),
            ),
        ],
      );
    },
  );
}

class _ClassicFrameOutlinePainter extends CustomPainter {
  const _ClassicFrameOutlinePainter(this.template);

  final PhotoFrameTemplate template;

  @override
  void paint(Canvas canvas, Size size) {
    final photoSlots = template.photoSlots;
    final framePaint = Paint()
      ..color = _ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(5)),
      framePaint,
    );
    final slotPaint = Paint()
      ..color = _ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (final slot in photoSlots) {
      canvas.drawRect(
        Rect.fromLTRB(
          slot.left * size.width,
          slot.top * size.height,
          slot.right * size.width,
          slot.bottom * size.height,
        ),
        slotPaint,
      );
    }
    paintLandscapeFrameDesign(canvas, size, template);
  }

  @override
  bool shouldRepaint(_ClassicFrameOutlinePainter oldDelegate) =>
      !identical(template, oldDelegate.template);
}

class _ClassicFramePreview extends StatelessWidget {
  const _ClassicFramePreview({required this.template});

  final PhotoFrameTemplate template;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 100,
    height: 100 / template.classicAspectRatio,
    child: CustomPaint(painter: _ClassicFramePreviewPainter(template)),
  );
}

class _ClassicFramePreviewPainter extends CustomPainter {
  const _ClassicFramePreviewPainter(this.template);

  final PhotoFrameTemplate template;

  @override
  void paint(Canvas canvas, Size size) {
    final photoSlots = template.photoSlots;
    for (final destination in _classicPreviewSlots(size, photoSlots)) {
      canvas.drawRect(destination, Paint()..color = const Color(0xFF716C6C));
    }
  }

  @override
  bool shouldRepaint(_ClassicFramePreviewPainter oldDelegate) =>
      !identical(template, oldDelegate.template);
}

List<Rect> _classicPreviewSlots(Size size, List<Rect> photoSlots) => photoSlots
    .map(
      (slot) => Rect.fromLTRB(
        slot.left * size.width,
        slot.top * size.height,
        slot.right * size.width,
        slot.bottom * size.height,
      ),
    )
    .toList(growable: false);

class _FrameChoiceCard extends StatelessWidget {
  const _FrameChoiceCard({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.child,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 1, 0, 2),
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: double.infinity,
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFEAF0F5) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: selected ? Border.all(color: _accent, width: 2) : null,
          boxShadow: [
            BoxShadow(
              color: selected
                  ? const Color(0x2847667D)
                  : const Color(0x120F172A),
              blurRadius: selected ? 10 : 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: FittedBox(fit: BoxFit.contain, child: child),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _ink,
                fontSize: 9,
                fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _WorkspaceFilterTile extends StatelessWidget {
  const _WorkspaceFilterTile({
    required this.effect,
    required this.photo,
    required this.selected,
    required this.tablet,
    required this.onTap,
  });

  final PhotoEffect effect;
  final File photo;
  final bool selected;
  final bool tablet;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(10),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: selected ? Border.all(color: _accent, width: 2) : null,
          boxShadow: [
            BoxShadow(
              color: selected
                  ? const Color(0x2847667D)
                  : const Color(0x120F172A),
              blurRadius: selected ? 8 : 5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: SizedBox.expand(
                  child: ColorFiltered(
                    colorFilter: _liveEffectColorFilter(effect),
                    child: Image.file(photo, fit: BoxFit.cover),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              effect.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _ink,
                fontSize: tablet ? 14 : 10,
                fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _WorkspaceStickerTile extends StatelessWidget {
  const _WorkspaceStickerTile({
    required this.sticker,
    required this.iconSize,
    required this.onTap,
  });

  final PhotoSticker sticker;
  final double iconSize;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: sticker.label,
    child: Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            boxShadow: const [
              BoxShadow(
                color: Color(0x120F172A),
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: sticker.imagePath != null
              ? Padding(
                  padding: const EdgeInsets.all(7),
                  child: Image.file(
                    File(sticker.imagePath!),
                    fit: BoxFit.contain,
                  ),
                )
              : sticker.emoji != null
              ? Text(sticker.emoji!, style: TextStyle(fontSize: iconSize))
              : Icon(sticker.icon, color: _ink, size: iconSize),
        ),
      ),
    ),
  );
}

class _SessionLayoutChoiceCard extends StatelessWidget {
  const _SessionLayoutChoiceCard({
    required this.template,
    required this.selected,
    required this.onTap,
  });

  final PhotoFrameTemplate template;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final count = template.photoCount;
    return Semantics(
      button: true,
      selected: selected,
      label: '$count ${count == 1 ? 'photo' : 'photos'} classic layout',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: _ClassicFramePreview(template: template),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '$count ${count == 1 ? 'PHOTO' : 'PHOTOS'}',
                      style: TextStyle(
                        color: selected ? _accent : _ink,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.6,
                      ),
                    ),
                    if (selected) ...[
                      const SizedBox(width: 5),
                      const Icon(
                        Icons.check_circle_rounded,
                        color: _accent,
                        size: 16,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PaymentMethodCard extends StatelessWidget {
  const _PaymentMethodCard({
    required this.icon,
    required this.title,
    required this.price,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String price;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: enabled,
    label: '$title, $price',
    child: Material(
      color: enabled ? Colors.white : const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          constraints: const BoxConstraints(minHeight: 140),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: enabled ? const Color(0xFFDCE3EA) : _outline,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 36, color: enabled ? _accent : _muted),
              const SizedBox(height: 8),
              Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: TextStyle(
                  color: enabled ? _ink : _muted,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                price,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _muted,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _CoinInsertionAnimation extends StatefulWidget {
  const _CoinInsertionAnimation();

  @override
  State<_CoinInsertionAnimation> createState() =>
      _CoinInsertionAnimationState();
}

class _CoinInsertionAnimationState extends State<_CoinInsertionAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1250),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 150,
    height: 190,
    child: AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final progress = Curves.easeInCubic.transform(_controller.value);
        final coinOpacity =
            (1 - (_controller.value - 0.76).clamp(0, 0.24) / 0.24).clamp(
              0.0,
              1.0,
            );
        return Stack(
          alignment: Alignment.topCenter,
          children: [
            Positioned(
              top: 4,
              child: Container(
                width: 102,
                height: 102,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFF3F4F6), Color(0xFFB8BDC3)],
                  ),
                  border: Border.all(color: const Color(0xFF9AA1A9), width: 2),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x26000000),
                      blurRadius: 8,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: Center(
                  child: Container(
                    width: 13,
                    height: 47,
                    decoration: BoxDecoration(
                      color: const Color(0xFF363B40),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF777D83)),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 105,
              child: Opacity(
                opacity: 0.25 + 0.75 * (1 - progress),
                child: const Icon(
                  Icons.arrow_upward_rounded,
                  color: Color(0xFF2580E8),
                  size: 28,
                ),
              ),
            ),
            Positioned(
              top: 127 - progress * 60,
              child: Opacity(
                opacity: coinOpacity,
                child: Container(
                  width: 29,
                  height: 29,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFFFC533),
                    border: Border.all(
                      color: const Color(0xFFE59B0A),
                      width: 2,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x33000000),
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Text(
                    '₱',
                    style: TextStyle(
                      color: Color(0xFF9B6000),
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}

class _PrinterEjectionAnimation extends StatefulWidget {
  const _PrinterEjectionAnimation({
    required this.photo,
    required this.sentToPrinter,
  });

  final File photo;
  final bool sentToPrinter;

  @override
  State<_PrinterEjectionAnimation> createState() =>
      _PrinterEjectionAnimationState();
}

class _PrinterEjectionAnimationState extends State<_PrinterEjectionAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final scale = (screenSize.height / 800).clamp(0.72, 1.0).toDouble();
    final printerWidth = min(650.0, screenSize.width * 0.9);
    final printerHeight = printerWidth * 225 / 615;
    final paperWidth = printerWidth * 0.25;
    final printerSlotWidth = paperWidth * 1.14;
    final paperHeight = paperWidth * 1.55;
    final stageHeight = printerHeight + paperHeight + 70 * scale;
    final slotTop = printerHeight * 0.52;
    return Container(
      color: const Color(0xFFF7F8FA),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.max,
        children: [
          const Icon(Icons.auto_awesome_rounded, color: _accent, size: 38),
          const SizedBox(height: 12),
          Text(
            widget.sentToPrinter ? 'Print sent!' : 'Printing your photo',
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _ink,
              fontFamily: 'DancingScript',
              fontSize: 34 * scale,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            widget.sentToPrinter
                ? 'Your photo is coming out now'
                : 'Please wait while your photo prints',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _muted,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 24 * scale),
          SizedBox(
            width: printerWidth,
            height: stageHeight,
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  width: printerWidth,
                  height: printerHeight,
                  child: Image.asset(
                    'assets/printer_slot.png',
                    fit: BoxFit.fill,
                  ),
                ),
                Positioned(
                  left: printerWidth * 0.12,
                  top: slotTop - printerHeight * 0.075,
                  width: printerWidth * 0.76,
                  height: printerHeight * 0.15,
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFFF9FAFB), Color(0xFFD9DDE1)],
                      ),
                      borderRadius: BorderRadius.circular(printerHeight * 0.07),
                      border: Border.all(color: const Color(0xFFB8BEC4)),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x33000000),
                          blurRadius: 4,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Container(
                      width: printerSlotWidth,
                      height: printerHeight * 0.055,
                      decoration: BoxDecoration(
                        color: const Color(0xFF111315),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFF555B60)),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x77000000),
                            blurRadius: 3,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) => Positioned(
                    left: (printerWidth - paperWidth) / 2,
                    top: slotTop - 8 * scale + _controller.value * 130 * scale,
                    width: paperWidth,
                    height: paperHeight,
                    child: child!,
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x33000000),
                          blurRadius: 8,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: Image.file(
                        widget.photo,
                        fit: BoxFit.contain,
                        alignment: Alignment.topCenter,
                        errorBuilder: (context, error, stackTrace) =>
                            const ColoredBox(
                              color: Color(0xFFE2E8F0),
                              child: Icon(Icons.photo_outlined),
                            ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 12 * scale),
          SizedBox(
            width: 34,
            height: 34,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: _accent,
              backgroundColor: const Color(0xFFE0E4E8),
            ),
          ),
          Text(
            widget.sentToPrinter
                ? 'Print request accepted'
                : 'Sending to printer',
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _muted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _FilmTapeBackgroundPainter extends CustomPainter {
  _FilmTapeBackgroundPainter({required this.animation})
    : super(repaint: animation);

  final Animation<double> animation;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final tapeWidth = size.shortestSide < 600 ? 34.0 : 48.0;
    final tapeLength = sqrt(
      size.width * size.width + size.height * size.height,
    );
    final layouts = <(double, double, double)>[
      (size.width * 0.28, size.height * 0.24, -0.42),
      (size.width * 0.72, size.height * 0.67, 0.34),
      (size.width * 0.88, size.height * 0.34, -0.68),
    ];
    final bodyPaint = Paint()..color = const Color(0x2A17212B);
    final railPaint = Paint()
      ..color = const Color(0x5517212B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final framePaint = Paint()..color = const Color(0x3817212B);
    final perforationPaint = Paint()..color = const Color(0x7017212B);
    final frameStep = tapeWidth * 2.2;

    for (var index = 0; index < layouts.length; index++) {
      final (centerX, centerY, angle) = layouts[index];
      final phase = (animation.value + index / layouts.length) % 1;
      final travel = phase * frameStep;
      canvas.save();
      canvas.translate(centerX, centerY);
      canvas.rotate(angle);
      final left = -tapeLength * 0.7;
      final strip = Rect.fromLTWH(
        left,
        -tapeWidth / 2,
        tapeLength * 1.4,
        tapeWidth,
      );
      canvas.drawRect(strip, bodyPaint);
      canvas.drawRect(strip, railPaint);

      final holeWidth = tapeWidth * 0.23;
      final holeHeight = tapeWidth * 0.12;
      final holeInset = tapeWidth * 0.09;
      final step = frameStep / 5;
      for (
        var x = left + tapeWidth * 0.14 - travel;
        x < strip.right - tapeWidth * 0.14;
        x += step
      ) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, -tapeWidth / 2 + holeInset, holeWidth, holeHeight),
            const Radius.circular(2),
          ),
          perforationPaint,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              x,
              tapeWidth / 2 - holeInset - holeHeight,
              holeWidth,
              holeHeight,
            ),
            const Radius.circular(2),
          ),
          perforationPaint,
        );
      }

      final frameTop = -tapeWidth * 0.22;
      final frameHeight = tapeWidth * 0.44;
      final frameWidth = tapeWidth * 1.4;
      for (
        var x = left + tapeWidth * 0.4 - travel;
        x < strip.right - tapeWidth * 0.38;
        x += frameStep
      ) {
        final frameRect = Rect.fromLTWH(x, frameTop, frameWidth, frameHeight);
        canvas.drawRRect(
          RRect.fromRectAndRadius(frameRect, const Radius.circular(2)),
          framePaint,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(frameRect, const Radius.circular(2)),
          Paint()
            ..color = const Color(0x2817212B)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
      }
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _FilmTapeBackgroundPainter oldDelegate) =>
      animation != oldDelegate.animation;
}

class _CameraPhotoCardsPainter extends CustomPainter {
  const _CameraPhotoCardsPainter({required this.language});

  final AppLanguage language;

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.shortestSide;
    final cardShadow = Paint()
      ..color = const Color(0x300B1220)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, unit * 0.018);

    void drawPhotoCard({
      required Rect rect,
      required double rotation,
      required bool foreground,
    }) {
      canvas.save();
      canvas.translate(rect.center.dx, rect.center.dy);
      canvas.rotate(rotation);
      final card = Rect.fromCenter(
        center: Offset.zero,
        width: rect.width,
        height: rect.height,
      );
      final radius = Radius.circular(unit * 0.025);
      final cardShape = RRect.fromRectAndRadius(card, radius);
      canvas.drawRRect(cardShape.shift(Offset(0, unit * 0.018)), cardShadow);
      canvas.drawRRect(cardShape, Paint()..color = Colors.white);
      canvas.drawRRect(
        RRect.fromRectAndRadius(card.deflate(unit * 0.018), radius),
        Paint()..color = const Color(0xFFF1F4F7),
      );
      canvas.drawRRect(
        cardShape,
        Paint()
          ..color = const Color(0xFF47667D)
          ..style = PaintingStyle.stroke
          ..strokeWidth = unit * (foreground ? 0.008 : 0.005),
      );
      canvas.restore();
    }

    drawPhotoCard(
      rect: Rect.fromLTWH(
        size.width * 0.07,
        size.height * 0.59,
        size.width * 0.31,
        size.height * 0.36,
      ),
      rotation: -0.10,
      foreground: false,
    );
    drawPhotoCard(
      rect: Rect.fromLTWH(
        size.width * 0.62,
        size.height * 0.59,
        size.width * 0.31,
        size.height * 0.36,
      ),
      rotation: 0.10,
      foreground: false,
    );
    drawPhotoCard(
      rect: Rect.fromLTWH(
        size.width * 0.345,
        size.height * 0.54,
        size.width * 0.31,
        size.height * 0.40,
      ),
      rotation: 0,
      foreground: true,
    );

    final cameraBody = Rect.fromLTWH(
      size.width * 0.23,
      size.height * 0.10,
      size.width * 0.54,
      size.height * 0.39,
    );
    final cameraRadius = Radius.circular(unit * 0.075);
    final bodyShape = RRect.fromRectAndRadius(cameraBody, cameraRadius);
    canvas.drawRRect(bodyShape.shift(Offset(0, unit * 0.018)), cardShadow);
    canvas.drawRRect(
      bodyShape,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF66849A), Color(0xFF344F64)],
        ).createShader(cameraBody),
    );
    canvas.drawRRect(
      bodyShape,
      Paint()
        ..color = const Color(0xFF263F52)
        ..style = PaintingStyle.stroke
        ..strokeWidth = unit * 0.009,
    );

    final viewfinder = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.36,
        size.height * 0.035,
        size.width * 0.18,
        size.height * 0.12,
      ),
      Radius.circular(unit * 0.025),
    );
    canvas.drawRRect(viewfinder, Paint()..color = const Color(0xFF344F64));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        viewfinder.outerRect.deflate(unit * 0.012),
        viewfinder.brRadius,
      ),
      Paint()..color = const Color(0xFF7894A8),
    );

    final lensCenter = Offset(size.width * 0.50, size.height * 0.30);
    canvas.drawCircle(
      lensCenter,
      unit * 0.13,
      Paint()..color = const Color(0xFF263F52),
    );
    canvas.drawCircle(
      lensCenter,
      unit * 0.105,
      Paint()
        ..shader =
            const RadialGradient(
              colors: [Color(0xFF9AB4C5), Color(0xFF47667D), Color(0xFF172B3B)],
              stops: [0, 0.42, 1],
            ).createShader(
              Rect.fromCircle(center: lensCenter, radius: unit * 0.105),
            ),
    );
    canvas.drawCircle(
      lensCenter,
      unit * 0.046,
      Paint()..color = const Color(0xFF1A2A36),
    );
    canvas.drawCircle(
      lensCenter.translate(-unit * 0.033, -unit * 0.033),
      unit * 0.018,
      Paint()..color = const Color(0xBFFFFFFF),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * 0.66,
          size.height * 0.18,
          size.width * 0.055,
          size.height * 0.035,
        ),
        Radius.circular(unit * 0.012),
      ),
      Paint()..color = const Color(0xFFFFD166),
    );

    final prompt = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.10,
        size.height * 0.71,
        size.width * 0.80,
        size.height * 0.135,
      ),
      Radius.circular(unit * 0.045),
    );
    canvas.drawRRect(prompt.shift(Offset(0, unit * 0.012)), cardShadow);
    canvas.drawRRect(prompt, Paint()..color = const Color(0xFF47667D));
    final textPainter = TextPainter(
      text: TextSpan(
        text: translateAppText('TAP TO START', language),
        style: TextStyle(
          color: Colors.white,
          fontSize: min(unit * 0.095, size.width * 0.082),
          fontWeight: FontWeight.w900,
          letterSpacing: unit * 0.004,
          shadows: const [
            Shadow(
              color: Color(0x55000000),
              blurRadius: 3,
              offset: Offset(0, 1),
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: prompt.width - unit * 0.04);
    textPainter.paint(
      canvas,
      Offset(
        prompt.center.dx - textPainter.width / 2,
        prompt.center.dy - textPainter.height / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant _CameraPhotoCardsPainter oldDelegate) =>
      language != oldDelegate.language;
}

class _RecentCustomerPhotoGallery extends StatelessWidget {
  const _RecentCustomerPhotoGallery({
    required this.photos,
    required this.animatingOut,
  });

  final List<File> photos;
  final bool animatingOut;

  static const _positions = <(double, double, double, double, double)>[
    (0.018, 0.025, 0.17, 0.22, -0.16),
    (0.235, 0.015, 0.16, 0.21, 0.12),
    (0.605, 0.02, 0.16, 0.21, -0.11),
    (0.812, 0.025, 0.17, 0.22, 0.15),
    (0.005, 0.29, 0.12, 0.17, 0.12),
    (0.875, 0.30, 0.12, 0.17, -0.15),
    (0.005, 0.49, 0.12, 0.17, -0.10),
    (0.875, 0.50, 0.12, 0.17, 0.13),
    (0.015, 0.765, 0.14, 0.19, 0.14),
    (0.845, 0.775, 0.14, 0.19, -0.12),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          for (
            var index = 0;
            index < min(photos.length, _positions.length);
            index++
          )
            _buildPhoto(constraints.biggest, index),
        ],
      ),
    );
  }

  Widget _buildPhoto(Size size, int index) {
    final (left, top, width, height, angle) = _positions[index];
    final photoWidth = size.width * width;
    final photoHeight = size.height * height;
    return Positioned(
      left: size.width * left,
      top: size.height * top,
      width: photoWidth,
      height: photoHeight,
      child: AnimatedOpacity(
        opacity: animatingOut ? 0 : 0.3,
        duration: const Duration(milliseconds: 350),
        child: Transform.rotate(
          angle: angle,
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: const BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Color(0x55000000),
                  blurRadius: 8,
                  offset: Offset(2, 3),
                ),
              ],
            ),
            child: ClipRect(
              child: Image.file(
                photos[index],
                fit: BoxFit.cover,
                errorBuilder: (context, error, stack) => const ColoredBox(
                  color: Color(0xFFD9D7D7),
                  child: Icon(Icons.photo_camera_back_rounded, color: _muted),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BoothScreenState extends State<BoothScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final _settings = _SettingsStore();
  final _salesLedger = SalesLedger();
  final _payments = _Esp32PaymentClient();
  final _ganapPayments = GanapPaymentClient();
  final _payMongoPayments = PayMongoPaymentClient();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _welcomeController = TextEditingController();
  final _activationCodeController = TextEditingController();
  final _softCopyService = const SoftCopyService();
  final _fleetMonitoringService = const FleetMonitoringService();
  final _kioskPermissionService = KioskPermissionService();
  late final KioskMode _kioskMode;
  final _appStartedAt = DateTime.now();

  Timer? _logoTapResetTimer;
  Timer? _idleTimer;
  Timer? _activationExpiryTimer;
  Timer? _liveWallpaperTimer;
  Timer? _homeTransitionTimer;
  late final AnimationController _startPromptController;
  late final AnimationController _filmTapeController;
  OverlayEntry? _paymentNoticeEntry;
  DateTime? _lastLogoTap;
  DateTime? _lastRecoveryTap;
  int _logoTapCount = 0;
  int _recoveryTapCount = 0;
  CameraController? _camera;
  File? _previewPhoto;
  List<File> _sessionCapturePreviews = const [];
  List<File> _recentCustomerPhotos = const [];
  List<String> _customerFrameGallery = const [];
  List<String> _customerDecorationGallery = const [];
  Uri? _softCopyUrl;
  Uri? _gifDownloadUrl;
  Uri? _videoDownloadUrl;
  String? _softCopyError;
  String? _gifUploadError;
  String? _videoUploadError;
  String? _sessionGifError;
  String? _sessionVideoError;
  bool _softCopyUploading = false;
  StateSetter? _softCopyQrDialogSetState;
  Timer? _pollTimer;
  Timer? _deviceHealthTimer;
  Timer? _fleetMonitoringTimer;
  Timer? _appUpdateCheckTimer;
  StreamSubscription<BleStatus>? _bleStatusSubscription;
  DateTime? _lastAutomaticAppUpdateCheck;
  Future<(AppUpdateManifest, int)>? _appUpdateCheck;
  AppUpdateManifest? _availableAppUpdate;
  bool _appUpdateInstalling = false;
  int _printCopies = 1;
  int _receiptWidthDots = 576;
  double _receiptBrightness = 0.35;
  EscPosCutMode _receiptCutMode = EscPosCutMode.full;
  int _countdownDuration = 3;
  int _chargeStartPercent = 20;
  int _chargeStopPercent = 90;
  int _previewDuration = 5;
  int _idleTimeoutSeconds = 30;
  Set<int> _enabledPhotoCounts = {1, 2, 3, 4, 5};
  int? _selectedPhotoCount;
  PhotoFrameTemplate? _selectedSessionFrameTemplate;
  int? _countdownSeconds;
  PhotoBorderStyle _photoBorderStyle = PhotoBorderStyle.none;
  BoothEventTheme _eventTheme = BoothEventTheme.classic;
  PhotoEffect _liveEffect = PhotoEffect.original;
  bool _voiceGuidanceEnabled = false;
  String? _customPhotoBorderPath;
  int? _credits;
  bool _cameraReady = false;
  bool _permissionsGranted = false;
  bool _boothUnavailable = false;
  String? _lastBoothError;
  String? _voiceGuidanceError;
  String _printerHealthStatus = 'Not configured';
  Map<String, Object?> _deviceHealth = const {};
  bool _settingsLoaded = false;
  bool _adminPasswordConfigured = false;
  bool _adminDialogOpen = false;
  String? _recoveredCustomerFramePath;
  bool _resumeAdminForRecoveredFrame = false;
  bool _resumeAdminAfterFrameRecoveryScheduled = false;
  bool _polling = false;
  bool _startingPhotoSession = false;
  bool _photoInProgress = false;
  bool _waitingForManualCapture = false;
  Completer<void>? _manualCaptureRequest;
  bool _preparingPhoto = false;
  bool _isPrinting = false;
  bool _printCompleted = false;
  bool _printSubmitted = false;
  bool _previewPrintAttempted = false;
  Completer<void>? _previewDismissed;
  bool _kioskActive = false;
  bool _cameraInitializing = false;
  bool _cameraInitializationRequested = false;
  Future<void> _cameraDisposal = Future<void>.value();
  int _cameraRecoveryAttempts = 0;
  bool _paidPhotoPending = false;
  bool _coinPaymentReady = false;
  bool _walletDialogOpen = false;
  bool _boothPaused = false;
  bool _dashboardStarting = false;
  bool _walletPaymentEnabled = false;
  bool _payMongoPaymentsEnabled = false;
  bool _aiStylesEnabled = false;
  bool _aiCoinPaymentEnabled = false;
  bool _aiQrPaymentEnabled = false;
  bool _aiConversionPaid = false;
  bool _aiOutputPhoto = false;
  bool _aiConversionBusy = false;
  AiPhotoStyle? _pendingAiStyle;
  _AiPhotoComposer? _aiPhotoComposer;
  final Map<String, File> _aiGeneratedPhotoCache = {};
  AiPhotoStyle? _aiGeneratedPhotoCacheStyle;
  Map<int, int> _aiStylePricesPesos = const {1: 20, 2: 20, 3: 20, 4: 20, 5: 20};
  int _coinPricePesos = _defaultCoinPricePesos;
  int _payMongoAmountPesos = _sessionPricePesos;
  bool _activationAllowsGanap = false;
  bool _activationAllowsPayMongo = false;
  bool _esp32Detected = false;
  bool _testModeEnabled = false;
  bool _rentModeEnabled = false;
  bool _activationReady = false;
  DateTime? _activationExpiresAt;

  bool get _hasActivePayment =>
      _walletDialogOpen ||
      _paidPhotoPending ||
      _coinPaymentReady ||
      (_credits ?? 0) > 0;
  bool _activationActive = false;
  bool _activationBusy = false;
  bool _activationChecking = false;
  bool _fleetReporting = false;
  bool _fleetReportPending = false;
  String _fleetReportStatus = 'No report sent yet.';
  bool _fleetLocationSharingEnabled = false;
  bool _appInForeground = true;
  Position? _fleetLocation;
  DateTime? _fleetLocationCapturedAt;
  DateTime? _fleetLocationAttemptedAt;
  Map<String, Object?>? _fleetCommandResult;
  String? _activationDeviceId;
  String? _activationMessage;
  CameraLensDirection _cameraDirection = CameraLensDirection.back;
  bool _showIdleScreen = true;
  bool _showLiveWallpaperScreen = false;
  bool _showPaymentMethodPage = false;
  bool _showCoinPaymentPage = false;
  bool _liveWallpaperEnabled = false;
  bool _homeTransitioning = false;
  String? _recentPhotosError;
  String? _printerAddress;
  _PrinterType _printerType = _PrinterType.receipt;
  String? _walletQrPath;
  final String _softCopyEndpoint = defaultSoftCopyUploadEndpoint;
  String? _dashboardError;
  late final Future<void> _salesLoading;
  Map<String, Object?> _salesSummary = const {
    'totalSales': 0,
    'totalTransactions': 0,
    'salesToday': 0,
    'transactionsToday': 0,
    'salesThisWeek': 0,
    'week': <Map<String, Object?>>[],
  };
  bool _salesLoaded = false;
  String? _salesError;
  LocalDashboardServer? _dashboard;
  List<String> _dashboardUrls = const [];
  final List<String> _dashboardEvents = [];
  String? _idleScreenImagePath;
  String? _brandLogoPath;
  String? _idleScreenVideoPath;
  bool _idleVideoLoop = true;
  String _welcomeMessage = 'TAKE HOME A MEMORY';
  _BrandLogoAnimation _brandLogoAnimation = _BrandLogoAnimation.none;
  List<_PairedPrinter> _pairedPrinters = const [];
  String _message = 'Enable Bluetooth and power on the ESP32.';

  bool get _isTestMode =>
      !_rentModeEnabled &&
      (_boothTestMode || _testModeEnabled) &&
      !_esp32Detected;

  Widget _buildBrandLogo({required double width, required double height}) {
    final path = _brandLogoPath;
    if (path == null) {
      return Image.asset(
        'assets/photobooth_logo.png',
        width: width,
        height: height,
        fit: BoxFit.contain,
      );
    }
    return Image.file(
      File(path),
      width: width,
      height: height,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stack) => Image.asset(
        'assets/photobooth_logo.png',
        width: width,
        height: height,
        fit: BoxFit.contain,
      ),
    );
  }

  Widget _buildAnimatedBrandLogo({
    required _BrandLogoAnimation animation,
    required double width,
    required double height,
    Widget? logo,
  }) {
    return AnimatedBuilder(
      animation: _filmTapeController,
      child: logo ?? _buildBrandLogo(width: width, height: height),
      builder: (context, child) {
        final phase = _filmTapeController.value * 2 * pi;
        final wave = sin(phase);
        switch (animation) {
          case _BrandLogoAnimation.none:
            return child!;
          case _BrandLogoAnimation.jump:
            final jump = wave > 0 ? wave : 0.0;
            return Transform.translate(
              offset: Offset(0, -22 * jump),
              child: child,
            );
          case _BrandLogoAnimation.pump:
            final scale = 1 + (0.08 * (0.5 + 0.5 * wave));
            return Transform.scale(scale: scale, child: child);
          case _BrandLogoAnimation.sway:
            return Transform.rotate(angle: wave * 0.07, child: child);
          case _BrandLogoAnimation.float:
            return Transform.translate(
              offset: Offset(0, wave * 10),
              child: child,
            );
        }
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _kioskMode = KioskMode();
    _startPromptController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
      lowerBound: 0.94,
      upperBound: 1.06,
    )..repeat(reverse: true);
    _filmTapeController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat();
    WidgetsBinding.instance.addObserver(this);
    _salesLoading = _loadSalesSummary();
    unawaited(_refreshDeviceHealth());
    _deviceHealthTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(_refreshDeviceHealth()),
    );
    _fleetMonitoringTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => unawaited(_reportFleetHeartbeat()),
    );
    _bleStatusSubscription = _payments.statusStream.listen(
      _handleBluetoothStatus,
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('Could not observe Bluetooth status: $error\n$stackTrace');
        _setEsp32ConnectionStatus(false);
      },
    );
    unawaited(_checkForAppUpdateAutomatically());
    _appUpdateCheckTimer = Timer.periodic(
      const Duration(hours: 6),
      (_) => unawaited(_checkForAppUpdateAutomatically()),
    );
    unawaited(_loadSettings());
    unawaited(_initializeActivation());
    unawaited(_refreshKioskStatus());
    unawaited(_refreshPermissionState());
    unawaited(_recoverPendingCustomerFramePicker());
  }

  Future<void> _recoverPendingCustomerFramePicker() async {
    try {
      final startedAt = await _settings.loadPendingCustomerFramePicker();
      if (startedAt == null) return;

      final age = DateTime.now().difference(
        DateTime.fromMillisecondsSinceEpoch(startedAt),
      );
      if (age.isNegative || age > const Duration(minutes: 10)) {
        await _settings.clearPendingCustomerFramePicker();
        return;
      }

      final picker = FilePickerPlatform.instance;
      if (picker is! FilePickerAndroid) {
        throw StateError('Android file-picker recovery is unavailable.');
      }
      final lost = await picker.retrieveLostData();
      if (lost == null) {
        await _settings.clearPendingCustomerFramePicker();
        return;
      }
      if (lost.exception case final error?) throw error;
      if (lost.files.length != 1) {
        throw StateError('Android did not return the selected PNG frame.');
      }

      final path = await _saveCustomPhotoBorder(
        lost.files.single,
        detectPhotoSlots: true,
      );
      if (path == null) {
        throw StateError('Android did not return the selected PNG frame.');
      }
      await _settings.clearPendingCustomerFramePicker();
      if (!mounted) return;
      setState(() {
        _recoveredCustomerFramePath = path;
        _resumeAdminForRecoveredFrame = true;
      });
      _maybeResumeAdminAfterFrameRecovery();
    } on Object catch (error, stackTrace) {
      try {
        await _settings.clearPendingCustomerFramePicker();
      } on Object catch (clearError, clearStackTrace) {
        debugPrint(
          'Could not clear pending customer frame recovery: '
          '$clearError\n$clearStackTrace',
        );
      }
      debugPrint(
        'Could not recover the selected customer frame: '
        '$error\n$stackTrace',
      );
      if (mounted) {
        setState(() {
          _message = 'Could not recover the selected PNG frame: $error';
        });
      }
    }
  }

  void _maybeResumeAdminAfterFrameRecovery() {
    if (!_resumeAdminForRecoveredFrame ||
        !_settingsLoaded ||
        !_adminPasswordConfigured ||
        _adminDialogOpen ||
        _resumeAdminAfterFrameRecoveryScheduled) {
      return;
    }

    _resumeAdminAfterFrameRecoveryScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resumeAdminAfterFrameRecoveryScheduled = false;
      if (!mounted ||
          !_resumeAdminForRecoveredFrame ||
          !_settingsLoaded ||
          !_adminPasswordConfigured ||
          _adminDialogOpen) {
        return;
      }
      final framePath = _recoveredCustomerFramePath;
      if (framePath == null) return;
      _resumeAdminForRecoveredFrame = false;
      _recoveredCustomerFramePath = null;
      unawaited(
        _openAdmin(
          resumeAuthenticatedPicker: true,
          recoveredCustomerFramePath: framePath,
        ),
      );
    });
  }

  Future<void> _loadSettings() async {
    try {
      final passwordConfigured = await _settings.hasAdminPassword();
      final appLanguage = await _settings.loadAppLanguage();
      await _settings.removeLegacyCustomerFaceMaskGallery();
      final customerFrameGallery = await _settings.loadCustomerFrameGallery();
      final customerDecorationGallery = await _settings
          .loadCustomerDecorationGallery();
      final recentCustomerPhotos = await _settings.loadRecentCustomerPhotos();
      final borderStyle = await _settings.loadPhotoBorderStyle();
      final eventTheme = await _settings.loadEventTheme();
      final liveEffect = await _settings.loadLiveEffect();
      final voiceGuidanceEnabled = await _settings.loadVoiceGuidanceEnabled();
      final customBorderPath = await _settings.loadCustomPhotoBorderPath();
      final printerType = await _settings.loadPrinterType();
      final printerAddress = await _settings.loadPrinterAddress();
      final receiptWidthDots = await _settings.loadReceiptWidthDots();
      final receiptBrightness = await _settings.loadReceiptBrightness();
      final receiptCutMode = await _settings.loadReceiptCutMode();
      final printCopies = await _settings.loadPrintCopies();
      final countdownDuration = await _settings.loadCountdownDuration();
      final chargeStartPercent = await _settings.loadChargeStartPercent();
      final chargeStopPercent = await _settings.loadChargeStopPercent();
      final previewDuration = await _settings.loadPreviewDuration();
      final idleTimeoutSeconds = await _settings.loadIdleTimeout();
      final enabledPhotoCounts = await _settings.loadFleetPhotoCounts();
      final fleetLocationSharingEnabled = await _settings
          .loadFleetLocationSharing();
      final fleetCommandResult = await _settings.loadFleetCommandResult();
      final welcomeMessage = await _settings.loadWelcomeMessage();
      final brandLogoPath = await _settings.loadBrandLogo();
      final brandLogoAnimation = await _settings.loadBrandLogoAnimation();
      final liveWallpaperEnabled = await _settings.loadLiveWallpaperEnabled();
      final idleScreenImagePath = await _settings.loadIdleScreenImage();
      final idleScreenVideoPath = await _settings.loadIdleScreenVideo();
      final idleVideoLoop = await _settings.loadIdleVideoLoop();
      final testModeEnabled = await _settings.loadTestModeEnabled();
      final rentModeEnabled = await _settings.loadRentModeEnabled();
      final cameraDirection = await _settings.loadCameraDirection();
      final walletPaymentEnabled = await _settings.loadWalletPaymentEnabled();
      final payMongoPaymentsEnabled = await _settings
          .loadPayMongoPaymentsEnabled();
      final payMongoAmountPesos = await _settings.loadPayMongoAmountPesos();
      final coinPricePesos = await _settings.loadCoinPricePesos();
      final aiStylesEnabled = await _settings.loadAiStylesEnabled();
      final aiCoinPaymentEnabled = await _settings.loadAiCoinPaymentEnabled();
      final aiQrPaymentEnabled = await _settings.loadAiQrPaymentEnabled();
      final aiStylePricesPesos = await _settings.loadAiStylePricesPesos();
      final walletQrPath = await _settings.loadWalletQrPath();
      await _settings.removeLegacySoftCopySettings();
      final hasIdleScreenImage =
          idleScreenImagePath != null &&
          await File(idleScreenImagePath).exists();
      final hasBrandLogo =
          brandLogoPath != null && await File(brandLogoPath).exists();
      final hasIdleScreenVideo =
          idleScreenVideoPath != null &&
          await File(idleScreenVideoPath).exists();
      final hasCustomBorder =
          customBorderPath != null && await File(customBorderPath).exists();
      final availableCustomerFrames = <String>[];
      for (final path in customerFrameGallery) {
        if (await File(path).exists()) availableCustomerFrames.add(path);
      }
      final availableCustomerDecorations = <String>[];
      for (final path in customerDecorationGallery) {
        if (availableCustomerDecorations.length ==
            _maxCustomerDecorationCount) {
          break;
        }
        if (await File(path).exists()) {
          availableCustomerDecorations.add(path);
        }
      }
      final availableRecentPhotos = <String>[];
      for (final path in recentCustomerPhotos) {
        if (availableRecentPhotos.length == 10) break;
        if (await File(path).exists()) availableRecentPhotos.add(path);
      }
      final hasWalletQr =
          walletQrPath != null && await File(walletQrPath).exists();
      if (!mounted) return;
      setState(() {
        _customerFrameGallery = availableCustomerFrames;
        _customerDecorationGallery = availableCustomerDecorations;
        _recentCustomerPhotos = availableRecentPhotos
            .map(File.new)
            .toList(growable: false);
        _adminPasswordConfigured = passwordConfigured;
        _photoBorderStyle =
            borderStyle == PhotoBorderStyle.custom && !hasCustomBorder
            ? PhotoBorderStyle.none
            : borderStyle;
        _eventTheme = eventTheme;
        _liveEffect = liveEffect;
        _voiceGuidanceEnabled = voiceGuidanceEnabled;
        _customPhotoBorderPath = customBorderPath;
        _printerType = _PrinterType.values.firstWhere(
          (type) => type.name == printerType,
          orElse: () => _PrinterType.receipt,
        );
        _printerAddress = printerAddress;
        _printerHealthStatus = printerAddress == null
            ? 'Not configured'
            : 'Not tested this run';
        _printCopies = printCopies.clamp(1, 3);
        _receiptWidthDots = const [384, 576].contains(receiptWidthDots)
            ? receiptWidthDots
            : 576;
        _receiptBrightness = receiptBrightness.clamp(0.2, 0.5).toDouble();
        _receiptCutMode = receiptCutMode;
        _countdownDuration = countdownDuration.clamp(1, 5);
        _chargeStartPercent = chargeStartPercent.clamp(0, 99);
        _chargeStopPercent = chargeStopPercent.clamp(1, 100);
        if (_chargeStartPercent >= _chargeStopPercent) {
          _chargeStartPercent = 20;
          _chargeStopPercent = 90;
        }
        _previewDuration = const [3, 5, 8, 10, 15].contains(previewDuration)
            ? previewDuration
            : 5;
        _idleTimeoutSeconds =
            const [30, 60, 120, 300].contains(idleTimeoutSeconds)
            ? idleTimeoutSeconds
            : 30;
        _enabledPhotoCounts = enabledPhotoCounts.toSet();
        _fleetLocationSharingEnabled = fleetLocationSharingEnabled;
        _fleetCommandResult = fleetCommandResult;
        _welcomeMessage = welcomeMessage;
        _brandLogoPath = hasBrandLogo ? brandLogoPath : null;
        _brandLogoAnimation = brandLogoAnimation;
        _liveWallpaperEnabled = liveWallpaperEnabled;
        _idleScreenImagePath = hasIdleScreenImage ? idleScreenImagePath : null;
        _idleScreenVideoPath = hasIdleScreenVideo ? idleScreenVideoPath : null;
        _idleVideoLoop = idleVideoLoop;
        _testModeEnabled = testModeEnabled;
        _rentModeEnabled = rentModeEnabled;
        _cameraDirection = cameraDirection == 'front'
            ? CameraLensDirection.front
            : CameraLensDirection.back;
        _walletPaymentEnabled = walletPaymentEnabled;
        _payMongoPaymentsEnabled = payMongoPaymentsEnabled;
        _coinPricePesos = coinPricePesos;
        _payMongoAmountPesos = payMongoAmountPesos;
        _aiStylesEnabled = aiStylesEnabled;
        _aiCoinPaymentEnabled = aiCoinPaymentEnabled;
        _aiQrPaymentEnabled = aiQrPaymentEnabled;
        _aiStylePricesPesos = aiStylePricesPesos;
        _walletQrPath = hasWalletQr ? walletQrPath : null;
        _settingsLoaded = true;
      });
      appLanguageNotifier.value = appLanguage;
      unawaited(_syncBatteryStatus());
      unawaited(_initializeLocalDashboard());
      if (_activationActive) unawaited(_initializeCamera());
      _resetLiveWallpaperTimer();
      _maybeResumeAdminAfterFrameRecovery();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _settingsLoaded = true;
        _message = 'Could not load settings: $error';
      });
      if (_activationActive) unawaited(_initializeCamera());
    }
  }

  Future<void> _loadSalesSummary() async {
    try {
      final summary = await _salesLedger.load();
      if (!mounted) return;
      setState(() {
        _salesSummary = summary;
        _salesLoaded = true;
        _salesError = null;
      });
    } on Object catch (error, stackTrace) {
      debugPrint('Could not load sales history: $error\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _salesLoaded = true;
        _salesError = 'Sales history could not be loaded: $error';
      });
      _recordDashboardEvent('Sales history could not be loaded.');
    }
  }

  Future<void> _resetSalesSummary() async {
    await _salesLoading;
    try {
      final summary = await _salesLedger.reset();
      if (!mounted) return;
      setState(() {
        _salesSummary = summary;
        _salesError = null;
      });
      _recordDashboardEvent(
        'Saved sales history was reset by the administrator.',
      );
      unawaited(_reportFleetHeartbeat());
    } on Object catch (error, stackTrace) {
      debugPrint('Could not reset sales history: $error\n$stackTrace');
      if (mounted) {
        setState(() {
          _salesError = 'Sales history could not be reset: $error';
        });
      }
      _recordDashboardEvent('Sales history could not be reset.');
      rethrow;
    }
  }

  Future<void> _reportFleetHeartbeat() async {
    if (!mounted || !_activationReady || !_activationActive) {
      return;
    }
    if (_fleetReporting) {
      _fleetReportPending = true;
      return;
    }
    final deviceId = _activationDeviceId;
    if (deviceId == null || deviceId.isEmpty) return;

    _fleetReporting = true;
    try {
      await _salesLoading;
      final activationCode = await _settings.loadActivationCode();
      if (activationCode == null || activationCode.isEmpty) {
        throw StateError('Activated device credentials are unavailable.');
      }
      final sales = await _salesLedger.load();
      final location = await _fleetLocationStatus();
      final commandResult = _fleetCommandResult;
      final response = await _fleetMonitoringService.report(
        endpoint: defaultFleetMonitoringEndpoint,
        deviceId: deviceId,
        activationCode: activationCode,
        status: {
          'cameraReady': _cameraReady,
          'esp32Connected': _esp32Detected,
          'paused': _boothPaused,
          'kioskActive': _kioskActive,
          'batteryPercent': _deviceHealth['batteryPercent'],
          'charging': _deviceHealth['charging'] == true,
          'storageFreeBytes': _deviceHealth['storageFreeBytes'],
          'printerHealth': _printerAddress == null
              ? 'Not configured'
              : _printerHealthStatus,
          'pairedPrinters': [
            for (final printer in _pairedPrinters)
              {'name': printer.name, 'address': printer.address},
          ],
          'appForeground': _appInForeground,
          'appSettings': {
            'eventTheme': _eventTheme.name,
            'welcomeMessage': _welcomeMessage,
            'idleTimeoutSeconds': _idleTimeoutSeconds,
            'photoCounts': _enabledPhotoCounts.toList()..sort(),
            'printerAddress': _printerAddress ?? '',
            'cameraDirection': _cameraDirection.name,
            'countdownDuration': _countdownDuration,
            'previewDuration': _previewDuration,
            'photoBorderStyle': _photoBorderStyle.name,
            'liveEffect': _liveEffect.name,
            'voiceGuidanceEnabled': _voiceGuidanceEnabled,
            'brandLogoAnimation': _brandLogoAnimation.name,
            'printerType': _printerType.name,
            'receiptWidthDots': _receiptWidthDots,
            'receiptBrightness': _receiptBrightness,
            'receiptCutMode': _receiptCutMode.name,
            'printCopies': _printCopies,
            'walletPaymentEnabled': _walletPaymentEnabled,
            'walletPaymentsAvailable':
                _activationAllowsGanap &&
                _ganapQrPhAvailable &&
                _walletQrPath != null,
            'payMongoPaymentsEnabled': _payMongoPaymentsEnabled,
            'payMongoPaymentsAvailable': _activationAllowsPayMongo,
            'coinPricePesos': _coinPricePesos,
            'payMongoAmountPesos': _payMongoAmountPesos,
            'aiStylesEnabled': _aiStylesEnabled,
            'aiCoinPaymentEnabled': _aiCoinPaymentEnabled,
            'aiQrPaymentEnabled':
                _aiQrPaymentEnabled && _activationAllowsPayMongo,
            'aiStylePricePesos': _selectedAiStylePricePesos,
            'liveWallpaperEnabled': _liveWallpaperEnabled,
            'idleVideoLoop': _idleVideoLoop,
            'fleetLocationSharingEnabled': _fleetLocationSharingEnabled,
            'chargeStartPercent': _chargeStartPercent,
            'chargeStopPercent': _chargeStopPercent,
          },
          ...location,
        },
        sales: {
          for (final key in const [
            'totalSales',
            'totalTransactions',
            'totalCoinSales',
            'totalCoinTransactions',
            'totalQrPhSales',
            'totalQrPhTransactions',
            'salesToday',
            'transactionsToday',
            'coinSalesToday',
            'coinTransactionsToday',
            'qrPhSalesToday',
            'qrPhTransactionsToday',
            'salesThisWeek',
            'coinSalesThisWeek',
            'qrPhSalesThisWeek',
          ])
            key: sales[key] ?? 0,
        },
        commandResult: commandResult,
      );
      if (mounted) {
        setState(() {
          _fleetReportStatus =
              'Connected to Fleet. Last report: ${TimeOfDay.now().format(context)}';
        });
      }
      if (commandResult != null) {
        _fleetCommandResult = null;
        await _settings.saveFleetCommandResult(null);
      }
      await _applyRemoteFleetSettings(response['settings']);
      await _processRemoteFleetCommand(response['command']);
    } on Object catch (error, stackTrace) {
      debugPrint('Could not report fleet status: $error\n$stackTrace');
      if (mounted) {
        setState(() => _fleetReportStatus = 'Fleet report failed: $error');
      }
    } finally {
      _fleetReporting = false;
      if (_fleetReportPending) {
        _fleetReportPending = false;
        unawaited(_reportFleetHeartbeat());
      }
    }
  }

  Future<Map<String, Object?>> _fleetLocationStatus() async {
    if (!_fleetLocationSharingEnabled || !_appInForeground) {
      return const {
        'latitude': null,
        'longitude': null,
        'locationAccuracyMeters': null,
        'locationTimestamp': null,
      };
    }
    final now = DateTime.now();
    final lastFix = _fleetLocationCapturedAt;
    final lastAttempt = _fleetLocationAttemptedAt;
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      final permission = await Geolocator.checkPermission();
      if (!serviceEnabled ||
          (permission != LocationPermission.always &&
              permission != LocationPermission.whileInUse)) {
        _fleetLocation = null;
        _fleetLocationCapturedAt = null;
      } else if ((lastFix == null ||
              now.difference(lastFix) >= const Duration(minutes: 1)) &&
          (lastAttempt == null ||
              now.difference(lastAttempt) >= const Duration(seconds: 45))) {
        _fleetLocationAttemptedAt = now;
        try {
          final position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.medium,
              timeLimit: Duration(seconds: 8),
            ),
          );
          _fleetLocation = position;
          _fleetLocationCapturedAt = position.timestamp;
        } on Object catch (error, stackTrace) {
          debugPrint('Could not obtain booth location: $error\n$stackTrace');
        }
      }
    } on Object catch (error, stackTrace) {
      debugPrint(
        'Could not check booth location permission: $error\n$stackTrace',
      );
    }
    final position = _fleetLocation;
    final capturedAt = _fleetLocationCapturedAt;
    if (position == null || capturedAt == null) {
      return const {
        'latitude': null,
        'longitude': null,
        'locationAccuracyMeters': null,
        'locationTimestamp': null,
      };
    }
    return {
      'latitude': position.latitude,
      'longitude': position.longitude,
      'locationAccuracyMeters': position.accuracy,
      'locationTimestamp': capturedAt.toUtc().millisecondsSinceEpoch ~/ 1000,
    };
  }

  Future<void> _applyRemoteFleetSettings(Object? value) async {
    if (value is! Map<String, dynamic> || value.isEmpty) return;
    try {
      T readEnum<T extends Enum>(
        List<T> values,
        Object? requested,
        T fallback,
      ) {
        if (requested == null) return fallback;
        if (requested is! String) {
          throw const FormatException('Invalid remote enum setting.');
        }
        return values.firstWhere(
          (candidate) => candidate.name == requested,
          orElse: () =>
              throw const FormatException('Invalid remote enum setting.'),
        );
      }

      final themeName = value['eventTheme'] ?? _eventTheme.name;
      final theme = BoothEventTheme.values.firstWhere(
        (candidate) => candidate.name == themeName,
        orElse: () => throw const FormatException('Invalid remote theme.'),
      );
      final welcome = value['welcomeMessage'] ?? _welcomeMessage;
      if (welcome is! String ||
          welcome.trim().isEmpty ||
          welcome.trim().length > 36) {
        throw const FormatException('Invalid remote welcome message.');
      }
      final idleTimeout = value['idleTimeoutSeconds'] ?? _idleTimeoutSeconds;
      if (idleTimeout is! int ||
          !const [30, 60, 120, 300].contains(idleTimeout)) {
        throw const FormatException('Invalid remote idle timeout.');
      }
      final rawPhotoCounts =
          value['photoCounts'] ?? (_enabledPhotoCounts.toList()..sort());
      if (rawPhotoCounts is! List ||
          rawPhotoCounts.isEmpty ||
          rawPhotoCounts.any(
            (count) => count is! int || count < 1 || count > 5,
          )) {
        throw const FormatException('Invalid remote photo-count options.');
      }
      final photoCounts = rawPhotoCounts.cast<int>().toSet().toList()..sort();
      if (photoCounts.length != rawPhotoCounts.length) {
        throw const FormatException('Duplicate remote photo-count options.');
      }
      final printerAddress = value['printerAddress'] ?? _printerAddress ?? '';
      if (printerAddress is! String) {
        throw const FormatException('Invalid remote printer setting.');
      }
      var pairedPrinters = _pairedPrinters
          .where((printer) => printer.address == printerAddress)
          .toList(growable: false);
      if (printerAddress.isNotEmpty && pairedPrinters.isEmpty) {
        final refreshedPrinters = await _loadPairedPrinters();
        _pairedPrinters = refreshedPrinters;
        pairedPrinters = refreshedPrinters
            .where((printer) => printer.address == printerAddress)
            .toList(growable: false);
      }
      final selectedPrinter = printerAddress.isEmpty
          ? null
          : pairedPrinters.isNotEmpty
          ? pairedPrinters.first.address
          : _printerAddress != null &&
                _pairedPrinters.any(
                  (printer) => printer.address == _printerAddress,
                )
          ? _printerAddress
          : null;
      final printerWarning = printerAddress.isNotEmpty && pairedPrinters.isEmpty
          ? " Remote printer is not paired; this booth's printer selection was kept."
          : null;
      final cameraDirection = readEnum(
        CameraLensDirection.values,
        value['cameraDirection'],
        _cameraDirection,
      );
      final countdownDuration =
          value['countdownDuration'] ?? _countdownDuration;
      final previewDuration = value['previewDuration'] ?? _previewDuration;
      final photoBorderStyle = readEnum(
        PhotoBorderStyle.values
            .where((style) => style != PhotoBorderStyle.custom)
            .toList(),
        value['photoBorderStyle'],
        _photoBorderStyle,
      );
      final liveEffect = readEnum(
        PhotoEffect.values,
        value['liveEffect'],
        _liveEffect,
      );
      final voiceGuidanceEnabled =
          value['voiceGuidanceEnabled'] ?? _voiceGuidanceEnabled;
      final logoAnimation = readEnum(
        _BrandLogoAnimation.values,
        value['brandLogoAnimation'],
        _brandLogoAnimation,
      );
      final printerType = readEnum(
        _PrinterType.values,
        value['printerType'],
        _printerType,
      );
      final receiptWidthDots = value['receiptWidthDots'] ?? _receiptWidthDots;
      final receiptBrightness =
          (value['receiptBrightness'] as num?)?.toDouble() ??
          _receiptBrightness;
      final receiptCutMode = readEnum(
        EscPosCutMode.values,
        value['receiptCutMode'],
        _receiptCutMode,
      );
      final printCopies = value['printCopies'] ?? _printCopies;
      final coinPricePesos = value['coinPricePesos'] ?? _coinPricePesos;
      final payMongoAmountPesos =
          value['payMongoAmountPesos'] ?? _payMongoAmountPesos;
      final requestedWalletPaymentEnabled =
          value['walletPaymentEnabled'] ?? _walletPaymentEnabled;
      final requestedPayMongoPaymentsEnabled =
          value['payMongoPaymentsEnabled'] ?? _payMongoPaymentsEnabled;
      if (requestedWalletPaymentEnabled is! bool ||
          requestedPayMongoPaymentsEnabled is! bool) {
        throw const FormatException('Invalid remote payment setting.');
      }
      if (requestedWalletPaymentEnabled &&
          (!_activationAllowsGanap ||
              !_ganapQrPhAvailable ||
              _walletQrPath == null)) {
        throw const FormatException(
          'Ganap payments need local activation and QR setup on the booth.',
        );
      }
      if (requestedPayMongoPaymentsEnabled && !_activationAllowsPayMongo) {
        throw const FormatException(
          'PayMongo payments are not enabled for this booth activation.',
        );
      }
      final walletPaymentEnabled = requestedWalletPaymentEnabled;
      final payMongoPaymentsEnabled = requestedPayMongoPaymentsEnabled;
      final liveWallpaperEnabled =
          value['liveWallpaperEnabled'] ?? _liveWallpaperEnabled;
      final idleVideoLoop = value['idleVideoLoop'] ?? _idleVideoLoop;
      final fleetLocationSharingEnabled =
          value['fleetLocationSharingEnabled'] ?? _fleetLocationSharingEnabled;
      final chargeStart = value['chargeStartPercent'] ?? _chargeStartPercent;
      final chargeStop = value['chargeStopPercent'] ?? _chargeStopPercent;
      if (countdownDuration is! int ||
          countdownDuration < 1 ||
          countdownDuration > 5 ||
          previewDuration is! int ||
          !const [3, 5, 8, 10, 15].contains(previewDuration) ||
          receiptWidthDots is! int ||
          !const [384, 576].contains(receiptWidthDots) ||
          receiptBrightness < 0.2 ||
          receiptBrightness > 0.5 ||
          printCopies is! int ||
          printCopies < 1 ||
          printCopies > 3 ||
          coinPricePesos is! int ||
          coinPricePesos < 1 ||
          coinPricePesos > 100000 ||
          payMongoAmountPesos is! int ||
          payMongoAmountPesos < 1 ||
          payMongoAmountPesos > 100000 ||
          voiceGuidanceEnabled is! bool ||
          liveWallpaperEnabled is! bool ||
          idleVideoLoop is! bool ||
          fleetLocationSharingEnabled is! bool ||
          chargeStart is! int ||
          chargeStart < 0 ||
          chargeStart > 99 ||
          chargeStop is! int ||
          chargeStop < 1 ||
          chargeStop > 100 ||
          chargeStart >= chargeStop) {
        throw const FormatException('Invalid remote booth setting value.');
      }
      if (_eventTheme == theme &&
          _welcomeMessage == welcome.trim() &&
          _idleTimeoutSeconds == idleTimeout &&
          _enabledPhotoCounts.length == photoCounts.length &&
          _enabledPhotoCounts.containsAll(photoCounts) &&
          _printerAddress == selectedPrinter &&
          _cameraDirection == cameraDirection &&
          _countdownDuration == countdownDuration &&
          _previewDuration == previewDuration &&
          _photoBorderStyle == photoBorderStyle &&
          _liveEffect == liveEffect &&
          _voiceGuidanceEnabled == voiceGuidanceEnabled &&
          _brandLogoAnimation == logoAnimation &&
          _printerType == printerType &&
          _receiptWidthDots == receiptWidthDots &&
          _receiptBrightness == receiptBrightness &&
          _receiptCutMode == receiptCutMode &&
          _printCopies == printCopies &&
          _walletPaymentEnabled == walletPaymentEnabled &&
          _payMongoPaymentsEnabled == payMongoPaymentsEnabled &&
          _coinPricePesos == coinPricePesos &&
          _payMongoAmountPesos == payMongoAmountPesos &&
          _liveWallpaperEnabled == liveWallpaperEnabled &&
          _idleVideoLoop == idleVideoLoop &&
          _fleetLocationSharingEnabled == fleetLocationSharingEnabled &&
          _chargeStartPercent == chargeStart &&
          _chargeStopPercent == chargeStop) {
        return;
      }
      await _settings.saveRemoteFleetSettings(
        eventTheme: theme,
        welcomeMessage: welcome.trim(),
        idleTimeoutSeconds: idleTimeout,
        photoCounts: photoCounts,
        printerAddress: selectedPrinter,
      );
      await _settings.savePrinterType(printerType.name);
      await _settings.saveReceiptWidthDots(receiptWidthDots);
      await _settings.saveReceiptBrightness(receiptBrightness);
      await _settings.saveReceiptCutMode(receiptCutMode);
      await _settings.saveBrandLogoAnimation(logoAnimation);
      await _settings.savePhotoBorder(photoBorderStyle, _customPhotoBorderPath);
      await _settings.saveBoothOptions(
        autoPrint: false,
        printerAddress: selectedPrinter,
        printCopies: printCopies,
        countdownDuration: countdownDuration,
        previewDuration: previewDuration,
        welcomeMessage: welcome.trim(),
        idleScreenImage: _idleScreenImagePath,
        idleScreenVideo: _idleScreenVideoPath,
        idleVideoLoop: idleVideoLoop,
        testModeEnabled: _testModeEnabled,
        cameraDirection: cameraDirection.name,
        walletPaymentEnabled: walletPaymentEnabled,
        walletQrPath: _walletQrPath,
        eventTheme: theme,
        voiceGuidanceEnabled: voiceGuidanceEnabled,
        liveEffect: liveEffect,
      );
      await _settings.saveWalletPaymentEnabled(walletPaymentEnabled);
      await _settings.savePayMongoPaymentsEnabled(payMongoPaymentsEnabled);
      await _settings.saveCoinPricePesos(coinPricePesos);
      await _settings.savePayMongoAmountPesos(payMongoAmountPesos);
      await _settings.saveFleetLocationSharing(fleetLocationSharingEnabled);
      await _settings.saveChargeThresholds(
        startPercent: chargeStart,
        stopPercent: chargeStop,
      );
      if (!mounted) return;
      final cameraChanged = _cameraDirection != cameraDirection;
      setState(() {
        _eventTheme = theme;
        _welcomeMessage = welcome.trim();
        _idleTimeoutSeconds = idleTimeout;
        _enabledPhotoCounts = photoCounts.toSet();
        _printerAddress = selectedPrinter;
        _cameraDirection = cameraDirection;
        _countdownDuration = countdownDuration;
        _previewDuration = previewDuration;
        _photoBorderStyle = photoBorderStyle;
        _liveEffect = liveEffect;
        _voiceGuidanceEnabled = voiceGuidanceEnabled;
        _brandLogoAnimation = logoAnimation;
        _printerType = printerType;
        _receiptWidthDots = receiptWidthDots;
        _receiptBrightness = receiptBrightness;
        _receiptCutMode = receiptCutMode;
        _printCopies = printCopies;
        _walletPaymentEnabled = walletPaymentEnabled;
        _payMongoPaymentsEnabled = payMongoPaymentsEnabled;
        _coinPricePesos = coinPricePesos;
        _payMongoAmountPesos = payMongoAmountPesos;
        _liveWallpaperEnabled = liveWallpaperEnabled;
        _idleVideoLoop = idleVideoLoop;
        _fleetLocationSharingEnabled = fleetLocationSharingEnabled;
        _chargeStartPercent = chargeStart;
        _chargeStopPercent = chargeStop;
        _message = printerWarning == null
            ? 'Remote SnapLab Fleet settings applied.'
            : 'Remote SnapLab Fleet settings applied.$printerWarning';
      });
      _recordDashboardEvent(
        printerWarning == null
            ? 'Remote SnapLab Fleet settings applied.'
            : 'Remote SnapLab Fleet settings applied.$printerWarning',
      );
      _resetIdleTimer();
      if (!liveWallpaperEnabled) _showLiveWallpaperScreen = false;
      if (cameraChanged) await _applyCameraSelection(cameraDirection);
      if (!voiceGuidanceEnabled) {
        _voiceGuidanceError = null;
        unawaited(_stopVoiceGuidance());
      }
    } on Object catch (error, stackTrace) {
      debugPrint('Could not apply remote fleet settings: $error\n$stackTrace');
      if (mounted) {
        _recordDashboardEvent('Remote fleet settings failed to apply.');
        setState(
          () => _message = 'Remote fleet settings failed to apply: $error',
        );
      }
    }
  }

  Future<void> _processRemoteFleetCommand(Object? value) async {
    if (value is! Map<String, dynamic>) return;
    final commandId = value['commandId'];
    final name = value['name'];
    if (commandId is! int || name is! String) return;
    final lastCommandId = await _settings.loadFleetLastCommandId();
    if (commandId <= lastCommandId) return;
    await _settings.saveFleetLastCommandId(commandId);
    try {
      switch (name) {
        case 'restart_app':
          _fleetCommandResult = {
            'commandId': commandId,
            'status': 'complete',
            'message': 'app_restart_requested',
          };
          await _settings.saveFleetCommandResult(_fleetCommandResult);
          await _kioskMode.restartApp();
          return;
        case 'reboot_device':
          _fleetCommandResult = {
            'commandId': commandId,
            'status': 'complete',
            'message': 'device_reboot_requested',
          };
          await _settings.saveFleetCommandResult(_fleetCommandResult);
          await _kioskMode.rebootDevice();
          return;
        case 'pause_booth':
        case 'resume_booth':
          if (name == 'pause_booth' &&
              (_photoInProgress || _hasActivePayment)) {
            throw StateError(
              'Finish or cancel the current photo/payment before pausing.',
            );
          }
          await _setDashboardPaused(name == 'pause_booth');
          _fleetCommandResult = {
            'commandId': commandId,
            'status': 'complete',
            'message': name == 'pause_booth' ? 'booth_paused' : 'booth_resumed',
          };
          await _settings.saveFleetCommandResult(_fleetCommandResult);
          return;
        case 'enable_kiosk':
          final permissions = await _kioskPermissionService.refresh();
          final checks = await _runKioskPreflight();
          if (!permissions.criticalPermissionsGranted ||
              checks['Camera working'] != true ||
              checks['Storage writable'] != true) {
            throw StateError(
              'Kiosk mode needs camera and storage setup completed locally.',
            );
          }
          if (!await _kioskMode.enter()) {
            throw StateError('Android did not enable kiosk mode.');
          }
          if (mounted) setState(() => _kioskActive = true);
          _fleetCommandResult = {
            'commandId': commandId,
            'status': 'complete',
            'message': 'kiosk_enabled',
          };
          await _settings.saveFleetCommandResult(_fleetCommandResult);
          return;
        case 'disable_kiosk':
          await _kioskMode.exit();
          if (mounted) setState(() => _kioskActive = false);
          _fleetCommandResult = {
            'commandId': commandId,
            'status': 'complete',
            'message': 'kiosk_disabled',
          };
          await _settings.saveFleetCommandResult(_fleetCommandResult);
          return;
        case 'check_app_update':
          final (manifest, installedVersionCode) = await _checkForAppUpdate();
          if (!manifest.isNewerThan(installedVersionCode)) {
            _fleetCommandResult = {
              'commandId': commandId,
              'status': 'complete',
              'message': 'no_update_available_build_$installedVersionCode',
            };
            await _settings.saveFleetCommandResult(_fleetCommandResult);
            return;
          }
          await _openUpdateDownload(manifest);
          _fleetCommandResult = {
            'commandId': commandId,
            'status': 'complete',
            'message': 'update_installer_opened',
          };
          await _settings.saveFleetCommandResult(_fleetCommandResult);
          return;
        case 'test_print':
          await _printFleetTestPage();
          _fleetCommandResult = {
            'commandId': commandId,
            'status': 'complete',
            'message': 'printer_test_sent',
          };
          await _settings.saveFleetCommandResult(_fleetCommandResult);
          return;
        default:
          throw const FormatException('Unsupported fleet command.');
      }
    } on Object catch (error, stackTrace) {
      debugPrint(
        'Could not execute fleet command $commandId: $error\n$stackTrace',
      );
      final failureMessage = switch (error) {
        PlatformException() => error.message ?? error.code,
        StateError() => error.message.toString(),
        FormatException() => error.message,
        _ => error.toString(),
      };
      _fleetCommandResult = {
        'commandId': commandId,
        'status': 'failed',
        'message': failureMessage.length > 150
            ? failureMessage.substring(0, 150)
            : failureMessage,
      };
      await _settings.saveFleetCommandResult(_fleetCommandResult);
    }
  }

  Future<void> _printFleetTestPage() async {
    final address = _printerAddress;
    if (_printerType != _PrinterType.receipt) {
      throw StateError(
        'Remote test printing currently supports Bluetooth receipt printers only.',
      );
    }
    if (address == null || address.isEmpty) {
      throw StateError('No paired receipt printer is configured.');
    }
    final widthBytes = _receiptWidthDots ~/ 8;
    const imageHeight = 32;
    final raster = Uint8List(widthBytes * imageHeight);
    for (var y = 0; y < imageHeight; y++) {
      for (var x = 0; x < widthBytes * 8; x++) {
        if (x == 0 ||
            x == widthBytes * 8 - 1 ||
            y == 0 ||
            y == imageHeight - 1 ||
            x == y * 4) {
          raster[y * widthBytes + x ~/ 8] |= 0x80 >> (x & 7);
        }
      }
    }
    await _kioskChannel.invokeMethod<void>('printEscPos', <String, Object>{
      'address': address,
      'data': Uint8List.fromList([
        0x1B,
        0x40,
        0x1B,
        0x61,
        0x01,
        0x1D,
        0x76,
        0x30,
        0x00,
        widthBytes,
        0,
        imageHeight,
        0,
        ...raster,
        0x1B,
        0x64,
        12,
        0x1D,
        0x56,
        _receiptCutMode.commandValue,
      ]),
      'copies': 1,
    });
  }

  void _handleBluetoothStatus(BleStatus status) {
    if (status != BleStatus.ready) {
      _setEsp32ConnectionStatus(false);
    }
  }

  void _setEsp32ConnectionStatus(bool connected) {
    if (_esp32Detected == connected) return;
    if (mounted) {
      setState(() {
        _esp32Detected = connected;
        if (!connected) _credits = null;
      });
    } else {
      _esp32Detected = connected;
      if (!connected) _credits = null;
    }
    if (_activationActive) unawaited(_reportFleetHeartbeat());
  }

  Future<void> _refreshKioskStatus() async {
    try {
      final active = await _kioskChannel.invokeMethod<bool>('isKioskActive');
      final isActive = active ?? false;
      await _kioskMode.synchronize(isActive);
      if (mounted) {
        final kioskModeRecovered =
            isActive &&
            _lastBoothError == 'Android Lock Task ended unexpectedly.';
        setState(() {
          if (_kioskActive && !isActive) {
            _boothUnavailable = true;
            _lastBoothError = 'Android Lock Task ended unexpectedly.';
            _message =
                'Booth temporarily unavailable. Please ask the attendant.';
          } else if (kioskModeRecovered) {
            _boothUnavailable = false;
            _lastBoothError = null;
          }
          _kioskActive = isActive;
        });
        if (kioskModeRecovered && !_cameraReady) {
          unawaited(_initializeCamera());
        }
      }
    } on PlatformException catch (error) {
      _lastBoothError = 'Kiosk mode error: ${error.message}';
      if (mounted) {
        setState(() => _message = 'Kiosk mode error: ${error.message}');
      }
    }
  }

  Future<void> _refreshPermissionState() async {
    try {
      final snapshot = await _kioskPermissionService.refresh();
      if (!mounted) return;
      final cameraGranted =
          snapshot.states[KioskPermissionId.camera] ==
              KioskPermissionState.granted ||
          snapshot.states[KioskPermissionId.camera] ==
              KioskPermissionState.limited;
      if (cameraGranted && !_cameraReady && _activationActive) {
        await _initializeCamera();
      }
      if (!mounted) return;
      final criticalPermissionsGranted = snapshot.criticalPermissionsGranted;
      setState(() {
        _permissionsGranted = criticalPermissionsGranted;
        if (!cameraGranted || !criticalPermissionsGranted) {
          _boothUnavailable = true;
          _lastBoothError =
              'A critical camera or storage permission is missing.';
          _cameraReady = false;
          _message = 'Booth temporarily unavailable. Please ask the attendant.';
        } else if (_cameraReady &&
            _lastBoothError ==
                'A critical camera or storage permission is missing.') {
          _boothUnavailable = false;
          _lastBoothError = null;
        }
      });
      if (!cameraGranted || !criticalPermissionsGranted) {
        final camera = _camera;
        _camera = null;
        if (camera != null) await _disposeCameraController(camera);
      }
    } on Object catch (error, stackTrace) {
      debugPrint('Could not check kiosk permissions: $error\n$stackTrace');
      _lastBoothError = 'Permission status check failed: $error';
      if (mounted) {
        setState(() {
          _permissionsGranted = false;
          _boothUnavailable = true;
          _message = 'Booth temporarily unavailable. Please ask the attendant.';
        });
      }
    }
  }

  Future<bool> _checkStorageWritable() async {
    try {
      final directory = await getApplicationSupportDirectory();
      final probe = File(
        '${directory.path}${Platform.pathSeparator}'
        '.kiosk_preflight_${DateTime.now().microsecondsSinceEpoch}',
      );
      await probe.writeAsBytes(const [0], flush: true);
      await probe.delete();
      return true;
    } on Object catch (error, stackTrace) {
      debugPrint('Kiosk storage pre-flight failed: $error\n$stackTrace');
      _lastBoothError = 'Storage is not writable: $error';
      return false;
    }
  }

  Future<Map<String, bool>> _runKioskPreflight() async {
    final snapshot = await _kioskPermissionService.refresh();
    final cameraGranted =
        snapshot.states[KioskPermissionId.camera] ==
            KioskPermissionState.granted ||
        snapshot.states[KioskPermissionId.camera] ==
            KioskPermissionState.limited;
    var networkReady = true;
    if (_softCopyEndpoint.isNotEmpty) {
      try {
        final uri = Uri.parse(_softCopyEndpoint);
        await InternetAddress.lookup(uri.host)
            .timeout(const Duration(seconds: 3));
      } on Object {
        networkReady = false;
      }
    }
    var batteryReady = false;
    try {
      final details = await _kioskChannel.invokeMapMethod<String, Object?>(
        'getKioskDiagnostics',
      );
      final percent = details?['batteryPercent'];
      final charging = details?['charging'] == true;
      batteryReady = charging || percent is int && percent >= 15;
    } on Object catch (error) {
      _lastBoothError = 'Battery status unavailable: $error';
    }
    final storageWritable = await _checkStorageWritable();
    var printerReady = true;
    if (_printerAddress case final address?) {
      try {
        final pairedPrinters = await _loadPairedPrinters();
        printerReady = pairedPrinters.any(
          (printer) => printer.address == address,
        );
      } on Object catch (error) {
        _lastBoothError = 'Printer pre-flight failed: $error';
        printerReady = false;
      }
    }
    final cameraReady = cameraGranted && _cameraReady;
    final checks = <String, bool>{
      'Camera working': cameraReady,
      'Storage writable': storageWritable,
      'Printer paired': printerReady,
      'Network': networkReady,
      'Battery / charging status': batteryReady,
    };
    if (mounted) {
      setState(() {
        _permissionsGranted = snapshot.criticalPermissionsGranted;
        if (cameraReady && storageWritable) {
          _boothUnavailable = false;
          _lastBoothError = null;
        }
      });
    }
    return checks;
  }

  Future<Map<String, String>> _loadKioskDiagnostics() async {
    final uptime = DateTime.now().difference(_appStartedAt);
    final uptimeText = '${uptime.inHours}h ${uptime.inMinutes % 60}m';
    var storage = 'Unavailable';
    try {
      final directory = await getApplicationSupportDirectory();
      final stat = await directory.stat();
      storage = stat.type == FileSystemEntityType.directory
          ? 'App storage accessible'
          : 'Storage unavailable';
    } on Object catch (error) {
      storage = 'Error: $error';
    }
    var battery = 'Unavailable';
    var freeSpace = '';
    try {
      final details = await _kioskChannel.invokeMapMethod<String, Object?>(
        'getKioskDiagnostics',
      );
      final percent = details?['batteryPercent'];
      final charging = details?['charging'] == true;
      battery = '${percent ?? 'Unknown'}%${charging ? ' · charging' : ''}';
      final bytes = details?['storageFreeBytes'];
      if (bytes is int) {
        freeSpace = ' · ${(bytes / 1024 / 1024).round()} MB free';
      }
    } on Object catch (error) {
      battery = 'Error: $error';
    }
    return {
      'Permissions': _permissionsGranted
          ? 'Critical access ready'
          : 'Setup required',
      'Last error': _lastBoothError ?? 'None',
      'Storage': '$storage$freeSpace',
      'Battery': battery,
      'Printer': _printerAddress == null
          ? 'Not configured'
          : 'Selected: $_printerAddress · $_printerHealthStatus',
      'Voice guidance': !_voiceGuidanceEnabled
          ? 'Off'
          : _voiceGuidanceError ?? 'Enabled',
      'Uptime': uptimeText,
      'Lockdown': _kioskActive ? 'Active' : 'Not active',
      'Platform path': 'Android Lock Task (device owner or screen pinning)',
    };
  }

  Future<void> _refreshDeviceHealth() async {
    try {
      final details = await _kioskChannel.invokeMapMethod<String, Object?>(
        'getKioskDiagnostics',
      );
      if (!mounted) return;
      setState(() => _deviceHealth = details ?? const {});
      unawaited(_syncBatteryStatus());
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() {
        _deviceHealth = const {};
        _lastBoothError = 'Device health check failed: ${error.message}';
      });
      _recordDashboardEvent('Device health check failed: ${error.message}');
    }
  }

  String? _batterySyncError;
  bool _batteryReportSucceeded = false;

  Future<void> _syncBatteryStatus() async {
    final percent = _deviceHealth['batteryPercent'];
    if (!mounted || percent is! int || percent < 0 || percent > 100) return;

    try {
      await _payments.reportBattery(
        percent,
        startPercent: _chargeStartPercent,
        stopPercent: _chargeStopPercent,
      );
      if (!mounted) return;
      if (!_batteryReportSucceeded || _batterySyncError != null) {
        final wasRecovering = _batterySyncError != null;
        setState(() {
          _batteryReportSucceeded = true;
          _batterySyncError = null;
        });
        if (wasRecovering) {
          _recordDashboardEvent('ESP32 battery reporting recovered.');
        }
      }
    } on Object catch (error) {
      if (!mounted) return;
      final message = error.toString();
      if (_batterySyncError != message || _batteryReportSucceeded) {
        setState(() {
          _batteryReportSucceeded = false;
          _batterySyncError = message;
        });
        _recordDashboardEvent('ESP32 battery reporting failed: $message');
      }
    }
  }

  Future<void> _speakGuidance(String text) async {
    if (!_voiceGuidanceEnabled) return;
    try {
      await _kioskChannel.invokeMethod<void>('speakGuidance', <String, Object>{
        'text': text,
      });
      _voiceGuidanceError = null;
    } on PlatformException catch (error) {
      _voiceGuidanceError =
          'Speech unavailable: ${error.message ?? error.code}';
      _recordDashboardEvent(_voiceGuidanceError!);
    }
  }

  Future<void> _stopVoiceGuidance() async {
    try {
      await _kioskChannel.invokeMethod<void>('stopVoiceGuidance');
    } on PlatformException catch (error) {
      debugPrint('Could not stop voice guidance: ${error.message}');
    }
  }

  void _setPrinterHealth({required bool success, Object? error}) {
    final status = success
        ? 'Last print succeeded at ${DateTime.now().toLocal().toString().substring(11, 19)}'
        : 'Last print failed: $error';
    if (!mounted) {
      _printerHealthStatus = status;
      return;
    }
    setState(() => _printerHealthStatus = status);
    unawaited(_refreshDeviceHealth());
  }

  Future<void> _showKioskSetup(BuildContext dialogContext) async {
    final diagnostics = await _loadKioskDiagnostics();
    if (!mounted || !dialogContext.mounted) return;
    await showDialog<void>(
      context: dialogContext,
      barrierDismissible: false,
      builder: (_) => KioskSetupScreen(
        permissionService: _kioskPermissionService,
        kioskLive: _kioskActive,
        diagnostics: diagnostics,
        preflight: _runKioskPreflight,
        onGoLive: () async {
          final active = await _kioskMode.enter();
          if (!active) {
            throw StateError(
              'Android could not enable Lock Task Mode. '
              'Provision as device owner or enable screen pinning.',
            );
          }
          if (mounted) setState(() => _kioskActive = true);
        },
        onExitKiosk: () async {
          await _kioskMode.exit();
          if (mounted) setState(() => _kioskActive = false);
          if (dialogContext.mounted) Navigator.of(dialogContext).pop();
        },
      ),
    );
  }

  Future<List<_PairedPrinter>> _loadPairedPrinters() async {
    final devices = await _kioskChannel.invokeMethod<List<dynamic>>(
      'getPairedBluetoothPrinters',
    );
    return (devices ?? const <dynamic>[])
        .map((device) {
          if (device is! Map) {
            throw const FormatException(
              'Android returned an invalid paired printer.',
            );
          }
          final name = device['name'];
          final address = device['address'];
          if (name is! String || address is! String) {
            throw const FormatException(
              'Android returned an invalid paired printer.',
            );
          }
          return _PairedPrinter(name: name, address: address);
        })
        .toList(growable: false);
  }

  Future<(AppUpdateManifest, int)> _checkForAppUpdate() {
    final pendingCheck = _appUpdateCheck;
    if (pendingCheck != null) return pendingCheck;

    final check = _fetchAppUpdate();
    _appUpdateCheck = check;
    return check.whenComplete(() {
      if (identical(_appUpdateCheck, check)) _appUpdateCheck = null;
    });
  }

  Future<(AppUpdateManifest, int)> _fetchAppUpdate() async {
    final uri = Uri.parse(_updateManifestUrl);
    final versionInfo = await const MethodChannel('photobooth/device')
        .invokeMapMethod<String, dynamic>('appVersion');
    final versionCode = versionInfo?['versionCode'];
    if (versionCode is! int || versionCode < 1) {
      throw StateError('Could not determine the installed app version.');
    }
    final manifest = await fetchAppUpdateManifest(uri);
    final preferences = await SharedPreferences.getInstance();
    final dismissedVersionCode = preferences.getInt(
      _dismissedUpdateVersionCodeKey,
    );
    if (mounted) {
      setState(() {
        _availableAppUpdate =
            manifest.isNewerThan(versionCode) &&
                manifest.versionCode != dismissedVersionCode
            ? manifest
            : null;
      });
    }
    return (manifest, versionCode);
  }

  Future<void> _checkForAppUpdateAutomatically({bool force = false}) async {
    const checkInterval = Duration(hours: 6);
    final now = DateTime.now();
    final lastCheck = _lastAutomaticAppUpdateCheck;
    if (!force &&
        lastCheck != null &&
        now.difference(lastCheck) < checkInterval) {
      return;
    }

    try {
      await _checkForAppUpdate();
      _lastAutomaticAppUpdateCheck = DateTime.now();
    } on Object catch (error) {
      debugPrint('Automatic app update check failed: $error');
    }
  }

  Future<void> _openUpdateDownload(AppUpdateManifest update) async {
    await const MethodChannel('photobooth/device').invokeMethod<void>(
      'downloadAndInstallApk',
      {'url': update.downloadUri.toString(), 'versionCode': update.versionCode},
    );
  }

  Future<void> _dismissAppUpdate(AppUpdateManifest update) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setInt(
        _dismissedUpdateVersionCodeKey,
        update.versionCode,
      );
    } on Object catch (error) {
      debugPrint('Could not save dismissed update notice: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'The update notice was hidden for now but may return after restart.',
            ),
          ),
        );
      }
    }
    if (!mounted) return;
    setState(() {
      if (_availableAppUpdate?.versionCode == update.versionCode) {
        _availableAppUpdate = null;
      }
    });
  }

  Future<void> _startAppUpdate(AppUpdateManifest update) async {
    if (_appUpdateInstalling) return;
    setState(() => _appUpdateInstalling = true);
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Downloading and verifying the update APK…'),
        duration: Duration(minutes: 2),
      ),
    );
    try {
      await _openUpdateDownload(update);
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Android installer opened. Confirm the installation to update Snap Lab.',
          ),
          duration: Duration(seconds: 8),
        ),
      );
    } on Object catch (error) {
      debugPrint('Could not download or install the app update: $error');
      if (mounted) {
        messenger.hideCurrentSnackBar();
        final message = error is PlatformException
            ? error.message ?? error.code
            : error.toString();
        messenger.showSnackBar(
          SnackBar(content: Text('Could not install the update: $message')),
        );
      }
    } finally {
      if (mounted) setState(() => _appUpdateInstalling = false);
    }
  }

  Future<void> _initializeLocalDashboard() async {
    if (_dashboard != null ||
        _dashboardStarting ||
        !_activationActive ||
        !_settingsLoaded ||
        !_adminPasswordConfigured ||
        !mounted) {
      return;
    }
    _dashboardStarting = true;
    final dashboard = LocalDashboardServer(
      statusProvider: _dashboardStatus,
      authenticate: _settings.verifyAdminPassword,
      updateSettings: _applyDashboardSettings,
      setPaused: _setDashboardPaused,
      resetSales: _resetSalesSummary,
      startCapture: _startDashboardCapture,
      updateMedia: _updateDashboardMedia,
    );
    try {
      await dashboard.start();
      if (!mounted) {
        await dashboard.stop();
        return;
      }
      setState(() {
        _dashboard = dashboard;
        _dashboardUrls = dashboard.urls;
        _dashboardError = null;
      });
      _recordDashboardEvent('Browser dashboard started.');
    } on Object catch (error) {
      if (mounted) {
        setState(() => _dashboardError = 'Could not start dashboard: $error');
      }
    } finally {
      _dashboardStarting = false;
    }
  }

  Future<void> _refreshLocalDashboardAddresses() async {
    final dashboard = _dashboard;
    if (dashboard == null) {
      await _initializeLocalDashboard();
      return;
    }
    try {
      await dashboard.refreshNetworkAddresses();
      if (!mounted) return;
      setState(() {
        _dashboardUrls = dashboard.urls;
        _dashboardError = null;
      });
    } on Object catch (error) {
      if (mounted) {
        setState(
          () => _dashboardError = 'Could not find Wi-Fi address: $error',
        );
      }
    }
  }

  String get _activationFeatureSummary {
    final features = [
      if (_activationAllowsPayMongo) 'PayMongo QR Ph',
      if (_activationAllowsGanap) 'Ganap QR Ph',
    ];
    return features.isEmpty ? 'No QR payment providers' : features.join(', ');
  }

  Map<String, Object?> _dashboardStatus() => {
    'cameraReady': _cameraReady,
    'esp32Connected': _esp32Detected,
    'credits': _credits,
    'photoInProgress': _photoInProgress,
    'selectedPhotoCount': _selectedPhotoCount,
    'paused': _boothPaused,
    'coinsPerPhoto': _coinPricePesos,
    'coinsPerSession': _coinPricePesos,
    'coinPricePesos': _coinPricePesos,
    'kioskActive': _kioskActive,
    'walletPaymentEnabled':
        _walletPaymentEnabled && _activationAllowsGanap && _ganapQrPhAvailable,
    'ganapQrPhAvailable': _activationAllowsGanap && _ganapQrPhAvailable,
    'activationAllowsPayMongo': _activationAllowsPayMongo,
    'payMongoPaymentsEnabled':
        _payMongoPaymentsEnabled && _activationAllowsPayMongo,
    'payMongoAmountPesos': _payMongoAmountPesos,
    'hasWalletQr': _walletQrPath != null,
    'hasIdleImage': _idleScreenImagePath != null,
    'hasIdleVideo': _idleScreenVideoPath != null,
    'liveWallpaperEnabled': _liveWallpaperEnabled,
    'hasCustomBorder': _customPhotoBorderPath != null,
    'message': _message,
    'welcomeMessage': _welcomeMessage,
    'cameraDirection': _cameraDirection.name,
    'frame': _photoBorderStyle.name,
    'eventTheme': _eventTheme.name,
    'liveEffect': _liveEffect.name,
    'voiceGuidanceEnabled': _voiceGuidanceEnabled,
    'batteryPercent': _deviceHealth['batteryPercent'],
    'charging': _deviceHealth['charging'] == true,
    'chargeStartPercent': _chargeStartPercent,
    'chargeStopPercent': _chargeStopPercent,
    'smartChargingConnected': _batteryReportSucceeded,
    'smartChargingError': _batterySyncError,
    'storageFreeBytes': _deviceHealth['storageFreeBytes'],
    'printerHealth': _printerAddress == null
        ? 'Not configured'
        : _printerHealthStatus,
    'voiceGuidanceError': _voiceGuidanceError,
    'countdownDuration': _countdownDuration,
    'previewDuration': _previewDuration,
    'autoPrint': false,
    'printerAddress': _printerAddress ?? '',
    'printCopies': _printCopies,
    'testModeEnabled': _testModeEnabled,
    'rentModeEnabled': _rentModeEnabled,
    'idleVideoLoop': _idleVideoLoop,
    'sales': {
      'loaded': _salesLoaded,
      'error': _salesError,
      'summary': _salesSummary,
    },
    'events': List<String>.unmodifiable(_dashboardEvents),
  };

  Future<void> _recordPaidSale({
    required int amount,
    required int photoCount,
    required String paymentMethod,
  }) async {
    await _salesLoading;
    if (_salesError != null) {
      _recordDashboardEvent(
        '$paymentMethod payment accepted, but its sale could not be recorded.',
      );
      return;
    }
    try {
      final summary = await _salesLedger.recordSale(
        amount: amount,
        photoCount: photoCount,
        paymentMethod: paymentMethod == 'Coin'
            ? SalePaymentMethod.coin
            : SalePaymentMethod.qrPh,
      );
      if (!mounted) return;
      setState(() {
        _salesSummary = summary;
        _salesError = null;
      });
      _recordDashboardEvent(
        '$paymentMethod sale recorded: $amount for $photoCount photo(s).',
      );
    } on Object catch (error, stackTrace) {
      debugPrint('Could not record accepted sale: $error\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _salesError = 'An accepted sale could not be recorded: $error';
      });
      _recordDashboardEvent(
        '$paymentMethod payment accepted, but its sale could not be recorded.',
      );
    }
  }

  void _recordDashboardEvent(String event) {
    final timestamp = DateTime.now().toLocal().toString().substring(0, 19);
    _dashboardEvents.insert(0, '$timestamp · $event');
    if (_dashboardEvents.length > 50) {
      _dashboardEvents.removeRange(50, _dashboardEvents.length);
    }
  }

  Future<void> _applyDashboardSettings(Map<String, Object?> input) async {
    int readInt(String key, {required int min, required int max}) {
      final value = input[key];
      if (value is! int || value < min || value > max) {
        throw FormatException('$key must be between $min and $max.');
      }
      return value;
    }

    String readString(String key, {required int maxLength}) {
      final value = input[key];
      if (value is! String || value.length > maxLength) {
        throw FormatException('$key is invalid.');
      }
      return value.trim();
    }

    bool readBool(String key) {
      final value = input[key];
      if (value is! bool) throw FormatException('$key must be true or false.');
      return value;
    }

    final countdown = readInt('countdownDuration', min: 1, max: 5);
    final preview = readInt('previewDuration', min: 3, max: 15);
    if (!const [3, 5, 8, 10, 15].contains(preview)) {
      throw const FormatException(
        'Preview must be 3, 5, 8, 10, or 15 seconds.',
      );
    }
    final copies = readInt('printCopies', min: 1, max: 3);
    final coinPricePesos = readInt(
      'coinPricePesos',
      min: 1,
      max: _maxCoinPricePesos,
    );
    final payMongoAmountPesos = readInt(
      'payMongoAmountPesos',
      min: 1,
      max: 100000,
    );
    final welcome = readString('welcomeMessage', maxLength: 36);
    if (welcome.isEmpty) {
      throw const FormatException('Welcome message cannot be empty.');
    }
    final camera = readString('cameraDirection', maxLength: 8);
    if (camera != CameraLensDirection.front.name &&
        camera != CameraLensDirection.back.name) {
      throw const FormatException('Select the front or back camera.');
    }
    final frameName = readString('frame', maxLength: 32);
    final border = PhotoBorderStyle.values.firstWhere(
      (style) => style.name == frameName,
      orElse: () => throw const FormatException('Choose a valid photo frame.'),
    );
    if (border == PhotoBorderStyle.custom &&
        (_customPhotoBorderPath == null ||
            !await File(_customPhotoBorderPath!).exists())) {
      throw const FormatException(
        'Upload a custom PNG border in the app before selecting it here.',
      );
    }
    final printer = readString('printerAddress', maxLength: 64);
    final testMode = readBool('testModeEnabled');
    final rentMode = readBool('rentModeEnabled');
    if (testMode && _esp32Detected) {
      throw const FormatException(
        'Free test mode cannot be enabled while the ESP32 is connected.',
      );
    }
    final loopVideo = readBool('idleVideoLoop');
    final walletEnabled =
        readBool('walletPaymentEnabled') &&
        _activationAllowsGanap &&
        _ganapQrPhAvailable;
    final payMongoEnabled =
        readBool('payMongoPaymentsEnabled') && _activationAllowsPayMongo;
    final cameraDirection = CameraLensDirection.values.firstWhere(
      (direction) => direction.name == camera,
    );
    final printerAddress = printer.isEmpty ? null : printer;
    await _settings.savePhotoBorder(border, _customPhotoBorderPath);
    await _settings.saveRentModeEnabled(rentMode);
    await _settings.saveCoinPricePesos(coinPricePesos);
    await _settings.savePayMongoAmountPesos(payMongoAmountPesos);
    await _settings.savePayMongoPaymentsEnabled(payMongoEnabled);
    await _settings.saveBoothOptions(
      autoPrint: false,
      printerAddress: printerAddress,
      printCopies: copies,
      countdownDuration: countdown,
      previewDuration: preview,
      welcomeMessage: welcome,
      idleScreenImage: _idleScreenImagePath,
      idleScreenVideo: _idleScreenVideoPath,
      idleVideoLoop: loopVideo,
      testModeEnabled: testMode,
      cameraDirection: camera,
      walletPaymentEnabled: walletEnabled,
      walletQrPath: _walletQrPath,
      eventTheme: _eventTheme,
      voiceGuidanceEnabled: _voiceGuidanceEnabled,
      liveEffect: _liveEffect,
    );
    final cameraChanged = cameraDirection != _cameraDirection;
    if (!mounted) return;
    setState(() {
      _photoBorderStyle = border;
      _printerAddress = printerAddress;
      _printCopies = copies;
      _countdownDuration = countdown;
      _previewDuration = preview;
      _welcomeMessage = welcome;
      _idleVideoLoop = loopVideo;
      _testModeEnabled = testMode;
      _rentModeEnabled = rentMode;
      _paidPhotoPending = false;
      _coinPaymentReady = false;
      _cameraDirection = cameraDirection;
      _walletPaymentEnabled = walletEnabled;
      _payMongoPaymentsEnabled = payMongoEnabled;
      _coinPricePesos = coinPricePesos;
      _payMongoAmountPesos = payMongoAmountPesos;
      _message = 'Settings updated from the browser dashboard.';
    });
    _recordDashboardEvent('Admin updated booth settings from the dashboard.');
    if (cameraChanged) await _applyCameraSelection(cameraDirection);
  }

  Future<void> _setDashboardPaused(bool paused) async {
    if (_boothPaused == paused) return;
    if (!mounted) return;
    setState(() {
      _boothPaused = paused;
      if (paused) {
        _selectedPhotoCount = null;
        _selectedSessionFrameTemplate = null;
        _paidPhotoPending = false;
        _coinPaymentReady = false;
        _message = 'Booth paused by admin.';
      } else {
        _message = 'Booth resumed by admin.';
      }
    });
    _recordDashboardEvent(paused ? 'Booth paused.' : 'Booth resumed.');
  }

  Future<void> _updateDashboardMedia(
    String type,
    String? filename,
    List<int>? bytes,
  ) async {
    if ((filename == null) != (bytes == null)) {
      throw const FormatException(
        'The uploaded filename and file data are required.',
      );
    }
    String? newPath;
    if (bytes != null && filename != null) {
      final extension = filename.split('.').last.toLowerCase();
      final allowedExtensions = switch (type) {
        'walletQr' ||
        'idleImage' => const {'png', 'jpg', 'jpeg', 'webp', 'bmp'},
        'photoBorder' => const {'png'},
        'idleVideo' => const {'mp4', 'm4v', 'mov', 'webm'},
        _ => const <String>{},
      };
      if (!allowedExtensions.contains(extension)) {
        throw const FormatException('The uploaded file type is not supported.');
      }
      if (type == 'photoBorder') {
        await validateCustomPhotoBorderPng(Uint8List.fromList(bytes));
      } else if (type != 'idleVideo') {
        final codec = await ui.instantiateImageCodec(Uint8List.fromList(bytes));
        try {
          final frame = await codec.getNextFrame();
          frame.image.dispose();
        } finally {
          codec.dispose();
        }
      } else {
        final supportDirectory = await getApplicationSupportDirectory();
        final candidate = File(
          '${supportDirectory.path}${Platform.pathSeparator}'
          'dashboard_upload_check_${DateTime.now().millisecondsSinceEpoch}.$extension',
        );
        await candidate.writeAsBytes(bytes, flush: true);
        final controller = VideoPlayerController.file(candidate);
        try {
          await controller.initialize();
        } finally {
          await controller.dispose();
          if (await candidate.exists()) await candidate.delete();
        }
      }

      final supportDirectory = await getApplicationSupportDirectory();
      final safeExtension = RegExp(r'^[a-z0-9]{1,8}$').hasMatch(extension)
          ? extension
          : throw const FormatException(
              'The uploaded file extension is invalid.',
            );
      final path =
          '${supportDirectory.path}${Platform.pathSeparator}'
          'dashboard_${type}_${DateTime.now().millisecondsSinceEpoch}.$safeExtension';
      await File(path).writeAsBytes(bytes, flush: true);
      newPath = path;
    }

    var imagePath = _idleScreenImagePath;
    var videoPath = _idleScreenVideoPath;
    var qrPath = _walletQrPath;
    var borderPath = _customPhotoBorderPath;
    var borderStyle = _photoBorderStyle;
    var walletEnabled = _walletPaymentEnabled;
    switch (type) {
      case 'walletQr':
        qrPath = newPath;
        if (qrPath == null) walletEnabled = false;
      case 'idleImage':
        imagePath = newPath;
      case 'idleVideo':
        videoPath = newPath;
      case 'photoBorder':
        borderPath = newPath;
        if (borderPath == null && borderStyle == PhotoBorderStyle.custom) {
          borderStyle = PhotoBorderStyle.none;
        }
      default:
        throw const FormatException('Choose a valid media type.');
    }
    await _settings.savePhotoBorder(borderStyle, borderPath);
    await _settings.saveBoothOptions(
      autoPrint: false,
      printerAddress: _printerAddress,
      printCopies: _printCopies,
      countdownDuration: _countdownDuration,
      previewDuration: _previewDuration,
      welcomeMessage: _welcomeMessage,
      idleScreenImage: imagePath,
      idleScreenVideo: videoPath,
      idleVideoLoop: _idleVideoLoop,
      testModeEnabled: _testModeEnabled,
      cameraDirection: _cameraDirection.name,
      walletPaymentEnabled: walletEnabled,
      walletQrPath: qrPath,
      eventTheme: _eventTheme,
      voiceGuidanceEnabled: _voiceGuidanceEnabled,
      liveEffect: _liveEffect,
    );
    if (!mounted) return;
    setState(() {
      _idleScreenImagePath = imagePath;
      _idleScreenVideoPath = videoPath;
      _walletQrPath = qrPath;
      _customPhotoBorderPath = borderPath;
      _photoBorderStyle = borderStyle;
      _walletPaymentEnabled = walletEnabled;
      _message = 'Media updated from the browser dashboard.';
    });
    _recordDashboardEvent(
      newPath == null
          ? 'Removed dashboard media: $type.'
          : 'Uploaded dashboard media: $type.',
    );
  }

  void _startDashboardCapture(int photoCount) {
    if (!mounted || !_cameraReady || _photoInProgress) {
      throw StateError(
        'Camera is not ready or a photo session is in progress.',
      );
    }
    setState(() {
      _selectedPhotoCount = photoCount;
      _paidPhotoPending = true;
      _message = 'Admin started a remote photo session.';
      _showIdleScreen = false;
    });
    _recordDashboardEvent('Admin started a $photoCount-photo remote session.');
    unawaited(_startPhotoSession());
  }

  Future<void> _initializeActivation() async {
    if (_activationChecking) return;
    _activationChecking = true;
    if (mounted) {
      setState(() {
        _activationReady = false;
        _activationActive = false;
        _activationAllowsGanap = false;
        _activationAllowsPayMongo = false;
        _activationMessage = null;
      });
    }
    try {
      final deviceId = await const MethodChannel('photobooth/device')
          .invokeMethod<String>('androidId');
      if (deviceId == null || deviceId.isEmpty) {
        throw StateError('Android did not provide a device activation ID.');
      }
      _activationDeviceId = deviceId;
      final savedCode = await _settings.loadActivationCode();
      final activation = savedCode == null
          ? null
          : await parseDeviceActivationCode(
              deviceId: deviceId,
              code: savedCode,
            );
      final effectiveNow = await _settings.loadEffectiveTrialNow();
      final active =
          activation != null && !activation.isExpiredAt(effectiveNow);
      if (!mounted) return;
      setState(() {
        _activationActive = active;
        _activationExpiresAt = activation?.expiresAt;
        _activationAllowsGanap =
            active && activation.allows(ActivationFeature.ganapQrPh);
        _activationAllowsPayMongo =
            active && activation.allows(ActivationFeature.payMongoQrPh);
        _activationReady = true;
        _activationMessage = activation == null
            ? null
            : active
            ? null
            : 'This trial activation has expired. Enter a new activation code.';
      });
      final expiresAt = activation?.expiresAt;
      _scheduleActivationExpiry(active ? expiresAt : null);
      if (!active) {
        _pollTimer?.cancel();
        _pollTimer = null;
        final camera = _camera;
        _camera = null;
        if (camera != null) unawaited(_disposeCameraController(camera));
      }
      if (active) unawaited(_reportFleetHeartbeat());
      unawaited(_initializeLocalDashboard());
      if (_activationActive && _settingsLoaded) {
        unawaited(_initializeCamera());
      }
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _activationReady = true;
        _activationActive = false;
        _activationExpiresAt = null;
        _activationAllowsGanap = false;
        _activationAllowsPayMongo = false;
        _activationMessage = 'Activation check failed: $error';
      });
    } finally {
      _activationChecking = false;
    }
  }

  Future<void> _submitActivationCode() async {
    final deviceId = _activationDeviceId;
    final code = _activationCodeController.text.trim();
    if (deviceId == null || deviceId.isEmpty || code.isEmpty) {
      setState(() => _activationMessage = 'Enter your activation code.');
      return;
    }
    setState(() {
      _activationBusy = true;
      _activationMessage = null;
    });
    try {
      final activation = await parseDeviceActivationCode(
        deviceId: deviceId,
        code: code,
      );
      if (activation == null) {
        throw const FormatException(
          'That code is invalid or was created for a different device.',
        );
      }
      final effectiveNow = await _settings.loadEffectiveTrialNow();
      if (activation.isExpiredAt(effectiveNow)) {
        throw const FormatException(
          'This trial code has expired. Ask the app owner for a new code.',
        );
      }
      await _settings.saveActivationCode(code.replaceAll(RegExp(r'\s'), ''));
      if (!mounted) return;
      setState(() {
        _activationActive = true;
        _activationExpiresAt = activation.expiresAt;
        _activationAllowsGanap = activation.allows(ActivationFeature.ganapQrPh);
        _activationAllowsPayMongo = activation.allows(
          ActivationFeature.payMongoQrPh,
        );
        _activationReady = true;
        _activationMessage = null;
      });
      _scheduleActivationExpiry(activation.expiresAt);
      unawaited(_reportFleetHeartbeat());
      _resetLiveWallpaperTimer();
      _activationCodeController.clear();
      if (_settingsLoaded) unawaited(_initializeCamera());
    } on Object catch (error) {
      if (mounted) setState(() => _activationMessage = '$error');
    } finally {
      if (mounted) setState(() => _activationBusy = false);
    }
  }

  void _scheduleActivationExpiry(DateTime? expiresAt) {
    _activationExpiryTimer?.cancel();
    if (expiresAt == null) return;
    final remaining = expiresAt.difference(DateTime.now().toUtc());
    if (remaining <= Duration.zero) {
      unawaited(_expireTrialActivation());
      return;
    }
    _activationExpiryTimer = Timer(remaining, _expireTrialActivation);
  }

  Future<void> _expireTrialActivation() async {
    if (!mounted || !_activationActive || _activationExpiresAt == null) return;
    setState(() {
      _activationActive = false;
      _activationAllowsGanap = false;
      _activationAllowsPayMongo = false;
      _activationMessage =
          'This trial activation has expired. Enter a new activation code.';
      _cameraReady = false;
      _cameraInitializing = false;
    });
    _pollTimer?.cancel();
    _pollTimer = null;
    final camera = _camera;
    _camera = null;
    if (camera != null) await _disposeCameraController(camera);
    await _settings.loadEffectiveTrialNow();
  }

  Future<void> _replaceActivationLicense(BuildContext context) async {
    final deviceId = _activationDeviceId;
    if (deviceId == null || deviceId.isEmpty) {
      throw StateError('The device activation ID is unavailable.');
    }
    final codeController = TextEditingController();
    final activation = await showDialog<DeviceActivation>(
      context: context,
      builder: (dialogContext) {
        var busy = false;
        var errorMessage = '';
        return StatefulBuilder(
          builder: (context, refreshDialog) => AlertDialog(
            title: const Text('Update activation features'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Paste the replacement code issued for this device. Its signed license determines which payment providers this booth can use.',
                ),
                const SizedBox(height: 8),
                SelectableText('Device ID: $deviceId'),
                const SizedBox(height: 12),
                TextField(
                  controller: codeController,
                  autocorrect: false,
                  enableSuggestions: false,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: translateAppText(
                      'New activation code',
                      appLanguageNotifier.value,
                    ),
                  ),
                ),
                if (errorMessage.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    errorMessage,
                    style: const TextStyle(color: Color(0xFFB42318)),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: busy
                    ? null
                    : () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: busy
                    ? null
                    : () async {
                        refreshDialog(() {
                          busy = true;
                          errorMessage = '';
                        });
                        try {
                          final code = codeController.text.trim();
                          final parsed = await parseDeviceActivationCode(
                            deviceId: deviceId,
                            code: code,
                          );
                          if (parsed == null) {
                            throw const FormatException(
                              'This code is invalid or was issued for a different device.',
                            );
                          }
                          if (parsed.expiresAt != null) {
                            throw const FormatException(
                              'Trial codes must be entered on the activation screen.',
                            );
                          }
                          if (dialogContext.mounted) {
                            Navigator.of(dialogContext).pop(parsed);
                          }
                        } on Object catch (error) {
                          if (dialogContext.mounted) {
                            refreshDialog(() => errorMessage = '$error');
                          }
                        } finally {
                          if (dialogContext.mounted) {
                            refreshDialog(() => busy = false);
                          }
                        }
                      },
                child: busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('APPLY CODE'),
              ),
            ],
          ),
        );
      },
    );
    try {
      if (activation != null) {
        await _settings.saveActivationCode(
          codeController.text.replaceAll(RegExp(r'\s'), ''),
        );
        if (mounted) {
          _activationExpiryTimer?.cancel();
          setState(() {
            _activationExpiresAt = null;
            _activationAllowsGanap = activation.allows(
              ActivationFeature.ganapQrPh,
            );
            _activationAllowsPayMongo = activation.allows(
              ActivationFeature.payMongoQrPh,
            );
            _message = 'Device activation features updated.';
          });
        }
      }
    } on Object catch (error) {
      if (mounted) {
        setState(
          () => _message = 'Could not update activation features: $error',
        );
      }
    } finally {
      codeController.dispose();
    }
  }

  Widget _buildActivationGate() {
    final phoneLayout = MediaQuery.sizeOf(context).shortestSide < 600;
    return Positioned.fill(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 420),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.97, end: 1).animate(animation),
            child: child,
          ),
        ),
        child: !_activationReady
            ? const ColoredBox(
                key: ValueKey('activation-checking'),
                color: _ink,
                child: SafeArea(
                  child: Center(
                    child: CircularProgressIndicator(color: _accent),
                  ),
                ),
              )
            : !_activationActive
            ? ColoredBox(
                key: const ValueKey('activation-gate'),
                color: _ink,
                child: SafeArea(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.all(phoneLayout ? 16 : 28),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 460),
                        child: Card(
                          color: _panel,
                          child: Padding(
                            padding: EdgeInsets.all(phoneLayout ? 20 : 32),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.lock_person_rounded,
                                  size: 64,
                                  color: _accent,
                                ),
                                const SizedBox(height: 16),
                                const Text(
                                  'Activate Photobooth',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: _ink,
                                    fontSize: 24,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Enter the device-specific activation code provided by the app owner. Internet access is not required.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: _muted),
                                ),
                                const SizedBox(height: 20),
                                if (_activationBusy)
                                  const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: CircularProgressIndicator(
                                      color: _accent,
                                    ),
                                  )
                                else if (!_activationActive) ...[
                                  if (_activationDeviceId case final deviceId?)
                                    SelectableText(
                                      'Device ID: $deviceId',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: _ink,
                                        fontSize: 12,
                                      ),
                                    ),
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller: _activationCodeController,
                                    autocorrect: false,
                                    enableSuggestions: false,
                                    keyboardType: TextInputType.visiblePassword,
                                    maxLines: 2,
                                    decoration: InputDecoration(
                                      labelText: translateAppText(
                                        'Activation code',
                                        appLanguageNotifier.value,
                                      ),
                                      helperText: translateAppText(
                                        'Paste the full code exactly as provided.',
                                        appLanguageNotifier.value,
                                      ),
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                  if (_activationMessage case final message?)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 12),
                                      child: Text(
                                        message,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: Color(0xFFB42318),
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  const SizedBox(height: 16),
                                  SizedBox(
                                    width: double.infinity,
                                    child: FilledButton(
                                      onPressed: _activationBusy
                                          ? null
                                          : _submitActivationCode,
                                      child: const Text('ACTIVATE DEVICE'),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              )
            : const SizedBox.expand(key: ValueKey('activation-gate-hidden')),
      ),
    );
  }

  Future<void> _initializeCamera() async {
    if (!_settingsLoaded || !_activationActive || !mounted) {
      return;
    }
    if (_cameraInitializing) {
      _cameraInitializationRequested = true;
      return;
    }
    _cameraInitializing = true;
    CameraController? pendingController;
    try {
      await _cameraDisposal;
      final currentCamera = _camera;
      if (currentCamera != null &&
          currentCamera.value.isInitialized &&
          currentCamera.description.lensDirection == _cameraDirection) {
        if (mounted && !_cameraReady) {
          setState(() {
            _cameraReady = true;
            _boothUnavailable = false;
            _lastBoothError = null;
          });
        }
        return;
      }
      final permissionSnapshot = await _kioskPermissionService.refresh();
      final cameraGranted =
          permissionSnapshot.states[KioskPermissionId.camera] ==
              KioskPermissionState.granted ||
          permissionSnapshot.states[KioskPermissionId.camera] ==
              KioskPermissionState.limited;
      if (mounted) {
        setState(() {
          _permissionsGranted = permissionSnapshot.criticalPermissionsGranted;
          _boothUnavailable =
              !cameraGranted || !permissionSnapshot.criticalPermissionsGranted;
        });
      }
      if (!cameraGranted) {
        _lastBoothError = 'Camera permission is not granted.';
        _cameraReady = false;
        return;
      }
      final requestedDirection = _cameraDirection;
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw StateError(
          'No camera is available on this device. On the emulator, map a webcam with: -camera-back webcam0 -camera-front none.',
        );
      }

      final matchingCameras = cameras
          .where((camera) => camera.lensDirection == requestedDirection)
          .toList();
      if (matchingCameras.isEmpty) {
        throw StateError(
          'The selected ${requestedDirection.name} camera is not available on this device.',
        );
      }

      final controller = CameraController(
        matchingCameras.first,
        ResolutionPreset.high,
        enableAudio: false,
        fps: 24,
        videoBitrate: 2000000,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      pendingController = controller;
      await controller.initialize();
      if (!mounted ||
          !_appInForeground ||
          requestedDirection != _cameraDirection) {
        pendingController = null;
        await _disposeCameraController(controller);
        if (mounted && _appInForeground) {
          _cameraInitializationRequested = true;
        }
        return;
      }
      final previousCamera = _camera;
      if (previousCamera != null && !identical(previousCamera, controller)) {
        _camera = null;
        await _disposeCameraController(previousCamera);
      }
      setState(() {
        _camera = controller;
        _cameraReady = true;
        _cameraRecoveryAttempts = 0;
        _boothUnavailable = false;
        _lastBoothError = null;
        _message = 'Choose 1–5 photos to begin';
      });
      pendingController = null;
      _pollTimer ??= Timer.periodic(
        const Duration(seconds: 1),
        (_) => unawaited(_pollCredits()),
      );
      unawaited(_pollCredits());
    } on CameraException catch (error) {
      final failedCamera = pendingController;
      pendingController = null;
      if (failedCamera != null) {
        await _disposeCameraController(failedCamera);
      }
      _lastBoothError =
          'Camera could not start: ${error.description ?? error.code}';
      if (mounted) {
        setState(() {
          _cameraReady = false;
          _boothUnavailable = true;
          _message = _kioskActive
              ? 'Booth temporarily unavailable. Please ask the attendant.'
              : 'Camera could not start: ${error.description ?? error.code}';
        });
      }
      _scheduleCameraRecovery();
    } on Object catch (error) {
      final failedCamera = pendingController;
      pendingController = null;
      if (failedCamera != null) {
        await _disposeCameraController(failedCamera);
      }
      _lastBoothError = 'Camera could not start: $error';
      if (mounted) {
        setState(() {
          _cameraReady = false;
          _boothUnavailable = true;
          _message = _kioskActive
              ? 'Booth temporarily unavailable. Please ask the attendant.'
              : 'Camera could not start: $error';
        });
      }
      _scheduleCameraRecovery();
    } finally {
      _cameraInitializing = false;
      if (_cameraInitializationRequested && mounted && _appInForeground) {
        _cameraInitializationRequested = false;
        unawaited(_initializeCamera());
      }
    }
  }

  void _scheduleCameraRecovery() {
    if (_cameraRecoveryAttempts > 0 || !_appInForeground) return;
    _cameraRecoveryAttempts++;
    Future<void>.delayed(const Duration(milliseconds: 600), () {
      if (mounted &&
          !_cameraReady &&
          _appInForeground &&
          _settingsLoaded &&
          _activationActive) {
        unawaited(_initializeCamera());
      }
    });
  }

  Future<void> _disposeCameraController(CameraController controller) {
    final disposal = _cameraDisposal
        .then((_) => controller.dispose())
        .catchError((Object error, StackTrace stackTrace) {
          debugPrint('Could not dispose the camera controller: $error');
        });
    _cameraDisposal = disposal;
    return disposal;
  }

  Future<void> _pollCredits() async {
    final showingPhotoResult = _previewPhoto != null;
    if (_polling ||
        _startingPhotoSession ||
        !_cameraReady ||
        !_settingsLoaded ||
        _adminDialogOpen ||
        (_photoInProgress && !showingPhotoResult) ||
        _walletDialogOpen ||
        _boothPaused ||
        _rentModeEnabled ||
        !mounted) {
      return;
    }

    _polling = true;
    try {
      final credits = await _payments.readCredits();
      if (!mounted) return;
      final wasEsp32Detected = _esp32Detected;
      final disableTestMode = _testModeEnabled;
      final coinPaymentAccepted =
          !showingPhotoResult &&
          _selectedPhotoCount != null &&
          !_paidPhotoPending &&
          !_coinPaymentReady &&
          credits >= _requiredCredits;
      final previousCredits = _credits;
      setState(() {
        _esp32Detected = true;
        _testModeEnabled = false;
        _credits = credits;
        if (!showingPhotoResult) {
          _message = _selectedPhotoCount == null
              ? 'Choose 1–5 photos to begin'
              : _paidPhotoPending
              ? 'Payment Recieved. Tap START PHOTO SESSION when you are ready.'
              : credits >= _requiredCredits
              ? 'Payment Recieved. Tap START PHOTO SESSION when you are ready.'
              : credits == 0
              ? 'Insert $_coinPricePesos credits (₱$_coinPricePesos) for this session'
              : 'Insert ${_requiredCredits - credits} more credits '
                    '($credits / $_requiredCredits)';
        }
        _coinPaymentReady =
            !showingPhotoResult &&
            _selectedPhotoCount != null &&
            !_paidPhotoPending &&
            credits >= _requiredCredits;
        if (coinPaymentAccepted) {
          _showCoinPaymentPage = false;
          _showPaymentMethodPage = false;
        }
      });
      if (credits > 0) {
        _idleTimer?.cancel();
      } else if ((previousCredits ?? 0) > 0) {
        _resetIdleTimer();
      }
      if (!wasEsp32Detected && _activationActive) {
        unawaited(_reportFleetHeartbeat());
      }
      if (coinPaymentAccepted) {
        _showPaymentAcceptedNotice();
      }
      if (disableTestMode) {
        unawaited(_settings.saveTestModeEnabled(false));
      }
      if (_photoInProgress || _adminDialogOpen) return;
      if (_selectedPhotoCount == null) return;
      if (_paidPhotoPending) return;
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _esp32Detected = false;
          _credits = null;
          if (!showingPhotoResult) {
            _message = 'ESP32 Bluetooth unavailable: $error';
          }
        });
      } else {
        _esp32Detected = false;
        _credits = null;
      }
      if (_activationActive) unawaited(_reportFleetHeartbeat());
    } finally {
      _polling = false;
    }
  }

  Future<void> _uploadCustomerDownloads({
    required File photo,
    required File? gif,
    required File? video,
  }) async {
    try {
      final activationCode = await _settings.loadActivationCode();
      final deviceId = _activationDeviceId;
      if (activationCode == null || deviceId == null) {
        throw StateError(
          'The activated device credentials are unavailable for photo upload.',
        );
      }
      final result = await _softCopyService.uploadPhotos(
        photo: photo,
        gif: gif,
        video: video,
        endpoint: _softCopyEndpoint,
        deviceId: deviceId,
        activationCode: activationCode,
        onProgress: (result, isComplete) {
          if (!mounted) return;
          setState(() {
            if (result.photoUrl != null || result.photoError != null) {
              _softCopyUrl = result.photoUrl;
              _softCopyError = result.photoError;
            }
            if (result.gifUrl != null || result.gifError != null) {
              _gifDownloadUrl = result.gifUrl;
              _gifUploadError = result.gifError;
            }
            if (result.videoUrl != null || result.videoError != null) {
              _videoDownloadUrl = result.videoUrl;
              _videoUploadError = result.videoError;
            }
            _softCopyUploading = !isComplete;
          });
          _refreshSoftCopyQrDialog();
        },
      );
      if (!mounted) return;
      setState(() {
        _softCopyUrl = result.photoUrl;
        _gifDownloadUrl = result.gifUrl;
        _videoDownloadUrl = result.videoUrl;
        _softCopyError = result.photoError;
        _gifUploadError = result.gifError;
        _videoUploadError = result.videoError;
        _softCopyUploading = false;
      });
      if (result.photoUrl != null) {
        _recordDashboardEvent('Photo soft copy uploaded for QR download.');
      }
      if (result.gifUrl != null) {
        _recordDashboardEvent('Animated GIF uploaded for QR download.');
      }
      if (result.videoUrl != null) {
        _recordDashboardEvent('Moving photo video uploaded for QR download.');
      }
      if (result.photoError != null) {
        debugPrint('Photo soft-copy upload failed: ${result.photoError}');
      }
      if (result.gifError != null) {
        debugPrint('Animated GIF upload failed: ${result.gifError}');
      }
      if (result.videoError != null) {
        debugPrint('Moving photo video upload failed: ${result.videoError}');
      }
    } on Object catch (error, stackTrace) {
      debugPrint('Photo downloads could not be authorized: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        _softCopyError = error.toString();
        _gifUploadError = gif == null ? null : error.toString();
        _videoUploadError = video == null ? null : error.toString();
        _softCopyUploading = false;
      });
      _refreshSoftCopyQrDialog();
    }
  }

  Future<void> _waitForManualCapture(int captureNumber, int photoCount) async {
    final request = Completer<void>();
    _manualCaptureRequest = request;
    if (mounted) {
      setState(() {
        _waitingForManualCapture = true;
        _message =
            'Tap the shutter to take photo $captureNumber of $photoCount.';
      });
    }
    await request.future;
    if (!mounted) return;
    setState(() {
      _waitingForManualCapture = false;
      _message = 'Get ready for photo $captureNumber of $photoCount.';
    });
    if (identical(_manualCaptureRequest, request)) {
      _manualCaptureRequest = null;
    }
  }

  void _requestManualCapture() {
    final request = _manualCaptureRequest;
    if (!_waitingForManualCapture || request == null || request.isCompleted) {
      return;
    }
    request.complete();
  }

  Future<void> _startPhotoSession({bool testMode = false}) async {
    if (!mounted ||
        _photoInProgress ||
        _startingPhotoSession ||
        _boothUnavailable) {
      return;
    }
    if (testMode && !_isTestMode) {
      setState(() {
        _message =
            'Test mode is disabled because the ESP32 coin slot is connected.';
      });
      return;
    }
    final photoCount = _selectedPhotoCount;
    if (photoCount == null) return;
    if (!testMode && !_paidPhotoPending && !_rentModeEnabled) {
      if (!_coinPaymentReady) return;
      setState(() => _startingPhotoSession = true);
      try {
        final amount = _requiredCredits;
        final payment = await _payments.consumeCredits(amount);
        if (!mounted) return;
        if (!payment.consumed) {
          setState(() {
            _credits = payment.credits;
            _coinPaymentReady = false;
            _startingPhotoSession = false;
            _message = 'Credits changed. Please insert coins again.';
          });
          _resetIdleTimer();
          return;
        }
        setState(() {
          _credits = payment.credits;
          _coinPaymentReady = false;
          _paidPhotoPending = true;
        });
        _recordDashboardEvent(
          'Coin payment accepted for $photoCount photo(s).',
        );
        await _recordPaidSale(
          amount: amount,
          photoCount: photoCount,
          paymentMethod: 'Coin',
        );
      } on Object catch (error) {
        if (mounted) {
          setState(() {
            _coinPaymentReady = false;
            _startingPhotoSession = false;
            _message = 'Could not confirm coin payment: $error';
          });
          _resetIdleTimer();
        }
        return;
      }
      if (!mounted) return;
      setState(() => _startingPhotoSession = false);
    }
    setState(() {
      _photoInProgress = true;
      _previewPhoto = null;
      _previewPrintAttempted = false;
      _printCompleted = false;
      _aiConversionPaid = false;
      _aiOutputPhoto = false;
      _aiConversionBusy = false;
      _aiGeneratedPhotoCache.clear();
      _aiGeneratedPhotoCacheStyle = null;
      _aiPhotoComposer = null;
      _sessionCapturePreviews = const [];
      _softCopyUrl = null;
      _gifDownloadUrl = null;
      _videoDownloadUrl = null;
      _softCopyError = null;
      _gifUploadError = null;
      _videoUploadError = null;
      _sessionGifError = null;
      _sessionVideoError = null;
      _softCopyUploading = false;
    });
    var sessionCompleted = false;
    final videoClips = <File>[];
    File? composedSessionVideo;
    Future<void> cleanUpVideoFiles(Iterable<File> files) async {
      for (final file in files) {
        try {
          if (await file.exists()) await file.delete();
        } on FileSystemException catch (error) {
          debugPrint('Could not delete temporary session video: $error');
        }
      }
    }

    try {
      await _ensureSelectedCameraReady();
      final photos = <File>[];
      String? videoCaptureError;
      DateTime? captureDate;
      var retakeUsed = false;
      late _PhotoCustomization customization;
      while (true) {
        photos.clear();
        await cleanUpVideoFiles(videoClips);
        videoClips.clear();
        videoCaptureError = null;
        captureDate = null;
        if (mounted) {
          setState(() {
            _sessionCapturePreviews = const [];
            _waitingForManualCapture = false;
          });
        }
        for (var index = 0; index < photoCount; index++) {
          await _waitForManualCapture(index + 1, photoCount);
          if (!mounted) return;
          await _speakGuidance('Photo ${index + 1} of $photoCount. Get ready.');
          var recordingCamera = await _ensureSelectedCameraReady();
          var videoRecordingStarted = false;
          try {
            await recordingCamera.startVideoRecording();
            videoRecordingStarted = true;
          } on Object catch (error) {
            videoCaptureError ??= 'Could not record photo ${index + 1}: $error';
            debugPrint(videoCaptureError);
          }
          for (var seconds = _countdownDuration; seconds > 0; seconds--) {
            if (!mounted) return;
            setState(() {
              _countdownSeconds = seconds;
              _message = 'Photo ${index + 1} of $photoCount';
            });
            if (seconds == 1) unawaited(_speakGuidance('Smile!'));
            await Future<void>.delayed(const Duration(seconds: 1));
          }
          if (!mounted) return;
          setState(() {
            _countdownSeconds = null;
            _message = 'Taking photo ${index + 1} of $photoCount...';
          });
          if (videoRecordingStarted) {
            try {
              final clip = await recordingCamera.stopVideoRecording();
              videoClips.add(File(clip.path));
            } on Object catch (error) {
              videoCaptureError ??=
                  'Could not finish recording photo ${index + 1}: $error';
              debugPrint(videoCaptureError);
            }
          }
          try {
            await _kioskChannel.invokeMethod<void>('playShutterSound');
          } on PlatformException catch (error) {
            debugPrint('Could not play camera shutter sound: ${error.message}');
          }
          final photo = await _takePhotoForSession();
          captureDate ??= DateTime.now();
          photos.add(File(photo.path));
          if (mounted) {
            setState(() {
              _sessionCapturePreviews = List<File>.unmodifiable(photos);
            });
          }
          if (index + 1 < photoCount) {
            await Future<void>.delayed(const Duration(milliseconds: 700));
          }
        }
        if (!mounted) return;
        final result = await showDialog<_PhotoCustomization>(
          context: context,
          barrierDismissible: false,
          builder: (_) => _PhotoCustomizationDialog(
            photos: photos,
            captureDate: captureDate ?? DateTime.now(),
            decorationPaths: _customerDecorationGallery,
            customerFramePaths: _customerFrameGallery,
            brandLogoPath: _brandLogoPath,
            captureVideoPaths: videoClips
                .map((clip) => clip.path)
                .toList(growable: false),
            countdownSeconds: _countdownDuration,
            captureVideoError: videoCaptureError,
            borderStyle: _photoBorderStyle,
            customBorderPath: _customPhotoBorderPath,
            initialEffect: _liveEffect,
            aiGeneratedPhotoCache: _aiGeneratedPhotoCache,
            initialFrameTemplate: _selectedSessionFrameTemplate,
            canRetake: !retakeUsed,
            onFinalizationChanged: (isFinalizing) {
              if (!mounted) return;
              setState(() {
                _preparingPhoto = isFinalizing;
                if (isFinalizing) {
                  _message =
                      'Please wait a moment. Your photo is almost ready.';
                }
              });
            },
          ),
        );
        if (!mounted) return;
        if (result == null) {
          throw StateError('Photo customization was closed before saving.');
        }
        if (result.retakeRequested) {
          if (retakeUsed) {
            throw StateError('Only one retake is allowed per photo session.');
          }
          retakeUsed = true;
          continue;
        }
        customization = result;
        composedSessionVideo = customization.sessionVideo;
        _aiPhotoComposer = customization.aiPhotoComposer;
        break;
      }
      final photoToSave = customization.photo;
      if (photoToSave == null) {
        throw StateError('Photo customization did not return a saved photo.');
      }
      await _kioskChannel.invokeMethod<void>('savePhoto', <String, Object>{
        'path': photoToSave.path,
      });
      final animatedGif = customization.animatedGif;
      var gifSavedLocally = false;
      if (animatedGif != null) {
        try {
          await _kioskChannel.invokeMethod<void>('savePhoto', <String, Object>{
            'path': animatedGif.path,
          });
          gifSavedLocally = true;
        } on Object catch (error) {
          _sessionGifError = 'Animated GIF could not be saved: $error';
          debugPrint(_sessionGifError);
        }
      } else {
        _sessionGifError = customization.gifError;
      }
      _sessionVideoError = customization.videoError;
      await _rememberCustomerPhoto(photoToSave);
      final previewDismissed = Completer<void>();
      _previewDismissed = previewDismissed;
      if (mounted) {
        setState(() {
          _preparingPhoto = false;
          _previewPhoto = photoToSave;
          _softCopyUploading = _softCopyEndpoint.isNotEmpty;
          _message = 'Your photo is ready.';
        });
      }
      unawaited(_speakGuidance('Your photo is ready.'));
      var uploadFuture = Future<void>.value();
      if (_softCopyEndpoint.isNotEmpty) {
        uploadFuture = _uploadCustomerDownloads(
          photo: photoToSave,
          gif: animatedGif,
          video: composedSessionVideo,
        );
      }
      _recordDashboardEvent(
        'Photo session completed: $photoCount photo(s) captured.',
      );
      await uploadFuture;
      _paidPhotoPending = false;
      if (mounted) {
        setState(() {
          _previewPhoto = photoToSave;
          _message = _videoDownloadUrl != null
              ? 'Your moving photo video is ready! Scan its QR code to download.'
              : _softCopyUrl != null && _gifDownloadUrl != null
              ? 'Your photo and animated GIF are ready! Scan the QR codes to download either one.'
              : _softCopyUrl != null
              ? 'Your photo is ready to download. The GIF download is unavailable.'
              : _gifDownloadUrl != null
              ? 'Your animated GIF is ready to download. The photo download is unavailable.'
              : _softCopyError != null ||
                    _gifUploadError != null ||
                    _videoUploadError != null ||
                    _sessionVideoError != null
              ? gifSavedLocally
                    ? 'Photo and GIF are saved on the booth. Online downloads are unavailable.'
                    : 'Photo is saved on the booth. Online download is unavailable.'
              : testMode
              ? gifSavedLocally
                    ? 'Test photo and GIF saved to Pictures/Photobooth'
                    : 'Test photo saved to Pictures/Photobooth'
              : gifSavedLocally
              ? 'Photo and GIF saved to Pictures/Photobooth'
              : 'Photo saved to Pictures/Photobooth';
        });
        await previewDismissed.future;
        if (identical(_previewDismissed, previewDismissed)) {
          _previewDismissed = null;
        }
        if (mounted) {
          setState(() {
            _previewPhoto = null;
            _previewPrintAttempted = false;
          });
        }
      }
      sessionCompleted = true;
    } on CameraException catch (error, stackTrace) {
      debugPrint('Photo session camera error: $error\n$stackTrace');
      _lastBoothError = 'Photo session camera error: $error';
      final failedCamera = _camera;
      _camera = null;
      if (failedCamera != null) {
        unawaited(_disposeCameraController(failedCamera));
      }
      if (mounted) {
        setState(() {
          _boothUnavailable = true;
          _cameraReady = false;
          _message = 'Booth temporarily unavailable. Please ask the attendant.';
        });
        _scheduleCameraRecovery();
      }
    } on PlatformException catch (error, stackTrace) {
      debugPrint('Photo session platform error: $error\n$stackTrace');
      _lastBoothError =
          'Photo save/platform error: ${error.message ?? error.code}';
      if (mounted) {
        setState(() {
          _boothUnavailable = true;
          _cameraReady = false;
          _message = 'Booth temporarily unavailable. Please ask the attendant.';
        });
      }
    } on Object catch (error, stackTrace) {
      debugPrint('Photo session failed: $error\n$stackTrace');
      if (mounted) {
        setState(() => _message = 'The photo session could not be completed.');
      }
    } finally {
      await cleanUpVideoFiles(videoClips);
      if (composedSessionVideo != null) {
        await cleanUpVideoFiles([composedSessionVideo]);
      }
      if (mounted) {
        setState(() {
          _preparingPhoto = false;
          _countdownSeconds = null;
          _waitingForManualCapture = false;
          _manualCaptureRequest = null;
          _previewPhoto = null;
          _previewPrintAttempted = false;
          _sessionCapturePreviews = const [];
          _previewDismissed = null;
          _photoInProgress = false;
          _softCopyUploading = false;
          _selectedPhotoCount = null;
          _selectedSessionFrameTemplate = null;
          _paidPhotoPending = false;
          _coinPaymentReady = false;
          _showIdleScreen = sessionCompleted;
          _showLiveWallpaperScreen = false;
          _showPaymentMethodPage = false;
          _showCoinPaymentPage = false;
        });
        _idleTimer?.cancel();
        _resetLiveWallpaperTimer();
        unawaited(_pollCredits());
      }
    }
  }

  void _startOverFromPreview() {
    final dismissed = _previewDismissed;
    if (dismissed != null && !dismissed.isCompleted) dismissed.complete();
  }

  Future<void> _printPreviewPhoto() async {
    final photo = _previewPhoto;
    final printerAddress = _printerAddress;
    if (photo == null || _isPrinting || _previewPrintAttempted) return;
    if (_printerType == _PrinterType.receipt && printerAddress == null) {
      setState(() => _message = 'Set up a Bluetooth printer in Admin first.');
      return;
    }

    final printStartedAt = DateTime.now();
    setState(() {
      _isPrinting = true;
      _printSubmitted = false;
      _previewPrintAttempted = true;
      _message = 'Sending your photo to the printer…';
    });
    try {
      if (_printerType == _PrinterType.color) {
        await _kioskChannel.invokeMethod<void>(
          'printColorPhoto',
          <String, Object>{'path': photo.path, 'copies': _printCopies},
        );
      } else {
        final printData = await encodeEscPosRaster(
          photo,
          widthDots: _receiptWidthDots,
          shadowLightening: _receiptBrightness,
          cutMode: _receiptCutMode,
        );
        await _kioskChannel.invokeMethod<void>('printEscPos', <String, Object>{
          'address': printerAddress!,
          'data': printData,
          'copies': _printCopies,
        });
      }
      if (!mounted) return;
      setState(() {
        _printSubmitted = true;
        _printCompleted = true;
        _message = _printerType == _PrinterType.color
            ? 'Choose a color printer in the Android print dialog.'
            : 'Your photo was sent to the printer.';
      });
      if (_printerType == _PrinterType.receipt) {
        _setPrinterHealth(success: true);
      }
    } on Object catch (error) {
      final detail = error is PlatformException
          ? error.message ?? error.code
          : error;
      if (!mounted) return;
      setState(() {
        _printSubmitted = false;
        _previewPrintAttempted = false;
        _message = 'Print failed: $detail';
      });
      _setPrinterHealth(success: false, error: detail);
    } finally {
      final animationTime = DateTime.now().difference(printStartedAt);
      if (_printSubmitted &&
          animationTime < const Duration(milliseconds: 2200)) {
        await Future<void>.delayed(
          const Duration(milliseconds: 2200) - animationTime,
        );
      }
      if (mounted) {
        setState(() {
          _isPrinting = false;
          _printSubmitted = false;
        });
      }
    }
  }

  bool get _aiCoinPaymentAvailable =>
      _aiCoinPaymentEnabled && _esp32Detected && _credits != null;

  bool get _aiQrPaymentAvailable =>
      _aiQrPaymentEnabled &&
      _payMongoPaymentsEnabled &&
      _activationAllowsPayMongo;

  int get _selectedAiStylePricePesos =>
      _aiStylePricesPesos[_selectedPhotoCount ?? 1] ??
      _aiStylePricesPesos[1] ??
      20;

  Future<void> _offerPaidAiStyles() async {
    if (!_aiStylesEnabled ||
        _previewPhoto == null ||
        _aiOutputPhoto ||
        _aiConversionBusy) {
      return;
    }
    if (_aiConversionPaid && _pendingAiStyle != null) {
      await _generatePaidAiStyle(_pendingAiStyle!);
      return;
    }

    final style = await showDialog<AiPhotoStyle>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Dialog.fullscreen(
        backgroundColor: Colors.white,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                    const Expanded(
                      child: Text(
                        'Choose an AI style',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _ink,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
              Text(
                'Tap a style to choose it and continue to payment. · ₱$_selectedAiStylePricePesos for ${_selectedPhotoCount ?? 1} photo(s)',
                textAlign: TextAlign.center,
                style: const TextStyle(color: _muted, fontSize: 13),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.all(14),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.82,
                  ),
                  itemCount: AiPhotoStyle.values.length,
                  itemBuilder: (context, index) {
                    final style = AiPhotoStyle.values[index];
                    return Card(
                      clipBehavior: Clip.antiAlias,
                      color: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: _outline, width: 1),
                      ),
                      child: InkWell(
                        onTap: () => Navigator.of(dialogContext).pop(style),
                        child: Column(
                          children: [
                            Expanded(
                              child: Image.asset(
                                style.previewAsset,
                                fit: BoxFit.contain,
                                width: double.infinity,
                                errorBuilder: (context, error, stack) =>
                                    const ColoredBox(
                                      color: Color(0xFFF1F3F5),
                                      child: Center(
                                        child: Icon(Icons.auto_awesome_rounded),
                                      ),
                                    ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              child: Text(
                                style.label,
                                style: const TextStyle(
                                  color: _ink,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || style == null) return;

    if (!_printCompleted) {
      setState(() {
        _message = 'Print your original photo first. Then tap Conversion Preview to unlock paid AI styles.';
      });
      return;
    }
    if (!_aiCoinPaymentAvailable && !_aiQrPaymentAvailable) {
      setState(() {
        _message =
            'AI payment is unavailable. Please contact the booth attendant.';
      });
      return;
    }

    final paymentMethod = await _chooseAiPaymentMethod();
    if (!mounted || paymentMethod == null) return;
    final paid = paymentMethod == _AiPaymentMethod.coins
        ? await _payForAiWithCoins()
        : await _payForAiWithQrPh();
    if (!mounted || !paid) return;

    setState(() {
      _aiConversionPaid = true;
      _pendingAiStyle = style;
    });
    await _generatePaidAiStyle(style);
  }

  Future<_AiPaymentMethod?> _chooseAiPaymentMethod() async {
    final price = _selectedAiStylePricePesos;
    final photoCount = _selectedPhotoCount ?? 1;
    final coinAvailable = _aiCoinPaymentAvailable;
    final qrAvailable = _aiQrPaymentAvailable;
    if (!coinAvailable && !qrAvailable) return null;
    return showDialog<_AiPaymentMethod>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Choose payment'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: _panel,
                borderRadius: BorderRadius.circular(14),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x140F172A),
                    blurRadius: 8,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Text(
                    'AI STYLE PRICE FOR $photoCount PHOTO(S)',
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '₱$price',
                    style: const TextStyle(
                      color: _ink,
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            const Text('Choose how you would like to pay.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          if (coinAvailable)
            OutlinedButton.icon(
              onPressed: () =>
                  Navigator.of(context).pop(_AiPaymentMethod.coins),
              icon: const Icon(Icons.toll_rounded),
              label: const Text('Coins'),
            ),
          if (qrAvailable)
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(_AiPaymentMethod.qrPh),
              icon: const Icon(Icons.qr_code_2_rounded),
              label: const Text('QR PH'),
            ),
        ],
      ),
    );
  }

  Future<bool> _payForAiWithCoins() async {
    if (!_aiCoinPaymentAvailable) return false;
    final price = _selectedAiStylePricePesos;
    final photoCount = _selectedPhotoCount ?? 1;
    var insertedCredits = _credits ?? 0;
    var paying = false;
    var errorMessage = '';
    Timer? creditRefresh;
    try {
      return await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (dialogContext) => StatefulBuilder(
              builder: (context, refreshDialog) {
                creditRefresh ??= Timer.periodic(
                  const Duration(milliseconds: 500),
                  (_) {
                    if (!dialogContext.mounted) return;
                    final updatedCredits = _credits ?? 0;
                    if (updatedCredits != insertedCredits) {
                      refreshDialog(() => insertedCredits = updatedCredits);
                    }
                  },
                );
                return AlertDialog(
                  title: const Text('Pay with coins'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.toll_rounded, color: _accent, size: 44),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: _panel,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x140F172A),
                              blurRadius: 8,
                              offset: Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            Text(
                              'AI STYLE PRICE FOR $photoCount PHOTO(S)',
                              style: TextStyle(
                                color: _muted,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                              ),
                            ),
                            Text(
                              '₱$price',
                              style: const TextStyle(
                                color: _ink,
                                fontSize: 36,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Insert coins into the coin slot.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      LinearProgressIndicator(
                        value: (insertedCredits / price).clamp(0, 1).toDouble(),
                        color: _accent,
                        backgroundColor: const Color(0xFFE8ECF0),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '₱$insertedCredits / ₱$price',
                        style: const TextStyle(
                          color: _ink,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (errorMessage.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          errorMessage,
                          style: const TextStyle(
                            color: Color(0xFFB42318),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: paying
                          ? null
                          : () => Navigator.of(dialogContext).pop(false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: paying || insertedCredits < price
                          ? null
                          : () async {
                              refreshDialog(() {
                                paying = true;
                                errorMessage = '';
                              });
                              try {
                                final payment = await _payments.consumeCredits(
                                  price,
                                );
                                if (!dialogContext.mounted) return;
                                if (!payment.consumed) {
                                  refreshDialog(() {
                                    insertedCredits = payment.credits;
                                    paying = false;
                                    errorMessage =
                                        'Credits changed. Insert coins again.';
                                  });
                                  return;
                                }
                                if (mounted) {
                                  setState(() => _credits = payment.credits);
                                  _recordDashboardEvent(
                                    'Coin payment accepted for AI photo conversion.',
                                  );
                                  await _recordPaidSale(
                                    amount: price,
                                    photoCount: photoCount,
                                    paymentMethod: 'Coin',
                                  );
                                }
                                if (dialogContext.mounted) {
                                  Navigator.of(dialogContext).pop(true);
                                }
                              } on Object catch (error) {
                                if (dialogContext.mounted) {
                                  refreshDialog(() {
                                    paying = false;
                                    errorMessage =
                                        'Could not confirm coin payment: $error';
                                  });
                                }
                              }
                            },
                      child: paying
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Pay & generate'),
                    ),
                  ],
                );
              },
            ),
          ) ??
          false;
    } finally {
      creditRefresh?.cancel();
    }
  }

  Future<bool> _payForAiWithQrPh() async {
    final deviceId = _activationDeviceId;
    final price = _selectedAiStylePricePesos;
    final photoCount = _selectedPhotoCount ?? 1;
    if (!_aiQrPaymentAvailable || deviceId == null || _walletDialogOpen) {
      return false;
    }
    final activationCode = await _settings.loadActivationCode();
    if (!mounted) return false;
    if (activationCode == null || activationCode.isEmpty) {
      setState(
        () => _message = 'Activate this booth before accepting payments.',
      );
      return false;
    }
    _walletDialogOpen = true;
    _idleTimer?.cancel();
    Timer? paymentPoll;
    var polling = false;
    var creatingCheckout = false;
    var checkoutStarted = false;
    var errorMessage = '';
    PayMongoCheckout? checkout;
    String? idempotencyKey;
    Future<void> checkPayment(
      StateSetter refreshDialog,
      PayMongoCheckout activeCheckout,
      BuildContext dialogContext,
    ) async {
      if (polling || !dialogContext.mounted) return;
      polling = true;
      try {
        final status = await _payMongoPayments.getStatus(
          deviceId: deviceId,
          activationCode: activationCode,
          idempotencyKey: activeCheckout.idempotencyKey,
        );
        if (!dialogContext.mounted) return;
        if (status == 'paid') {
          Navigator.of(dialogContext).pop(true);
        } else if (status == 'expired') {
          paymentPoll?.cancel();
          refreshDialog(
            () => errorMessage =
                'This payment request expired. Cancel and try again.',
          );
        }
      } on Object catch (error) {
        if (!dialogContext.mounted) return;
        refreshDialog(
          () => errorMessage = 'Could not confirm payment yet: $error',
        );
      } finally {
        polling = false;
      }
    }

    Future<void> createCheckout(
      StateSetter refreshDialog,
      BuildContext dialogContext,
    ) async {
      refreshDialog(() {
        creatingCheckout = true;
        errorMessage = '';
      });
      try {
        final newCheckout = await _payMongoPayments.createCheckout(
          deviceId: deviceId,
          activationCode: activationCode,
          idempotencyKey: idempotencyKey ??=
              PayMongoPaymentClient.createIdempotencyKey(),
          amountPesos: price,
        );
        if (!dialogContext.mounted) return;
        refreshDialog(() => checkout = newCheckout);
        paymentPoll = Timer.periodic(
          const Duration(seconds: 4),
          (_) => unawaited(
            checkPayment(refreshDialog, newCheckout, dialogContext),
          ),
        );
        unawaited(checkPayment(refreshDialog, newCheckout, dialogContext));
      } on Object catch (error) {
        if (dialogContext.mounted) {
          refreshDialog(() => errorMessage = '$error');
        }
      } finally {
        if (dialogContext.mounted) {
          refreshDialog(() => creatingCheckout = false);
        }
      }
    }

    var confirmed = false;
    try {
      confirmed =
          await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (dialogContext) => StatefulBuilder(
              builder: (context, refreshDialog) {
                if (!checkoutStarted) {
                  checkoutStarted = true;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (dialogContext.mounted) {
                      unawaited(createCheckout(refreshDialog, dialogContext));
                    }
                  });
                }
                final qrSize = min(
                  300.0,
                  MediaQuery.sizeOf(context).shortestSide * 0.62,
                );
                return Dialog.fullscreen(
                  backgroundColor: Colors.white,
                  child: SafeArea(
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 28, 20, 10),
                          child: Column(
                            children: [
                              const Text(
                                'Pay with QR PH',
                                style: TextStyle(
                                  color: _ink,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: _panel,
                                  borderRadius: BorderRadius.circular(14),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x140F172A),
                                      blurRadius: 8,
                                      offset: Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: Text(
                                  '₱$price',
                                  style: const TextStyle(
                                    color: _ink,
                                    fontSize: 34,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Total for this AI conversion and $photoCount photo(s)',
                                style: const TextStyle(
                                  color: _muted,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Center(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (checkout == null)
                                    SizedBox(
                                      width: qrSize,
                                      height: qrSize,
                                      child: Center(
                                        child: creatingCheckout
                                            ? const CircularProgressIndicator(
                                                color: _accent,
                                              )
                                            : const Icon(
                                                Icons.qr_code_2_rounded,
                                                size: 64,
                                                color: _muted,
                                              ),
                                      ),
                                    )
                                  else
                                    SizedBox(
                                      width: qrSize,
                                      height: qrSize,
                                      child: checkout!.testUrl == null
                                          ? Image.memory(
                                              checkout!.imageBytes,
                                              fit: BoxFit.contain,
                                            )
                                          : QrImageView(
                                              data: checkout!.testUrl!,
                                              size: qrSize,
                                              backgroundColor: Colors.white,
                                            ),
                                    ),
                                  const SizedBox(height: 14),
                                  Text(
                                    checkout == null
                                        ? 'Preparing secure QR PH payment…'
                                        : 'Scan the QR code. Generation starts after payment is confirmed.',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(color: _muted),
                                  ),
                                  if (checkout != null) ...[
                                    const SizedBox(height: 12),
                                    const Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        SizedBox.square(
                                          dimension: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: _accent,
                                          ),
                                        ),
                                        SizedBox(width: 8),
                                        Text('Waiting for payment…'),
                                      ],
                                    ),
                                  ],
                                  if (errorMessage.isNotEmpty) ...[
                                    const SizedBox(height: 12),
                                    Text(
                                      errorMessage,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Color(0xFFB42318),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: OutlinedButton(
                            onPressed: () =>
                                Navigator.of(dialogContext).pop(false),
                            child: const Text('Cancel payment'),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ) ??
          false;
    } finally {
      paymentPoll?.cancel();
      _walletDialogOpen = false;
      if (!confirmed) _resetIdleTimer();
    }
    if (!mounted || !confirmed) return false;
    _recordDashboardEvent('PayMongo QR PH payment verified for AI conversion.');
    await _recordPaidSale(
      amount: price,
      photoCount: photoCount,
      paymentMethod: 'PayMongo QR Ph',
    );
    return true;
  }

  Future<void> _generatePaidAiStyle(AiPhotoStyle style) async {
    final photoComposer = _aiPhotoComposer;
    final deviceId = _activationDeviceId;
    if (!_aiConversionPaid ||
        _previewPhoto == null ||
        photoComposer == null ||
        deviceId == null ||
        _aiConversionBusy) {
      return;
    }
    final activationCode = await _settings.loadActivationCode();
    if (!mounted) return;
    if (activationCode == null || activationCode.isEmpty) {
      setState(() => _message = 'Activate this booth before AI generation.');
      return;
    }
    setState(() {
      _aiConversionBusy = true;
      _message = 'Creating your ${style.label} photo…';
    });
    try {
      if (_aiGeneratedPhotoCacheStyle != style) {
        _aiGeneratedPhotoCache.clear();
        _aiGeneratedPhotoCacheStyle = style;
      }
      final service = const AiCartoonService();
      final generated = await photoComposer(
        (photo) => service.generate(
          photo: photo,
          endpoint: defaultAiCartoonEndpoint,
          deviceId: deviceId,
          activationCode: activationCode,
          style: style,
        ),
      );
      if (!mounted) return;
      setState(() {
        _previewPhoto = generated;
        _previewPrintAttempted = false;
        _printCompleted = false;
        _printSubmitted = false;
        _aiOutputPhoto = true;
        _aiConversionPaid = false;
        _pendingAiStyle = null;
        _aiGeneratedPhotoCache.clear();
        _aiGeneratedPhotoCacheStyle = null;
        _softCopyUrl = null;
        _softCopyError = null;
        _softCopyUploading = true;
        _message =
            '${style.label} photo ready. Print it or scan the QR to download.';
      });
      unawaited(
        _uploadCustomerDownloads(photo: generated, gif: null, video: null),
      );
      _recordDashboardEvent('${style.label} AI photo generated after payment.');
    } on Object catch (error, stackTrace) {
      debugPrint(
        'Paid AI ${style.label} generation failed: $error\n$stackTrace',
      );
      if (!mounted) return;
      final errorText = error.toString();
      final photoFailure = RegExp(r'photo \d+ of \d+').firstMatch(errorText);
      final serverError = RegExp(r'\((replicate_[a-z_]+)\)')
          .firstMatch(errorText);
      final failureDetails = [
        if (photoFailure != null) photoFailure.group(0),
        if (serverError != null) serverError.group(1),
      ].whereType<String>().join(' · ');
      setState(() {
        _message = failureDetails.isEmpty
            ? 'AI generation failed. Tap Retry AI generation; you will not be charged again.'
            : 'AI generation failed ($failureDetails). Tap Retry; you will not be charged again.';
      });
    } finally {
      if (mounted) setState(() => _aiConversionBusy = false);
    }
  }

  Future<void> _rememberCustomerPhoto(File photo) async {
    try {
      final supportDirectory = await getApplicationSupportDirectory();
      final galleryDirectory = Directory(
        '${supportDirectory.path}${Platform.pathSeparator}'
        'recent_customer_photos',
      );
      await galleryDirectory.create(recursive: true);
      final archive = await photo.copy(
        '${galleryDirectory.path}${Platform.pathSeparator}'
        'photo_${DateTime.now().microsecondsSinceEpoch}.png',
      );
      final previous = _recentCustomerPhotos.map((file) => file.path).toList();
      final recent = [archive.path, ...previous].take(10).toList();
      await _settings.saveRecentCustomerPhotos(recent);
      if (mounted) {
        setState(() {
          _recentCustomerPhotos = recent.map(File.new).toList(growable: false);
          _recentPhotosError = null;
        });
      }
      final retained = recent.toSet();
      for (final oldPath in previous.where(
        (path) => !retained.contains(path),
      )) {
        if (!oldPath.startsWith(
          '${galleryDirectory.path}${Platform.pathSeparator}',
        )) {
          continue;
        }
        final oldFile = File(oldPath);
        if (await oldFile.exists()) await oldFile.delete();
      }
    } on Object catch (error, stackTrace) {
      debugPrint(
        'Could not update the recent customer photo gallery: $error\n$stackTrace',
      );
      if (mounted) {
        setState(() {
          _recentPhotosError = 'Recent photo gallery unavailable: $error';
        });
      }
    }
  }

  void _beginCustomerTransition() {
    if (_photoInProgress ||
        _boothUnavailable ||
        _adminDialogOpen ||
        !_showIdleScreen ||
        _homeTransitioning) {
      return;
    }
    setState(() => _homeTransitioning = true);
    _homeTransitionTimer?.cancel();
    _homeTransitionTimer = Timer(const Duration(milliseconds: 850), () {
      if (!mounted) return;
      _openCustomerPage();
    });
  }

  void _openCustomerPage() {
    if (_photoInProgress ||
        _boothUnavailable ||
        _adminDialogOpen ||
        !_showIdleScreen) {
      return;
    }
    _homeTransitionTimer?.cancel();
    _liveWallpaperTimer?.cancel();
    setState(() {
      _homeTransitioning = false;
      _showIdleScreen = false;
      _showLiveWallpaperScreen = false;
      _showPaymentMethodPage = false;
      _showCoinPaymentPage = false;
      _selectedPhotoCount = null;
      _selectedSessionFrameTemplate = null;
      _message = 'Choose 1–5 photos to begin';
    });
    _resetIdleTimer();
  }

  void _showSoftCopyQr({required bool showGif, bool showVideo = false}) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          _softCopyQrDialogSetState = setDialogState;
          final downloadUrl = showVideo
              ? _videoDownloadUrl
              : showGif
              ? _gifDownloadUrl
              : _softCopyUrl;
          final isUploading = _softCopyUploading;
          return AlertDialog(
            backgroundColor: Colors.white,
            title: const Text(
              'Scan to download',
              style: TextStyle(color: _ink),
            ),
            content: downloadUrl != null
                ? _buildDownloadQr(
                    downloadUrl,
                    label: showVideo
                        ? 'MOVING PHOTO VIDEO'
                        : showGif
                        ? 'ANIMATED GIF'
                        : 'PHOTO SOFT COPY',
                  )
                : SizedBox(
                    width: 280,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isUploading)
                          const CircularProgressIndicator(color: _accent)
                        else
                          const Icon(
                            Icons.cloud_off_rounded,
                            color: Color(0xFFB42318),
                            size: 40,
                          ),
                        const SizedBox(height: 12),
                        Text(
                          isUploading
                              ? 'Preparing this download QR code. Please keep this screen open and try again shortly.'
                              : showGif && _gifUploadError != null
                              ? 'GIF upload failed: $_gifUploadError'
                              : showVideo && _videoUploadError != null
                              ? 'Video upload failed: $_videoUploadError'
                              : showVideo && _sessionVideoError != null
                              ? 'The video is unavailable: $_sessionVideoError'
                              : !showGif && _softCopyError != null
                              ? 'Photo upload failed: $_softCopyError'
                              : showGif && _sessionGifError != null
                              ? 'The GIF is unavailable: $_sessionGifError'
                              : 'This download is unavailable. The photo is saved on the booth.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: _ink),
                        ),
                      ],
                    ),
                  ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('CLOSE'),
              ),
            ],
          );
        },
      ),
    ).whenComplete(() => _softCopyQrDialogSetState = null);
  }

  void _refreshSoftCopyQrDialog() {
    _softCopyQrDialogSetState?.call(() {});
  }

  Widget _buildDownloadQr(Uri downloadUrl, {required String label}) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [
            BoxShadow(
              color: Color(0x180F172A),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: QrImageView(
          data: downloadUrl.toString(),
          size: 220,
          version: QrVersions.auto,
          backgroundColor: Colors.white,
        ),
      ),
      const SizedBox(height: 12),
      Text(
        label,
        style: const TextStyle(
          color: _ink,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.6,
        ),
      ),
    ],
  );

  void _resetIdleTimer() {
    _idleTimer?.cancel();
    if (_showIdleScreen ||
        _photoInProgress ||
        _adminDialogOpen ||
        _startingPhotoSession ||
        _hasActivePayment) {
      return;
    }
    _idleTimer = Timer(
      Duration(seconds: _idleTimeoutSeconds),
      () => unawaited(_returnToIdleForTimeout()),
    );
  }

  void _resetLiveWallpaperTimer() {
    _liveWallpaperTimer?.cancel();
    if (!_liveWallpaperEnabled ||
        !_activationActive ||
        !_showIdleScreen ||
        _photoInProgress ||
        _adminDialogOpen ||
        _startingPhotoSession ||
        _hasActivePayment) {
      return;
    }
    _liveWallpaperTimer = Timer(const Duration(minutes: 1), () {
      if (!mounted ||
          !_liveWallpaperEnabled ||
          !_showIdleScreen ||
          _photoInProgress ||
          _adminDialogOpen ||
          _startingPhotoSession) {
        return;
      }
      setState(() => _showLiveWallpaperScreen = true);
    });
  }

  Future<void> _returnToIdleForTimeout() async {
    if (!mounted ||
        _showIdleScreen ||
        _photoInProgress ||
        _adminDialogOpen ||
        _startingPhotoSession ||
        _hasActivePayment) {
      return;
    }
    setState(() {
      _showIdleScreen = true;
      _showLiveWallpaperScreen = false;
      _showPaymentMethodPage = false;
      _showCoinPaymentPage = false;
      _selectedPhotoCount = null;
      _selectedSessionFrameTemplate = null;
      _paidPhotoPending = false;
      _coinPaymentReady = false;
      _message = 'Tap the screen to start';
    });
    _idleTimer?.cancel();
    _resetLiveWallpaperTimer();
  }

  void _handleRecoveryTap() {
    final now = DateTime.now();
    final previous = _lastRecoveryTap;
    if (previous == null ||
        now.difference(previous) > const Duration(seconds: 3)) {
      _recoveryTapCount = 0;
    }
    _lastRecoveryTap = now;
    _recoveryTapCount++;
    if (_recoveryTapCount < 5) return;
    _recoveryTapCount = 0;
    _lastRecoveryTap = null;
    unawaited(_openAdmin());
  }

  void _handleScreenPointerDown(PointerDownEvent event, Size screenSize) {
    if (!_activationActive ||
        _boothUnavailable ||
        _photoInProgress ||
        _adminDialogOpen ||
        _homeTransitioning) {
      return;
    }
    final isAdminHotspot =
        !_showLiveWallpaperScreen &&
        event.localPosition.dx >= screenSize.width - 112 &&
        event.localPosition.dy <= 150;
    if (isAdminHotspot) return;
    if (_showIdleScreen) {
      _beginCustomerTransition();
    } else {
      _resetIdleTimer();
    }
  }

  Widget _buildPaymentMethodPage({
    required bool phoneLayout,
    required bool qrPayMongoEnabled,
    required bool qrGanapEnabled,
  }) {
    final qrPaymentEnabled = qrPayMongoEnabled || qrGanapEnabled;
    final coinPaymentEnabled = _esp32Detected && _credits != null;
    final bothPaymentMethodsEnabled = coinPaymentEnabled && qrPaymentEnabled;
    final qrAmountPesos = qrPayMongoEnabled
        ? _payMongoAmountPesos
        : _sessionPricePesos;
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Container(
              padding: EdgeInsets.all(phoneLayout ? 18 : 24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x160F172A),
                    blurRadius: 22,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'CHOOSE PAYMENT METHOD',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _ink,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 22),
                  if (bothPaymentMethodsEnabled)
                    Row(
                      children: [
                        Expanded(
                          child: _PaymentMethodCard(
                            icon: Icons.monetization_on_rounded,
                            title: 'Insert Coins',
                            price: '₱$_coinPricePesos per session',
                            enabled: _cameraReady && !_boothPaused,
                            onTap: _selectCoinPaymentMethod,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _PaymentMethodCard(
                            icon: Icons.qr_code_2_rounded,
                            title: 'Scan QR PH',
                            price: '₱$qrAmountPesos per session',
                            enabled: _cameraReady && !_boothPaused,
                            onTap: () => _selectQrPaymentMethod(
                              qrPayMongoEnabled: qrPayMongoEnabled,
                              qrGanapEnabled: qrGanapEnabled,
                            ),
                          ),
                        ),
                      ],
                    )
                  else if (coinPaymentEnabled || qrPaymentEnabled)
                    SizedBox(
                      width: min(230.0, double.infinity),
                      child: _PaymentMethodCard(
                        icon: coinPaymentEnabled
                            ? Icons.monetization_on_rounded
                            : Icons.qr_code_2_rounded,
                        title: coinPaymentEnabled
                            ? 'Insert Coins'
                            : 'Scan QR PH',
                        price: coinPaymentEnabled
                            ? '₱$_coinPricePesos per session'
                            : '₱$qrAmountPesos per session',
                        enabled: _cameraReady && !_boothPaused,
                        onTap: coinPaymentEnabled
                            ? _selectCoinPaymentMethod
                            : () => _selectQrPaymentMethod(
                                qrPayMongoEnabled: qrPayMongoEnabled,
                                qrGanapEnabled: qrGanapEnabled,
                              ),
                      ),
                    )
                  else ...[
                    const SizedBox(height: 10),
                    const Text(
                      'No payment method is available right now. Please contact the booth attendant.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFFB42318),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  if (bothPaymentMethodsEnabled) ...[
                    const SizedBox(height: 15),
                    const Row(
                      children: [
                        Expanded(child: Divider(color: _outline)),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 10),
                          child: Text(
                            'or',
                            style: TextStyle(
                              color: _muted,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Expanded(child: Divider(color: _outline)),
                      ],
                    ),
                  ],
                  if (qrPaymentEnabled) ...[
                    const SizedBox(height: 18),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.qr_code_2_rounded,
                          color: Color(0xFF1769AA),
                          size: 20,
                        ),
                        SizedBox(width: 6),
                        Text(
                          'QR PH',
                          style: TextStyle(
                            color: _ink,
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () =>
                          setState(() => _showPaymentMethodPage = false),
                      icon: const Icon(Icons.arrow_back_rounded, size: 18),
                      label: const Text('BACK'),
                      style: TextButton.styleFrom(
                        foregroundColor: _ink,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCoinPaymentPage({required bool phoneLayout}) {
    final insertedCredits = (_credits ?? 0).clamp(0, _requiredCredits);
    final remainingCredits = (_requiredCredits - insertedCredits).clamp(
      0,
      _requiredCredits,
    );
    final progress = _requiredCredits <= 0
        ? 0.0
        : insertedCredits / _requiredCredits;
    return ColoredBox(
      color: const Color(0xFFFAFBFC),
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 18,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Insert Coins',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _ink,
                            fontSize: phoneLayout ? 22 : 26,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '₱$_requiredCredits per session',
                          style: const TextStyle(
                            color: _ink,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const _CoinInsertionAnimation(),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            for (var index = 0; index < 5; index++) ...[
                              if (index > 0) const SizedBox(width: 8),
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 220),
                                width: 14,
                                height: 14,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: progress >= (index + 1) / 5
                                      ? const Color(0xFFF9B82D)
                                      : Colors.white,
                                  border: Border.all(
                                    color: progress >= (index + 1) / 5
                                        ? const Color(0xFFE7A41B)
                                        : const Color(0xFFCBD2D9),
                                    width: 1.5,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 14),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          child: Text(
                            'Please insert ₱$remainingCredits more.',
                            key: ValueKey(remainingCredits),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: _ink,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0F2F4),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.info_outline_rounded,
                                color: _muted,
                                size: 17,
                              ),
                              const SizedBox(width: 7),
                              Flexible(
                                child: Text(
                                  'Coins are counted at ₱1 per credit',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: _muted,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
                child: TextButton.icon(
                  onPressed: _cancelCoinPaymentMethod,
                  icon: const Icon(Icons.arrow_back_rounded, size: 18),
                  label: const Text('CANCEL'),
                  style: TextButton.styleFrom(
                    foregroundColor: _ink,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIdleHome({required bool compactLayout}) {
    final phoneLayout = MediaQuery.sizeOf(context).shortestSide < 600;
    return Positioned.fill(
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: 1),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
        builder: (context, entrance, child) => AnimatedOpacity(
          opacity: _homeTransitioning ? 0 : entrance,
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeInOut,
          child: AnimatedScale(
            scale: _homeTransitioning ? 0.94 : 0.97 + entrance * 0.03,
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeInOut,
            child: child,
          ),
        ),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _beginCustomerTransition,
          child: Stack(
            fit: StackFit.expand,
            children: [
              SafeArea(
                top: false,
                bottom: false,
                left: false,
                right: false,
                child: Container(
                  decoration: BoxDecoration(
                    color: _eventTheme.usesWhiteBackground
                        ? Colors.white
                        : const Color(0xFFE1E4E9),
                  ),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: IgnorePointer(
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: CustomPaint(
                                  painter: BoothThemeBackgroundPainter(
                                    theme: _eventTheme,
                                    animation: _filmTapeController,
                                  ),
                                ),
                              ),
                              if (_eventTheme == BoothEventTheme.classic)
                                Positioned.fill(
                                  child: CustomPaint(
                                    painter: _FilmTapeBackgroundPainter(
                                      animation: _filmTapeController,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: IgnorePointer(
                          child: _RecentCustomerPhotoGallery(
                            photos: _recentCustomerPhotos,
                            animatingOut: _homeTransitioning,
                          ),
                        ),
                      ),
                      Positioned(
                        top: MediaQuery.sizeOf(context).height * 0.15,
                        left: 0,
                        right: 0,
                        child: SizedBox(
                          height: MediaQuery.sizeOf(context).height * 0.33,
                          child: Center(
                            child: TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0.65, end: 1),
                              duration: const Duration(milliseconds: 700),
                              curve: Curves.easeOutBack,
                              builder: (context, scale, child) =>
                                  Transform.scale(scale: scale, child: child),
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: _handleLogoTap,
                                child: _buildAnimatedBrandLogo(
                                  animation: _brandLogoAnimation,
                                  width: min(
                                    MediaQuery.sizeOf(context).width * 0.88,
                                    650,
                                  ),
                                  height:
                                      MediaQuery.sizeOf(context).height * 0.30,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: MediaQuery.sizeOf(context).height * 0.48,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: SizedBox(
                            width: min(
                              MediaQuery.sizeOf(context).width * 0.80,
                              620,
                            ),
                            height: MediaQuery.sizeOf(context).height * 0.47,
                            child: Semantics(
                              button: true,
                              label: translateAppText(
                                'Tap anywhere to start',
                                appLanguageNotifier.value,
                              ),
                              child: AnimatedBuilder(
                                animation: _startPromptController,
                                builder: (context, child) => Transform.scale(
                                  scale: _startPromptController.value,
                                  child: child,
                                ),
                                child: CustomPaint(
                                  painter: _CameraPhotoCardsPainter(
                                    language: appLanguageNotifier.value,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (_availableAppUpdate case final update?)
                        Positioned(
                          top: MediaQuery.sizeOf(context).height * 0.47,
                          left: phoneLayout ? 12 : 20,
                          right: phoneLayout ? 12 : 20,
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 620),
                              child: AnimatedBuilder(
                                animation: _startPromptController,
                                builder: (context, child) {
                                  final pulse =
                                      ((_startPromptController.value - 0.94) /
                                              0.12)
                                          .clamp(0.0, 1.0);
                                  return Opacity(
                                    opacity: 0.72 + pulse * 0.28,
                                    child: Transform.scale(
                                      scale: 0.985 + pulse * 0.015,
                                      child: child,
                                    ),
                                  );
                                },
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF111111),
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Color(0x33000000),
                                        blurRadius: 14,
                                        offset: Offset(0, 5),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Row(
                                        children: [
                                          const Icon(
                                            Icons.system_update_alt_rounded,
                                            color: _accent,
                                            size: 30,
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Text(
                                                  'BOOTH UPDATE AVAILABLE',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.w900,
                                                    fontSize: 14,
                                                    letterSpacing: 0.6,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  'New version ${update.version} '
                                                  '(build ${update.versionCode}) '
                                                  'is available. Download and confirm installation to update.',
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Wrap(
                                        alignment: WrapAlignment.end,
                                        spacing: 8,
                                        runSpacing: 4,
                                        children: [
                                          TextButton(
                                            onPressed: () =>
                                                _dismissAppUpdate(update),
                                            style: TextButton.styleFrom(
                                              foregroundColor: Colors.white,
                                            ),
                                            child: const Text('LATER'),
                                          ),
                                          FilledButton.icon(
                                            onPressed: _appUpdateInstalling
                                                ? null
                                                : () => _startAppUpdate(update),
                                            style: FilledButton.styleFrom(
                                              backgroundColor: _accent,
                                              foregroundColor: Colors.white,
                                            ),
                                            icon: _appUpdateInstalling
                                                ? const SizedBox(
                                                    width: 18,
                                                    height: 18,
                                                    child:
                                                        CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                        ),
                                                  )
                                                : const Icon(
                                                    Icons.system_update_alt,
                                                    size: 18,
                                                  ),
                                            label: Text(
                                              _appUpdateInstalling
                                                  ? 'DOWNLOADING…'
                                                  : 'DOWNLOAD & INSTALL',
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (_recentPhotosError != null)
                        Positioned(
                          left: 8,
                          right: 8,
                          bottom: 4,
                          child: Text(
                            _recentPhotosError!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Color(0xFF8A1C13),
                              fontSize: 10,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLiveWallpaperPage() {
    final videoPath = _idleScreenVideoPath;
    final imagePath = _idleScreenImagePath;
    return Positioned.fill(
      child: ColoredBox(
        color: _ink,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (videoPath != null)
              _IdleVideoBackground(
                key: ValueKey('live-wallpaper-video-$videoPath'),
                videoPath: videoPath,
                looping: _idleVideoLoop,
                fallbackImagePath: imagePath,
              )
            else if (imagePath != null)
              Image.file(
                File(imagePath),
                fit: BoxFit.cover,
                errorBuilder: (context, error, stack) =>
                    const ColoredBox(color: _ink),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _applyCameraSelection(CameraLensDirection direction) async {
    final currentCamera = _camera;
    if (_cameraDirection == direction &&
        currentCamera?.value.isInitialized == true &&
        currentCamera?.description.lensDirection == direction) {
      return;
    }
    setState(() {
      _cameraDirection = direction;
      _cameraReady = false;
    });
    _camera = null;
    if (currentCamera != null) await _disposeCameraController(currentCamera);
    await _initializeCamera();
  }

  Future<CameraController> _ensureSelectedCameraReady() async {
    for (var attempt = 0; _cameraInitializing && attempt < 80; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (_cameraInitializing) {
      throw StateError('The selected camera is taking too long to start.');
    }
    final cameras = await availableCameras();
    final matchingCameras = cameras
        .where((camera) => camera.lensDirection == _cameraDirection)
        .toList();
    if (matchingCameras.isEmpty) {
      throw StateError(
        'The selected ${_cameraDirection.name} camera is not available on this device.',
      );
    }
    final selectedCamera = matchingCameras.first;
    final currentCamera = _camera;
    if (currentCamera != null &&
        currentCamera.value.isInitialized &&
        currentCamera.description.name == selectedCamera.name &&
        currentCamera.description.lensDirection == _cameraDirection) {
      return currentCamera;
    }
    if (currentCamera != null) {
      _camera = null;
      _cameraReady = false;
      await _disposeCameraController(currentCamera);
    }
    await _initializeCamera();
    for (var attempt = 0; _cameraInitializing && attempt < 80; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    final initializedCamera = _camera;
    if (initializedCamera == null ||
        !initializedCamera.value.isInitialized ||
        initializedCamera.description.name != selectedCamera.name ||
        initializedCamera.description.lensDirection != _cameraDirection) {
      throw StateError(
        'The selected ${_cameraDirection.name} camera could not be initialized. Please contact the booth attendant.',
      );
    }
    return initializedCamera;
  }

  Future<XFile> _takePhotoForSession() async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final camera = await _ensureSelectedCameraReady();
      try {
        return await camera.takePicture();
      } on CameraException catch (error) {
        final controllerWasReplaced =
            !identical(_camera, camera) || !_cameraReady;
        final controllerWasDisposed = error.code.toLowerCase().contains(
          'disposed',
        );
        if (attempt > 0 ||
            (!controllerWasReplaced && !controllerWasDisposed) ||
            !_appInForeground) {
          rethrow;
        }

        if (identical(_camera, camera)) {
          _camera = null;
          _cameraReady = false;
          await _disposeCameraController(camera);
        }
      }
    }
    throw StateError('The selected camera could not take a photo.');
  }

  int get _requiredCredits => _coinPricePesos;

  void _showPaymentAcceptedNotice() {
    if (!mounted) return;
    _paymentNoticeEntry?.remove();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => Positioned.fill(
        child: Material(
          color: Colors.white,
          child: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 76,
                            height: 76,
                            decoration: const BoxDecoration(
                              color: Color(0xFF2FB66D),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.check_rounded,
                              color: Colors.white,
                              size: 52,
                            ),
                          ),
                          const SizedBox(height: 18),
                          Semantics(
                            liveRegion: true,
                            child: Text(
                              'Payment Successful!',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: _ink,
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'You can now take your photo.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: _muted, fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
                  child: SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: FilledButton(
                      onPressed: () {
                        if (_paymentNoticeEntry != entry) return;
                        entry.remove();
                        _paymentNoticeEntry = null;
                        unawaited(_startPhotoSession());
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF347FF0),
                        foregroundColor: Colors.white,
                        shape: const StadiumBorder(),
                        textStyle: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      child: const Text('Start'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    _paymentNoticeEntry = entry;
    Overlay.of(context, rootOverlay: true).insert(entry);
  }

  void _selectSessionTemplate(PhotoFrameTemplate template) {
    final count = template.photoCount;
    if (!_enabledPhotoCounts.contains(count)) return;
    if (!_cameraReady || _photoInProgress || _adminDialogOpen) return;
    if (_boothPaused) {
      setState(() => _message = 'The booth is temporarily paused.');
      return;
    }
    final countChanged = _selectedPhotoCount != count;
    final paymentConfirmed =
        _paidPhotoPending || (!countChanged && _coinPaymentReady);
    setState(() {
      _selectedSessionFrameTemplate = template;
      _selectedPhotoCount = count;
      _showPaymentMethodPage = !_rentModeEnabled && !_isTestMode;
      _showCoinPaymentPage = false;
      if (countChanged) _coinPaymentReady = false;
      _message = _rentModeEnabled || _isTestMode
          ? '$count ${count == 1 ? 'photo' : 'photos'} selected'
          : paymentConfirmed
          ? 'Payment received. Tap START PHOTO SESSION when you are ready.'
          : 'Insert $_coinPricePesos credits (₱$_coinPricePesos) for this session';
    });
    _resetIdleTimer();
    unawaited(_pollCredits());
  }

  void _selectCoinPaymentMethod() {
    if (!_showPaymentMethodPage) return;
    setState(() {
      _showPaymentMethodPage = false;
      _showCoinPaymentPage = true;
    });
    _resetIdleTimer();
    unawaited(_pollCredits());
  }

  void _cancelCoinPaymentMethod() {
    setState(() {
      _showCoinPaymentPage = false;
      _showPaymentMethodPage = true;
    });
    _resetIdleTimer();
  }

  void _selectQrPaymentMethod({
    required bool qrPayMongoEnabled,
    required bool qrGanapEnabled,
  }) {
    if (!qrPayMongoEnabled && !qrGanapEnabled) return;
    if (qrPayMongoEnabled) {
      unawaited(_startPayMongoPayment());
    } else {
      unawaited(_startWalletPayment());
    }
  }

  Future<void> _startWalletPayment() async {
    final photoCount = _selectedPhotoCount;
    final deviceId = _activationDeviceId;
    if (_boothPaused ||
        _isTestMode ||
        _rentModeEnabled ||
        !_ganapQrPhAvailable ||
        !_activationAllowsGanap ||
        !_walletPaymentEnabled ||
        photoCount == null ||
        deviceId == null ||
        !_cameraReady ||
        _photoInProgress) {
      if (mounted) {
        setState(
          () => _message = !_ganapQrPhAvailable
              ? 'Ganap QRPh is unavailable because its ₱$_ganapQrPhMinimumPesos minimum is above the ₱$_sessionPricePesos session price.'
              : 'Ganap payment is not ready. Please contact the booth attendant.',
        );
      }
      return;
    }
    final activationCode = await _settings.loadActivationCode();
    if (!mounted) return;
    if (activationCode == null || activationCode.isEmpty) {
      setState(
        () => _message = 'Activate this booth before accepting payments.',
      );
      return;
    }

    _walletDialogOpen = true;
    _idleTimer?.cancel();
    Timer? paymentPoll;
    bool? paymentConfirmed;
    try {
      paymentConfirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          var errorMessage = '';
          var creatingCheckout = false;
          var polling = false;
          var checkoutStarted = false;
          GanapCheckout? checkout;
          String? idempotencyKey;

          Future<void> checkPayment(
            StateSetter refreshDialog,
            GanapCheckout activeCheckout,
          ) async {
            if (polling || !dialogContext.mounted) return;
            polling = true;
            try {
              final status = await _ganapPayments.getStatus(
                deviceId: deviceId,
                activationCode: activationCode,
                idempotencyKey: activeCheckout.idempotencyKey,
              );
              if (!dialogContext.mounted) return;
              if (status == 'paid') {
                Navigator.of(dialogContext).pop(true);
              } else if (status == 'expired') {
                paymentPoll?.cancel();
                refreshDialog(
                  () => errorMessage = 'This payment request expired. Cancel and create a new one.',
                );
              }
            } on Object catch (error) {
              if (!dialogContext.mounted) return;
              refreshDialog(
                () => errorMessage = 'Could not confirm payment yet: $error',
              );
            } finally {
              polling = false;
            }
          }

          return StatefulBuilder(
            builder: (context, refreshDialog) {
              Future<void> createCheckout() async {
                refreshDialog(() {
                  creatingCheckout = true;
                  errorMessage = '';
                });
                try {
                  final newCheckout = await _ganapPayments.createCheckout(
                    deviceId: deviceId,
                    activationCode: activationCode,
                    idempotencyKey: idempotencyKey ??=
                        GanapPaymentClient.createIdempotencyKey(),
                  );
                  if (!dialogContext.mounted) return;
                  refreshDialog(() {
                    checkout = newCheckout;
                    errorMessage = '';
                  });
                  paymentPoll = Timer.periodic(
                    const Duration(seconds: 4),
                    (_) => unawaited(checkPayment(refreshDialog, newCheckout)),
                  );
                  unawaited(checkPayment(refreshDialog, newCheckout));
                } on Object catch (error) {
                  if (!dialogContext.mounted) return;
                  refreshDialog(() => errorMessage = '$error');
                } finally {
                  if (dialogContext.mounted) {
                    refreshDialog(() => creatingCheckout = false);
                  }
                }
              }

              if (!checkoutStarted) {
                checkoutStarted = true;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (dialogContext.mounted) unawaited(createCheckout());
                });
              }

              final qrSize = min(
                300.0,
                MediaQuery.sizeOf(context).shortestSide * 0.62,
              );
              return Dialog.fullscreen(
                backgroundColor: Colors.white,
                child: SafeArea(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 28, 20, 8),
                        child: Column(
                          children: [
                            const Text(
                              'Scan with QR PH',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: _ink,
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 5),
                            const Text(
                              '₱$_sessionPricePesos per session',
                              style: TextStyle(color: _muted, fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 420),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (checkout == null) ...[
                                    const SizedBox(height: 52),
                                    const CircularProgressIndicator(
                                      color: _accent,
                                    ),
                                    const SizedBox(height: 18),
                                    const Text(
                                      'Preparing your secure QR PH payment…',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: _muted),
                                    ),
                                  ] else ...[
                                    Container(
                                      width: qrSize,
                                      height: qrSize,
                                      padding: const EdgeInsets.all(8),
                                      color: Colors.white,
                                      child: switch (checkout!.qrType) {
                                        GanapQrType.checkoutUrl ||
                                        GanapQrType.payload => QrImageView(
                                          data: checkout!.qrContent,
                                          size: qrSize - 16,
                                          backgroundColor: Colors.white,
                                        ),
                                        GanapQrType.imageData => Image.memory(
                                          Uint8List.fromList(
                                            checkout!.imageBytes!,
                                          ),
                                          fit: BoxFit.contain,
                                          errorBuilder: (_, _, _) =>
                                              const Center(
                                                child: Text(
                                                  'QR image could not load.',
                                                ),
                                              ),
                                        ),
                                        GanapQrType.imageUrl => Image.network(
                                          checkout!.qrContent,
                                          fit: BoxFit.contain,
                                          errorBuilder: (_, _, _) =>
                                              const Center(
                                                child: Text(
                                                  'QR image could not load.',
                                                ),
                                              ),
                                        ),
                                      },
                                    ),
                                    const SizedBox(height: 14),
                                    const Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.qr_code_2_rounded,
                                          color: Color(0xFF1769AA),
                                          size: 21,
                                        ),
                                        SizedBox(width: 6),
                                        Text(
                                          'QR PH',
                                          style: TextStyle(
                                            color: _ink,
                                            fontSize: 16,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    const Text(
                                      'Open your QR PH app and scan the code above.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: _muted,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    const Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        SizedBox.square(
                                          dimension: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: _accent,
                                          ),
                                        ),
                                        SizedBox(width: 8),
                                        Text(
                                          'Waiting for payment…',
                                          style: TextStyle(color: _muted),
                                        ),
                                      ],
                                    ),
                                  ],
                                  if (errorMessage.isNotEmpty) ...[
                                    const SizedBox(height: 12),
                                    Text(
                                      errorMessage,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Color(0xFFB42318),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
                        child: Row(
                          children: [
                            TextButton.icon(
                              onPressed: creatingCheckout
                                  ? null
                                  : () =>
                                        Navigator.of(dialogContext).pop(false),
                              icon: const Icon(
                                Icons.arrow_back_rounded,
                                size: 17,
                              ),
                              label: const Text('Cancel'),
                              style: TextButton.styleFrom(
                                foregroundColor: _ink,
                              ),
                            ),
                            const Spacer(),
                            if (checkout == null)
                              TextButton(
                                onPressed: creatingCheckout
                                    ? null
                                    : () => unawaited(createCheckout()),
                                child: creatingCheckout
                                    ? const SizedBox.square(
                                        dimension: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Text('RETRY'),
                              )
                            else
                              TextButton(
                                onPressed: polling
                                    ? null
                                    : () => unawaited(
                                        checkPayment(refreshDialog, checkout!),
                                      ),
                                child: const Text('CHECK PAYMENT'),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );
    } finally {
      paymentPoll?.cancel();
      _walletDialogOpen = false;
      if (paymentConfirmed != true) _resetIdleTimer();
    }
    if (!mounted || paymentConfirmed != true) return;
    _recordDashboardEvent('Ganap QRPh payment verified by the server.');
    await _recordPaidSale(
      amount: _sessionPricePesos,
      photoCount: photoCount,
      paymentMethod: 'Ganap QRPh',
    );
    setState(() {
      _showPaymentMethodPage = false;
      _paidPhotoPending = true;
      _message = 'Payment Recieved. Tap START PHOTO SESSION when ready.';
    });
    _showPaymentAcceptedNotice();
  }

  Future<void> _startPayMongoPayment() async {
    final photoCount = _selectedPhotoCount;
    final deviceId = _activationDeviceId;
    final amountPesos = _payMongoAmountPesos;
    if (_boothPaused ||
        _isTestMode ||
        _rentModeEnabled ||
        !_activationAllowsPayMongo ||
        !_payMongoPaymentsEnabled ||
        photoCount == null ||
        deviceId == null ||
        !_cameraReady ||
        _photoInProgress ||
        _walletDialogOpen) {
      if (mounted) {
        setState(
          () => _message = 'PayMongo payment is not ready. Please contact the booth attendant.',
        );
      }
      return;
    }
    final activationCode = await _settings.loadActivationCode();
    if (!mounted) return;
    if (activationCode == null || activationCode.isEmpty) {
      setState(
        () => _message = 'Activate this booth before accepting payments.',
      );
      return;
    }

    _walletDialogOpen = true;
    _idleTimer?.cancel();
    Timer? paymentPoll;
    bool? paymentConfirmed;
    try {
      paymentConfirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          var errorMessage = '';
          var creatingCheckout = false;
          var polling = false;
          var checkoutStarted = false;
          PayMongoCheckout? checkout;
          String? idempotencyKey;

          Future<void> checkPayment(
            StateSetter refreshDialog,
            PayMongoCheckout activeCheckout,
          ) async {
            if (polling || !dialogContext.mounted) return;
            polling = true;
            try {
              final status = await _payMongoPayments.getStatus(
                deviceId: deviceId,
                activationCode: activationCode,
                idempotencyKey: activeCheckout.idempotencyKey,
              );
              if (!dialogContext.mounted) return;
              if (status == 'paid') {
                Navigator.of(dialogContext).pop(true);
              } else if (status == 'expired') {
                paymentPoll?.cancel();
                refreshDialog(
                  () => errorMessage = 'This payment request expired. Cancel and create a new one.',
                );
              }
            } on Object catch (error) {
              if (!dialogContext.mounted) return;
              refreshDialog(
                () => errorMessage = 'Could not confirm payment yet: $error',
              );
            } finally {
              polling = false;
            }
          }

          return StatefulBuilder(
            builder: (context, refreshDialog) {
              Future<void> createCheckout() async {
                refreshDialog(() {
                  creatingCheckout = true;
                  errorMessage = '';
                });
                try {
                  final newCheckout = await _payMongoPayments.createCheckout(
                    deviceId: deviceId,
                    activationCode: activationCode,
                    idempotencyKey: idempotencyKey ??=
                        PayMongoPaymentClient.createIdempotencyKey(),
                    amountPesos: amountPesos,
                  );
                  if (!dialogContext.mounted) return;
                  refreshDialog(() {
                    checkout = newCheckout;
                    errorMessage = '';
                  });
                  paymentPoll = Timer.periodic(
                    const Duration(seconds: 4),
                    (_) => unawaited(checkPayment(refreshDialog, newCheckout)),
                  );
                  unawaited(checkPayment(refreshDialog, newCheckout));
                } on Object catch (error) {
                  if (!dialogContext.mounted) return;
                  refreshDialog(() => errorMessage = '$error');
                } finally {
                  if (dialogContext.mounted) {
                    refreshDialog(() => creatingCheckout = false);
                  }
                }
              }

              if (!checkoutStarted) {
                checkoutStarted = true;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (dialogContext.mounted) unawaited(createCheckout());
                });
              }

              final qrSize = min(
                300.0,
                MediaQuery.sizeOf(context).shortestSide * 0.62,
              );
              return Dialog.fullscreen(
                backgroundColor: Colors.white,
                child: SafeArea(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 28, 20, 8),
                        child: Column(
                          children: [
                            const Text(
                              'Scan with QR PH',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: _ink,
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              '₱$amountPesos per session',
                              style: const TextStyle(
                                color: _muted,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 420),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (checkout == null) ...[
                                    SizedBox(height: qrSize * 0.25),
                                    const CircularProgressIndicator(
                                      color: _accent,
                                    ),
                                    const SizedBox(height: 18),
                                    const Text(
                                      'Preparing your secure QR PH payment…',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: _muted),
                                    ),
                                  ] else ...[
                                    Container(
                                      width: qrSize,
                                      height: qrSize,
                                      padding: const EdgeInsets.all(8),
                                      color: Colors.white,
                                      child: checkout!.testUrl == null
                                          ? Image.memory(
                                              checkout!.imageBytes,
                                              fit: BoxFit.contain,
                                              errorBuilder: (_, _, _) =>
                                                  const Center(
                                                    child: Text(
                                                      'QR image could not load.',
                                                    ),
                                                  ),
                                            )
                                          : QrImageView(
                                              data: checkout!.testUrl!,
                                              size: qrSize - 16,
                                              backgroundColor: Colors.white,
                                            ),
                                    ),
                                    const SizedBox(height: 14),
                                    const Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.qr_code_2_rounded,
                                          color: Color(0xFF1769AA),
                                          size: 21,
                                        ),
                                        SizedBox(width: 6),
                                        Text(
                                          'QR PH',
                                          style: TextStyle(
                                            color: _ink,
                                            fontSize: 16,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      checkout!.testUrl == null
                                          ? 'Open your QR PH app and scan the code above.'
                                          : 'Test QR only. Do not use real funds to scan this code.',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: _muted,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    const Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        SizedBox.square(
                                          dimension: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: _accent,
                                          ),
                                        ),
                                        SizedBox(width: 8),
                                        Text(
                                          'Waiting for payment…',
                                          style: TextStyle(color: _muted),
                                        ),
                                      ],
                                    ),
                                  ],
                                  if (errorMessage.isNotEmpty) ...[
                                    const SizedBox(height: 12),
                                    Text(
                                      errorMessage,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Color(0xFFB42318),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
                        child: Row(
                          children: [
                            TextButton.icon(
                              onPressed: creatingCheckout
                                  ? null
                                  : () =>
                                        Navigator.of(dialogContext).pop(false),
                              icon: const Icon(
                                Icons.arrow_back_rounded,
                                size: 17,
                              ),
                              label: const Text('Cancel'),
                              style: TextButton.styleFrom(
                                foregroundColor: _ink,
                              ),
                            ),
                            const Spacer(),
                            if (checkout == null)
                              TextButton(
                                onPressed: creatingCheckout
                                    ? null
                                    : () => unawaited(createCheckout()),
                                child: creatingCheckout
                                    ? const SizedBox.square(
                                        dimension: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Text('RETRY'),
                              )
                            else
                              TextButton(
                                onPressed: polling
                                    ? null
                                    : () => unawaited(
                                        checkPayment(refreshDialog, checkout!),
                                      ),
                                child: const Text('CHECK PAYMENT'),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );
    } finally {
      paymentPoll?.cancel();
      _walletDialogOpen = false;
      if (paymentConfirmed != true) _resetIdleTimer();
    }
    if (!mounted || paymentConfirmed != true) return;
    _recordDashboardEvent('PayMongo QR Ph payment verified by the server.');
    await _recordPaidSale(
      amount: amountPesos,
      photoCount: photoCount,
      paymentMethod: 'PayMongo QR Ph',
    );
    setState(() {
      _showPaymentMethodPage = false;
      _paidPhotoPending = true;
      _message = 'Payment Recieved. Tap START PHOTO SESSION when ready.';
    });
    _showPaymentAcceptedNotice();
  }

  void _handleLogoTap() {
    if (!_settingsLoaded || _adminDialogOpen || _photoInProgress) return;
    final now = DateTime.now();
    final lastTap = _lastLogoTap;
    if (lastTap == null ||
        now.difference(lastTap) > const Duration(seconds: 2)) {
      _logoTapCount = 0;
    }
    _lastLogoTap = now;
    _logoTapCount++;
    _logoTapResetTimer?.cancel();
    if (_logoTapCount >= 3) {
      _logoTapCount = 0;
      _lastLogoTap = null;
      _idleTimer?.cancel();
      unawaited(_openAdmin());
      return;
    }
    _logoTapResetTimer = Timer(const Duration(seconds: 2), () {
      _logoTapCount = 0;
      _lastLogoTap = null;
    });
  }

  Future<void> _openAdmin({
    bool resumeAuthenticatedPicker = false,
    String? recoveredCustomerFramePath,
  }) async {
    if (!_settingsLoaded || !mounted) return;
    _liveWallpaperTimer?.cancel();
    unawaited(_refreshLocalDashboardAddresses());
    _passwordController.clear();
    _confirmController.clear();
    _welcomeController.text = _welcomeMessage;
    setState(() => _adminDialogOpen = true);
    var selectedLanguage = appLanguageNotifier.value;
    var savingLanguage = false;
    var cameraSelectionChanged = false;
    var authenticated = resumeAuthenticatedPicker;
    var busy = false;
    var selectingBorder = false;
    var loadingPrinters = false;
    var printingTestPage = false;
    var selectingIdleMedia = false;
    var errorMessage = '';
    var selectedBorderStyle = _photoBorderStyle;
    var selectedEventTheme = _eventTheme;
    var liveEffect = _liveEffect;
    var voiceGuidanceEnabled = _voiceGuidanceEnabled;
    var selectedCustomBorderPath = _customPhotoBorderPath;
    var selectedCustomerFrames = List<String>.from(_customerFrameGallery);
    if (recoveredCustomerFramePath != null &&
        !selectedCustomerFrames.contains(recoveredCustomerFramePath)) {
      selectedCustomerFrames.add(recoveredCustomerFramePath);
    }
    var selectedCustomerDecorations = List<String>.from(
      _customerDecorationGallery,
    );
    var printerAddress = _printerAddress;
    var printerType = _printerType;
    var receiptWidthDots = _receiptWidthDots;
    var receiptBrightness = _receiptBrightness;
    var receiptCutMode = _receiptCutMode;
    var printCopies = _printCopies;
    var countdownDuration = _countdownDuration;
    var chargeStartText = '$_chargeStartPercent';
    var chargeStopText = '$_chargeStopPercent';
    var previewDuration = _previewDuration;
    var idleTimeoutSeconds = _idleTimeoutSeconds;
    var fleetLocationSharingEnabled = _fleetLocationSharingEnabled;
    var cameraDirection = _cameraDirection;
    var testModeEnabled = _testModeEnabled;
    var pairedPrinters = _pairedPrinters;
    var brandLogoPath = _brandLogoPath;
    var brandLogoAnimation = _brandLogoAnimation;
    var liveWallpaperEnabled = _liveWallpaperEnabled;
    var idleScreenImagePath = _idleScreenImagePath;
    var idleScreenVideoPath = _idleScreenVideoPath;
    var idleVideoLoop = _idleVideoLoop;
    var rentModeEnabled = _rentModeEnabled;
    var walletPaymentEnabled =
        _walletPaymentEnabled && _activationAllowsGanap && _ganapQrPhAvailable;
    var payMongoPaymentsEnabled =
        _payMongoPaymentsEnabled && _activationAllowsPayMongo;
    var coinPriceText = '$_coinPricePesos';
    var payMongoAmountText = '$_payMongoAmountPesos';
    var aiStylesEnabled = _aiStylesEnabled;
    var aiCoinPaymentEnabled = _aiCoinPaymentEnabled;
    var aiQrPaymentEnabled = _aiQrPaymentEnabled;
    var aiStylePriceTexts = <int, String>{
      for (var photoCount = 1; photoCount <= 5; photoCount++)
        photoCount: '${_aiStylePricesPesos[photoCount] ?? 20}',
    };
    var walletQrPath = _walletQrPath;
    var checkingForUpdate = false;
    var updateStatus = '';
    AppUpdateManifest? checkedUpdate;
    const adminNavigationItems = <(String, IconData)>[
      ('Device & Fleet', Icons.devices_rounded),
      ('Payments', Icons.payments_rounded),
      ('Customer Experience', Icons.storefront_rounded),
      ('Photo Design', Icons.photo_library_rounded),
      ('Printer', Icons.print_rounded),
      ('App Updates', Icons.system_update_alt),
    ];
    final adminSettingsScrollController = ScrollController();
    var selectedAdminSection = adminNavigationItems.first.$1;
    final expandedAdminGroups = <String, bool>{
      'Local Browser Dashboard': true,
      'General': true,
      'Smart Charging': true,
      'Fleet Connection': true,
      'Camera': true,
    };

    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, refreshDialog) {
              final isSetup = !_adminPasswordConfigured;
              Widget adminSettingsGroup({
                required String title,
                required IconData icon,
                required List<Widget> children,
              }) {
                final expanded = expandedAdminGroups[title] ?? true;
                return Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x120F172A),
                        blurRadius: 10,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      Material(
                        color: const Color(0xFFF7F9FB),
                        child: InkWell(
                          onTap: () => refreshDialog(
                            () => expandedAdminGroups[title] = !expanded,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 16,
                            ),
                            child: Row(
                              children: [
                                Icon(icon, color: _ink, size: 23),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Text(
                                    title,
                                    style: const TextStyle(
                                      color: _ink,
                                      fontSize: 17,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                Icon(
                                  expanded
                                      ? Icons.keyboard_arrow_up_rounded
                                      : Icons.keyboard_arrow_down_rounded,
                                  color: _muted,
                                  size: 25,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (expanded)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: children,
                          ),
                        ),
                    ],
                  ),
                );
              }

              Widget adminSectionHeading(String label) => Padding(
                padding: const EdgeInsets.only(top: 18, bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        label.toUpperCase(),
                        style: const TextStyle(
                          color: _accent,
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.15,
                        ),
                      ),
                    ),
                    const SizedBox(width: 20),
                    Container(
                      width: 48,
                      height: 2,
                      decoration: BoxDecoration(
                        color: _outline,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ],
                ),
              );

              void navigateToAdminSection(String label) {
                if (adminSettingsScrollController.hasClients) {
                  adminSettingsScrollController.jumpTo(0);
                }
                refreshDialog(() => selectedAdminSection = label);
              }

              Future<void> chooseCustomBorder() async {
                refreshDialog(() {
                  selectingBorder = true;
                  errorMessage = '';
                });
                try {
                  final path = await _pickCustomPhotoBorder();
                  if (path == null || !dialogContext.mounted) return;
                  refreshDialog(() {
                    selectedCustomBorderPath = path;
                    selectedBorderStyle = PhotoBorderStyle.custom;
                  });
                } on Object catch (error) {
                  if (!dialogContext.mounted) return;
                  refreshDialog(() {
                    errorMessage = 'Could not load border image: $error';
                  });
                } finally {
                  if (dialogContext.mounted) {
                    refreshDialog(() => selectingBorder = false);
                  }
                }
              }

              Future<void> setFleetLocationSharing(bool enabled) async {
                if (!enabled) {
                  await _settings.saveFleetLocationSharing(false);
                  _fleetLocation = null;
                  _fleetLocationCapturedAt = null;
                  if (dialogContext.mounted) {
                    refreshDialog(() => fleetLocationSharingEnabled = false);
                  }
                  if (mounted) {
                    setState(() => _fleetLocationSharingEnabled = false);
                  }
                  unawaited(_reportFleetHeartbeat());
                  return;
                }
                refreshDialog(() {
                  busy = true;
                  errorMessage = '';
                });
                try {
                  if (!await Geolocator.isLocationServiceEnabled()) {
                    await Geolocator.openLocationSettings();
                    throw StateError(
                      'Turn on Location services, then enable location sharing again.',
                    );
                  }
                  var permission = await Geolocator.checkPermission();
                  if (permission == LocationPermission.denied) {
                    permission = await Geolocator.requestPermission();
                  }
                  if (permission != LocationPermission.whileInUse &&
                      permission != LocationPermission.always) {
                    throw StateError(
                      permission == LocationPermission.deniedForever
                          ? 'Location permission is blocked. Allow it in Android app settings.'
                          : 'Allow location access while using the app to share booth location.',
                    );
                  }
                  await _settings.saveFleetLocationSharing(true);
                  if (!mounted || !dialogContext.mounted) return;
                  setState(() {
                    _fleetLocationSharingEnabled = true;
                    _fleetLocation = null;
                    _fleetLocationCapturedAt = null;
                  });
                  refreshDialog(() => fleetLocationSharingEnabled = true);
                  _recordDashboardEvent(
                    'Location sharing enabled by the local admin.',
                  );
                  unawaited(_reportFleetHeartbeat());
                } on Object catch (error) {
                  if (dialogContext.mounted) {
                    refreshDialog(
                      () =>
                          errorMessage = 'Location sharing unavailable: $error',
                    );
                  }
                } finally {
                  if (dialogContext.mounted) {
                    refreshDialog(() => busy = false);
                  }
                }
              }

              Future<void> addCustomerDecoration() async {
                if (selectingBorder ||
                    selectedCustomerDecorations.length >=
                        _maxCustomerDecorationCount) {
                  return;
                }
                refreshDialog(() {
                  selectingBorder = true;
                  errorMessage = '';
                });
                try {
                  final path = await _pickPhotoDecoration();
                  if (path == null || !dialogContext.mounted) return;
                  refreshDialog(() => selectedCustomerDecorations.add(path));
                } on Object catch (error) {
                  if (!dialogContext.mounted) return;
                  refreshDialog(() {
                    errorMessage = 'Could not add decoration: $error';
                  });
                } finally {
                  if (dialogContext.mounted) {
                    refreshDialog(() => selectingBorder = false);
                  }
                }
              }

              Future<void> addCustomerFrame() async {
                if (selectingBorder) return;
                refreshDialog(() {
                  selectingBorder = true;
                  errorMessage = '';
                });
                try {
                  await _settings.markCustomerFramePickerPending();
                  final path = await _pickCustomPhotoBorder(
                    detectPhotoSlots: true,
                  );
                  if (path != null &&
                      dialogContext.mounted &&
                      !selectedCustomerFrames.contains(path)) {
                    refreshDialog(() => selectedCustomerFrames.add(path));
                  }
                } on Object catch (error) {
                  if (dialogContext.mounted) {
                    refreshDialog(
                      () =>
                          errorMessage = 'Could not add customer frame: $error',
                    );
                  }
                } finally {
                  await _settings.clearPendingCustomerFramePicker();
                  if (dialogContext.mounted) {
                    refreshDialog(() => selectingBorder = false);
                  }
                }
              }

              Future<void> chooseIdleImage() async {
                if (selectingIdleMedia) return;
                refreshDialog(() {
                  selectingIdleMedia = true;
                  errorMessage = '';
                });
                try {
                  final path = await _pickIdleScreenImage();
                  if (path != null && dialogContext.mounted) {
                    refreshDialog(() => idleScreenImagePath = path);
                  }
                } on Object catch (error) {
                  if (dialogContext.mounted) {
                    refreshDialog(
                      () => errorMessage =
                          'Could not load the home screen image: $error',
                    );
                  }
                } finally {
                  if (dialogContext.mounted) {
                    refreshDialog(() => selectingIdleMedia = false);
                  }
                }
              }

              Future<void> chooseBrandLogo() async {
                if (selectingIdleMedia) return;
                refreshDialog(() {
                  selectingIdleMedia = true;
                  errorMessage = '';
                });
                try {
                  final path = await _pickBrandLogo();
                  if (path != null && dialogContext.mounted) {
                    refreshDialog(() => brandLogoPath = path);
                  }
                } on Object catch (error) {
                  if (dialogContext.mounted) {
                    refreshDialog(
                      () => errorMessage = 'Could not load the logo: $error',
                    );
                  }
                } finally {
                  if (dialogContext.mounted) {
                    refreshDialog(() => selectingIdleMedia = false);
                  }
                }
              }

              Future<void> chooseIdleVideo() async {
                if (selectingIdleMedia) return;
                refreshDialog(() {
                  selectingIdleMedia = true;
                  errorMessage = '';
                });
                try {
                  final path = await _pickIdleScreenVideo();
                  if (path != null && dialogContext.mounted) {
                    refreshDialog(() => idleScreenVideoPath = path);
                  }
                } on Object catch (error) {
                  if (dialogContext.mounted) {
                    refreshDialog(
                      () => errorMessage =
                          'Could not load the home screen video: $error',
                    );
                  }
                } finally {
                  if (dialogContext.mounted) {
                    refreshDialog(() => selectingIdleMedia = false);
                  }
                }
              }

              Future<void> refreshPrinters() async {
                if (loadingPrinters || busy) return;
                refreshDialog(() {
                  loadingPrinters = true;
                  errorMessage = '';
                });
                try {
                  final printers = await _loadPairedPrinters();
                  if (!dialogContext.mounted) return;
                  refreshDialog(() {
                    pairedPrinters = printers;
                    _pairedPrinters = printers;
                    if (printerAddress != null &&
                        !printers.any(
                          (printer) => printer.address == printerAddress,
                        )) {
                      errorMessage = 'The saved printer is not paired. Pair it in Android Bluetooth settings.';
                    } else if (printers.isEmpty) {
                      errorMessage = 'No paired Bluetooth devices found. Pair the printer in Android Bluetooth settings first.';
                    }
                  });
                } on Object catch (error) {
                  if (dialogContext.mounted) {
                    refreshDialog(
                      () => errorMessage =
                          'Could not load paired Bluetooth devices: $error',
                    );
                  }
                } finally {
                  if (dialogContext.mounted) {
                    refreshDialog(() => loadingPrinters = false);
                  }
                }
              }

              Future<void> printTestPage() async {
                if (printingTestPage || printerAddress == null) return;
                refreshDialog(() {
                  printingTestPage = true;
                  errorMessage = '';
                });
                try {
                  final testRaster = <int>[];
                  for (var y = 0; y < 16; y++) {
                    for (var byteX = 0; byteX < 2; byteX++) {
                      var bits = 0;
                      for (var bit = 0; bit < 8; bit++) {
                        final x = byteX * 8 + bit;
                        if (x == 0 || x == 15 || y == 0 || y == 15 || x == y) {
                          bits |= 0x80 >> bit;
                        }
                      }
                      testRaster.add(bits);
                    }
                  }
                  await _kioskChannel.invokeMethod<void>(
                    'printEscPos',
                    <String, Object>{
                      'address': printerAddress!,
                      'data': Uint8List.fromList([
                        ...utf8.encode(
                          '\x1B@\x1Ba\x01PHOTOBOOTH\nRaster test\n',
                        ),
                        0x1B,
                        0x64,
                        3,
                        0x1D,
                        0x76,
                        0x30,
                        0,
                        2,
                        0,
                        16,
                        0,
                        ...testRaster,
                        0x1B,
                        0x64,
                        8,
                        0x1D,
                        0x56,
                        receiptCutMode.commandValue,
                      ]),
                      'copies': 1,
                    },
                  );
                  if (dialogContext.mounted) {
                    refreshDialog(
                      () => errorMessage =
                          'Raster test page sent to the printer.',
                    );
                  }
                  _setPrinterHealth(success: true);
                  _recordDashboardEvent('Bluetooth printer test succeeded.');
                } on Object catch (error) {
                  _setPrinterHealth(success: false, error: error);
                  _recordDashboardEvent(
                    'Bluetooth printer test failed: $error',
                  );
                  if (dialogContext.mounted) {
                    refreshDialog(
                      () => errorMessage = 'Printer test failed: $error',
                    );
                  }
                } finally {
                  if (dialogContext.mounted) {
                    refreshDialog(() => printingTestPage = false);
                  }
                }
              }

              Future<void> submit() async {
                if (busy || selectingBorder || selectingIdleMedia) return;
                refreshDialog(() {
                  busy = true;
                  errorMessage = '';
                });
                try {
                  if (!authenticated && isSetup) {
                    final password = _passwordController.text;
                    if (password.length < 8) {
                      throw const FormatException(
                        'Use a password with at least 8 characters.',
                      );
                    }
                    if (password != _confirmController.text) {
                      throw const FormatException('Passwords do not match.');
                    }
                    await _settings.createAdminPassword(password);
                    _adminPasswordConfigured = true;
                    unawaited(_initializeLocalDashboard());
                    try {
                      pairedPrinters = await _loadPairedPrinters();
                      _pairedPrinters = pairedPrinters;
                    } on Object catch (error) {
                      errorMessage =
                          'Could not load paired Bluetooth devices: $error';
                    }
                    refreshDialog(() => authenticated = true);
                  } else if (!authenticated) {
                    final valid = await _settings.verifyAdminPassword(
                      _passwordController.text,
                    );
                    if (!valid) {
                      throw const FormatException('Incorrect password.');
                    }
                    try {
                      pairedPrinters = await _loadPairedPrinters();
                      _pairedPrinters = pairedPrinters;
                    } on Object catch (error) {
                      errorMessage =
                          'Could not load paired Bluetooth devices: $error';
                    }
                    refreshDialog(() => authenticated = true);
                  } else {
                    final normalizedWelcome = _welcomeController.text.trim();
                    final chargeStartPercent = int.tryParse(chargeStartText);
                    final chargeStopPercent = int.tryParse(chargeStopText);
                    if (normalizedWelcome.isEmpty ||
                        normalizedWelcome.length > 36) {
                      throw const FormatException(
                        'Welcome text must contain 1 to 36 characters.',
                      );
                    }
                    final payMongoAmountPesos = int.tryParse(
                      payMongoAmountText.trim(),
                    );
                    final coinPricePesos = int.tryParse(coinPriceText.trim());
                    final aiStylePricesPesos = <int, int>{};
                    for (var photoCount = 1; photoCount <= 5; photoCount++) {
                      final price = int.tryParse(
                        (aiStylePriceTexts[photoCount] ?? '').trim(),
                      );
                      if (price == null || price < 1 || price > 100000) {
                        throw FormatException(
                          'AI conversion price for $photoCount photo(s) must be a whole peso amount from ₱1 to ₱100,000.',
                        );
                      }
                      aiStylePricesPesos[photoCount] = price;
                    }
                    if (coinPricePesos == null ||
                        coinPricePesos < 1 ||
                        coinPricePesos > _maxCoinPricePesos) {
                      throw const FormatException(
                        'Coin-slot price must be a whole peso amount from ₱1 to ₱100,000.',
                      );
                    }
                    if (payMongoAmountPesos == null ||
                        payMongoAmountPesos < 1 ||
                        payMongoAmountPesos > 100000) {
                      throw const FormatException(
                        'PayMongo QR Ph price must be a whole peso amount from ₱1 to ₱100,000.',
                      );
                    }
                    if (aiStylesEnabled &&
                        !aiCoinPaymentEnabled &&
                        !aiQrPaymentEnabled) {
                      throw const FormatException(
                        'Enable coin or QR PH payment before offering paid AI styles.',
                      );
                    }
                    if (aiStylesEnabled &&
                        aiQrPaymentEnabled &&
                        !_activationAllowsPayMongo) {
                      throw const FormatException(
                        'AI QR PH payment requires PayMongo activation.',
                      );
                    }
                    if (chargeStartPercent == null ||
                        chargeStopPercent == null ||
                        chargeStartPercent < 0 ||
                        chargeStartPercent > 99 ||
                        chargeStopPercent < 1 ||
                        chargeStopPercent > 100 ||
                        chargeStartPercent >= chargeStopPercent) {
                      throw const FormatException(
                        'Charging start must be 0–99%, and stop must be 1–100% and higher than start.',
                      );
                    }
                    await _settings.savePhotoBorder(
                      selectedBorderStyle,
                      selectedCustomBorderPath,
                    );
                    await _settings.saveCustomerFrameGallery(
                      selectedCustomerFrames,
                    );
                    await _settings.saveCustomerDecorationGallery(
                      selectedCustomerDecorations,
                    );
                    await _settings.saveRentModeEnabled(rentModeEnabled);
                    await _settings.saveBrandLogo(brandLogoPath);
                    await _settings.saveBrandLogoAnimation(brandLogoAnimation);
                    await _settings.saveLiveWallpaperEnabled(
                      liveWallpaperEnabled,
                    );
                    await _settings.savePrinterType(printerType.name);
                    await _settings.saveReceiptWidthDots(receiptWidthDots);
                    await _settings.saveReceiptBrightness(receiptBrightness);
                    await _settings.saveReceiptCutMode(receiptCutMode);
                    await _settings.saveBoothOptions(
                      autoPrint: false,
                      printerAddress: printerAddress,
                      printCopies: printCopies,
                      countdownDuration: countdownDuration,
                      previewDuration: previewDuration,
                      welcomeMessage: normalizedWelcome,
                      idleScreenImage: idleScreenImagePath,
                      idleScreenVideo: idleScreenVideoPath,
                      idleVideoLoop: idleVideoLoop,
                      testModeEnabled: testModeEnabled,
                      cameraDirection: cameraDirection.name,
                      walletPaymentEnabled: walletPaymentEnabled,
                      walletQrPath: walletQrPath,
                      eventTheme: selectedEventTheme,
                      voiceGuidanceEnabled: voiceGuidanceEnabled,
                      liveEffect: liveEffect,
                    );
                    await _settings.savePayMongoPaymentsEnabled(
                      payMongoPaymentsEnabled,
                    );
                    await _settings.savePayMongoAmountPesos(
                      payMongoAmountPesos,
                    );
                    await _settings.saveCoinPricePesos(coinPricePesos);
                    await _settings.saveAiStylesEnabled(aiStylesEnabled);
                    await _settings.saveAiCoinPaymentEnabled(
                      aiCoinPaymentEnabled,
                    );
                    await _settings.saveAiQrPaymentEnabled(aiQrPaymentEnabled);
                    await _settings.saveAiStylePricesPesos(aiStylePricesPesos);
                    await _settings.saveIdleTimeout(idleTimeoutSeconds);
                    await _settings.saveFleetLocationSharing(
                      fleetLocationSharingEnabled,
                    );
                    await _settings.saveChargeThresholds(
                      startPercent: chargeStartPercent,
                      stopPercent: chargeStopPercent,
                    );
                    await _settings.verifyAdminSettings({
                      'auto_print': false,
                      'photo_border_style': selectedBorderStyle.name,
                      'custom_photo_border_path': selectedCustomBorderPath,
                      'customer_frame_gallery': selectedCustomerFrames,
                      'customer_decoration_gallery':
                          selectedCustomerDecorations,
                      'rent_mode_enabled': rentModeEnabled,
                      'brand_logo_path': brandLogoPath,
                      'brand_logo_animation': brandLogoAnimation.name,
                      'live_wallpaper_enabled': liveWallpaperEnabled,
                      'printer_type': printerType.name,
                      'printer_address': printerAddress,
                      'receipt_width_dots': receiptWidthDots,
                      'receipt_brightness': receiptBrightness,
                      'receipt_cut_mode': receiptCutMode.name,
                      'print_copies': printCopies,
                      'countdown_duration': countdownDuration,
                      'charge_start_percent': chargeStartPercent,
                      'charge_stop_percent': chargeStopPercent,
                      'preview_duration': previewDuration,
                      'kiosk_idle_timeout': idleTimeoutSeconds,
                      'fleet_location_sharing': fleetLocationSharingEnabled,
                      'welcome_message': normalizedWelcome,
                      'idle_screen_image': idleScreenImagePath,
                      'idle_screen_video': idleScreenVideoPath,
                      'idle_screen_video_loop': idleVideoLoop,
                      'test_mode_enabled': testModeEnabled,
                      'camera_direction': cameraDirection.name,
                      'wallet_payment_enabled': walletPaymentEnabled,
                      'wallet_qr_path': walletQrPath,
                      'booth_event_theme': selectedEventTheme.name,
                      'voice_guidance_enabled': voiceGuidanceEnabled,
                      'live_camera_effect': liveEffect.name,
                      'paymongo_payments_enabled': payMongoPaymentsEnabled,
                      'paymongo_amount_pesos': payMongoAmountPesos,
                      'coin_price_pesos': coinPricePesos,
                      'ai_styles_enabled': aiStylesEnabled,
                      'ai_coin_payment_enabled': aiCoinPaymentEnabled,
                      'ai_qr_payment_enabled': aiQrPaymentEnabled,
                      'ai_style_price_pesos': aiStylePricesPesos[1]!,
                      for (final entry in aiStylePricesPesos.entries)
                        'ai_style_price_pesos_${entry.key}': entry.value,
                    });
                    cameraSelectionChanged =
                        cameraDirection != _cameraDirection;
                    if (!mounted || !dialogContext.mounted) return;
                    setState(() {
                      _cameraDirection = cameraDirection;
                      _photoBorderStyle = selectedBorderStyle;
                      _eventTheme = selectedEventTheme;
                      _liveEffect = liveEffect;
                      _voiceGuidanceEnabled = voiceGuidanceEnabled;
                      _customPhotoBorderPath = selectedCustomBorderPath;
                      _customerFrameGallery = selectedCustomerFrames;
                      _customerDecorationGallery = selectedCustomerDecorations;
                      _printerAddress = printerAddress;
                      _printerType = printerType;
                      _receiptWidthDots = receiptWidthDots;
                      _receiptBrightness = receiptBrightness;
                      _receiptCutMode = receiptCutMode;
                      _printCopies = printCopies;
                      _countdownDuration = countdownDuration;
                      _chargeStartPercent = chargeStartPercent;
                      _chargeStopPercent = chargeStopPercent;
                      _previewDuration = previewDuration;
                      _idleTimeoutSeconds = idleTimeoutSeconds;
                      _fleetLocationSharingEnabled =
                          fleetLocationSharingEnabled;
                      _welcomeMessage = normalizedWelcome;
                      _brandLogoPath = brandLogoPath;
                      _brandLogoAnimation = brandLogoAnimation;
                      _liveWallpaperEnabled = liveWallpaperEnabled;
                      if (!liveWallpaperEnabled) {
                        _showLiveWallpaperScreen = false;
                      }
                      _idleScreenImagePath = idleScreenImagePath;
                      _idleScreenVideoPath = idleScreenVideoPath;
                      _idleVideoLoop = idleVideoLoop;
                      _testModeEnabled = testModeEnabled;
                      _rentModeEnabled = rentModeEnabled;
                      _paidPhotoPending = false;
                      _coinPaymentReady = false;
                      _walletPaymentEnabled = walletPaymentEnabled;
                      _payMongoPaymentsEnabled = payMongoPaymentsEnabled;
                      _coinPricePesos = coinPricePesos;
                      _payMongoAmountPesos = payMongoAmountPesos;
                      _aiStylesEnabled = aiStylesEnabled;
                      _aiCoinPaymentEnabled = aiCoinPaymentEnabled;
                      _aiQrPaymentEnabled = aiQrPaymentEnabled;
                      _aiStylePricesPesos = aiStylePricesPesos;
                      _walletQrPath = walletQrPath;
                      _message = 'Settings saved.';
                    });
                    unawaited(_syncBatteryStatus());
                    if (!voiceGuidanceEnabled) {
                      _voiceGuidanceError = null;
                      unawaited(_stopVoiceGuidance());
                    } else {
                      _voiceGuidanceError = null;
                    }
                    if (cameraSelectionChanged) {
                      await _applyCameraSelection(cameraDirection);
                      cameraSelectionChanged = false;
                    }
                    if (!dialogContext.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Settings saved.')),
                    );
                  }
                } on Object catch (error) {
                  if (!dialogContext.mounted) return;
                  refreshDialog(() {
                    errorMessage = error is FormatException
                        ? error.message
                        : 'Could not save settings: $error';
                  });
                } finally {
                  if (dialogContext.mounted) {
                    refreshDialog(() => busy = false);
                  }
                }
              }

              Future<void> toggleKioskMode() async {
                if (busy || selectingBorder || selectingIdleMedia) return;
                final enable = !_kioskActive;
                refreshDialog(() {
                  busy = true;
                  errorMessage = '';
                });
                try {
                  var active = false;
                  if (enable) {
                    final snapshot = await _kioskPermissionService.refresh();
                    final checks = await _runKioskPreflight();
                    if (!snapshot.criticalPermissionsGranted ||
                        checks['Camera working'] != true ||
                        checks['Storage writable'] != true) {
                      throw StateError(
                        'Complete operator setup and pass the camera and '
                        'storage checks before going live.',
                      );
                    }
                    active = await _kioskMode.enter();
                  } else {
                    await _kioskMode.exit();
                  }
                  if (active != enable) {
                    throw StateError(
                      enable
                          ? 'Android did not activate Lock Task Mode.'
                          : 'Android did not exit Lock Task Mode.',
                    );
                  }
                  if (!mounted || !dialogContext.mounted) return;
                  setState(() {
                    _kioskActive = enable;
                    _message = enable
                        ? 'Kiosk mode enabled.'
                        : 'Logged out of kiosk mode.';
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        enable ? 'Kiosk mode enabled.' : 'Kiosk mode disabled.',
                      ),
                    ),
                  );
                } on Object catch (error) {
                  if (!dialogContext.mounted) return;
                  refreshDialog(() {
                    errorMessage = error is PlatformException
                        ? error.message ?? error.code
                        : 'Could not change kiosk mode: $error';
                  });
                } finally {
                  if (dialogContext.mounted) {
                    refreshDialog(() => busy = false);
                  }
                }
              }

              Future<void> checkForUpdate() async {
                if (checkingForUpdate) return;
                refreshDialog(() {
                  checkingForUpdate = true;
                  checkedUpdate = null;
                  updateStatus = '';
                  errorMessage = '';
                });
                try {
                  final (manifest, installedVersionCode) =
                      await _checkForAppUpdate();
                  final update = manifest.isNewerThan(installedVersionCode)
                      ? manifest
                      : null;
                  if (!dialogContext.mounted) return;
                  refreshDialog(() {
                    checkedUpdate = update;
                    updateStatus = update != null
                        ? 'Update available: build ${manifest.versionCode} '
                              '(installed build $installedVersionCode).'
                        : manifest.versionCode == installedVersionCode
                        ? 'No update: installed and published builds are both '
                              '$installedVersionCode.'
                        : 'No update: published build ${manifest.versionCode} '
                              'is older than installed build '
                              '$installedVersionCode. Update the public '
                              'manifest after publishing the newer APK.';
                  });
                } on Object catch (error) {
                  if (!dialogContext.mounted) return;
                  refreshDialog(() {
                    updateStatus = '';
                    errorMessage = 'Update check failed: $error';
                  });
                } finally {
                  if (dialogContext.mounted) {
                    refreshDialog(() => checkingForUpdate = false);
                  }
                }
              }

              Future<void> downloadUpdate() async {
                final update = checkedUpdate;
                if (update == null) return;
                await _startAppUpdate(update);
              }

              if (!authenticated) {
                return AlertDialog(
                  backgroundColor: Colors.white,
                  surfaceTintColor: Colors.transparent,
                  insetPadding: EdgeInsets.symmetric(
                    horizontal: MediaQuery.sizeOf(dialogContext).width < 400
                        ? 12
                        : 40,
                    vertical: 16,
                  ),
                  constraints: const BoxConstraints(maxWidth: 420),
                  title: Text(
                    isSetup ? 'Create admin password' : 'Admin login',
                  ),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _passwordController,
                          obscureText: true,
                          autofocus: true,
                          keyboardType: TextInputType.visiblePassword,
                          textCapitalization: TextCapitalization.none,
                          autocorrect: false,
                          enableSuggestions: false,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) {
                            if (!busy) unawaited(submit());
                          },
                          decoration: InputDecoration(
                            labelText: translateAppText(
                              isSetup
                                  ? 'New password (8+ characters)'
                                  : 'Password',
                              appLanguageNotifier.value,
                            ),
                          ),
                        ),
                        if (isSetup)
                          TextField(
                            controller: _confirmController,
                            obscureText: true,
                            keyboardType: TextInputType.visiblePassword,
                            textCapitalization: TextCapitalization.none,
                            autocorrect: false,
                            enableSuggestions: false,
                            decoration: InputDecoration(
                              labelText: translateAppText(
                                'Confirm password',
                                appLanguageNotifier.value,
                              ),
                            ),
                          ),
                        if (errorMessage.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(
                            errorMessage,
                            style: const TextStyle(color: Color(0xFFB42318)),
                          ),
                        ],
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => Navigator.of(dialogContext).pop(),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: busy ? null : submit,
                      child: busy
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(isSetup ? 'Create password' : 'Sign in'),
                    ),
                  ],
                );
              }

              return PopScope(
                canPop: false,
                child: AlertDialog(
                  backgroundColor: Colors.white,
                  surfaceTintColor: Colors.transparent,
                  insetPadding: EdgeInsets.zero,
                  constraints: const BoxConstraints.expand(),
                  titlePadding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
                  contentPadding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
                  actionsPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                  actionsAlignment: MainAxisAlignment.center,
                  title: Row(
                    children: [
                      IconButton(
                        onPressed: busy
                            ? null
                            : () => Navigator.of(dialogContext).pop(),
                        icon: const Icon(Icons.arrow_back_rounded),
                        color: _ink,
                        tooltip: translateAppText(
                          'Exit admin settings',
                          appLanguageNotifier.value,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          authenticated
                              ? 'Photobooth settings'
                              : isSetup
                              ? 'Create admin password'
                              : 'Admin login',
                          style: const TextStyle(
                            color: _ink,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  content: SingleChildScrollView(
                    controller: adminSettingsScrollController,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!authenticated) ...[
                          TextField(
                            controller: _passwordController,
                            obscureText: true,
                            autofocus: true,
                            keyboardType: TextInputType.visiblePassword,
                            textCapitalization: TextCapitalization.none,
                            autocorrect: false,
                            enableSuggestions: false,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) {
                              if (!busy) unawaited(submit());
                            },
                            decoration: InputDecoration(
                              labelText: translateAppText(
                                isSetup
                                    ? 'New password (8+ characters)'
                                    : 'Password',
                                appLanguageNotifier.value,
                              ),
                            ),
                          ),
                          if (isSetup)
                            TextField(
                              controller: _confirmController,
                              obscureText: true,
                              keyboardType: TextInputType.visiblePassword,
                              textCapitalization: TextCapitalization.none,
                              autocorrect: false,
                              enableSuggestions: false,
                              decoration: InputDecoration(
                                labelText: translateAppText(
                                  'Confirm password',
                                  appLanguageNotifier.value,
                                ),
                              ),
                            ),
                        ] else ...[
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                for (final (label, icon)
                                    in adminNavigationItems)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      right: 10,
                                      bottom: 4,
                                    ),
                                    child: SizedBox(
                                      width: switch (label) {
                                        'Device & Fleet' => 205,
                                        'Payments' => 150,
                                        'Customer Experience' => 220,
                                        'Photo Design' => 175,
                                        'Printer' => 140,
                                        _ => 170,
                                      },
                                      height: 58,
                                      child: Material(
                                        color: selectedAdminSection == label
                                            ? const Color(0xFF2F80ED)
                                            : const Color(0xFFF1F4F7),
                                        borderRadius: BorderRadius.circular(13),
                                        child: InkWell(
                                          borderRadius: BorderRadius.circular(
                                            13,
                                          ),
                                          onTap: () =>
                                              navigateToAdminSection(label),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 14,
                                            ),
                                            child: Row(
                                              children: [
                                                Icon(
                                                  icon,
                                                  size: 21,
                                                  color:
                                                      selectedAdminSection ==
                                                          label
                                                      ? Colors.white
                                                      : _ink,
                                                ),
                                                const SizedBox(width: 11),
                                                Expanded(
                                                  child: Text(
                                                    label,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      color:
                                                          selectedAdminSection ==
                                                              label
                                                          ? Colors.white
                                                          : _ink,
                                                      fontSize: 14,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (selectedAdminSection == 'Device & Fleet') ...[
                            adminSettingsGroup(
                              title: 'Local Browser Dashboard',
                              icon: Icons.language_rounded,
                              children: [
                                const Text(
                                  'Open one of these addresses on a device connected to the same Wi-Fi. Sign in with this admin password.',
                                  style: TextStyle(color: _muted, fontSize: 14),
                                ),
                                const SizedBox(height: 10),
                                if (_dashboardUrls.isEmpty)
                                  Text(
                                    _dashboardError ??
                                        (_dashboardStarting
                                            ? 'Starting dashboard...'
                                            : 'No Wi-Fi address is available. Connect this device to Wi-Fi and reopen settings.'),
                                    style: TextStyle(
                                      color: _dashboardError == null
                                          ? _muted
                                          : const Color(0xFFB42318),
                                    ),
                                  )
                                else
                                  ..._dashboardUrls.map(
                                    (url) => Container(
                                      margin: const EdgeInsets.only(bottom: 6),
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF5F8FA),
                                        borderRadius: BorderRadius.circular(9),
                                        boxShadow: const [
                                          BoxShadow(
                                            color: Color(0x100F172A),
                                            blurRadius: 6,
                                            offset: Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: SelectableText(
                                              url,
                                              style: const TextStyle(
                                                color: _ink,
                                                fontSize: 16,
                                              ),
                                            ),
                                          ),
                                          IconButton(
                                            onPressed: () async {
                                              await Clipboard.setData(
                                                ClipboardData(text: url),
                                              );
                                              if (dialogContext.mounted) {
                                                ScaffoldMessenger.of(
                                                  dialogContext,
                                                ).showSnackBar(
                                                  const SnackBar(
                                                    content: Text(
                                                      'Dashboard address copied.',
                                                    ),
                                                  ),
                                                );
                                              }
                                            },
                                            icon: const Icon(
                                              Icons.copy_rounded,
                                              size: 20,
                                            ),
                                            tooltip: translateAppText(
                                              'Copy address',
                                              appLanguageNotifier.value,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Use only on a trusted private Wi-Fi network. Browser traffic is not encrypted.',
                                  style: TextStyle(color: _muted, fontSize: 12),
                                ),
                              ],
                            ),
                            adminSettingsGroup(
                              title: 'General',
                              icon: Icons.settings_rounded,
                              children: [
                                Text(
                                  'App language',
                                  style: const TextStyle(
                                    color: _ink,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Choose the language used throughout the app.',
                                  style: TextStyle(color: _muted, fontSize: 13),
                                ),
                                const SizedBox(height: 10),
                                SegmentedButton<AppLanguage>(
                                  segments: const [
                                    ButtonSegment<AppLanguage>(
                                      value: AppLanguage.english,
                                      label: Text('English'),
                                    ),
                                    ButtonSegment<AppLanguage>(
                                      value: AppLanguage.tagalog,
                                      label: Text('Tagalog'),
                                    ),
                                  ],
                                  selected: {selectedLanguage},
                                  showSelectedIcon: false,
                                  onSelectionChanged: busy || savingLanguage
                                      ? null
                                      : (selection) async {
                                          final language = selection.single;
                                          if (language == selectedLanguage) {
                                            return;
                                          }
                                          refreshDialog(
                                            () => savingLanguage = true,
                                          );
                                          try {
                                            await _settings.saveAppLanguage(
                                              language,
                                            );
                                          } on Object catch (
                                            error,
                                            stackTrace
                                          ) {
                                            debugPrint(
                                              'Could not save app language: '
                                              '$error\n$stackTrace',
                                            );
                                            if (dialogContext.mounted) {
                                              refreshDialog(
                                                () => savingLanguage = false,
                                              );
                                              ScaffoldMessenger.of(
                                                dialogContext,
                                              ).showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                    'Could not save the language setting: $error',
                                                  ),
                                                ),
                                              );
                                            }
                                            return;
                                          }
                                          if (!dialogContext.mounted) return;
                                          appLanguageNotifier.value = language;
                                          refreshDialog(() {
                                            selectedLanguage = language;
                                            savingLanguage = false;
                                          });
                                        },
                                ),
                                if (savingLanguage) ...[
                                  const SizedBox(height: 8),
                                  const LinearProgressIndicator(),
                                ],
                                const SizedBox(height: 18),
                                const Text(
                                  'ESP32 connection:',
                                  style: TextStyle(
                                    color: _muted,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Bluetooth Low Energy',
                                  style: TextStyle(
                                    color: _ink,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Enable Bluetooth and power on the ESP32. Requires the PhotoboothSmartChargeServer sketch for smart charging.',
                                  style: TextStyle(color: _muted, fontSize: 13),
                                ),
                                const SizedBox(height: 16),
                                OutlinedButton.icon(
                                  onPressed:
                                      busy ||
                                          selectingBorder ||
                                          selectingIdleMedia
                                      ? null
                                      : () => _showKioskSetup(dialogContext),
                                  icon: const Icon(
                                    Icons.admin_panel_settings_outlined,
                                  ),
                                  label: const Text(
                                    'Operator setup & diagnostics',
                                  ),
                                ),
                                const SizedBox(height: 8),
                                OutlinedButton.icon(
                                  onPressed: busy
                                      ? null
                                      : () => unawaited(
                                          _replaceActivationLicense(
                                            dialogContext,
                                          ),
                                        ),
                                  icon: const Icon(
                                    Icons.verified_user_outlined,
                                  ),
                                  label: const Text(
                                    'Update activation features',
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Included: $_activationFeatureSummary',
                                  style: const TextStyle(
                                    color: _muted,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                            adminSettingsGroup(
                              title: 'Smart Charging',
                              icon: Icons.bolt_rounded,
                              children: [
                                const Text(
                                  'Requires the PhotoboothSmartChargeServer sketch on the ESP32. Charging starts below the start level and stops when the battery reaches the stop level.',
                                  style: TextStyle(color: _muted, fontSize: 13),
                                ),
                                const SizedBox(height: 14),
                                LayoutBuilder(
                                  builder: (context, constraints) {
                                    final fields = [
                                      (
                                        'Start charging at (%)',
                                        'charge-start-$_chargeStartPercent',
                                        chargeStartText,
                                        'Start charging when battery level is below this percentage.',
                                        (String value) =>
                                            chargeStartText = value,
                                      ),
                                      (
                                        'Stop charging at (%)',
                                        'charge-stop-$_chargeStopPercent',
                                        chargeStopText,
                                        'Stop charging when battery level reaches this percentage.',
                                        (String value) =>
                                            chargeStopText = value,
                                      ),
                                    ];
                                    return Wrap(
                                      spacing: 14,
                                      runSpacing: 12,
                                      children: [
                                        for (final field in fields)
                                          SizedBox(
                                            width: constraints.maxWidth > 560
                                                ? (constraints.maxWidth - 14) /
                                                      2
                                                : constraints.maxWidth,
                                            child: DecoratedBox(
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFF8FAFC),
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                boxShadow: const [
                                                  BoxShadow(
                                                    color: Color(0x100F172A),
                                                    blurRadius: 6,
                                                    offset: Offset(0, 2),
                                                  ),
                                                ],
                                              ),
                                              child: Padding(
                                                padding: const EdgeInsets.all(
                                                  14,
                                                ),
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      field.$1,
                                                      style: const TextStyle(
                                                        color: _muted,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 8),
                                                    TextFormField(
                                                      key: ValueKey(field.$2),
                                                      initialValue: field.$3,
                                                      keyboardType:
                                                          TextInputType.number,
                                                      decoration:
                                                          const InputDecoration(
                                                            isDense: true,
                                                            contentPadding:
                                                                EdgeInsets.all(
                                                                  12,
                                                                ),
                                                          ),
                                                      onChanged: field.$5,
                                                    ),
                                                    const SizedBox(height: 6),
                                                    Text(
                                                      field.$4,
                                                      style: const TextStyle(
                                                        color: _muted,
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    );
                                  },
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  _batteryReportSucceeded
                                      ? 'Battery reports are communicating.'
                                      : _batterySyncError == null
                                      ? 'Waiting for a successful battery report.'
                                      : 'Smart charging error: $_batterySyncError',
                                  style: TextStyle(
                                    color: _batterySyncError == null
                                        ? _muted
                                        : const Color(0xFFB42318),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              margin: const EdgeInsets.only(bottom: 14),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(11),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x100F172A),
                                    blurRadius: 7,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.location_on_rounded,
                                    color: _ink,
                                    size: 23,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Share booth location with SnapLab Fleet',
                                          style: TextStyle(
                                            color: _ink,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        const Text(
                                          'Shares approximate coordinates only while the app is open. Location permission is required.',
                                          style: TextStyle(
                                            color: _muted,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Switch(
                                    value: fleetLocationSharingEnabled,
                                    onChanged: busy
                                        ? null
                                        : setFleetLocationSharing,
                                  ),
                                ],
                              ),
                            ),
                            adminSettingsGroup(
                              title: 'Fleet Connection',
                              icon: Icons.cloud_sync_rounded,
                              children: [
                                Text(
                                  _fleetReportStatus,
                                  style: TextStyle(
                                    color:
                                        _fleetReportStatus.startsWith(
                                          'Fleet report failed:',
                                        )
                                        ? const Color(0xFFB42318)
                                        : _muted,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                OutlinedButton.icon(
                                  onPressed: busy || !_activationActive
                                      ? null
                                      : () async {
                                          refreshDialog(() {
                                            _fleetReportStatus =
                                                'Checking connection to Fleet…';
                                          });
                                          await _reportFleetHeartbeat();
                                          if (dialogContext.mounted) {
                                            refreshDialog(() {});
                                          }
                                        },
                                  icon: const Icon(Icons.sync),
                                  label: const Text(
                                    'Check Fleet connection now',
                                  ),
                                ),
                              ],
                            ),
                            adminSettingsGroup(
                              title: 'Camera',
                              icon: Icons.photo_camera_rounded,
                              children: [
                                DropdownButtonFormField<CameraLensDirection>(
                                  key: ValueKey(cameraDirection),
                                  initialValue: cameraDirection,
                                  decoration: InputDecoration(
                                    labelText: translateAppText(
                                      'Camera',
                                      appLanguageNotifier.value,
                                    ),
                                  ),
                                  items: const [
                                    DropdownMenuItem(
                                      value: CameraLensDirection.back,
                                      child: Text('Back camera'),
                                    ),
                                    DropdownMenuItem(
                                      value: CameraLensDirection.front,
                                      child: Text('Front camera'),
                                    ),
                                  ],
                                  onChanged: busy
                                      ? null
                                      : (direction) {
                                          if (direction != null) {
                                            refreshDialog(
                                              () => cameraDirection = direction,
                                            );
                                          }
                                        },
                                ),
                              ],
                            ),
                          ],
                          if (selectedAdminSection == 'Payments') ...[
                            adminSectionHeading('Payments'),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Enable free test mode'),
                              subtitle: Text(
                                _esp32Detected
                                    ? 'Disabled because the ESP32 has been detected.'
                                    : 'Shows a free photo button on this device. Turn off before serving customers.',
                              ),
                              value: testModeEnabled,
                              onChanged: _esp32Detected || busy
                                  ? null
                                  : (enabled) => refreshDialog(
                                      () => testModeEnabled = enabled,
                                    ),
                            ),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Enable rent mode'),
                              subtitle: const Text(
                                'Do not collect payment. The customer can start a session after choosing photos.',
                              ),
                              value: rentModeEnabled,
                              onChanged: busy
                                  ? null
                                  : (enabled) => refreshDialog(
                                      () => rentModeEnabled = enabled,
                                    ),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              key: const ValueKey('coin-price'),
                              initialValue: coinPriceText,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: translateAppText(
                                  'Coin-slot price per session (₱)',
                                  appLanguageNotifier.value,
                                ),
                                helperText: translateAppText(
                                  'Whole pesos, ₱1–₱100,000. The ESP32 must report the same number of credits (1 credit per ₱1).',
                                  appLanguageNotifier.value,
                                ),
                              ),
                              onChanged: (value) =>
                                  refreshDialog(() => coinPriceText = value),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Coin-slot pricing is separate from QR payment pricing. Ganap QRPh retains its existing ₱20 checkout amount.',
                              style: TextStyle(color: _muted, fontSize: 12),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'PAID AI PHOTO STYLES',
                              style: TextStyle(
                                color: _accent,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.2,
                              ),
                            ),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Offer paid AI photo styles'),
                              subtitle: const Text(
                                'Show Anime, Pencil Sketch, 3D Cartoon, Chibi, Pop Art, and Line Art after the original photo is printed.',
                              ),
                              value: aiStylesEnabled,
                              onChanged: busy
                                  ? null
                                  : (enabled) => refreshDialog(
                                      () => aiStylesEnabled = enabled,
                                    ),
                            ),
                            const Text(
                              'Set a separate total price for each photo count. One paid conversion stylizes every photo in that session.',
                              style: TextStyle(color: _muted, fontSize: 12),
                            ),
                            for (
                              var photoCount = 1;
                              photoCount <= 5;
                              photoCount++
                            )
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: TextFormField(
                                  key: ValueKey('ai-style-price-$photoCount'),
                                  initialValue:
                                      aiStylePriceTexts[photoCount] ?? '20',
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(
                                    labelText:
                                        'AI conversion price for $photoCount photo(s) (₱)',
                                    helperText:
                                        'One total charge for all $photoCount generated photo(s).',
                                  ),
                                  onChanged: (value) => refreshDialog(
                                    () => aiStylePriceTexts[photoCount] = value,
                                  ),
                                ),
                              ),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Allow coin payment for AI'),
                              subtitle: Text(
                                _esp32Detected
                                    ? 'Customer pays with coin-slot credits.'
                                    : 'Enable when the ESP32 coin slot is connected.',
                              ),
                              value: aiCoinPaymentEnabled,
                              onChanged: busy
                                  ? null
                                  : (enabled) => refreshDialog(
                                      () => aiCoinPaymentEnabled = enabled,
                                    ),
                            ),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Allow QR PH payment for AI'),
                              subtitle: Text(
                                _activationAllowsPayMongo
                                    ? 'Customer pays with a PayMongo QR PH checkout.'
                                    : 'Unavailable until PayMongo QR PH is enabled for this booth activation.',
                              ),
                              value: aiQrPaymentEnabled,
                              onChanged: busy || !_activationAllowsPayMongo
                                  ? null
                                  : (enabled) => refreshDialog(
                                      () => aiQrPaymentEnabled = enabled,
                                    ),
                            ),
                            if (_activationAllowsGanap) ...[
                              const SizedBox(height: 12),
                              const Text(
                                'GANAP QRPH PAYMENT',
                                style: TextStyle(
                                  color: _accent,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Allow Ganap QRPh payments'),
                                subtitle: Text(
                                  _ganapQrPhAvailable
                                      ? 'Enable Ganap QR Ph payments for this booth.'
                                      : 'Unavailable: Ganap currently requires at least ₱200, while its checkout amount is ₱20. Payments stay disabled to prevent an incorrect charge.',
                                ),
                                value:
                                    walletPaymentEnabled && _ganapQrPhAvailable,
                                onChanged: busy || !_ganapQrPhAvailable
                                    ? null
                                    : (enabled) => refreshDialog(
                                        () => walletPaymentEnabled = enabled,
                                      ),
                              ),
                              const Text(
                                'Checkout requires the Ganap project UUID and signing secret to be set in the private Hostinger configuration.',
                                style: TextStyle(color: _muted, fontSize: 12),
                              ),
                              const SizedBox(height: 16),
                            ],
                            if (_activationAllowsPayMongo) ...[
                              const Text(
                                'PAYMONGO QRPH PAYMENT',
                                style: TextStyle(
                                  color: _accent,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text(
                                  'Allow PayMongo QR Ph payments',
                                ),
                                subtitle: const Text(
                                  'Controls QR Ph payments only. Coin-slot sessions use the separate coin-slot price above.',
                                ),
                                value: payMongoPaymentsEnabled,
                                onChanged: busy
                                    ? null
                                    : (enabled) => refreshDialog(
                                        () => payMongoPaymentsEnabled = enabled,
                                      ),
                              ),
                              TextFormField(
                                key: const ValueKey('paymongo-amount'),
                                initialValue: payMongoAmountText,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  labelText: translateAppText(
                                    'PayMongo QR Ph amount (₱)',
                                    appLanguageNotifier.value,
                                  ),
                                  helperText: translateAppText(
                                    'Whole pesos, ₱1–₱100,000. This is separate from the coin-slot price.',
                                    appLanguageNotifier.value,
                                  ),
                                ),
                                onChanged: (value) => refreshDialog(
                                  () => payMongoAmountText = value,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'PayMongo API keys are kept on the Hostinger server. Upload paymongo_common.php, paymongo_checkout.php, and paymongo_status.php after configuring the private server keys.',
                                style: TextStyle(color: _muted, fontSize: 12),
                              ),
                              const SizedBox(height: 8),
                            ],
                          ],
                          if (selectedAdminSection ==
                              'Customer Experience') ...[
                            adminSectionHeading('Customer Experience'),
                            const Text(
                              'ONLINE PHOTO DOWNLOAD',
                              style: TextStyle(
                                color: _accent,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.2,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Preconfigured for activated booths. The app requests a short-lived upload credential from the secure server; no upload token needs to be entered or stored on this device. Download links expire after 7 days.',
                              style: TextStyle(color: _muted, fontSize: 12),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              defaultSoftCopyUploadEndpoint,
                              style: TextStyle(
                                color: _muted,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _welcomeController,
                              maxLength: 36,
                              decoration: InputDecoration(
                                labelText: translateAppText(
                                  'Customer welcome message',
                                  appLanguageNotifier.value,
                                ),
                                helperText: translateAppText(
                                  'Displayed on the customer screen',
                                  appLanguageNotifier.value,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'BOOTH LOGO',
                              style: TextStyle(
                                color: _accent,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.2,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Shown on the idle home screen and customer photo-count screen.',
                              style: TextStyle(color: _muted, fontSize: 12),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              width: double.infinity,
                              height: 130,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: _buildAnimatedBrandLogo(
                                animation: brandLogoAnimation,
                                width: 260,
                                height: 106,
                                logo: brandLogoPath == null
                                    ? Image.asset(
                                        'assets/photobooth_logo.png',
                                        fit: BoxFit.contain,
                                      )
                                    : Image.file(
                                        File(brandLogoPath!),
                                        fit: BoxFit.contain,
                                        errorBuilder: (context, error, stack) =>
                                            const Center(
                                              child: Text(
                                                'Logo preview unavailable',
                                                style: TextStyle(color: _muted),
                                              ),
                                            ),
                                      ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            DropdownButtonFormField<_BrandLogoAnimation>(
                              key: ValueKey(brandLogoAnimation),
                              initialValue: brandLogoAnimation,
                              decoration: InputDecoration(
                                labelText: translateAppText(
                                  'Logo animation',
                                  appLanguageNotifier.value,
                                ),
                              ),
                              items: _BrandLogoAnimation.values
                                  .map(
                                    (animation) =>
                                        DropdownMenuItem<_BrandLogoAnimation>(
                                          value: animation,
                                          child: Text(animation.label),
                                        ),
                                  )
                                  .toList(),
                              onChanged: busy
                                  ? null
                                  : (animation) {
                                      if (animation != null) {
                                        refreshDialog(
                                          () => brandLogoAnimation = animation,
                                        );
                                      }
                                    },
                            ),
                            const Text(
                              'Choose how the logo moves on the home screen and photo-count page.',
                              style: TextStyle(color: _muted, fontSize: 12),
                            ),
                            Wrap(
                              spacing: 8,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: selectingIdleMedia || busy
                                      ? null
                                      : chooseBrandLogo,
                                  icon: selectingIdleMedia
                                      ? const SizedBox.square(
                                          dimension: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.image_outlined),
                                  label: Text(
                                    brandLogoPath == null
                                        ? 'Upload logo'
                                        : 'Replace logo',
                                  ),
                                ),
                                if (brandLogoPath != null)
                                  TextButton.icon(
                                    onPressed: busy || selectingIdleMedia
                                        ? null
                                        : () => refreshDialog(
                                            () => brandLogoPath = null,
                                          ),
                                    icon: const Icon(Icons.delete_outline),
                                    label: const Text('Use default'),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'IDLE HOME SCREEN',
                              style: TextStyle(
                                color: _accent,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.2,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Shown while nobody is using the booth. Customers tap anywhere to begin.',
                              style: TextStyle(color: _muted, fontSize: 12),
                            ),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text(
                                'Enable full-screen live wallpaper',
                              ),
                              subtitle: const Text(
                                'After 10 minutes without activity, hide the home screen and show only the selected wallpaper. Tapping it opens photo selection.',
                              ),
                              value: liveWallpaperEnabled,
                              onChanged: busy
                                  ? null
                                  : (enabled) => refreshDialog(
                                      () => liveWallpaperEnabled = enabled,
                                    ),
                            ),
                            const SizedBox(height: 8),
                            if (idleScreenImagePath != null)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.file(
                                  File(idleScreenImagePath!),
                                  height: 150,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stack) =>
                                      const SizedBox(
                                        height: 100,
                                        child: Center(
                                          child: Text(
                                            'Home image preview unavailable',
                                          ),
                                        ),
                                      ),
                                ),
                              ),
                            Wrap(
                              spacing: 8,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: selectingIdleMedia || busy
                                      ? null
                                      : chooseIdleImage,
                                  icon: selectingIdleMedia
                                      ? const SizedBox.square(
                                          dimension: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.image_outlined),
                                  label: Text(
                                    idleScreenImagePath == null
                                        ? 'Upload home image'
                                        : 'Replace home image',
                                  ),
                                ),
                                if (idleScreenImagePath != null)
                                  TextButton.icon(
                                    onPressed: busy || selectingIdleMedia
                                        ? null
                                        : () => refreshDialog(
                                            () => idleScreenImagePath = null,
                                          ),
                                    icon: const Icon(Icons.delete_outline),
                                    label: const Text('Use default'),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            if (idleScreenVideoPath != null)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: _ink,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.video_library_outlined,
                                      color: _accent,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        idleScreenVideoPath!
                                            .split(Platform.pathSeparator)
                                            .last,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            Wrap(
                              spacing: 8,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: selectingIdleMedia || busy
                                      ? null
                                      : chooseIdleVideo,
                                  icon: selectingIdleMedia
                                      ? const SizedBox.square(
                                          dimension: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.video_file_outlined),
                                  label: Text(
                                    idleScreenVideoPath == null
                                        ? 'Upload live wallpaper video'
                                        : 'Replace live wallpaper video',
                                  ),
                                ),
                                if (idleScreenVideoPath != null)
                                  TextButton.icon(
                                    onPressed: busy || selectingIdleMedia
                                        ? null
                                        : () => refreshDialog(
                                            () => idleScreenVideoPath = null,
                                          ),
                                    icon: const Icon(Icons.delete_outline),
                                    label: const Text('Remove video'),
                                  ),
                              ],
                            ),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Loop idle video'),
                              subtitle: Text(
                                idleScreenVideoPath == null
                                    ? 'Upload a video to enable playback.'
                                    : idleVideoLoop
                                    ? 'Video repeats continuously on the idle home.'
                                    : 'Video plays once and holds on its final frame.',
                              ),
                              value: idleVideoLoop,
                              onChanged:
                                  idleScreenVideoPath == null ||
                                      busy ||
                                      selectingIdleMedia
                                  ? null
                                  : (enabled) => refreshDialog(
                                      () => idleVideoLoop = enabled,
                                    ),
                            ),
                            const Text(
                              'Supports MP4, M4V, MOV, and WebM videos up to 100 MB. The video plays over the uploaded home image; the image remains as a fallback.',
                              style: TextStyle(color: _muted, fontSize: 12),
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<int>(
                              key: ValueKey(countdownDuration),
                              initialValue: countdownDuration,
                              decoration: InputDecoration(
                                labelText: translateAppText(
                                  'Countdown before each photo',
                                  appLanguageNotifier.value,
                                ),
                              ),
                              items: const [1, 2, 3, 4, 5]
                                  .map(
                                    (seconds) => DropdownMenuItem(
                                      value: seconds,
                                      child: Text('$seconds seconds'),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (seconds) {
                                if (seconds != null) {
                                  refreshDialog(
                                    () => countdownDuration = seconds,
                                  );
                                }
                              },
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<int>(
                              key: ValueKey(previewDuration),
                              initialValue: previewDuration,
                              decoration: InputDecoration(
                                labelText: translateAppText(
                                  'Photo preview duration',
                                  appLanguageNotifier.value,
                                ),
                              ),
                              items: const [3, 5, 8, 10, 15]
                                  .map(
                                    (seconds) => DropdownMenuItem(
                                      value: seconds,
                                      child: Text('$seconds seconds'),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (seconds) {
                                if (seconds != null) {
                                  refreshDialog(
                                    () => previewDuration = seconds,
                                  );
                                }
                              },
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<int>(
                              key: ValueKey(idleTimeoutSeconds),
                              initialValue: idleTimeoutSeconds,
                              decoration: InputDecoration(
                                labelText: translateAppText(
                                  'Return to attract screen after inactivity',
                                  appLanguageNotifier.value,
                                ),
                              ),
                              items: const [30, 60, 120, 300]
                                  .map(
                                    (seconds) => DropdownMenuItem(
                                      value: seconds,
                                      child: Text(
                                        seconds < 60
                                            ? '$seconds seconds'
                                            : '${seconds ~/ 60} minutes',
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (seconds) {
                                if (seconds != null) {
                                  refreshDialog(
                                    () => idleTimeoutSeconds = seconds,
                                  );
                                }
                              },
                            ),
                            const SizedBox(height: 20),
                            DropdownButtonFormField<BoothEventTheme>(
                              key: ValueKey(selectedEventTheme),
                              initialValue: selectedEventTheme,
                              decoration: InputDecoration(
                                labelText: translateAppText(
                                  'Booth background design',
                                  appLanguageNotifier.value,
                                ),
                              ),
                              items: BoothEventTheme.values
                                  .map(
                                    (theme) => DropdownMenuItem(
                                      value: theme,
                                      child: Text(theme.label),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (theme) {
                                if (theme == null) return;
                                refreshDialog(() {
                                  selectedEventTheme = theme;
                                  selectedBorderStyle = theme.borderStyle;
                                  _welcomeController.text =
                                      theme.welcomeMessage;
                                });
                              },
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<PhotoEffect>(
                              key: ValueKey(liveEffect),
                              initialValue: liveEffect,
                              decoration: InputDecoration(
                                labelText: translateAppText(
                                  'Live camera preview effect',
                                  appLanguageNotifier.value,
                                ),
                              ),
                              items: PhotoEffect.values
                                  .map(
                                    (effect) => DropdownMenuItem(
                                      value: effect,
                                      child: Text(effect.label),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (effect) {
                                if (effect != null) {
                                  refreshDialog(() => liveEffect = effect);
                                }
                              },
                            ),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Voice guidance'),
                              subtitle: const Text(
                                'Speak photo and ready prompts aloud.',
                              ),
                              value: voiceGuidanceEnabled,
                              onChanged: (enabled) => refreshDialog(
                                () => voiceGuidanceEnabled = enabled,
                              ),
                            ),
                            const SizedBox(height: 20),
                          ],
                          if (selectedAdminSection == 'Photo Design') ...[
                            adminSectionHeading('Photo Design'),
                            const Text(
                              'PHOTO BORDER',
                              style: TextStyle(
                                color: _accent,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.2,
                              ),
                            ),
                            const SizedBox(height: 16),
                            DropdownButtonFormField<PhotoBorderStyle>(
                              key: ValueKey(selectedBorderStyle),
                              initialValue: selectedBorderStyle,
                              decoration: InputDecoration(
                                labelText: translateAppText(
                                  'Photo border',
                                  appLanguageNotifier.value,
                                ),
                              ),
                              items: PhotoBorderStyle.values
                                  .where(
                                    (style) =>
                                        style != PhotoBorderStyle.custom ||
                                        selectedCustomBorderPath != null,
                                  )
                                  .map(
                                    (style) => DropdownMenuItem(
                                      value: style,
                                      child: Text(style.label),
                                    ),
                                  )
                                  .toList(),
                              onChanged: selectingBorder
                                  ? null
                                  : (style) {
                                      if (style != null) {
                                        refreshDialog(
                                          () => selectedBorderStyle = style,
                                        );
                                      }
                                    },
                            ),
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              onPressed: selectingBorder
                                  ? null
                                  : chooseCustomBorder,
                              icon: selectingBorder
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.upload_file),
                              label: Text(
                                selectedCustomBorderPath == null
                                    ? 'Choose custom PNG border'
                                    : 'Replace custom PNG border',
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'CUSTOMER PNG FRAME GALLERY',
                              style: TextStyle(
                                color: _accent,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.1,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Upload a transparent PNG with 1–5 enclosed photo openings. The app detects the photo count and fits each photo into its opening.',
                              style: TextStyle(color: _muted, fontSize: 12),
                            ),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final framePath in selectedCustomerFrames)
                                  InputChip(
                                    avatar: const Icon(
                                      Icons.filter_frames_rounded,
                                    ),
                                    label: Text(
                                      _customerFrameDisplayName(framePath),
                                    ),
                                    onDeleted: selectingBorder
                                        ? null
                                        : () => refreshDialog(
                                            () => selectedCustomerFrames.remove(
                                              framePath,
                                            ),
                                          ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              onPressed: selectingBorder
                                  ? null
                                  : addCustomerFrame,
                              icon: const Icon(
                                Icons.add_photo_alternate_outlined,
                              ),
                              label: const Text('Add customer PNG frame'),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'CUSTOMER DECORATIONS',
                              style: TextStyle(
                                color: _accent,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.1,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Upload transparent PNG or WebP stickers customers can drag, resize, and add to their photos. Up to 50 images, 12 MB each.',
                              style: TextStyle(color: _muted, fontSize: 12),
                            ),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final decorationPath
                                    in selectedCustomerDecorations)
                                  InputChip(
                                    avatar: ClipOval(
                                      child: Image.file(
                                        File(decorationPath),
                                        width: 24,
                                        height: 24,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                    label: Text(
                                      File(decorationPath)
                                          .uri
                                          .pathSegments
                                          .last,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    onDeleted: selectingBorder
                                        ? null
                                        : () => refreshDialog(
                                            () => selectedCustomerDecorations
                                                .remove(decorationPath),
                                          ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              onPressed:
                                  selectingBorder ||
                                      selectedCustomerDecorations.length >=
                                          _maxCustomerDecorationCount
                                  ? null
                                  : addCustomerDecoration,
                              icon: const Icon(
                                Icons.add_photo_alternate_rounded,
                              ),
                              label: Text(
                                selectedCustomerDecorations.length >=
                                        _maxCustomerDecorationCount
                                    ? 'Decoration limit reached'
                                    : 'Add PNG or WebP decoration',
                              ),
                            ),
                            const SizedBox(height: 20),
                          ],
                          if (selectedAdminSection == 'App Updates') ...[
                            adminSectionHeading('App Updates'),
                            const Text(
                              'APP UPDATES',
                              style: TextStyle(
                                color: _accent,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.2,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'The update link is built into this app. Update the public manifest online when you release a new version.',
                              style: TextStyle(color: _muted, fontSize: 12),
                            ),
                            const SizedBox(height: 8),
                            SelectableText(
                              _updateManifestUrl,
                              style: const TextStyle(
                                color: _muted,
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: checkingForUpdate || busy
                                    ? null
                                    : checkForUpdate,
                                icon: checkingForUpdate
                                    ? const SizedBox.square(
                                        dimension: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.system_update_alt),
                                label: Text(
                                  checkingForUpdate
                                      ? 'Checking...'
                                      : 'Check for updates',
                                ),
                              ),
                            ),
                            if (updateStatus.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                updateStatus,
                                style: const TextStyle(color: _ink),
                              ),
                            ],
                            if (checkedUpdate case final update?) ...[
                              if (update.releaseNotes.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  update.releaseNotes,
                                  style: const TextStyle(color: _muted),
                                ),
                              ],
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  onPressed: _appUpdateInstalling
                                      ? null
                                      : downloadUpdate,
                                  icon: _appUpdateInstalling
                                      ? const SizedBox.square(
                                          dimension: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.system_update_alt),
                                  label: Text(
                                    _appUpdateInstalling
                                        ? 'Downloading update...'
                                        : 'Download & install update',
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 20),
                          ],
                          if (selectedAdminSection == 'Printer') ...[
                            adminSectionHeading('Printer'),
                            DropdownButtonFormField<_PrinterType>(
                              key: ValueKey(printerType),
                              initialValue: printerType,
                              decoration: InputDecoration(
                                labelText: translateAppText(
                                  'Printer type',
                                  appLanguageNotifier.value,
                                ),
                              ),
                              items: _PrinterType.values
                                  .map(
                                    (type) => DropdownMenuItem(
                                      value: type,
                                      child: Text(type.label),
                                    ),
                                  )
                                  .toList(),
                              onChanged: busy
                                  ? null
                                  : (type) {
                                      if (type != null) {
                                        refreshDialog(() => printerType = type);
                                      }
                                    },
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'PRINTER SETUP',
                              style: TextStyle(
                                color: _accent,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              printerType == _PrinterType.receipt
                                  ? 'Receipt printers use Bluetooth ESC/POS. Choose 58 mm or 80 mm paper to match the printer; photos are scaled to the full paper width and keep their original aspect ratio.'
                                  : 'Color printers use the Android system print dialog. Connect a compatible printer service (such as Mopria or the printer manufacturer’s service) and choose the printer when printing.',
                              style: const TextStyle(
                                color: _muted,
                                fontSize: 12,
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.only(bottom: 8),
                              child: Text(
                                'Guests choose when to print by tapping “Print my photo”. The selected copy count is used.',
                                style: TextStyle(color: _muted, fontSize: 12),
                              ),
                            ),
                            if (printerType == _PrinterType.receipt) ...[
                              DropdownButtonFormField<int>(
                                key: ValueKey(receiptWidthDots),
                                initialValue: receiptWidthDots,
                                decoration: InputDecoration(
                                  labelText: translateAppText(
                                    'Receipt paper width',
                                    appLanguageNotifier.value,
                                  ),
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: 384,
                                    child: Text('58 mm (384 dots)'),
                                  ),
                                  DropdownMenuItem(
                                    value: 576,
                                    child: Text('80 mm (576 dots)'),
                                  ),
                                ],
                                onChanged: (width) {
                                  if (width != null) {
                                    refreshDialog(
                                      () => receiptWidthDots = width,
                                    );
                                  }
                                },
                              ),
                              DropdownButtonFormField<EscPosCutMode>(
                                key: ValueKey(receiptCutMode),
                                initialValue: receiptCutMode,
                                decoration: InputDecoration(
                                  labelText: translateAppText(
                                    'Automatic paper cut',
                                    appLanguageNotifier.value,
                                  ),
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: EscPosCutMode.full,
                                    child: Text('Full cut'),
                                  ),
                                  DropdownMenuItem(
                                    value: EscPosCutMode.partial,
                                    child: Text('Partial cut'),
                                  ),
                                ],
                                onChanged: busy
                                    ? null
                                    : (mode) {
                                        if (mode != null) {
                                          refreshDialog(
                                            () => receiptCutMode = mode,
                                          );
                                        }
                                      },
                              ),
                              const Padding(
                                padding: EdgeInsets.only(top: 4, bottom: 4),
                                child: Text(
                                  'Sends the standard ESC/POS cut command after each copy. Automatic cutting requires a built-in cutter; if one mode does not work, try the other. Color-printer cutting is controlled by its Android printer service.',
                                  style: TextStyle(color: _muted, fontSize: 12),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Photo brightness · '
                                      '${(receiptBrightness * 100).round()}%',
                                      style: const TextStyle(
                                        color: _ink,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    Slider(
                                      value: receiptBrightness,
                                      min: 0.2,
                                      max: 0.5,
                                      divisions: 6,
                                      label:
                                          '${(receiptBrightness * 100).round()}%',
                                      onChanged: busy
                                          ? null
                                          : (value) => refreshDialog(
                                              () => receiptBrightness = value,
                                            ),
                                    ),
                                    const Text(
                                      'Increase brightness if photo prints look too dark. This affects receipt printers only.',
                                      style: TextStyle(
                                        color: _muted,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              DropdownButtonFormField<String>(
                                key: ValueKey(
                                  'printer-${printerAddress ?? 'none'}-'
                                  '${pairedPrinters.length}',
                                ),
                                initialValue: printerAddress ?? '',
                                decoration: InputDecoration(
                                  labelText: translateAppText(
                                    'Paired Bluetooth printer',
                                    appLanguageNotifier.value,
                                  ),
                                ),
                                items: [
                                  const DropdownMenuItem<String>(
                                    value: '',
                                    child: Text('Select a printer'),
                                  ),
                                  if (printerAddress != null &&
                                      !pairedPrinters.any(
                                        (printer) =>
                                            printer.address == printerAddress,
                                      ))
                                    DropdownMenuItem(
                                      value: printerAddress!,
                                      child: Text(
                                        'Not paired · $printerAddress',
                                      ),
                                    ),
                                  ...pairedPrinters.map(
                                    (printer) => DropdownMenuItem(
                                      value: printer.address,
                                      child: Text(
                                        printer.label,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                ],
                                onChanged: (address) => refreshDialog(
                                  () => printerAddress =
                                      address == null || address.isEmpty
                                      ? null
                                      : address,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: loadingPrinters || busy
                                          ? null
                                          : refreshPrinters,
                                      icon: loadingPrinters
                                          ? const SizedBox.square(
                                              dimension: 18,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Icon(Icons.refresh),
                                      label: const Text(
                                        'Refresh paired devices',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            DropdownButtonFormField<int>(
                              key: ValueKey(printCopies),
                              initialValue: printCopies,
                              decoration: InputDecoration(
                                labelText: translateAppText(
                                  'Print copies',
                                  appLanguageNotifier.value,
                                ),
                              ),
                              items: const [1, 2, 3]
                                  .map(
                                    (copies) => DropdownMenuItem(
                                      value: copies,
                                      child: Text(
                                        '$copies ${copies == 1 ? 'copy' : 'copies'}',
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (copies) {
                                if (copies != null) {
                                  refreshDialog(() => printCopies = copies);
                                }
                              },
                            ),
                            const SizedBox(height: 8),
                            if (printerType == _PrinterType.receipt)
                              OutlinedButton.icon(
                                onPressed:
                                    printerAddress == null ||
                                        printingTestPage ||
                                        busy
                                    ? null
                                    : printTestPage,
                                icon: printingTestPage
                                    ? const SizedBox.square(
                                        dimension: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.print_outlined),
                                label: const Text('Print test page'),
                              ),
                            const SizedBox(height: 6),
                            const Text(
                              'Custom borders need a transparent center so the photo remains visible.',
                              style: TextStyle(color: _muted, fontSize: 12),
                            ),
                            const SizedBox(height: 12),
                            Align(
                              alignment: Alignment.center,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: AspectRatio(
                                  aspectRatio: 3 / 4,
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      ColoredBox(
                                        color: Color(0xFF373940),
                                        child: Center(
                                          child: Icon(
                                            Icons.person,
                                            size: 56,
                                            color: Color(0xFF8E9098),
                                          ),
                                        ),
                                      ),
                                      if (selectedBorderStyle ==
                                              PhotoBorderStyle.custom &&
                                          selectedCustomBorderPath != null)
                                        Image.file(
                                          File(selectedCustomBorderPath!),
                                          fit: BoxFit.contain,
                                          errorBuilder:
                                              (context, error, stack) =>
                                                  const ColoredBox(
                                                    color: _panel,
                                                    child: Center(
                                                      child: Text(
                                                        'Border preview unavailable',
                                                      ),
                                                    ),
                                                  ),
                                        ),
                                      if (selectedBorderStyle !=
                                              PhotoBorderStyle.custom ||
                                          selectedCustomBorderPath == null)
                                        CustomPaint(
                                          painter: PhotoBorderPainter(
                                            selectedBorderStyle,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _kioskActive
                                  ? 'This tablet is locked to the booth app.'
                                  : 'Provision this app as device owner to prevent app switching.',
                              style: const TextStyle(
                                color: _muted,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed:
                                  busy || selectingBorder || selectingIdleMedia
                                  ? null
                                  : toggleKioskMode,
                              icon: Icon(
                                _kioskActive ? Icons.logout : Icons.lock,
                              ),
                              label: Text(
                                _kioskActive
                                    ? 'Log out and exit kiosk mode'
                                    : 'Enable kiosk mode',
                              ),
                            ),
                          ],
                        ],
                        if (errorMessage.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(
                            errorMessage,
                            style: const TextStyle(color: Color(0xFFB42318)),
                          ),
                        ],
                      ],
                    ),
                  ),
                  actions: [
                    SizedBox(
                      width: MediaQuery.sizeOf(dialogContext).width - 36,
                      child: Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              style: TextButton.styleFrom(
                                backgroundColor: const Color(0xFFF0F3F6),
                                foregroundColor: _ink,
                                minimumSize: const Size.fromHeight(54),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed:
                                  busy ||
                                      selectingBorder ||
                                      selectingIdleMedia ||
                                      loadingPrinters ||
                                      printingTestPage
                                  ? null
                                  : () => Navigator.of(dialogContext).pop(),
                              child: const Text(
                                'Exit',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF2F80ED),
                                foregroundColor: Colors.white,
                                minimumSize: const Size.fromHeight(54),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed:
                                  busy ||
                                      selectingBorder ||
                                      selectingIdleMedia ||
                                      loadingPrinters ||
                                      printingTestPage
                                  ? null
                                  : submit,
                              child: busy
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Text(
                                      authenticated
                                          ? 'Save settings'
                                          : isSetup
                                          ? 'Create password'
                                          : 'Sign in',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      );
      if (cameraSelectionChanged && mounted) {
        await _applyCameraSelection(_cameraDirection);
      }
    } finally {
      adminSettingsScrollController.dispose();
      if (mounted) {
        setState(() => _adminDialogOpen = false);
        _resetIdleTimer();
        unawaited(_pollCredits());
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _appInForeground = true;
      _cameraRecoveryAttempts = 0;
      unawaited(_checkForAppUpdateAutomatically(force: true));
      unawaited(_initializeActivation());
      unawaited(_refreshKioskStatus());
      unawaited(_refreshPermissionState());
      unawaited(_refreshDeviceHealth());
      _resetIdleTimer();
      _resetLiveWallpaperTimer();
      unawaited(_reportFleetHeartbeat());
      if (_settingsLoaded && _activationActive && !_cameraReady) {
        unawaited(_initializeCamera());
      }
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _appInForeground = false;
      if (state != AppLifecycleState.inactive) {
        unawaited(_reportFleetHeartbeat());
      }
      if (_activationExpiresAt != null) {
        unawaited(_settings.loadEffectiveTrialNow());
      }
      unawaited(_stopVoiceGuidance());
      _pollTimer?.cancel();
      _pollTimer = null;
      _cameraReady = false;
      final camera = _camera;
      _camera = null;
      if (camera != null) unawaited(_disposeCameraController(camera));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _startPromptController.dispose();
    _filmTapeController.dispose();
    _paymentNoticeEntry?.remove();
    _logoTapResetTimer?.cancel();
    _idleTimer?.cancel();
    _activationExpiryTimer?.cancel();
    _liveWallpaperTimer?.cancel();
    _homeTransitionTimer?.cancel();
    _pollTimer?.cancel();
    _deviceHealthTimer?.cancel();
    _fleetMonitoringTimer?.cancel();
    _appUpdateCheckTimer?.cancel();
    unawaited(_bleStatusSubscription?.cancel());
    unawaited(_stopVoiceGuidance());
    final camera = _camera;
    if (camera != null) unawaited(_disposeCameraController(camera));
    _passwordController.dispose();
    _confirmController.dispose();
    _welcomeController.dispose();
    _activationCodeController.dispose();
    unawaited(_payments.dispose());
    final dashboard = _dashboard;
    if (dashboard != null) unawaited(dashboard.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final camera = _camera;
    final previewPhoto = _previewPhoto;
    final screenSize = MediaQuery.sizeOf(context);
    final resultTextColor = _eventTheme.resultTextColor;
    final phoneLayout = screenSize.shortestSide < 600;
    final showPrintAnimation =
        _isPrinting &&
        previewPhoto != null &&
        _printerType == _PrinterType.receipt;
    final canPrintPhoto =
        _printerType == _PrinterType.color || _printerAddress != null;
    final showPostPrintActions =
        _printCompleted ||
        _aiOutputPhoto ||
        !canPrintPhoto ||
        _message.startsWith('Print failed:');
    final portraitCapture = screenSize.height >= screenSize.width;
    final captureSideInset = (screenSize.width * 0.035)
        .clamp(12.0, 30.0)
        .toDouble();
    final captureThumbnailHeight = phoneLayout ? 74.0 : 90.0;
    final captureBottomInset =
        captureThumbnailHeight + 8 + captureSideInset * 2;
    final compactLayout = screenSize.width > screenSize.height || phoneLayout;
    final landscape = screenSize.width > screenSize.height;
    final classicSessionTemplates =
        classicPhotoFrameTemplates
            .where(
              (template) =>
                  template.landscape == landscape &&
                  _enabledPhotoCounts.contains(template.photoCount) &&
                  template.id != 'classic-staggered-4',
            )
            .toList(growable: true)
          ..sort(
            (first, second) => _classicPhotoChoiceOrder
                .indexOf(first.photoCount)
                .compareTo(_classicPhotoChoiceOrder.indexOf(second.photoCount)),
          );
    final liveCameraPreview = camera == null
        ? null
        : _liveEffect == PhotoEffect.original
        ? CameraPreview(camera, key: const ValueKey('live-camera'))
        : ColorFiltered(
            colorFilter: _liveEffectColorFilter(_liveEffect),
            child: CameraPreview(camera, key: const ValueKey('live-camera')),
          );
    final qrPayMongoEnabled =
        _payMongoPaymentsEnabled && _activationAllowsPayMongo;
    final qrGanapEnabled =
        _walletPaymentEnabled && _activationAllowsGanap && _ganapQrPhAvailable;
    final qrPaymentEnabled = qrPayMongoEnabled || qrGanapEnabled;
    final coinSlotConnected = _esp32Detected && _credits != null;
    final showQrAndCoinPaymentPrompt =
        !_isTestMode &&
        !_rentModeEnabled &&
        _selectedPhotoCount != null &&
        qrPaymentEnabled &&
        coinSlotConnected;
    final showCoinProgressModal =
        _showCoinPaymentPage &&
        !_rentModeEnabled &&
        !_isTestMode &&
        _selectedPhotoCount != null &&
        !_coinPaymentReady &&
        !_paidPhotoPending &&
        !_photoInProgress &&
        !_boothPaused;
    return Scaffold(
      backgroundColor: Colors.white,
      body: Listener(
        onPointerDown: (event) => _handleScreenPointerDown(event, screenSize),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 700),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.97, end: 1).animate(
                      CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeOutCubic,
                      ),
                    ),
                    child: child,
                  ),
                ),
                child: previewPhoto != null
                    ? ColoredBox(
                        key: ValueKey('photo-${previewPhoto.path}'),
                        color: Colors.white,
                        child: Padding(
                          padding: EdgeInsets.only(
                            bottom: min(250.0, screenSize.height * 0.32),
                          ),
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x1A17212B),
                                    blurRadius: 18,
                                    offset: Offset(0, 7),
                                  ),
                                ],
                              ),
                              child: Stack(
                                fit: StackFit.passthrough,
                                children: [
                                  Image.file(
                                    previewPhoto,
                                    fit: BoxFit.contain,
                                    errorBuilder: (context, error, stack) =>
                                        const Center(
                                          child: Text(
                                            'Photo preview could not be displayed.',
                                            style: TextStyle(color: _ink),
                                          ),
                                        ),
                                  ),
                                  if (_aiConversionBusy)
                                    _AiGenerationOverlay(
                                      styleLabel:
                                          _pendingAiStyle?.label ?? 'AI photo',
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      )
                    : _photoInProgress &&
                          _cameraReady &&
                          liveCameraPreview != null
                    ? portraitCapture
                          ? Padding(
                              padding: EdgeInsets.fromLTRB(
                                captureSideInset,
                                captureSideInset,
                                captureSideInset,
                                captureBottomInset,
                              ),
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(28),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x1A172033),
                                      blurRadius: 16,
                                      offset: Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(24),
                                  child: SizedBox.expand(
                                    child: liveCameraPreview,
                                  ),
                                ),
                              ),
                            )
                          : liveCameraPreview
                    : const ColoredBox(
                        key: ValueKey('white-screen'),
                        color: Colors.white,
                      ),
              ),
            ),
            if (previewPhoto == null &&
                _photoInProgress &&
                _cameraReady &&
                _photoBorderStyle != PhotoBorderStyle.none)
              Positioned.fill(
                child: IgnorePointer(
                  child:
                      _photoBorderStyle == PhotoBorderStyle.custom &&
                          _customPhotoBorderPath != null
                      ? Image.file(
                          File(_customPhotoBorderPath!),
                          fit: BoxFit.fill,
                          errorBuilder: (context, error, stackTrace) {
                            debugPrint(
                              'Could not display the live custom photo border: '
                              '$error',
                            );
                            return const SizedBox.expand();
                          },
                        )
                      : CustomPaint(
                          painter: PhotoBorderPainter(_photoBorderStyle),
                        ),
                ),
              ),
            if (previewPhoto == null && !_photoInProgress)
              Positioned.fill(
                child: IgnorePointer(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: BoothThemeBackgroundPainter(
                            theme: _eventTheme,
                            animation: _filmTapeController,
                          ),
                        ),
                      ),
                      if (_eventTheme == BoothEventTheme.classic)
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _FilmTapeBackgroundPainter(
                              animation: _filmTapeController,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            if (showPrintAnimation)
              Positioned.fill(
                child: SafeArea(
                  child: _PrinterEjectionAnimation(
                    photo: previewPhoto,
                    sentToPrinter: _printSubmitted,
                  ),
                ),
              ),
            if (previewPhoto != null && !showPrintAnimation)
              Positioned(
                left: 12,
                right: 12,
                bottom: 10,
                child: SafeArea(
                  top: false,
                  child: Center(
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 680),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x1A17212B),
                            blurRadius: 20,
                            offset: Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _message,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: resultTextColor,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (_softCopyError != null ||
                              _gifUploadError != null ||
                              _sessionGifError != null ||
                              _videoUploadError != null ||
                              _sessionVideoError != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              _softCopyError ??
                                  _gifUploadError ??
                                  _sessionGifError ??
                                  _videoUploadError ??
                                  _sessionVideoError!,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFFB42318),
                                fontSize: 11,
                              ),
                            ),
                          ],
                          Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 380),
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  final buttonWidth =
                                      (constraints.maxWidth - 8) / 2;
                                  return SizedBox(
                                    width: constraints.maxWidth,
                                    child: Wrap(
                                      alignment: WrapAlignment.center,
                                      spacing: 8,
                                      runSpacing: 6,
                                      children: [
                                        if (canPrintPhoto &&
                                            !_printCompleted &&
                                            !_previewPrintAttempted)
                                          SizedBox(
                                            width: buttonWidth,
                                            child: _PhotoResultActionButton(
                                              icon: Icons.print_rounded,
                                              label: 'Print photo',
                                              enabled: !_isPrinting,
                                              foregroundColor: resultTextColor,
                                              onPressed: _printPreviewPhoto,
                                            ),
                                          ),
                                        if (_aiStylesEnabled &&
                                            _printCompleted &&
                                            !_aiOutputPhoto)
                                          SizedBox(
                                            width: buttonWidth,
                                            child: _PhotoResultActionButton(
                                              icon: _aiConversionPaid
                                                  ? Icons.refresh_rounded
                                                  : Icons.auto_awesome_rounded,
                                              label: _aiConversionBusy
                                                  ? 'Creating AI photo…'
                                                  : _aiConversionPaid
                                                  ? 'Retry AI generation'
                                                  : 'Conversion Preview',
                                              enabled:
                                                  !_isPrinting &&
                                                  !_aiConversionBusy,
                                              foregroundColor: resultTextColor,
                                              onPressed: _offerPaidAiStyles,
                                            ),
                                          ),
                                        if (_printCompleted && !_aiOutputPhoto)
                                          SizedBox(
                                            width: constraints.maxWidth,
                                            child: Text(
                                              'Tap a green cloud button to download your photo, GIF, or video.',
                                              textAlign: TextAlign.center,
                                              style: const TextStyle(
                                                color: Color(0xFF168A45),
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                        if (showPostPrintActions)
                                          SizedBox(
                                            width: buttonWidth,
                                            child: _PhotoDownloadActionButton(
                                              label: 'Download photo QR',
                                              enabled: !_isPrinting,
                                              foregroundColor: resultTextColor,
                                              highlighted:
                                                  _printCompleted &&
                                                  !_aiOutputPhoto,
                                              onPressed: () => _showSoftCopyQr(
                                                showGif: false,
                                              ),
                                            ),
                                          ),
                                        if (showPostPrintActions &&
                                            !_aiOutputPhoto)
                                          SizedBox(
                                            width: buttonWidth,
                                            child: _PhotoDownloadActionButton(
                                              label: 'Download GIF QR',
                                              enabled: !_isPrinting,
                                              foregroundColor: resultTextColor,
                                              highlighted:
                                                  _printCompleted &&
                                                  !_aiOutputPhoto,
                                              onPressed: () => _showSoftCopyQr(
                                                showGif: true,
                                              ),
                                            ),
                                          ),
                                        if (showPostPrintActions &&
                                            !_aiOutputPhoto)
                                          SizedBox(
                                            width: buttonWidth,
                                            child: _PhotoDownloadActionButton(
                                              label: 'Download video QR',
                                              enabled: !_isPrinting,
                                              foregroundColor: resultTextColor,
                                              highlighted:
                                                  _printCompleted &&
                                                  !_aiOutputPhoto,
                                              onPressed: () => _showSoftCopyQr(
                                                showGif: false,
                                                showVideo: true,
                                              ),
                                            ),
                                          ),
                                        if (showPostPrintActions)
                                          SizedBox(
                                            width: buttonWidth,
                                            child: _PhotoResultActionButton(
                                              icon: Icons.restart_alt_rounded,
                                              label: 'Start over',
                                              enabled: !_isPrinting,
                                              foregroundColor: resultTextColor,
                                              onPressed: _isPrinting
                                                  ? null
                                                  : _startOverFromPreview,
                                            ),
                                          ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (previewPhoto == null && _photoInProgress && _cameraReady)
              Positioned(
                left: 0,
                right: 0,
                bottom: 10,
                child: SafeArea(
                  top: false,
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_waitingForManualCapture)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              _sessionCapturePreviews.isEmpty
                                  ? 'TAP TO TAKE YOUR PHOTO'
                                  : 'TAP TO TAKE PHOTO ${_sessionCapturePreviews.length + 1}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.8,
                                shadows: [
                                  Shadow(color: Colors.black87, blurRadius: 8),
                                ],
                              ),
                            ),
                          ),
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.62),
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x44000000),
                                blurRadius: 10,
                                offset: Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (
                                var index = 0;
                                index < _sessionCapturePreviews.length;
                                index++
                              ) ...[
                                if (index > 0) const SizedBox(width: 6),
                                Container(
                                  width: phoneLayout ? 48 : 60,
                                  height: phoneLayout ? 62 : 78,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(7),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Color(0x44000000),
                                        blurRadius: 5,
                                        offset: Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: Image.file(
                                    _sessionCapturePreviews[index],
                                    fit: BoxFit.cover,
                                    errorBuilder:
                                        (context, error, stackTrace) =>
                                            const Icon(
                                              Icons.photo_outlined,
                                              color: _muted,
                                            ),
                                  ),
                                ),
                              ],
                              if (_waitingForManualCapture) ...[
                                if (_sessionCapturePreviews.isNotEmpty)
                                  const SizedBox(width: 8),
                                Material(
                                  color: Colors.transparent,
                                  shape: const CircleBorder(),
                                  child: InkWell(
                                    onTap: _requestManualCapture,
                                    customBorder: const CircleBorder(),
                                    child: Container(
                                      width: phoneLayout ? 64 : 76,
                                      height: phoneLayout ? 64 : 76,
                                      padding: const EdgeInsets.all(5),
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Colors.white,
                                          width: 3,
                                        ),
                                      ),
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(
                                            99,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.camera_alt_rounded,
                                          color: _ink,
                                          size: 28,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (_showIdleScreen && previewPhoto == null && !_photoInProgress)
              _showLiveWallpaperScreen
                  ? _buildLiveWallpaperPage()
                  : _buildIdleHome(compactLayout: compactLayout),
            if (!_showIdleScreen && previewPhoto == null && !_photoInProgress)
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: 1),
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeInOutCubic,
                builder: (context, value, child) => Opacity(
                  opacity: value,
                  child: Transform.scale(
                    scale: 0.975 + value * 0.025,
                    child: Transform.translate(
                      offset: Offset(0, 10 * (1 - value)),
                      child: child,
                    ),
                  ),
                ),
                child: _showPaymentMethodPage
                    ? _buildPaymentMethodPage(
                        phoneLayout: phoneLayout,
                        qrPayMongoEnabled: qrPayMongoEnabled,
                        qrGanapEnabled: qrGanapEnabled,
                      )
                    : SafeArea(
                        child: Column(
                          children: [
                            Expanded(
                              child: LayoutBuilder(
                                builder: (context, constraints) => SingleChildScrollView(
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      minHeight: constraints.maxHeight,
                                    ),
                                    child: Center(
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 12,
                                        ),
                                        child: Container(
                                          width: double.infinity,
                                          padding: EdgeInsets.symmetric(
                                            horizontal: phoneLayout
                                                ? 12
                                                : compactLayout
                                                ? 24
                                                : 22,
                                            vertical: compactLayout ? 16 : 22,
                                          ),
                                          color: Colors.white,
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              SizedBox(
                                                height: compactLayout ? 4 : 8,
                                              ),
                                              Text(
                                                'HOW MANY PHOTOS?',
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  color: _ink,
                                                  fontSize: phoneLayout
                                                      ? 21
                                                      : 25,
                                                  fontWeight: FontWeight.w900,
                                                  letterSpacing: 1.3,
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              const Text(
                                                'Tap a layout to choose your photo count. You can customize your frame after capturing.',
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  color: _muted,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              const SizedBox(height: 10),
                                              if (classicSessionTemplates
                                                  .isEmpty)
                                                const Text(
                                                  'No classic templates are currently available.',
                                                  textAlign: TextAlign.center,
                                                  style: TextStyle(
                                                    color: _muted,
                                                  ),
                                                )
                                              else
                                                LayoutBuilder(
                                                  builder: (context, constraints) {
                                                    final columns =
                                                        constraints.maxWidth <
                                                            480
                                                        ? 2
                                                        : 3;
                                                    final spacing = columns == 2
                                                        ? 12.0
                                                        : 16.0;
                                                    final choiceWidth = min(
                                                      230.0,
                                                      (constraints.maxWidth -
                                                              spacing *
                                                                  (columns -
                                                                      1)) /
                                                          columns,
                                                    );
                                                    return Wrap(
                                                      alignment:
                                                          WrapAlignment.center,
                                                      spacing: spacing,
                                                      runSpacing: 14,
                                                      children: [
                                                        for (final template
                                                            in classicSessionTemplates)
                                                          SizedBox(
                                                            width: choiceWidth,
                                                            height: 174,
                                                            child: _SessionLayoutChoiceCard(
                                                              template:
                                                                  template,
                                                              selected:
                                                                  _selectedSessionFrameTemplate
                                                                      ?.id ==
                                                                  template.id,
                                                              onTap: () =>
                                                                  _selectSessionTemplate(
                                                                    template,
                                                                  ),
                                                            ),
                                                          ),
                                                      ],
                                                    );
                                                  },
                                                ),
                                              const SizedBox(height: 14),
                                              Container(
                                                width: double.infinity,
                                                constraints:
                                                    const BoxConstraints(
                                                      minHeight: 76,
                                                    ),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 20,
                                                      vertical: 12,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: Colors.white,
                                                  borderRadius:
                                                      BorderRadius.circular(16),
                                                  boxShadow: const [
                                                    BoxShadow(
                                                      color: Color(0x38384450),
                                                      blurRadius: 14,
                                                      spreadRadius: 1,
                                                      offset: Offset(0, 7),
                                                    ),
                                                    BoxShadow(
                                                      color: Color(0xBFFFFFFF),
                                                      blurRadius: 5,
                                                      offset: Offset(0, -2),
                                                    ),
                                                  ],
                                                ),
                                                child: Column(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: [
                                                    AnimatedSwitcher(
                                                      duration: const Duration(
                                                        milliseconds: 220,
                                                      ),
                                                      transitionBuilder:
                                                          (
                                                            child,
                                                            animation,
                                                          ) => FadeTransition(
                                                            opacity: animation,
                                                            child: SlideTransition(
                                                              position:
                                                                  Tween<Offset>(
                                                                    begin:
                                                                        const Offset(
                                                                          0,
                                                                          0.08,
                                                                        ),
                                                                    end: Offset
                                                                        .zero,
                                                                  ).animate(
                                                                    animation,
                                                                  ),
                                                              child: child,
                                                            ),
                                                          ),
                                                      child:
                                                          showQrAndCoinPaymentPrompt
                                                          ? Column(
                                                              key:
                                                                  const ValueKey(
                                                                    'payment-qr-and-coinslot',
                                                                  ),
                                                              mainAxisSize:
                                                                  MainAxisSize
                                                                      .min,
                                                              children: [
                                                                Row(
                                                                  mainAxisAlignment:
                                                                      MainAxisAlignment
                                                                          .center,
                                                                  children: [
                                                                    const Icon(
                                                                      Icons
                                                                          .qr_code_2_rounded,
                                                                      color:
                                                                          _accent,
                                                                      size: 23,
                                                                    ),
                                                                    const SizedBox(
                                                                      width: 8,
                                                                    ),
                                                                    Flexible(
                                                                      child: Text(
                                                                        'PAY ₱${qrPayMongoEnabled ? _payMongoAmountPesos : _sessionPricePesos} VIA QR PH · PER SESSION',
                                                                        textAlign:
                                                                            TextAlign.center,
                                                                        style: TextStyle(
                                                                          color:
                                                                              _ink,
                                                                          fontSize:
                                                                              phoneLayout
                                                                              ? 16
                                                                              : 20,
                                                                          height:
                                                                              1.05,
                                                                          fontFamily: 'serif',
                                                                          fontWeight:
                                                                              FontWeight.w900,
                                                                          letterSpacing:
                                                                              0.35,
                                                                        ),
                                                                      ),
                                                                    ),
                                                                  ],
                                                                ),
                                                                const SizedBox(
                                                                  height: 5,
                                                                ),
                                                                Row(
                                                                  mainAxisAlignment:
                                                                      MainAxisAlignment
                                                                          .center,
                                                                  children: [
                                                                    const Icon(
                                                                      Icons
                                                                          .payments_rounded,
                                                                      color:
                                                                          _muted,
                                                                      size: 19,
                                                                    ),
                                                                    const SizedBox(
                                                                      width: 7,
                                                                    ),
                                                                    Flexible(
                                                                      child: Text(
                                                                        'OR INSERT $_coinPricePesos COINS (₱$_coinPricePesos) PER SESSION TO START',
                                                                        textAlign:
                                                                            TextAlign.center,
                                                                        style: TextStyle(
                                                                          color:
                                                                              _muted,
                                                                          fontSize:
                                                                              phoneLayout
                                                                              ? 12
                                                                              : 14,
                                                                          height:
                                                                              1.05,
                                                                          fontFamily: 'serif',
                                                                          fontWeight:
                                                                              FontWeight.w800,
                                                                          letterSpacing:
                                                                              0.25,
                                                                        ),
                                                                      ),
                                                                    ),
                                                                  ],
                                                                ),
                                                              ],
                                                            )
                                                          : Text(
                                                              _rentModeEnabled
                                                                  ? _selectedPhotoCount ==
                                                                            null
                                                                        ? 'CHOOSE PHOTOS'
                                                                        : '${_selectedPhotoCount!} ${_selectedPhotoCount == 1 ? 'PHOTO' : 'PHOTOS'} SELECTED'
                                                                  : qrPayMongoEnabled &&
                                                                        !_isTestMode
                                                                  ? 'PAY ₱$_payMongoAmountPesos VIA QR PH PER SESSION'
                                                                  : _isTestMode
                                                                  ? 'TEST MODE · FREE'
                                                                  : _selectedPhotoCount ==
                                                                        null
                                                                  ? 'CHOOSE PHOTOS · COIN ₱$_coinPricePesos PER SESSION'
                                                                  : qrGanapEnabled
                                                                  ? 'SESSION PRICE · ₱20'
                                                                  : 'INSERT $_coinPricePesos COINS · ₱$_coinPricePesos',
                                                              key: ValueKey(
                                                                'payment-${_isTestMode
                                                                    ? 'test'
                                                                    : qrPayMongoEnabled
                                                                    ? 'paymongo-$_payMongoAmountPesos'
                                                                    : 'coins-$_coinPricePesos-${_selectedPhotoCount == null ? 'choose' : 'paid'}'}',
                                                              ),
                                                              textAlign:
                                                                  TextAlign
                                                                      .center,
                                                              style: TextStyle(
                                                                color: _ink,
                                                                fontSize:
                                                                    phoneLayout
                                                                    ? 21
                                                                    : 25,
                                                                height: 1.05,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w900,
                                                                letterSpacing:
                                                                    0.5,
                                                              ),
                                                            ),
                                                    ),
                                                    if (_selectedPhotoCount !=
                                                            null &&
                                                        !_rentModeEnabled &&
                                                        !_isTestMode)
                                                      Padding(
                                                        padding:
                                                            const EdgeInsets.only(
                                                              top: 4,
                                                            ),
                                                        child: Text(
                                                          '$_selectedPhotoCount '
                                                          '${_selectedPhotoCount == 1 ? 'PHOTO' : 'PHOTOS'}'
                                                          '  ·  ONE SESSION PRICE',
                                                          textAlign:
                                                              TextAlign.center,
                                                          style:
                                                              const TextStyle(
                                                                color: _ink,
                                                                fontSize: 13,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700,
                                                                letterSpacing:
                                                                    0.6,
                                                              ),
                                                        ),
                                                      ),
                                                    if (_selectedPhotoCount !=
                                                            null &&
                                                        !_rentModeEnabled &&
                                                        !_isTestMode &&
                                                        coinSlotConnected &&
                                                        !_paidPhotoPending) ...[
                                                      const SizedBox(height: 8),
                                                      Row(
                                                        mainAxisAlignment:
                                                            MainAxisAlignment
                                                                .center,
                                                        children: [
                                                          const Icon(
                                                            Icons
                                                                .payments_rounded,
                                                            color: _accent,
                                                            size: 16,
                                                          ),
                                                          const SizedBox(
                                                            width: 6,
                                                          ),
                                                          AnimatedSwitcher(
                                                            duration:
                                                                const Duration(
                                                                  milliseconds:
                                                                      180,
                                                                ),
                                                            child: Text(
                                                              'INSERTED ₱${_credits ?? 0} / ₱$_requiredCredits',
                                                              key: ValueKey(
                                                                'inserted-credits-$_credits-$_requiredCredits',
                                                              ),
                                                              style: const TextStyle(
                                                                color: _accent,
                                                                fontSize: 13,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w900,
                                                                letterSpacing:
                                                                    0.35,
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                      const SizedBox(height: 5),
                                                      SizedBox(
                                                        width: 150,
                                                        child: LinearProgressIndicator(
                                                          value:
                                                              _requiredCredits <=
                                                                  0
                                                              ? 0
                                                              : (_credits ?? 0)
                                                                        .clamp(
                                                                          0,
                                                                          _requiredCredits,
                                                                        ) /
                                                                    _requiredCredits,
                                                          minHeight: 4,
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                4,
                                                              ),
                                                          backgroundColor:
                                                              _outline,
                                                          color: _accent,
                                                        ),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(height: 12),
                                              if ((!_payMongoPaymentsEnabled ||
                                                      !_activationAllowsPayMongo) &&
                                                  !coinSlotConnected)
                                                if (!_rentModeEnabled)
                                                  Container(
                                                    constraints:
                                                        const BoxConstraints(
                                                          minHeight: 52,
                                                        ),
                                                    width: double.infinity,
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 16,
                                                          vertical: 9,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: _panel,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            14,
                                                          ),
                                                    ),
                                                    child: Row(
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .center,
                                                      children: [
                                                        Icon(
                                                          _credits == null
                                                              ? Icons
                                                                    .info_outline_rounded
                                                              : Icons
                                                                    .check_circle_rounded,
                                                          color:
                                                              _credits == null
                                                              ? const Color(
                                                                  0xFFB42318,
                                                                )
                                                              : const Color(
                                                                  0xFF287D3C,
                                                                ),
                                                          size: 24,
                                                        ),
                                                        const SizedBox(
                                                          width: 10,
                                                        ),
                                                        Flexible(
                                                          child: AnimatedSwitcher(
                                                            duration:
                                                                const Duration(
                                                                  milliseconds:
                                                                      200,
                                                                ),
                                                            transitionBuilder:
                                                                (
                                                                  child,
                                                                  animation,
                                                                ) => FadeTransition(
                                                                  opacity:
                                                                      animation,
                                                                  child: SlideTransition(
                                                                    position: Tween<Offset>(
                                                                      begin:
                                                                          const Offset(
                                                                            0,
                                                                            0.06,
                                                                          ),
                                                                      end: Offset
                                                                          .zero,
                                                                    ).animate(animation),
                                                                    child:
                                                                        child,
                                                                  ),
                                                                ),
                                                            child: Text(
                                                              _message,
                                                              key: ValueKey(
                                                                _message,
                                                              ),
                                                              textAlign:
                                                                  TextAlign
                                                                      .center,
                                                              style: const TextStyle(
                                                                color: _ink,
                                                                fontSize: 16,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                              if ((_rentModeEnabled ||
                                                      _paidPhotoPending ||
                                                      _coinPaymentReady) &&
                                                  !_photoInProgress &&
                                                  !_boothPaused) ...[
                                                const SizedBox(height: 10),
                                                SizedBox(
                                                  width: double.infinity,
                                                  height: 60,
                                                  child: _AnimatedStartButton(
                                                    onPressed: _cameraReady
                                                        ? () => unawaited(
                                                            _startPhotoSession(),
                                                          )
                                                        : null,
                                                  ),
                                                ),
                                              ],
                                              if (_isTestMode &&
                                                  !_rentModeEnabled) ...[
                                                const SizedBox(height: 8),
                                                const Text(
                                                  'ESP32 AND COIN PAYMENT BYPASSED',
                                                  style: TextStyle(
                                                    color: _muted,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 11,
                                                    letterSpacing: 0.8,
                                                  ),
                                                ),
                                                const SizedBox(height: 10),
                                                SizedBox(
                                                  width: double.infinity,
                                                  height: 60,
                                                  child: _AnimatedStartButton(
                                                    onPressed:
                                                        _cameraReady &&
                                                            _selectedPhotoCount !=
                                                                null &&
                                                            !_boothPaused
                                                        ? () => unawaited(
                                                            _startPhotoSession(
                                                              testMode: true,
                                                            ),
                                                          )
                                                        : null,
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 340,
                                ),
                                child: SizedBox(
                                  width: 280,
                                  height: 72,
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: _handleLogoTap,
                                    child: Center(
                                      child: _buildAnimatedBrandLogo(
                                        animation: _brandLogoAnimation,
                                        width: 180,
                                        height: 64,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            if (_countdownSeconds case final seconds?)
              Positioned.fill(
                child: Padding(
                  padding: portraitCapture
                      ? EdgeInsets.fromLTRB(
                          captureSideInset,
                          captureSideInset,
                          captureSideInset,
                          captureBottomInset,
                        )
                      : EdgeInsets.zero,
                  child: IgnorePointer(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 240),
                            transitionBuilder: (child, animation) =>
                                ScaleTransition(scale: animation, child: child),
                            child: Text(
                              '$seconds',
                              key: ValueKey(seconds),
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: min(
                                  103.0,
                                  min(screenSize.width, screenSize.height) *
                                      0.252,
                                ),
                                fontWeight: FontWeight.w800,
                                height: 1,
                                shadows: const [
                                  Shadow(
                                    color: Colors.black87,
                                    blurRadius: 16,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            seconds == 1 ? 'Smile!' : 'GET READY',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.1,
                              shadows: [
                                Shadow(color: Colors.black87, blurRadius: 10),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            _buildActivationGate(),
            if (showCoinProgressModal)
              Positioned.fill(
                child: _buildCoinPaymentPage(phoneLayout: phoneLayout),
              ),
            if (_preparingPhoto)
              Positioned.fill(
                child: ColoredBox(
                  color: Color(0xCC101114),
                  child: SafeArea(
                    child: Center(
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 420),
                        margin: const EdgeInsets.all(24),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 28,
                          vertical: 32,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black26,
                              blurRadius: 24,
                              offset: Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox.square(
                              dimension: 56,
                              child: CircularProgressIndicator(
                                strokeWidth: 5,
                                color: _accent,
                              ),
                            ),
                            const SizedBox(height: 24),
                            const Text(
                              'Please wait a moment...',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: _ink,
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Your photo is almost ready.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: _muted,
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _softCopyEndpoint.isNotEmpty
                                  ? 'Preparing and saving your photo...'
                                  : 'Preparing your full-quality photo...',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: _muted,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (_boothUnavailable && !_preparingPhoto)
              Positioned.fill(
                child: Stack(
                  children: [
                    ColoredBox(
                      color: Color(0xFFF8FAFC),
                      child: Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.camera_alt_outlined,
                                color: _muted,
                                size: 52,
                              ),
                              SizedBox(height: 16),
                              Text(
                                'Booth temporarily unavailable',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: _ink,
                                  fontSize: 23,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                'Please ask the attendant for assistance.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: _muted),
                              ),
                              if (_lastBoothError case final error?) ...[
                                SizedBox(height: 10),
                                Text(
                                  error,
                                  textAlign: TextAlign.center,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Color(0xFFB42318),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (_homeTransitioning)
                                  const Positioned.fill(
                                    child: _BarcodeWaveTransition(),
                                  ),
                              ],
                              SizedBox(height: 10),
                              Text(
                                'Attendant: tap the top-left corner five times for admin diagnostics.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: _muted, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 0,
                      left: 0,
                      width: 84,
                      height: 84,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _handleRecoveryTap,
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
