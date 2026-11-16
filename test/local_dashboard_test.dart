import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth_kiosk/local_dashboard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalDashboardServer dashboard;
  late Uri baseUri;
  var paused = false;
  var salesReset = false;
  var capturedCount = 0;
  Map<String, Object?>? savedSettings;
  List<int>? uploadedBytes;
  String? uploadedType;

  setUp(() async {
    dashboard = LocalDashboardServer(
      port: 0,
      statusProvider: () => {
        'cameraReady': true,
        'paused': paused,
        'batteryPercent': 86,
        'charging': true,
      },
      authenticate: (password) async => password == 'admin-password',
      updateSettings: (settings) async => savedSettings = settings,
      setPaused: (value) async => paused = value,
      resetSales: () async => salesReset = true,
      startCapture: (count) => capturedCount = count,
      updateMedia: (type, filename, bytes) async {
        uploadedType = type;
        uploadedBytes = bytes;
      },
    );
    await dashboard.start();
    baseUri = Uri.parse('http://127.0.0.1:${dashboard.listeningPort}');
  });

  tearDown(() async {
    await dashboard.stop();
  });

  test('requires admin login before returning booth status', () async {
    final response = await _request(baseUri, 'GET', '/api/status');
    expect(response.statusCode, HttpStatus.unauthorized);
  });

  test('serves separate dashboard pages with sidebar navigation', () async {
    final response = await _request(baseUri, 'GET', '/');
    expect(response.statusCode, HttpStatus.ok);
    expect(response.body, contains('data-page="overview"'));
    expect(response.body, contains('data-page="sales"'));
    expect(response.body, contains('data-page="activity"'));
    expect(response.body, contains('data-page="settings"'));
    expect(response.body, contains('data-page="media"'));
    expect(response.body, contains('data-page="capture"'));
    expect(response.body, contains('data-view="overview"'));
    expect(response.body, contains('data-view="sales"'));
    expect(response.body, contains('data-view="settings"'));
    expect(response.body, contains('data-view="media"'));
    expect(response.body, contains('salesChart'));
    expect(response.body, contains('id="resetSales"'));
    expect(response.body, contains('/api/sales/reset'));
    expect(response.body, contains('name="rentModeEnabled"'));
    expect(response.body, contains('name="coinPricePesos"'));
    expect(response.body, contains('min="1" max="100000"'));
    expect(response.body, contains('name="payMongoAmountPesos"'));
    expect(response.body, contains('name="payMongoPaymentsEnabled"'));
    expect(
      response.body,
      contains("['Charging',s.charging==null?'Unknown':s.charging?'Yes':'No']"),
    );
    expect(response.body, contains("'rentModeEnabled'"));
    expect(response.body, contains('Sales this week'));
    expect(response.body, contains("['Coin sales',summary.totalCoinSales]"));
    expect(response.body, contains("['QR Ph sales',summary.totalQrPhSales]"));
    expect(
      response.body,
      contains("['Coin sales today',summary.coinSalesToday]"),
    );
    expect(
      response.body,
      contains("['QR Ph sales today',summary.qrPhSalesToday]"),
    );
    expect(
      response.body,
      contains("['Coin sales this week',summary.coinSalesThisWeek]"),
    );
    expect(
      response.body,
      contains("['QR Ph sales this week',summary.qrPhSalesThisWeek]"),
    );
    expect(response.body, contains('async function restoreSession()'));
    expect(response.body, contains('restoreSession();'));
  });

  test('admin session can read status and control booth operations', () async {
    final login = await _request(
      baseUri,
      'POST',
      '/api/login',
      body: {'password': 'admin-password'},
    );
    expect(login.statusCode, HttpStatus.ok);
    final cookie = login.cookies.single;

    final status = await _request(
      baseUri,
      'GET',
      '/api/status',
      cookie: cookie,
    );
    expect(status.statusCode, HttpStatus.ok);
    expect(status.cookies.single.value, cookie.value);
    expect(status.cookies.single.maxAge, 30 * 60);
    expect(jsonDecode(status.body), {
      'cameraReady': true,
      'paused': false,
      'batteryPercent': 86,
      'charging': true,
    });

    final pauseResponse = await _request(
      baseUri,
      'POST',
      '/api/pause',
      body: {'paused': true},
      cookie: cookie,
    );
    expect(pauseResponse.statusCode, HttpStatus.ok);
    expect(paused, isTrue);

    final resetSalesResponse = await _request(
      baseUri,
      'POST',
      '/api/sales/reset',
      body: {},
      cookie: cookie,
    );
    expect(resetSalesResponse.statusCode, HttpStatus.ok);
    expect(salesReset, isTrue);

    final captureResponse = await _request(
      baseUri,
      'POST',
      '/api/capture',
      body: {'photoCount': 3},
      cookie: cookie,
    );
    expect(captureResponse.statusCode, HttpStatus.accepted);
    expect(capturedCount, 3);

    final settingsResponse = await _request(
      baseUri,
      'POST',
      '/api/settings',
      body: {
        'coinPricePesos': 35,
        'payMongoAmountPesos': 75,
        'payMongoPaymentsEnabled': true,
      },
      cookie: cookie,
    );
    expect(settingsResponse.statusCode, HttpStatus.ok);
    expect(savedSettings, {
      'coinPricePesos': 35,
      'payMongoAmountPesos': 75,
      'payMongoPaymentsEnabled': true,
    });

    final mediaResponse = await _request(
      baseUri,
      'POST',
      '/api/media?type=walletQr',
      rawBody: [1, 2, 3, 4],
      filename: 'wallet.png',
      cookie: cookie,
    );
    expect(mediaResponse.statusCode, HttpStatus.ok);
    expect(uploadedType, 'walletQr');
    expect(uploadedBytes, [1, 2, 3, 4]);
  });

  test('rejects invalid login and out-of-range remote capture', () async {
    final badLogin = await _request(
      baseUri,
      'POST',
      '/api/login',
      body: {'password': 'incorrect'},
    );
    expect(badLogin.statusCode, HttpStatus.unauthorized);

    final login = await _request(
      baseUri,
      'POST',
      '/api/login',
      body: {'password': 'admin-password'},
    );
    final badCapture = await _request(
      baseUri,
      'POST',
      '/api/capture',
      body: {'photoCount': 6},
      cookie: login.cookies.single,
    );
    expect(badCapture.statusCode, HttpStatus.badRequest);
  });
}

