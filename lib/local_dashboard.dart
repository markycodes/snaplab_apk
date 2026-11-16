import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

typedef DashboardStatusProvider = Map<String, Object?> Function();
typedef DashboardAuthenticator = Future<bool> Function(String password);
typedef DashboardSettingsHandler = Future<void> Function(
  Map<String, Object?> settings,
);
typedef DashboardPauseHandler = Future<void> Function(bool paused);
typedef DashboardSalesResetHandler = Future<void> Function();
typedef DashboardCaptureHandler = void Function(int photoCount);
typedef DashboardMediaHandler = Future<void> Function(
  String type,
  String? filename,
  List<int>? bytes,
);

class LocalDashboardServer {
  LocalDashboardServer({
    required this.statusProvider,
    required this.authenticate,
    required this.updateSettings,
    required this.setPaused,
    required this.resetSales,
    required this.startCapture,
    required this.updateMedia,
    this.port = 8765,
  });

  final DashboardStatusProvider statusProvider;
  final DashboardAuthenticator authenticate;
  final DashboardSettingsHandler updateSettings;
  final DashboardPauseHandler setPaused;
  final DashboardSalesResetHandler resetSales;
  final DashboardCaptureHandler startCapture;
  final DashboardMediaHandler updateMedia;
  final int port;

  final Map<String, DateTime> _sessions = {};
  final Map<String, List<DateTime>> _failedLogins = {};
  final Random _random = Random.secure();
  HttpServer? _server;
  List<String> _urls = const [];

  List<String> get urls => _urls;
  bool get isRunning => _server != null;
  int? get listeningPort => _server?.port;

  Future<void> start() async {
    if (_server != null) return;
    final server = await HttpServer.bind(
      InternetAddress.anyIPv4,
      port,
      shared: false,
    );
    _server = server;
    try {
      _urls = await _findDashboardUrls(server.port);
    } on Object {
      _server = null;
      await server.close(force: true);
      rethrow;
    }
    unawaited(_serveRequests(server));
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    _urls = const [];
    _sessions.clear();
    await server?.close(force: true);
  }

  Future<void> refreshNetworkAddresses() async {
    final server = _server;
    if (server == null) return;
    _urls = await _findDashboardUrls(server.port);
  }

  Future<void> _serveRequests(HttpServer server) async {
    await for (final request in server) {
      unawaited(_handleRequest(request));
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      request.response.headers
        ..set(HttpHeaders.cacheControlHeader, 'no-store')
        ..set('X-Content-Type-Options', 'nosniff')
        ..set('X-Frame-Options', 'DENY')
        ..set(
          'Content-Security-Policy',
          "default-src 'self'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; connect-src 'self'; img-src 'self' data:",
        );

      final path = request.uri.path;
      if (path == '/' && request.method == 'GET') {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.html
          ..contentLength = utf8.encode(_dashboardHtml).length
          ..write(_dashboardHtml);
        await request.response.close();
        return;
      }
      if (path == '/api/login' && request.method == 'POST') {
        await _login(request);
        return;
      }

      final session = _findSession(request);
      if (session == null) {
        await _writeJson(request.response, HttpStatus.unauthorized, {
          'error': 'Sign in again to use the dashboard.',
        });
        return;
      }

      switch ('${request.method} $path') {
        case 'GET /api/status':
          await _writeJson(request.response, HttpStatus.ok, statusProvider());
        case 'POST /api/settings':
          final body = await _readJson(request);
          await updateSettings(body);
          await _writeJson(request.response, HttpStatus.ok, {'ok': true});
        case 'POST /api/pause':
          final body = await _readJson(request);
          final paused = body['paused'];
          if (paused is! bool) {
            throw const FormatException(
              'The paused field must be true or false.',
            );
          }
          await setPaused(paused);
          await _writeJson(request.response, HttpStatus.ok, {'ok': true});
        case 'POST /api/sales/reset':
          await resetSales();
          await _writeJson(request.response, HttpStatus.ok, {'ok': true});
        case 'POST /api/capture':
          final body = await _readJson(request);
          final photoCount = body['photoCount'];
          if (photoCount is! int || photoCount < 1 || photoCount > 5) {
            throw const FormatException('Choose a photo count from 1 to 5.');
          }
          startCapture(photoCount);
          await _writeJson(request.response, HttpStatus.accepted, {'ok': true});
        case 'POST /api/media':
          final type = request.uri.queryParameters['type'];
          if (type == null || !_mediaLimits.containsKey(type)) {
            throw const FormatException('Choose a valid media type.');
          }
          final filename = request.headers.value('x-dashboard-filename');
          final bytes = await _readBytes(request, _mediaLimits[type]!);
          await updateMedia(type, filename, bytes);
          await _writeJson(request.response, HttpStatus.ok, {'ok': true});
        case 'DELETE /api/media':
          final type = request.uri.queryParameters['type'];
          if (type == null || !_mediaLimits.containsKey(type)) {
            throw const FormatException('Choose a valid media type.');
          }
          await updateMedia(type, null, null);
          await _writeJson(request.response, HttpStatus.ok, {'ok': true});
        case 'POST /api/logout':
          _sessions.remove(session);
          request.response.cookies.add(
            Cookie('booth_dashboard', '')
              ..path = '/'
              ..httpOnly = true
              ..sameSite = SameSite.strict
              ..expires = DateTime.fromMillisecondsSinceEpoch(0),
          );
          await _writeJson(request.response, HttpStatus.ok, {'ok': true});
        default:
          await _writeJson(request.response, HttpStatus.notFound, {
            'error': 'Not found.',
          });
      }
    } on FormatException catch (error) {
      await _writeJson(request.response, HttpStatus.badRequest, {
        'error': error.message,
      });
    } on Object catch (error, stackTrace) {
      stderr.writeln('Local dashboard request failed: $error\n$stackTrace');
      await _writeJson(request.response, HttpStatus.internalServerError, {
        'error': 'Dashboard request failed.',
      });
    }
  }

