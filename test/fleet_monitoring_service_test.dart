import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:photobooth_kiosk/fleet_monitoring_service.dart';

void main() {
  final activationCode = List.filled(86, 'A').join();

  test('requires an HTTPS fleet endpoint', () {
    expect(
      FleetMonitoringService.validateEndpoint(
        'https://snaplabbooth.com/pb_fleet_ingest.php',
      ).scheme,
      'https',
    );
    expect(
      () => FleetMonitoringService.validateEndpoint(
        'http://snaplabbooth.com/pb_fleet_ingest.php',
      ),
      throwsFormatException,
    );
  });

  test('posts activation-bound booth and sales telemetry', () async {
    Map<String, dynamic>? sent;
    final service = FleetMonitoringService(
      client: MockClient((request) async {
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({'ok': true, 'settings': {}, 'command': null}),
          200,
        );
      }),
    );

    await service.report(
      endpoint: 'https://snaplabbooth.com/pb_fleet_ingest.php',
      deviceId: 'test-device-123',
      activationCode: activationCode,
      status: const {'esp32Connected': true},
      sales: const {'totalSales': 80},
    );

    expect(sent?['deviceId'], 'test-device-123');
    expect(sent?['activationCode'], activationCode);
    expect(sent?['status']['esp32Connected'], isTrue);
    expect(sent?['sales']['totalSales'], 80);
  });

  test('includes non-secret app settings in Fleet telemetry', () async {
    Map<String, dynamic>? sent;
    final service = FleetMonitoringService(
      client: MockClient((request) async {
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({'ok': true, 'settings': {}, 'command': null}),
          200,
        );
      }),
    );
    const appSettings = {
      'eventTheme': 'birthday',
      'printerType': 'receipt',
      'coinPricePesos': 25,
    };

    await service.report(
      endpoint: 'https://snaplabbooth.com/pb_fleet_ingest.php',
      deviceId: 'test-device-123',
      activationCode: activationCode,
      status: const {'appSettings': appSettings},
      sales: const {},
    );

    expect(sent?['status']['appSettings'], appSettings);
  });

  test('accepts the compact signed activation code format', () async {
    final compactCode = '33${List.filled(86, 'A').join()}';
    Map<String, dynamic>? sent;
    final service = FleetMonitoringService(
      client: MockClient((request) async {
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({'ok': true, 'settings': {}, 'command': null}),
          200,
        );
      }),
    );

    await service.report(
      endpoint: 'https://snaplabbooth.com/pb_fleet_ingest.php',
      deviceId: 'test-device-123',
      activationCode: compactCode,
      status: const {},
      sales: const {},
    );

    expect(sent?['activationCode'], compactCode);
  });

  test('returns queued fleet settings and commands from the server', () async {
    final service = FleetMonitoringService(
      client: MockClient((request) async {
        final sent = jsonDecode(request.body) as Map<String, dynamic>;
        expect(sent['commandResult'], {
          'commandId': 12,
          'status': 'complete',
          'message': 'app_restart_requested',
        });
        expect(sent['status']['latitude'], closeTo(14.6, 0.01));
        return http.Response(
          jsonEncode({
            'ok': true,
            'settings': {'eventTheme': 'coffeeCup'},
            'command': {'commandId': 13, 'name': 'reboot_device'},
          }),
          200,
        );
      }),
    );

    final response = await service.report(
      endpoint: 'https://snaplabbooth.com/pb_fleet_ingest.php',
      deviceId: 'test-device-123',
      activationCode: activationCode,
      status: const {'latitude': 14.6},
      sales: const {},
      commandResult: const {
        'commandId': 12,
        'status': 'complete',
        'message': 'app_restart_requested',
      },
    );

    expect(response['settings'], {'eventTheme': 'coffeeCup'});
    expect(response['command'], {'commandId': 13, 'name': 'reboot_device'});
  });

  test('surfaces a rejected telemetry report', () async {
    final service = FleetMonitoringService(
      client: MockClient(
        (_) async =>
            http.Response(jsonEncode({'error': 'activation_required'}), 401),
      ),
    );

    await expectLater(
      service.report(
        endpoint: 'https://snaplabbooth.com/pb_fleet_ingest.php',
        deviceId: 'test-device-123',
        activationCode: activationCode,
        status: const {},
        sales: const {},
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('HTTP 401 (activation_required)'),
        ),
      ),
    );
  });
}
