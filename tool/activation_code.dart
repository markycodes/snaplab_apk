import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:photobooth_kiosk/trial_activation_duration.dart';

const _context = 'photobooth-kiosk-activation-v3:';
const _trialContext = 'photobooth-kiosk-trial-activation-v1:';
const _availableFeatures = {
  '--paymongo': 'paymongo_qrph',
  '--ganap': 'ganap_qrph',
};

Future<void> main(List<String> arguments) async {
  if (arguments.length == 2 && arguments.first == 'keygen') {
    await _generateKey(arguments[1]);
    return;
  }
  if (arguments.length == 4 && arguments.first == 'issue-trial') {
    await _issueTrialCode(arguments[1], arguments[2], arguments[3]);
    return;
  }
  if (arguments.length >= 3 && arguments.first == 'issue') {
    await _issueCode(arguments[1], arguments[2], arguments.skip(3).toList());
    return;
  }
  stderr.writeln(
    'Usage:\n'
    '  dart run tool/activation_code.dart keygen <private-key-file>\n'
    '  dart run tool/activation_code.dart issue-trial <private-key-file> <device-id> <duration>\n'
    '  dart run tool/activation_code.dart issue <private-key-file> <device-id> [--paymongo] [--ganap]\n'
    'Trial duration examples: 30m (minutes), 2h (hours), 14d (days); bare numbers mean days.\n'
    'Trial codes allow coin payments, disable QR payment, and expire after the selected duration (max 365 days).\n'
    'Payment features are off unless their option is explicitly selected.',
  );
  exitCode = 64;
}

Future<void> _generateKey(String path) async {
  final keyFile = File(path);
  if (await keyFile.exists()) {
    throw StateError(
      'Refusing to overwrite an existing key. Choose a new filename.',
    );
  }
  await keyFile.parent.create(recursive: true);

  final keyPair = await Ed25519().newKeyPair();
  final privateKey = await keyPair.extractPrivateKeyBytes();
  final publicKey = await keyPair.extractPublicKey();
  await keyFile.writeAsString(
    jsonEncode({'seed': base64Url.encode(privateKey)}),
    flush: true,
  );
  stdout.writeln(
    'Owner public key (copy into lib/device_activation.dart): '
    '${_hex(publicKey.bytes)}',
  );
  stdout.writeln('Private key saved to: ${keyFile.absolute.path}');
  stdout.writeln(
    'Keep the private key secure and backed up; never add it to the app or APK.',
  );
}

Future<void> _issueTrialCode(
  String path,
  String deviceId,
  String durationText,
) async {
  if (!RegExp(r'^[A-Za-z0-9._:-]{8,128}$').hasMatch(deviceId)) {
    throw const FormatException('The device ID format is invalid.');
  }
  final duration = parseTrialDuration(durationText);
  final keyPair = await _loadOwnerKey(path);
  final expiresAt = DateTime.now().toUtc().add(duration);
  final expirySeconds = expiresAt.millisecondsSinceEpoch ~/ 1000;
  final signature = await Ed25519().sign(
    utf8.encode('$_trialContext$deviceId:$expirySeconds'),
    keyPair: keyPair,
  );
  final encodedSignature = base64Url
      .encode(signature.bytes)
      .replaceAll('=', '');
  final activationCode =
      '4${expirySeconds.toRadixString(16).padLeft(8, '0')}$encodedSignature';
  stdout.writeln('Trial activation code: $activationCode');
  stdout.writeln(
    'Trial duration: ${formatTrialDuration(duration)} from code generation',
  );
  stdout.writeln('Trial expires at: ${expiresAt.toIso8601String()}');
  stdout.writeln('Coin payments: enabled; QR payments: disabled');
  stdout.writeln('This code activates only device ID: $deviceId');
}

Future<void> _issueCode(
  String path,
  String deviceId,
  List<String> featureOptions,
) async {
  if (!RegExp(r'^[A-Za-z0-9._:-]{8,128}$').hasMatch(deviceId)) {
    throw const FormatException('The device ID format is invalid.');
  }
  final selectedFeatures = <String>[];
  for (final option in featureOptions) {
    final feature = _availableFeatures[option];
    if (feature == null || selectedFeatures.contains(feature)) {
      throw FormatException('Unknown or duplicate activation option: $option');
    }
    selectedFeatures.add(feature);
  }
  selectedFeatures.sort();
  final keyPair = await _loadOwnerKey(path);
  final algorithm = Ed25519();
  final featureMask = selectedFeatures.fold<int>(
    0,
    (mask, feature) => mask | (feature == 'paymongo_qrph' ? 1 : 2),
  );
  final signature = await algorithm.sign(
    utf8.encode('$_context$deviceId:$featureMask'),
    keyPair: keyPair,
  );
  final encodedSignature = base64Url
      .encode(signature.bytes)
      .replaceAll('=', '');
  final activationCode = '3$featureMask$encodedSignature';
  stdout.writeln('Activation code: $activationCode');
  stdout.writeln('Activation code characters: ${activationCode.length}');
  stdout.writeln(
    selectedFeatures.isEmpty
        ? 'Payment features: none'
        : 'Payment features: ${selectedFeatures.join(', ')}',
  );
  stdout.writeln('This code activates only device ID: $deviceId');
}

Future<SimpleKeyPair> _loadOwnerKey(String path) async {
  final keyFile = File(path);
  if (!await keyFile.exists()) {
    throw StateError('Private key not found: ${keyFile.absolute.path}');
  }
  final keyJson = jsonDecode(await keyFile.readAsString());
  if (keyJson is! Map<String, dynamic> || keyJson['seed'] is! String) {
    throw const FormatException('The owner private-key file is invalid.');
  }
  final encodedSeed = keyJson['seed'] as String;
  final seed = base64Url.decode(
    '$encodedSeed${'=' * ((4 - encodedSeed.length % 4) % 4)}',
  );
  return Ed25519().newKeyPairFromSeed(seed);
}

String _hex(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