  Future<void> _login(HttpRequest request) async {
    final address = request.connectionInfo?.remoteAddress.address ?? 'unknown';
    final now = DateTime.now();
    final failures = (_failedLogins[address] ?? [])
        .where((time) => now.difference(time) < const Duration(minutes: 5))
        .toList();
    if (failures.length >= 5) {
      _failedLogins[address] = failures;
      await _writeJson(request.response, HttpStatus.tooManyRequests, {
        'error':
            'Too many failed attempts. Wait five minutes before trying again.',
      });
      return;
    }

    final body = await _readJson(request);
    final password = body['password'];
    if (password is! String || password.isEmpty) {
      throw const FormatException('Enter the admin password.');
    }
    if (!await authenticate(password)) {
      failures.add(now);
      _failedLogins[address] = failures;
      await _writeJson(request.response, HttpStatus.unauthorized, {
        'error': 'Incorrect admin password.',
      });
      return;
    }

    _failedLogins.remove(address);
    _sessions.removeWhere((_, expires) => !expires.isAfter(now));
    if (_sessions.length >= 32) {
      await _writeJson(request.response, HttpStatus.tooManyRequests, {
        'error': 'The dashboard already has too many active sessions.',
      });
      return;
    }
    final token = List<int>.generate(
      32,
      (_) => _random.nextInt(256),
    ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    _sessions[token] = now.add(const Duration(minutes: 30));
    request.response.cookies.add(_sessionCookie(token));
    await _writeJson(request.response, HttpStatus.ok, {'ok': true});
  }

  Cookie _sessionCookie(String token) => Cookie('booth_dashboard', token)
    ..path = '/'
    ..httpOnly = true
    ..sameSite = SameSite.strict
    ..maxAge = 30 * 60;

  String? _findSession(HttpRequest request) {
    final token = request.cookies
        .where((cookie) => cookie.name == 'booth_dashboard')
        .map((cookie) => cookie.value)
        .firstOrNull;
    if (token == null) return null;
    final expires = _sessions[token];
    if (expires == null || !expires.isAfter(DateTime.now())) {
      _sessions.remove(token);
      return null;
    }
    _sessions[token] = DateTime.now().add(const Duration(minutes: 30));
    request.response.cookies.add(_sessionCookie(token));
    return token;
  }

  Future<Map<String, Object?>> _readJson(HttpRequest request) async {
    if (request.headers.contentType?.mimeType != 'application/json') {
      throw const FormatException('Send a JSON request body.');
    }
    final bytes = await request.fold<BytesBuilder>(BytesBuilder(copy: false), (
      builder,
      chunk,
    ) {
      if (builder.length + chunk.length > 32 * 1024) {
        throw const FormatException('The dashboard request is too large.');
      }
      builder.add(chunk);
      return builder;
    });
    final decoded = jsonDecode(utf8.decode(bytes.takeBytes()));
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('The request body must be a JSON object.');
    }
    return decoded;
  }

  Future<List<int>> _readBytes(HttpRequest request, int maxBytes) async {
    final declaredLength = request.contentLength;
    if (declaredLength < 1 || declaredLength > maxBytes) {
      throw FormatException(
        'The uploaded file must be between 1 and $maxBytes bytes.',
      );
    }
    final builder = await request.fold<BytesBuilder>(
      BytesBuilder(copy: false),
      (accumulator, chunk) {
        if (accumulator.length + chunk.length > maxBytes) {
          throw FormatException('The uploaded file exceeds $maxBytes bytes.');
        }
        accumulator.add(chunk);
        return accumulator;
      },
    );
    return builder.takeBytes();
  }

