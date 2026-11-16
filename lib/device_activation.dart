import 'dart:convert';

import 'package:cryptography/cryptography.dart';

const activationPublicKeyHex =
    'b1ce6da0d0418573f7546b00017115b3f2cdef9e9aa234db235443103fa86a67';

const _legacyActivationContext = 'photobooth-kiosk-activation-v1:';
const _activationV2Context = 'photobooth-kiosk-activation-v2:';
const _activationV3Context = 'photobooth-kiosk-activation-v3:';
const _trialActivationContext = 'photobooth-kiosk-trial-activation-v1:';

enum ActivationFeature {
  payMongoQrPh('paymongo_qrph'),
  ganapQrPh('ganap_qrph');

  const ActivationFeature(this.token);

  final String token;
}

class DeviceActivation {
  const DeviceActivation({
    required this.deviceId,
    required this.features,
    this.expiresAt,
  });

  final String deviceId;
  final Set<ActivationFeature> features;
  final DateTime? expiresAt;

  bool isExpiredAt(DateTime time) =>
      expiresAt != null && !expiresAt!.isAfter(time);

  bool allows(ActivationFeature feature) => features.contains(feature);
}

String normalizeDeviceActivationCode(String code) =>
    code.replaceAll(RegExp(r'\s'), '').replaceFirst(RegExp(r'=+$'), '');

bool hasSupportedDeviceActivationCodeFormat(String code) {
  final normalizedCode = normalizeDeviceActivationCode(code);
  return RegExp(r'^[A-Za-z0-9_-]{86}$').hasMatch(normalizedCode) ||
      RegExp(r'^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]{86}$').hasMatch(normalizedCode) ||
      RegExp(r'^3[0-3][A-Za-z0-9_-]{86}$').hasMatch(normalizedCode) ||
      RegExp(r'^4[0-9a-fA-F]{8}[A-Za-z0-9_-]{86}$').hasMatch(normalizedCode);
}

Future<DeviceActivation?> parseDeviceActivationCode({
  required String deviceId,
  required String code,
  String publicKeyHex = activationPublicKeyHex,
}) async {
  if (deviceId.isEmpty || code.isEmpty || publicKeyHex.length != 64) {
    return null;
  }

  try {
    final normalizedCode = normalizeDeviceActivationCode(code);
    if (normalizedCode.length > 512) return null;
    final publicKeyBytes = <int>[
      for (var index = 0; index < publicKeyHex.length; index += 2)
        int.parse(publicKeyHex.substring(index, index + 2), radix: 16),
    ];
    final publicKey = SimplePublicKey(
      publicKeyBytes,
      type: KeyPairType.ed25519,
    );

    final components = normalizedCode.split('.');
    final List<int> signatureBytes;
    final List<int> signedMessage;
    final Set<ActivationFeature> features;
    DateTime? expiresAt;
    if (RegExp(r'^4[0-9a-fA-F]{8}[A-Za-z0-9_-]{86}$')
        .hasMatch(normalizedCode)) {
      final expirySeconds = int.parse(
        normalizedCode.substring(1, 9),
        radix: 16,
      );
      expiresAt = DateTime.fromMillisecondsSinceEpoch(
        expirySeconds * 1000,
        isUtc: true,
      );
      signatureBytes = _decodeBase64Url(normalizedCode.substring(9));
      signedMessage = utf8.encode(
        '$_trialActivationContext$deviceId:$expirySeconds',
      );
      features = const <ActivationFeature>{};
    } else if (RegExp(r'^3[0-3][A-Za-z0-9_-]{86}$').hasMatch(normalizedCode)) {
      final featureMask = int.parse(normalizedCode[1]);
      signatureBytes = _decodeBase64Url(normalizedCode.substring(2));
      signedMessage = utf8.encode(
        '$_activationV3Context$deviceId:$featureMask',
      );
      features = {
        if ((featureMask & 1) != 0) ActivationFeature.payMongoQrPh,
        if ((featureMask & 2) != 0) ActivationFeature.ganapQrPh,
      };
    } else if (components.length == 1) {
      signatureBytes = _decodeBase64Url(components.single);
      signedMessage = utf8.encode('$_legacyActivationContext$deviceId');
      features = const <ActivationFeature>{};
    } else if (components.length == 2) {
      final payloadBytes = _decodeBase64Url(components[0]);
      signatureBytes = _decodeBase64Url(components[1]);
      final payload = jsonDecode(utf8.decode(payloadBytes));
      if (payload is! Map<String, dynamic> ||
          payload['version'] != 2 ||
          payload['deviceId'] != deviceId ||
          payload['features'] is! List<dynamic>) {
        return null;
      }
      final featureTokens = payload['features'] as List<dynamic>;
      if (featureTokens.length > ActivationFeature.values.length) return null;
      final parsedFeatures = <ActivationFeature>{};
      for (final token in featureTokens) {
        if (token is! String) return null;
        final feature = _activationFeatureForToken(token);
        if (feature == null || !parsedFeatures.add(feature)) return null;
      }
      features = parsedFeatures;
      signedMessage = utf8.encode('$_activationV2Context${components[0]}');
    } else {
      return null;
    }
    if (signatureBytes.length != 64) return null;
    final verified = await Ed25519().verify(
      signedMessage,
      signature: Signature(signatureBytes, publicKey: publicKey),
    );
    return verified
        ? DeviceActivation(
            deviceId: deviceId,
            features: features,
            expiresAt: expiresAt,
          )
        : null;
  } on FormatException {
    return null;
  } on ArgumentError {
    return null;
  }
}

Future<bool> verifyDeviceActivationCode({
  required String deviceId,
  required String code,
  String publicKeyHex = activationPublicKeyHex,
}) async {
  return await parseDeviceActivationCode(
        deviceId: deviceId,
        code: code,
        publicKeyHex: publicKeyHex,
      ) !=
      null;
}

List<int> _decodeBase64Url(String value) {
  final normalized = value.replaceAll('-', '+').replaceAll('_', '/');
  return base64.decode('$normalized${'=' * ((4 - normalized.length % 4) % 4)}');
}

ActivationFeature? _activationFeatureForToken(String token) {
  for (final feature in ActivationFeature.values) {
    if (feature.token == token) return feature;
  }
  return null;
}
