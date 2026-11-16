import 'package:flutter/services.dart';

class KioskMode {
  KioskMode({this._channel = const MethodChannel('photobooth/kiosk')});

  final MethodChannel _channel;
  bool _entered = false;

  bool get isEntered => _entered;

  Future<bool> enter() async {
    final active =
        await _channel.invokeMethod<bool>('enableKioskMode') ?? false;
    if (!active) return false;
    await _channel.invokeMethod<void>('setScreenAwake', true);
    _entered = true;
    return true;
  }

  Future<void> exit() async {
    await _channel.invokeMethod<bool>('exitKioskMode');
    final active = await _channel.invokeMethod<bool>('isKioskActive') ?? false;
    if (active) {
      throw StateError('Android is still in Lock Task Mode.');
    }
    await _channel.invokeMethod<void>('setScreenAwake', false);
    _entered = false;
  }

  Future<void> synchronize(bool entered) async {
    _entered = entered;
    await _channel.invokeMethod<void>('setScreenAwake', entered);
  }

  Future<void> restartApp() => _channel.invokeMethod<void>('restartBoothApp');

  Future<void> rebootDevice() => _channel.invokeMethod<void>('rebootDevice');
}
