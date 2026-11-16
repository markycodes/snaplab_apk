<?php
header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');
header('X-Content-Type-Options: nosniff');

require_once __DIR__ . '/ganap_common.php';
require_once __DIR__ . '/fleet_db.php';
require_once __DIR__ . '/fleet_mailer.php';

function fleet_ingest_respond(int $status, array $body): never
{
    http_response_code($status);
    echo json_encode($body, JSON_UNESCAPED_SLASHES);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    header('Allow: POST');
    fleet_ingest_respond(405, ['error' => 'method_not_allowed']);
}
if (!in_array(strtolower((string)($_SERVER['HTTPS'] ?? '')), ['on', '1'], true)) {
    fleet_ingest_respond(403, ['error' => 'https_required']);
}

$request = ganap_read_request();
$config = ganap_config();
$db = fleet_db_connection($config);
if (!function_exists('sodium_crypto_sign_verify_detached')) {
    fleet_ingest_respond(503, ['error' => 'server_ed25519_support_unavailable']);
}
$activation = ganap_activation_claims($request, $config);
if ($activation === null) {
    fleet_ingest_respond(401, ['error' => 'activation_required']);
}
if (!is_array($request['status'] ?? null) ||
    !is_array($request['sales'] ?? null)) {
    fleet_ingest_respond(400, ['error' => 'invalid_telemetry']);
}

$status = $request['status'];
$sales = $request['sales'];
$booleanStatus = [
    'cameraReady',
    'esp32Connected',
    'paused',
    'kioskActive',
];
foreach ($booleanStatus as $key) {
    if (!is_bool($status[$key] ?? null)) {
        fleet_ingest_respond(400, ['error' => 'invalid_device_status']);
    }
}
if (isset($status['appForeground']) &&
    !is_bool($status['appForeground'])) {
    fleet_ingest_respond(400, ['error' => 'invalid_device_status']);
}
if (array_key_exists('charging', $status) &&
    !is_bool($status['charging'])) {
    fleet_ingest_respond(400, ['error' => 'invalid_device_status']);
}
foreach (['batteryPercent' => 100, 'storageFreeBytes' => PHP_INT_MAX] as $key => $max) {
    $value = $status[$key] ?? null;
    if ($value !== null &&
        (!is_int($value) || $value < 0 || $value > $max)) {
        fleet_ingest_respond(400, ['error' => 'invalid_device_status']);
    }
}
$printerHealth = $status['printerHealth'] ?? null;
if (!is_string($printerHealth) || strlen($printerHealth) > 80) {
    fleet_ingest_respond(400, ['error' => 'invalid_device_status']);
}
$latitude = $status['latitude'] ?? null;
$longitude = $status['longitude'] ?? null;
$locationAccuracy = $status['locationAccuracyMeters'] ?? null;
if (($latitude === null) !== ($longitude === null) ||
    ($latitude !== null &&
        ((!is_int($latitude) && !is_float($latitude)) ||
            !is_finite((float)$latitude) ||
            $latitude < -90 ||
            $latitude > 90 ||
            (!is_int($longitude) && !is_float($longitude)) ||
            !is_finite((float)$longitude) ||
            $longitude < -180 ||
            $longitude > 180)) ||
    ($locationAccuracy !== null &&
        (!is_int($locationAccuracy) &&
            !is_float($locationAccuracy) ||
            !is_finite((float)$locationAccuracy) ||
            $locationAccuracy < 0 ||
            $locationAccuracy > 100000))) {
    fleet_ingest_respond(400, ['error' => 'invalid_device_location']);
}
$locationTimestamp = $status['locationTimestamp'] ?? null;
if ($locationTimestamp !== null &&
    (!is_int($locationTimestamp) ||
        $locationTimestamp < 0 ||
        $locationTimestamp > time() + 300)) {
    fleet_ingest_respond(400, ['error' => 'invalid_device_location']);
}
$pairedPrinters = $status['pairedPrinters'] ?? [];
if (!is_array($pairedPrinters) ||
    count($pairedPrinters) > 20 ||
    array_filter(
        $pairedPrinters,
        static fn($printer): bool => !is_array($printer) ||
            !is_string($printer['address'] ?? null) ||
            !preg_match('/^[0-9A-Fa-f:]{17}$/D', $printer['address']) ||
            !is_string($printer['name'] ?? null) ||
            strlen($printer['name']) > 80
    ) !== []) {
    fleet_ingest_respond(400, ['error' => 'invalid_device_status']);
}