Future<_DashboardResponse> _request(
  Uri baseUri,
  String method,
  String path, {
  Map<String, Object?>? body,
  List<int>? rawBody,
  String? filename,
  Cookie? cookie,
}) async {
  final socket = await Socket.connect(baseUri.host, baseUri.port);
  final requestBody = body == null ? '' : jsonEncode(body);
  final requestBytes = rawBody ?? utf8.encode(requestBody);
  final headers = <String>[
    '$method $path HTTP/1.1',
    'Host: ${baseUri.host}:${baseUri.port}',
    'Connection: close',
    if (rawBody != null) 'Content-Type: application/octet-stream',
    if (body != null) 'Content-Type: application/json',
    if (body != null || rawBody != null)
      'Content-Length: ${requestBytes.length}',
    if (filename != null) 'X-Dashboard-Filename: $filename',
    if (cookie != null) 'Cookie: ${cookie.name}=${cookie.value}',
    '',
    '',
  ];
  socket.add([...utf8.encode(headers.join('\r\n')), ...requestBytes]);
  await socket.flush();
  final responseBytes = await socket.fold<BytesBuilder>(
    BytesBuilder(copy: false),
    (builder, chunk) => builder..add(chunk),
  );
  final responseText = utf8.decode(responseBytes.takeBytes());
  final delimiter = responseText.indexOf('\r\n\r\n');
  final responseHeaders = responseText.substring(0, delimiter).split('\r\n');
  final statusCode = int.parse(responseHeaders.first.split(' ')[1]);
  final cookies = responseHeaders
      .where((header) => header.toLowerCase().startsWith('set-cookie:'))
      .map(
        (header) => Cookie.fromSetCookieValue(
          header.substring('set-cookie:'.length).trim(),
        ),
      )
      .toList();
  return _DashboardResponse(
    statusCode: statusCode,
    cookies: cookies,
    body: responseText.substring(delimiter + 4),
  );
}

class _DashboardResponse {
  const _DashboardResponse({
    required this.statusCode,
    required this.cookies,
    required this.body,
  });

  final int statusCode;
  final List<Cookie> cookies;
  final String body;
}
