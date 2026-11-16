import 'dart:io';

import 'package:flutter/services.dart';

const _kioskChannel = MethodChannel('photobooth/kiosk');

Future<File> composeSessionVideo({
  required List<File> clips,
  required File posePhoto,
  required List<Rect> photoSlots,
  required int countdownSeconds,
}) async {
  if (clips.isEmpty || clips.length != photoSlots.length) {
    throw ArgumentError('At least one captured video clip is required.');
  }
  if (countdownSeconds < 1 || countdownSeconds > 5) {
    throw ArgumentError.value(countdownSeconds, 'countdownSeconds');
  }

  final output = File('${posePhoto.path}.session.mp4');
  final outputPath = await _kioskChannel.invokeMethod<String>(
    'composeSessionVideo',
    <String, Object>{
      'videoPaths': clips.map((clip) => clip.path).toList(growable: false),
      'posePhotoPath': posePhoto.path,
      'outputPath': output.path,
      'countdownSeconds': countdownSeconds,
      'photoSlots': photoSlots
          .map((slot) => <double>[slot.left, slot.top, slot.right, slot.bottom])
          .toList(growable: false),
    },
  );
  if (outputPath != output.path || !await output.exists()) {
    throw StateError('The moving photo video could not be created.');
  }
  return output;
}