  Future<void> _writeJson(
    HttpResponse response,
    int statusCode,
    Map<String, Object?> body,
  ) async {
    final serialized = jsonEncode(body);
    response
      ..statusCode = statusCode
      ..headers.contentType = ContentType.json
      ..contentLength = utf8.encode(serialized).length
      ..write(serialized);
    await response.close();
  }

  Future<List<String>> _findDashboardUrls(int port) async {
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      type: InternetAddressType.IPv4,
    );
    final addresses =
        interfaces
            .expand((interface) => interface.addresses)
            .where(
              (address) =>
                  !address.isLoopback &&
                  !address.isLinkLocal &&
                  address.address != '0.0.0.0',
            )
            .map((address) => 'http://${address.address}:$port')
            .toSet()
            .toList()
          ..sort();
    return addresses;
  }
}

const _mediaLimits = <String, int>{
  'walletQr': 15 * 1024 * 1024,
  'idleImage': 15 * 1024 * 1024,
  'photoBorder': 12 * 1024 * 1024,
  'idleVideo': 100 * 1024 * 1024,
};

const _dashboardHtml = r'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Photobooth dashboard</title>
<style>
:root{color-scheme:dark;--bg:#0c1018;--sidebar:#111722;--card:#151d29;--card-soft:#101722;--line:#263244;--accent:#47667d;--muted:#91a0b5;--green:#71dfa0;--red:#ff8e8e}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:#f5f7fb;font:15px Inter,ui-sans-serif,system-ui,-apple-system,"Segoe UI",sans-serif}
button,input,select{font:inherit;border-radius:10px;border:1px solid var(--line);padding:11px 13px;background:#0e1520;color:#f5f7fb}
button{background:var(--accent);color:#fff;font-weight:750;cursor:pointer;border:0;transition:filter .16s,transform .16s}button:hover{filter:brightness(1.08);transform:translateY(-1px)}button.secondary{background:#202b3a;color:#f5f7fb;border:1px solid #304057}
label{display:block;color:var(--muted);font-size:13px;margin:10px 0 5px}
.hidden{display:none!important}.app-shell{min-height:100vh}.sidebar{position:fixed;inset:0 auto 0 0;width:248px;background:var(--sidebar);border-right:1px solid var(--line);padding:24px 16px;display:flex;flex-direction:column;z-index:10}
.brand{display:flex;align-items:center;gap:12px;padding:4px 8px 28px}.brand-mark{width:40px;height:40px;border-radius:13px;background:linear-gradient(145deg,#6f8fa5,#47667d);color:#fff;display:grid;place-items:center;font-weight:950;font-size:18px}.brand strong{display:block;font-size:15px;letter-spacing:.01em}.brand small{display:block;color:var(--muted);font-size:11px;margin-top:3px}
.nav-caption{color:#637187;font-size:10px;font-weight:800;letter-spacing:.13em;padding:8px 10px}.nav-list{display:grid;gap:5px}.nav-link{width:100%;display:flex;align-items:center;gap:12px;text-align:left;background:transparent;color:#9eabc0;border:1px solid transparent;padding:11px 12px;font-weight:650;border-radius:10px}.nav-link:hover{background:#192332;color:#fff;transform:none}.nav-link.active{color:#c5d6e2;background:#1c2b38;border-color:#344e62}.nav-glyph{width:23px;text-align:center;font-size:16px}.sidebar-bottom{margin-top:auto;border-top:1px solid var(--line);padding:16px 8px 0;color:var(--muted);font-size:12px;line-height:1.6}
.workspace{margin-left:248px;min-height:100vh}.topbar{height:82px;padding:0 clamp(20px,4vw,48px);border-bottom:1px solid var(--line);display:flex;align-items:center;justify-content:space-between;background:rgba(12,16,24,.92);position:sticky;top:0;z-index:5}.topbar h1{margin:0;font-size:20px;letter-spacing:-.02em}.eyebrow{color:var(--muted);font-size:11px;text-transform:uppercase;letter-spacing:.12em;margin:0 0 4px}.top-actions{display:flex;align-items:center;gap:9px}.content{max-width:1350px;padding:26px clamp(18px,4vw,48px) 52px;margin:auto}.page{display:none}.page.active{display:block}.page-heading{margin:0 0 19px}.page-heading h2{font-size:24px;letter-spacing:-.03em;margin:0 0 6px}.page-heading p{margin:0;color:var(--muted);line-height:1.55}.card{background:var(--card);border-radius:15px;padding:20px;margin:15px 0;box-shadow:0 10px 26px rgba(0,0,0,.12)}.card h2{margin:0 0 16px;font-size:16px;letter-spacing:.01em}.card p{line-height:1.55}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:10px}.field input,.field select{width:100%}
.status{display:grid;grid-template-columns:repeat(auto-fit,minmax(160px,1fr));gap:10px}.tile{padding:15px;background:var(--card-soft);border-radius:11px;min-height:76px;box-shadow:0 6px 16px rgba(0,0,0,.12)}
.tile small{display:block;color:var(--muted);font-size:11px;margin-bottom:7px}.tile strong{overflow-wrap:anywhere;font-size:18px;letter-spacing:-.02em}
.chart{display:block;width:100%;height:260px;margin-top:14px}.muted{color:var(--muted);font-size:13px}
#error{color:var(--red);min-height:1.3em;margin:0 0 10px}#events{padding:0;margin:0;list-style:none}#events li{padding:12px 2px;color:#b5c1d2;border-bottom:1px solid var(--line);font-size:13px}#events li:last-child{border-bottom:0}
.hidden{display:none!important}.warn{color:#ffd27a;font-size:13px}.inline-actions{display:flex;align-items:center;gap:9px;flex-wrap:wrap}.field .secondary{margin-top:8px}.section-divider{border:0;border-top:1px solid var(--line);margin:20px 0}
#login-wrap{min-height:100vh;display:grid;place-items:center;padding:20px;background:radial-gradient(ellipse at 50% 25%,#1a2636 0%,var(--bg) 65%)}#login{width:min(440px,100%);padding:28px}#login h2{font-size:21px;color:#fff}#login p{color:var(--muted);font-size:13px}#login #loginError{color:var(--red)}#login input{width:100%}
#mobileNav{display:none}
@media(max-width:850px){.sidebar{width:215px}.workspace{margin-left:215px}.topbar{padding:0 20px}.content{padding:22px 20px 40px}}
@media(max-width:640px){.sidebar{transform:translateX(-100%);width:260px;transition:transform .2s ease;box-shadow:20px 0 50px rgba(0,0,0,.35)}.sidebar.open{transform:translateX(0)}.workspace{margin-left:0}.topbar{height:70px;padding:0 15px;gap:10px}.topbar h1{font-size:18px}#mobileNav{display:inline-flex;padding:9px 11px}.content{padding:18px 14px 32px}.top-actions .secondary{padding:9px 10px}.top-actions #refresh{display:none}.status{grid-template-columns:repeat(2,minmax(0,1fr))}.card{padding:16px}.page-heading h2{font-size:21px}}
</style>
</head>
<body>
<div id="login-wrap"><section id="login" class="card"><div class="brand"><div class="brand-mark">P</div><div><strong>Photobooth Kiosk</strong><small>BUSINESS CONTROL PANEL</small></div></div><h2>Admin sign in</h2><p>Sign in with your booth administrator password to manage your kiosk.</p><p id="loginError"></p><form id="loginForm">
<label for="password">Admin password</label><input id="password" type="password" required autocomplete="current-password">
<p><button>Sign in to dashboard</button></p></form></section></div>
<div id="dashboard" class="app-shell hidden">
<aside id="sidebar" class="sidebar">
<div class="brand"><div class="brand-mark">P</div><div><strong>Photobooth Kiosk</strong><small>BUSINESS CONTROL PANEL</small></div></div>
<div class="nav-caption">WORKSPACE</div><nav class="nav-list" aria-label="Dashboard sections">
<button class="nav-link active" data-page="overview"><span class="nav-glyph">◉</span>Overview</button>
<button class="nav-link" data-page="sales"><span class="nav-glyph">▤</span>Sales</button>
<button class="nav-link" data-page="activity"><span class="nav-glyph">◷</span>Activity log</button>
<div class="nav-caption">BOOTH MANAGEMENT</div>
<button class="nav-link" data-page="settings"><span class="nav-glyph">⚙</span>Booth settings</button>
<button class="nav-link" data-page="media"><span class="nav-glyph">▧</span>Media & branding</button>
<button class="nav-link" data-page="capture"><span class="nav-glyph">▣</span>Admin capture</button>
</nav><div class="sidebar-bottom">Local booth dashboard<br><span id="sidebarStatus">Connecting to booth…</span></div>
</aside>
<div class="workspace">
<header class="topbar"><div style="display:flex;align-items:center;gap:13px"><button id="mobileNav" class="secondary" aria-label="Open navigation">☰</button><div><p class="eyebrow">Photobooth management</p><h1 id="pageTitle">Overview</h1></div></div><div class="top-actions"><button id="refresh" class="secondary">Refresh</button><button id="logout" class="secondary">Sign out</button></div></header>
<main class="content"><p id="error" role="status" aria-live="polite"></p>
<section class="page active" data-view="overview"><div class="page-heading"><h2>Booth overview</h2><p>Live status and quick controls for your photobooth.</p></div><section class="card"><h2>Live booth status</h2><div id="status" class="status"></div><p id="message"></p><div class="inline-actions"><button id="pause" class="secondary">Pause booth</button></div></section></section>
<section class="page" data-view="sales"><div class="page-heading"><h2>Sales performance</h2><p>Track accepted booth payments and compare daily totals for the past week.</p></div><section class="card"><div class="inline-actions"><button id="resetSales" class="secondary" type="button">Reset sales details</button></div><div id="salesStats" class="status"></div><canvas id="salesChart" class="chart" height="260" role="img" aria-label="Sales totals for each of the past seven days">Seven-day sales chart</canvas><p id="salesNote" class="muted"></p></section></section>
<section class="page" data-view="activity"><div class="page-heading"><h2>Recent activity</h2><p>Latest events recorded during this app run.</p></div><section class="card"><ul id="events"></ul></section></section>
<section class="page" data-view="settings"><div class="page-heading"><h2>Booth settings</h2><p>Adjust the customer experience, capture, and printer options.</p></div><section class="card"><form id="settingsForm"><div class="grid">
<div class="field"><label>Coin-slot price per session (₱)</label><input name="coinPricePesos" type="number" value="20" min="1" max="100000" step="1" required></div>
<div class="field"><label>PayMongo QR Ph price per session (₱)</label><input name="payMongoAmountPesos" type="number" value="20" min="1" max="100000" step="1" required></div>
<div class="field"><label>Customer welcome text</label><input name="welcomeMessage" maxlength="36" required></div>
<div class="field"><label>Camera</label><select name="cameraDirection"><option value="back">Back</option><option value="front">Front</option></select></div>
<div class="field"><label>Frame</label><select name="frame"></select></div>
<div class="field"><label>Countdown seconds</label><select name="countdownDuration"><option>1</option><option>2</option><option>3</option><option>4</option><option>5</option></select></div>
<div class="field"><label>Preview seconds</label><select name="previewDuration"><option>3</option><option>5</option><option>8</option><option>10</option><option>15</option></select></div>
<div class="field"><label>Print copies (1–3)</label><select name="printCopies"><option>1</option><option>2</option><option>3</option></select></div>
<div class="field"><label>Printer address (paired Bluetooth)</label><input name="printerAddress"></div>
</div>
<p class="muted">Customers choose when to print by tapping “Print my photo”. The selected copy count is used.</p>
<p><label><input name="testModeEnabled" type="checkbox"> Free test mode (only when ESP32 is disconnected)</label></p>
<p><label><input name="rentModeEnabled" type="checkbox"> Enable rent mode (skip customer payments)</label></p>
<p><label><input name="idleVideoLoop" type="checkbox"> Loop idle-screen video</label></p>
<p><label><input name="walletPaymentEnabled" type="checkbox"> Enable Ganap QRPh payments</label></p>
<p><label><input name="payMongoPaymentsEnabled" type="checkbox"> Enable PayMongo QR Ph payments</label></p>
<p class="muted">Coin-slot credits are charged at 1 credit per peso. PayMongo QR Ph uses its own price; Ganap QRPh keeps its existing ₱20 checkout price. Payment options also require activation and server configuration.</p>
<p class="warn">Paid Ganap sessions start only after the server verifies its payment notification. Configure the Ganap project and signing secret on the server before enabling.</p><button>Save booth settings</button></form></section></section>
<section class="page" data-view="media"><div class="page-heading"><h2>Media & branding</h2><p>Manage idle-screen assets and custom photo borders. Ganap checkout QR codes are created per payment.</p></div><section class="card"><div class="grid">
<div class="field"><label>Idle home image</label><input id="idleImage" type="file" accept="image/*"><button type="button" data-upload="idleImage">Upload image</button> <button type="button" class="secondary" data-remove="idleImage">Remove</button></div>
<div class="field"><label>Idle home video (MP4/M4V/MOV/WebM, max 100 MB)</label><input id="idleVideo" type="file" accept=".mp4,.m4v,.mov,.webm"><button type="button" data-upload="idleVideo">Upload video</button> <button type="button" class="secondary" data-remove="idleVideo">Remove</button></div>
<div class="field"><label>Custom PNG photo border (transparent center)</label><input id="photoBorder" type="file" accept=".png,image/png"><button type="button" data-upload="photoBorder">Upload border</button> <button type="button" class="secondary" data-remove="photoBorder">Remove</button></div>
</div>
<hr class="section-divider"><p class="warn">Media changes apply immediately. Use only trusted local Wi-Fi; uploads are sent over unencrypted HTTP.</p></section></section>
<section class="page" data-view="capture"><div class="page-heading"><h2>Admin capture</h2><p>Start a camera session remotely for booth testing and maintenance.</p></div><section class="card"><label for="photoCount">Photo count</label><select id="photoCount"><option value="1">1 photo</option><option value="2">2 photos</option><option value="3">3 photos</option><option value="4">4 photos</option><option value="5">5 photos</option></select><p><button id="capture">Start photo session</button></p><p class="warn">Admin capture bypasses coin collection and e-wallet verification. It is not counted as a sale.</p></section></section>
</main></div></div>
<script>
const $=s=>document.querySelector(s),error=$('#error'),login=$('#login'),dashboard=$('#dashboard'),loginWrap=$('#login-wrap'),loginError=$('#loginError');
let latestSales=null;
const pageTitles={overview:'Overview',sales:'Sales performance',activity:'Activity log',settings:'Booth settings',media:'Media & branding',capture:'Admin capture'};
function navigateTo(name){if(!pageTitles[name])return;document.querySelectorAll('.page').forEach(page=>page.classList.toggle('active',page.dataset.view===name));document.querySelectorAll('.nav-link').forEach(link=>link.classList.toggle('active',link.dataset.page===name));$('#pageTitle').textContent=pageTitles[name];$('#sidebar').classList.remove('open');if(name==='sales'&&latestSales)renderSales(latestSales)}
document.querySelectorAll('.nav-link').forEach(link=>link.addEventListener('click',()=>navigateTo(link.dataset.page)));
$('#mobileNav').addEventListener('click',()=>$('#sidebar').classList.toggle('open'));
document.addEventListener('click',event=>{if(window.innerWidth<=640&&$('#sidebar').classList.contains('open')&&!$('#sidebar').contains(event.target)&&!$('#mobileNav').contains(event.target))$('#sidebar').classList.remove('open')});
const frames=['none','classic','party','elegant','christmas','valentinesDay','halloween','newYear','birthday','wedding','easter','summer','graduation','mothersDay','lunarNewYear','diwali','babyShower','anniversary','custom'];
const labels={none:'No border',classic:'Classic',party:'Party',elegant:'Elegant',christmas:'Christmas',valentinesDay:"Valentine's Day",halloween:'Halloween',newYear:'New Year',birthday:'Birthday',wedding:'Wedding',easter:'Easter',summer:'Summer',graduation:'Graduation',mothersDay:"Mother's Day",lunarNewYear:'Lunar New Year',diwali:'Diwali',babyShower:'Baby Shower',anniversary:'Anniversary',custom:'Custom PNG'};
const frame=$('[name=frame]');frames.forEach(v=>{const o=document.createElement('option');o.value=v;o.textContent=labels[v];frame.append(o)});
async function api(path,body){const r=await fetch(path,{method:body?'POST':'GET',headers:body?{'Content-Type':'application/json','X-Requested-With':'PhotoboothDashboard'}:{'X-Requested-With':'PhotoboothDashboard'},body:body?JSON.stringify(body):undefined,credentials:'same-origin'});let d={};try{d=await r.json()}catch{}if(!r.ok)throw Error(d.error||`Request failed (${r.status})`);return d}
$('#loginForm').addEventListener('submit',async e=>{e.preventDefault();loginError.textContent='';try{await api('/api/login',{password:$('#password').value});$('#password').value='';loginWrap.classList.add('hidden');dashboard.classList.remove('hidden');await refresh()}catch(x){loginError.textContent=x.message}});
async function restoreSession(){try{await api('/api/status');loginWrap.classList.add('hidden');dashboard.classList.remove('hidden');await refresh()}catch(x){if(!x.message.includes('Sign in again'))loginError.textContent=x.message}}
$('#settingsForm').addEventListener('submit',async e=>{
 e.preventDefault();error.textContent='';
 const f=new FormData(e.currentTarget),s={};
 for(const k of ['coinPricePesos','payMongoAmountPesos','countdownDuration','previewDuration','printCopies'])s[k]=Number(f.get(k));
 for(const k of ['welcomeMessage','cameraDirection','frame','printerAddress'])s[k]=String(f.get(k)||'');
 s.autoPrint=false;
 for(const k of ['testModeEnabled','rentModeEnabled','idleVideoLoop','walletPaymentEnabled','payMongoPaymentsEnabled'])s[k]=f.has(k);
 try{await api('/api/settings',s);error.textContent='Settings saved.';await refresh()}catch(x){error.textContent=x.message}
});
$('#resetSales').addEventListener('click',async e=>{const button=e.currentTarget;if(!confirm('Permanently reset all saved sales details, including lifetime totals and daily history? This cannot be undone.'))return;button.disabled=true;error.textContent='';try{await api('/api/sales/reset',{});await refresh();error.textContent='All sales details were reset.'}catch(x){error.textContent=`Could not reset sales details: ${x.message}`}finally{button.disabled=false}});
document.querySelectorAll('[data-upload]').forEach(b=>b.addEventListener('click',async()=>{const id=b.dataset.upload,file=$(`#${id}`).files[0];if(!file){error.textContent='Choose a file first.';return}try{const r=await fetch(`/api/media?type=${encodeURIComponent(id)}`,{method:'POST',credentials:'same-origin',headers:{'X-Dashboard-Filename':file.name,'Content-Type':'application/octet-stream'},body:file});const d=await r.json();if(!r.ok)throw Error(d.error||'Upload failed');error.textContent=`${file.name} uploaded.`;$('#'+id).value='';await refresh()}catch(x){error.textContent=x.message}}));
document.querySelectorAll('[data-remove]').forEach(b=>b.addEventListener('click',async()=>{if(!confirm('Remove this uploaded file?'))return;try{await fetch(`/api/media?type=${encodeURIComponent(b.dataset.remove)}`,{method:'DELETE',credentials:'same-origin'}).then(async r=>{const d=await r.json();if(!r.ok)throw Error(d.error||'Remove failed')});error.textContent='File removed.';await refresh()}catch(x){error.textContent=x.message}}));
function renderSales(sales){
 latestSales=sales;
 const summary=sales?.summary||{},loaded=Boolean(sales?.loaded),failed=Boolean(sales?.error);
 const value=number=>new Intl.NumberFormat().format(Number(number)||0);
 const cards=[['Total sales',summary.totalSales],['Coin sales',summary.totalCoinSales],['QR Ph sales',summary.totalQrPhSales],['Sales today',summary.salesToday],['Coin sales today',summary.coinSalesToday],['QR Ph sales today',summary.qrPhSalesToday],['Sales this week',summary.salesThisWeek],['Coin sales this week',summary.coinSalesThisWeek],['QR Ph sales this week',summary.qrPhSalesThisWeek],['Paid sessions today',summary.transactionsToday,false]];
 const stats=cards.map(([title,amount,units=true])=>{const d=document.createElement('div');d.className='tile';const small=document.createElement('small');small.textContent=title+(units?' (₱)':'');const strong=document.createElement('strong');strong.textContent=loaded&&!failed?value(amount):'Unavailable';d.append(small,strong);return d});
 $('#salesStats').replaceChildren(...stats);
 $('#salesNote').textContent=sales?.error||(!loaded?'Loading saved sales…':'Total sales combines coin and verified QR Ph payments. The payment-method breakdown includes sales recorded since this update; older combined-only sales remain in the total.');
 const canvas=$('#salesChart'),rect=canvas.getBoundingClientRect(),ratio=window.devicePixelRatio||1,width=Math.max(1,rect.width),height=260,ctx=canvas.getContext('2d'),days=summary.week||[];
 canvas.width=Math.floor(width*ratio);canvas.height=Math.floor(height*ratio);ctx.setTransform(ratio,0,0,ratio,0,0);ctx.clearRect(0,0,width,height);
 const left=42,right=12,top=18,bottom=36,plotWidth=width-left-right,plotHeight=height-top-bottom,max=Math.max(1,...days.map(day=>Number(day.sales)||0)),step=Math.ceil(max/4),axisMax=step*4;
 ctx.font='12px system-ui,sans-serif';ctx.textAlign='right';ctx.textBaseline='middle';
 for(let i=0;i<=4;i++){const y=top+plotHeight-(plotHeight*i/4);ctx.strokeStyle='#393a42';ctx.beginPath();ctx.moveTo(left,y);ctx.lineTo(width-right,y);ctx.stroke();ctx.fillStyle='#b8bac2';ctx.fillText(value(step*i),left-7,y)}
 const slot=plotWidth/Math.max(days.length,1),barWidth=Math.min(46,slot*.58);
 days.forEach((day,index)=>{const amount=Number(day.sales)||0,barHeight=amount?plotHeight*amount/axisMax:0,x=left+slot*index+(slot-barWidth)/2,y=top+plotHeight-barHeight;ctx.fillStyle='#ffb547';ctx.fillRect(x,y,barWidth,barHeight);ctx.fillStyle='#b8bac2';ctx.textAlign='center';ctx.textBaseline='top';const date=new Date(day.date+'T00:00:00');ctx.fillText(date.toLocaleDateString(undefined,{weekday:'short'}),x+barWidth/2,height-bottom+8);if(amount>0){ctx.fillStyle='#fff';ctx.textBaseline='bottom';ctx.fillText(value(amount),x+barWidth/2,y-4)}});
 canvas.setAttribute('aria-label','Sales for the past seven days: '+days.map(day=>day.date+' '+value(day.sales)).join(', '));
}
async function refresh(){
 try{
  const s=await api('/api/status');
  const battery=s.batteryPercent==null?'Unavailable':`${s.batteryPercent}%${s.charging?' · charging':''}`;
  const storage=s.storageFreeBytes==null?'Unavailable':`${Math.round(s.storageFreeBytes/1048576)} MB free`;
  const voice=s.voiceGuidanceError||(s.voiceGuidanceEnabled?'Enabled':'Off');
  const coinPrice=s.coinPricePesos??s.coinsPerSession??s.coinsPerPhoto??20;
  const rows=[
   ['Camera',s.cameraReady?'Ready':'Not ready'],['ESP32',s.esp32Connected?'Connected':'Not connected'],
   ['Printer',s.printerHealth||'Not configured'],['Battery',battery],
   ['Charging',s.charging==null?'Unknown':s.charging?'Yes':'No'],['Storage',storage],
   ['Voice guidance',voice],['Credits',s.credits??'Unavailable'],
   ['Session',s.photoInProgress?'Taking photo':(s.selectedPhotoCount?`${s.selectedPhotoCount} selected`:'Idle')],
   ['Booth',s.paused?'Paused':'Running'],
   ['Coin price / session',s.rentModeEnabled?'No customer payment':`₱${coinPrice}`],
   ['PayMongo QR Ph price',`₱${s.payMongoAmountPesos??20}`],
   ['Kiosk mode',s.kioskActive?'Active':'Off'],
   ['Ganap QRPh payments',s.walletPaymentEnabled?'Enabled':'Off'],
   ['PayMongo QR Ph payments',s.payMongoPaymentsEnabled?'Enabled':'Off']
  ];
  $('#status').replaceChildren(...rows.map(([a,b])=>{
   const d=document.createElement('div');d.className='tile';
   const sm=document.createElement('small');sm.textContent=a;
   const strong=document.createElement('strong');strong.textContent=b;
   d.append(sm,strong);return d
  }));
  $('#sidebarStatus').textContent=s.paused?'Booth paused':(s.cameraReady?'Booth online':'Waiting for camera');
  renderSales(s.sales);$('#message').textContent=s.message||'';
  $('#pause').textContent=s.paused?'Resume booth':'Pause booth';
  const form=$('#settingsForm');
  for(const k of ['coinPricePesos','payMongoAmountPesos','welcomeMessage','cameraDirection','frame','countdownDuration','previewDuration','printCopies','printerAddress']){
   if(document.activeElement!==form.elements[k])form.elements[k].value=s[k]??(k==='coinPricePesos'||k==='payMongoAmountPesos'?'20':'')
  }
  for(const k of ['testModeEnabled','rentModeEnabled','idleVideoLoop','walletPaymentEnabled','payMongoPaymentsEnabled'])form.elements[k].checked=Boolean(s[k]);
  form.elements.walletPaymentEnabled.disabled=!s.ganapQrPhAvailable;
  form.elements.payMongoPaymentsEnabled.disabled=!s.activationAllowsPayMongo;
  $('#events').replaceChildren(...(s.events||[]).map(x=>{const li=document.createElement('li');li.textContent=x;return li}));
 }catch(x){
  if(x.message.includes('Sign in again')){dashboard.classList.add('hidden');loginWrap.classList.remove('hidden')}
  error.textContent=x.message
 }
}
$('#pause').addEventListener('click',async()=>{try{const s=await api('/api/status');await api('/api/pause',{paused:!s.paused});await refresh()}catch(x){error.textContent=x.message}});
$('#capture').addEventListener('click',async()=>{if(!confirm('Start a session without checking payment?'))return;try{await api('/api/capture',{photoCount:Number($('#photoCount').value)});error.textContent='Remote photo session started.';await refresh()}catch(x){error.textContent=x.message}});
$('#refresh').addEventListener('click',refresh);$('#logout').addEventListener('click',async()=>{try{await api('/api/logout',{});dashboard.classList.add('hidden');loginWrap.classList.remove('hidden')}catch(x){error.textContent=x.message}});
window.addEventListener('resize',()=>{if(latestSales)renderSales(latestSales)});
setInterval(()=>{if(!dashboard.classList.contains('hidden'))refresh()},4000);
restoreSession();
</script></body></html>''';
