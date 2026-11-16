import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth_kiosk/kiosk_mode.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('photobooth/kiosk');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('exit verifies that Android left Lock Task Mode', () async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return call.method == 'isKioskActive' ? false : null;
        });

    await KioskMode().exit();

    expect(calls, ['exitKioskMode', 'isKioskActive', 'setScreenAwake']);
  });

  test('exit fails if Android remains in Lock Task Mode', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          return call.method == 'isKioskActive' ? true : null;
        });

    await expectLater(
      KioskMode().exit(),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'Android is still in Lock Task Mode.',
        ),
      ),
    );
  });
}
