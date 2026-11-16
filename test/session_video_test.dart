import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth_kiosk/session_video.dart';

void main() {
  test('requires one photo opening per recorded clip', () async {
    await expectLater(
      composeSessionVideo(
        clips: [File('clip.mp4')],
        posePhoto: File('photo.png'),
        photoSlots: const [],
        countdownSeconds: 3,
      ),
      throwsArgumentError,
    );
  });

  test('only accepts supported countdown durations', () async {
    await expectLater(
      composeSessionVideo(
        clips: [File('clip.mp4')],
        posePhoto: File('photo.png'),
        photoSlots: const [Rect.fromLTWH(0.1, 0.1, 0.8, 0.8)],
        countdownSeconds: 6,
      ),
      throwsArgumentError,
    );
  });
}