$deviceId = $activation['deviceId'];
try {
    $db->beginTransaction();
    $registration = fleet_db_execute(
        $db,
        'SELECT active, owner_id FROM fleet_registered_devices WHERE device_id = ? FOR UPDATE',
        [$deviceId]
    )->fetch();
    if (!is_array($registration) || !(bool)$registration['active']) {
        $db->rollBack();
        fleet_ingest_respond(403, ['error' => 'device_not_registered']);
    }

$salesFields = [
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
];
$cleanSales = [];
foreach ($salesFields as $key) {
    $value = $sales[$key] ?? null;
    if (!is_int($value) || $value < 0 || $value > 1000000000000) {
        fleet_ingest_respond(400, ['error' => 'invalid_sales_summary']);
    }
    $cleanSales[$key] = $value;
}
    $now = time();
    $appSettings = $status['appSettings'] ?? [];
    $allowedAppSettingKeys = [
        'eventTheme',
        'welcomeMessage',
        'idleTimeoutSeconds',
        'photoCounts',
        'printerAddress',
        'cameraDirection',
        'countdownDuration',
        'previewDuration',
        'photoBorderStyle',
        'liveEffect',
        'voiceGuidanceEnabled',
        'brandLogoAnimation',
        'printerType',
        'receiptWidthDots',
        'receiptBrightness',
        'receiptCutMode',
        'printCopies',
        'walletPaymentEnabled',
        'walletPaymentsAvailable',
        'payMongoPaymentsEnabled',
        'payMongoPaymentsAvailable',
        'coinPricePesos',
        'payMongoAmountPesos',
        'aiStylesEnabled',
        'aiCoinPaymentEnabled',
        'aiQrPaymentEnabled',
        'aiStylePricePesos',
        'liveWallpaperEnabled',
        'idleVideoLoop',
        'fleetLocationSharingEnabled',
        'chargeStartPercent',
        'chargeStopPercent',
    ];
    if (!is_array($appSettings) ||
        ($appSettings !== [] && (
        strlen(json_encode($appSettings, JSON_THROW_ON_ERROR)) > 4096 ||
        array_diff(array_keys($appSettings), $allowedAppSettingKeys) !== [] ||
        !is_string($appSettings['eventTheme'] ?? null) ||
        !in_array($appSettings['eventTheme'], [
            'classic', 'birthday', 'wedding', 'graduation', 'holiday',
            'summer', 'coffeeBeans', 'coffeeCup', 'latteArt', 'valentines',
        ], true) ||
        !is_string($appSettings['welcomeMessage'] ?? null) ||
        trim($appSettings['welcomeMessage']) === '' ||
        strlen($appSettings['welcomeMessage']) > 36 ||
        !is_int($appSettings['idleTimeoutSeconds'] ?? null) ||
        !in_array($appSettings['idleTimeoutSeconds'], [30, 60, 120, 300], true) ||
        !is_array($appSettings['photoCounts'] ?? null) ||
        count($appSettings['photoCounts']) < 1 ||
        count($appSettings['photoCounts']) > 5 ||
        count(array_unique($appSettings['photoCounts'])) !== count($appSettings['photoCounts']) ||
        array_filter(
            $appSettings['photoCounts'],
            static fn($count): bool => !is_int($count) || $count < 1 || $count > 5
        ) !== [] ||
        !is_string($appSettings['printerAddress'] ?? null) ||
        ($appSettings['printerAddress'] !== '' &&
            !preg_match('/^[0-9A-Fa-f:]{17}$/D', $appSettings['printerAddress'])) ||
        !is_string($appSettings['cameraDirection'] ?? null) ||
        !in_array($appSettings['cameraDirection'], ['front', 'back'], true) ||
        !is_int($appSettings['countdownDuration'] ?? null) ||
        !in_array($appSettings['countdownDuration'], [1, 2, 3, 4, 5], true) ||
        !is_int($appSettings['previewDuration'] ?? null) ||
        !in_array($appSettings['previewDuration'], [3, 5, 8, 10, 15], true) ||
        !is_string($appSettings['photoBorderStyle'] ?? null) ||
        !in_array($appSettings['photoBorderStyle'], [
            'none', 'classic', 'party', 'elegant', 'christmas',
            'valentinesDay', 'halloween', 'newYear', 'birthday', 'wedding',
            'easter', 'summer', 'graduation', 'mothersDay', 'lunarNewYear',
            'diwali', 'babyShower', 'anniversary', 'custom',
        ], true) ||
        !is_string($appSettings['liveEffect'] ?? null) ||
        !in_array($appSettings['liveEffect'], [
            'original', 'vivid', 'warm', 'monochrome', 'vintage',
            'cartoon', 'soft', 'cool', 'rose', 'matte', 'sepia',
            'cinematic', 'pastel', 'fade',
        ], true) ||
        !is_bool($appSettings['voiceGuidanceEnabled'] ?? null) ||
        !is_string($appSettings['brandLogoAnimation'] ?? null) ||
        !in_array($appSettings['brandLogoAnimation'], [
            'none', 'jump', 'pump', 'sway', 'float',
        ], true) ||
        !is_string($appSettings['printerType'] ?? null) ||
        !in_array($appSettings['printerType'], ['receipt', 'color'], true) ||
        !is_int($appSettings['receiptWidthDots'] ?? null) ||
        !in_array($appSettings['receiptWidthDots'], [384, 576], true) ||
        (!is_float($appSettings['receiptBrightness'] ?? null) &&
            !is_int($appSettings['receiptBrightness'] ?? null)) ||
        $appSettings['receiptBrightness'] < 0.2 ||
        $appSettings['receiptBrightness'] > 0.5 ||
        !is_string($appSettings['receiptCutMode'] ?? null) ||
        !in_array($appSettings['receiptCutMode'], ['full', 'partial'], true) ||
        !is_int($appSettings['printCopies'] ?? null) ||
        !in_array($appSettings['printCopies'], [1, 2, 3], true) ||
        !is_bool($appSettings['walletPaymentEnabled'] ?? null) ||
        !is_bool($appSettings['walletPaymentsAvailable'] ?? null) ||
        !is_bool($appSettings['payMongoPaymentsEnabled'] ?? null) ||
        !is_bool($appSettings['payMongoPaymentsAvailable'] ?? null) ||
        !is_int($appSettings['coinPricePesos'] ?? null) ||
        $appSettings['coinPricePesos'] < 1 ||
        $appSettings['coinPricePesos'] > 100000 ||
        !is_int($appSettings['payMongoAmountPesos'] ?? null) ||
        $appSettings['payMongoAmountPesos'] < 1 ||
        $appSettings['payMongoAmountPesos'] > 100000 ||
        !is_bool($appSettings['aiStylesEnabled'] ?? null) ||
        !is_bool($appSettings['aiCoinPaymentEnabled'] ?? null) ||
        !is_bool($appSettings['aiQrPaymentEnabled'] ?? null) ||
        !is_int($appSettings['aiStylePricePesos'] ?? null) ||
        $appSettings['aiStylePricePesos'] < 1 ||
        $appSettings['aiStylePricePesos'] > 100000 ||
        !is_bool($appSettings['liveWallpaperEnabled'] ?? null) ||
        !is_bool($appSettings['idleVideoLoop'] ?? null) ||
        !is_bool($appSettings['fleetLocationSharingEnabled'] ?? null) ||
        !is_int($appSettings['chargeStartPercent'] ?? null) ||
        $appSettings['chargeStartPercent'] < 0 ||
        $appSettings['chargeStartPercent'] > 99 ||
        !is_int($appSettings['chargeStopPercent'] ?? null) ||
        $appSettings['chargeStopPercent'] < 1 ||
        $appSettings['chargeStopPercent'] > 100 ||
        $appSettings['chargeStartPercent'] >= $appSettings['chargeStopPercent']))) {
        fleet_ingest_respond(400, ['error' => 'invalid_app_settings']);
    }
    $cleanStatus = [
    'cameraReady' => $status['cameraReady'],
    'esp32Connected' => $status['esp32Connected'],
    'paused' => $status['paused'],
    'kioskActive' => $status['kioskActive'],
    'batteryPercent' => $status['batteryPercent'] ?? null,
    'charging' => $status['charging'] ?? null,
    'storageFreeBytes' => $status['storageFreeBytes'] ?? null,
    'printerHealth' => $printerHealth,
    'pairedPrinters' => $pairedPrinters,
    'latitude' => $latitude === null ? null : (float)$latitude,
    'longitude' => $longitude === null ? null : (float)$longitude,
    'locationAccuracyMeters' => $locationAccuracy === null
        ? null
        : (float)$locationAccuracy,
    'locationTimestamp' => $locationTimestamp,
    'appForeground' => $status['appForeground'] ?? false,
    'appSettings' => $appSettings,
];
if (isset($request['commandResult'])) {
    $commandResult = $request['commandResult'];
    if (!is_array($commandResult) ||
        !is_int($commandResult['commandId'] ?? null) ||
        $commandResult['commandId'] < 1 ||
        !in_array($commandResult['status'] ?? null, ['complete', 'failed'], true) ||
        !is_string($commandResult['message'] ?? null) ||
        strlen($commandResult['message']) > 160) {
        fleet_ingest_respond(400, ['error' => 'invalid_command_result']);
    }
    fleet_db_execute(
        $db,
        'UPDATE fleet_device_commands SET status = ?, result_text = ?, updated_at = ?
         WHERE command_id = ? AND device_id = ? AND status = ?',
        [
            $commandResult['status'],
            $commandResult['message'],
            $now,
            $commandResult['commandId'],
            $deviceId,
            'delivered',
        ]
    );
}
fleet_db_execute(
    $db,
    'INSERT INTO fleet_device_telemetry
     (device_id, first_seen, last_seen, status_json, sales_json)
     VALUES (?, ?, ?, ?, ?)
     ON DUPLICATE KEY UPDATE
       last_seen = VALUES(last_seen),
       status_json = VALUES(status_json),
       sales_json = VALUES(sales_json)',
    [
        $deviceId,
        $now,
        $now,
        json_encode($cleanStatus, JSON_THROW_ON_ERROR),
        json_encode($cleanSales, JSON_THROW_ON_ERROR),
    ]
);
$alertCatalog = [
    'camera_unavailable' => [
        'severity' => 'critical',
        'problem' => 'The booth camera is unavailable. Check its connection and app permissions.',
        'resolved' => 'The booth camera is available again.',
    ],
    'esp32_disconnected' => [
        'severity' => 'warning',
        'problem' => 'The booth ESP32 is disconnected or not detected.',
        'resolved' => 'The booth ESP32 is connected again.',
    ],
    'printer_unavailable' => [
        'severity' => 'warning',
        'problem' => '',
        'resolved' => 'The booth printer is ready again.',
    ],
];
$alertDefinitions = [];
if (!$cleanStatus['cameraReady']) {
    $alertDefinitions['camera_unavailable'] = $alertCatalog['camera_unavailable'];
}
if (!$cleanStatus['esp32Connected']) {
    $alertDefinitions['esp32_disconnected'] = $alertCatalog['esp32_disconnected'];
}
if (!in_array($cleanStatus['printerHealth'], ['', 'Ready', 'Not configured'], true)) {
    $alertDefinitions['printer_unavailable'] = $alertCatalog['printer_unavailable'];
    $alertDefinitions['printer_unavailable']['problem'] =
        'The booth printer reports this status: ' . $cleanStatus['printerHealth'];
}
$activeAlertRows = fleet_db_execute(
    $db,
    'SELECT alert_key, opened_at, notification_status, updated_at FROM fleet_device_alerts
     WHERE device_id = ? AND active = 1 FOR UPDATE',
    [$deviceId]
)->fetchAll();
$activeAlerts = [];
foreach ($activeAlertRows as $activeAlertRow) {
    $activeAlerts[$activeAlertRow['alert_key']] = $activeAlertRow;
}
$notifications = [];
foreach ($activeAlerts as $alertKey => $activeAlert) {
    if (isset($alertDefinitions[$alertKey])) {
        continue;
    }
    $resolvedAlert = $alertCatalog[$alertKey] ?? [
        'resolved' => 'The reported booth problem has cleared.',
    ];
    fleet_db_execute(
        $db,
        'UPDATE fleet_device_alerts
         SET active = 0, notification_status = ?, updated_at = ?, resolved_at = ?
         WHERE device_id = ? AND alert_key = ? AND active = 1',
        ['pending', $now, $now, $deviceId, $alertKey]
    );
    $notifications[] = [
        'alertKey' => $alertKey,
        'severity' => 'info',
        'problem' => $resolvedAlert['resolved'],
        'active' => false,
        'eventAt' => $now,
    ];
}
foreach ($alertDefinitions as $alertKey => $definition) {
    if (isset($activeAlerts[$alertKey])) {
        continue;
    }
    fleet_db_execute(
        $db,
        'INSERT INTO fleet_device_alerts
         (device_id, alert_key, active, notification_status, opened_at, updated_at, resolved_at)
         VALUES (?, ?, 1, ?, ?, ?, NULL)
         ON DUPLICATE KEY UPDATE
           active = 1,
           notification_status = VALUES(notification_status),
           opened_at = VALUES(opened_at),
           updated_at = VALUES(updated_at),
           resolved_at = NULL',
        [$deviceId, $alertKey, 'pending', $now, $now]
    );
    $notifications[] = [
        'alertKey' => $alertKey,
        'severity' => $definition['severity'],
        'problem' => $definition['problem'],
        'active' => true,
        'eventAt' => $now,
    ];
}
$retryBefore = $now - 300;
foreach ($activeAlerts as $alertKey => $activeAlert) {
    if (!isset($alertDefinitions[$alertKey]) ||
        !in_array($activeAlert['notification_status'], ['pending', 'failed'], true) ||
        (int)$activeAlert['updated_at'] > $retryBefore) {
        continue;
    }
    fleet_db_execute(
        $db,
        'UPDATE fleet_device_alerts SET notification_status = ?, updated_at = ?
         WHERE device_id = ? AND alert_key = ? AND active = 1 AND opened_at = ?',
        ['pending', $now, $deviceId, $alertKey, (int)$activeAlert['opened_at']]
    );
    $notifications[] = [
        'alertKey' => $alertKey,
        'severity' => $alertDefinitions[$alertKey]['severity'],
        'problem' => $alertDefinitions[$alertKey]['problem'],
        'active' => true,
        'eventAt' => (int)$activeAlert['opened_at'],
    ];
}
$pendingResolutions = fleet_db_execute(
    $db,
    'SELECT alert_key, resolved_at FROM fleet_device_alerts
     WHERE device_id = ? AND active = 0 AND notification_status IN (?, ?)
       AND updated_at <= ? FOR UPDATE',
    [$deviceId, 'pending', 'failed', $retryBefore]
)->fetchAll();
foreach ($pendingResolutions as $pendingResolution) {
    $alertKey = $pendingResolution['alert_key'];
    fleet_db_execute(
        $db,
        'UPDATE fleet_device_alerts SET notification_status = ?, updated_at = ?
         WHERE device_id = ? AND alert_key = ? AND active = 0 AND resolved_at = ?',
        [
            'pending',
            $now,
            $deviceId,
            $alertKey,
            (int)$pendingResolution['resolved_at'],
        ]
    );
    $resolvedAlert = $alertCatalog[$alertKey] ?? [
        'resolved' => 'The reported booth problem has cleared.',
    ];
    $notifications[] = [
        'alertKey' => $alertKey,
        'severity' => 'info',
        'problem' => $resolvedAlert['resolved'],
        'active' => false,
        'eventAt' => (int)$pendingResolution['resolved_at'],
    ];
}
$ownerEmail = null;
if ($notifications !== []) {
    $owner = fleet_db_execute(
        $db,
        'SELECT email FROM fleet_accounts WHERE account_id = ?',
        [(string)$registration['owner_id']]
    )->fetch();
    $ownerEmail = is_array($owner) && is_string($owner['email'] ?? null)
        ? $owner['email']
        : null;
}
$settingsRow = fleet_db_execute(
    $db,
    'SELECT settings_json FROM fleet_device_settings WHERE device_id = ?',
    [$deviceId]
)->fetch();
$remoteSettings = is_array($settingsRow)
    ? json_decode($settingsRow['settings_json'], true, 16, JSON_THROW_ON_ERROR)
    : [];
$commandRow = fleet_db_execute(
    $db,
    'SELECT command_id, command_name FROM fleet_device_commands
     WHERE device_id = ? AND
       (status = ? OR (status = ? AND updated_at < ?)) AND ? = 1
     ORDER BY command_id LIMIT 1',
    [
        $deviceId,
        'pending',
        'delivered',
        $now - 30,
        ($status['appForeground'] ?? false) ? 1 : 0,
    ]
)->fetch();
$command = null;
if (is_array($commandRow)) {
    fleet_db_execute(
        $db,
        'UPDATE fleet_device_commands SET status = ?, updated_at = ?
         WHERE command_id = ? AND status = ?',
        ['delivered', $now, (int)$commandRow['command_id'], 'pending']
    );
    $command = [
        'commandId' => (int)$commandRow['command_id'],
        'name' => $commandRow['command_name'],
    ];
}
$db->commit();
foreach ($notifications as $notification) {
    $notificationStatus = 'sent';
    if ($ownerEmail === null) {
        $notificationStatus = 'failed';
        error_log('Fleet alert email not sent: registered device owner email is unavailable.');
    } else {
        try {
            fleet_send_problem_notification(
                $config,
                $ownerEmail,
                '',
                $notification['problem'],
                $deviceId,
                $notification['severity']
            );
        } catch (RuntimeException $error) {
            $notificationStatus = 'failed';
            error_log('Fleet alert email could not be delivered for device ' . $deviceId . ': ' .
                $error->getMessage());
        }
    }
    $eventCondition = $notification['active']
        ? 'active = 1 AND opened_at = ?'
        : 'active = 0 AND resolved_at = ?';
    fleet_db_execute(
        $db,
        'UPDATE fleet_device_alerts SET notification_status = ?, updated_at = ?
         WHERE device_id = ? AND alert_key = ? AND notification_status = ? AND ' . $eventCondition,
        [
            $notificationStatus,
            time(),
            $deviceId,
            $notification['alertKey'],
            'pending',
            $notification['eventAt'],
        ]
    );
}
} catch (PDOException $error) {
    if ($db->inTransaction()) {
        $db->rollBack();
    }
    error_log('Fleet telemetry write failed (' . (string)$error->getCode() . ')');
    fleet_ingest_respond(503, ['error' => 'fleet_database_unavailable']);
}

fleet_ingest_respond(200, [
    'ok' => true,
    'settings' => $remoteSettings,
    'command' => $command,
]);
