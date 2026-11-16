<?php
require_once __DIR__ . '/fleet_db.php';
require_once __DIR__ . '/paymongo_common.php';

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');
header('X-Content-Type-Options: nosniff');

function paymongo_webhook_respond(int $status, array $body): never
{
    http_response_code($status);
    echo json_encode($body, JSON_UNESCAPED_SLASHES);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    header('Allow: POST');
    paymongo_webhook_respond(405, ['error' => 'method_not_allowed']);
}
$https = strtolower((string)($_SERVER['HTTPS'] ?? ''));
if ($https !== 'on' && $https !== '1') {
    paymongo_webhook_respond(403, ['error' => 'https_required']);
}
$contentLength = $_SERVER['CONTENT_LENGTH'] ?? null;
if (is_string($contentLength) &&
    ctype_digit($contentLength) &&
    (int)$contentLength > 65536) {
    paymongo_webhook_respond(413, ['error' => 'request_too_large']);
}
$rawBody = file_get_contents('php://input');
if ($rawBody === false || strlen($rawBody) > 65536) {
    paymongo_webhook_respond(413, ['error' => 'request_too_large']);
}
$config = ganap_config();
$configuredWebhookSecret = $config['paymongo_identity_webhook_secret'] ?? '';
$environmentWebhookSecret = getenv('PAYMONGO_IDENTITY_WEBHOOK_SECRET');
$webhookSecret = is_string($configuredWebhookSecret) && $configuredWebhookSecret !== ''
    ? $configuredWebhookSecret
    : (is_string($environmentWebhookSecret) ? $environmentWebhookSecret : '');
$signatureHeader = $_SERVER['HTTP_PAYMONGO_SIGNATURE'] ?? '';
if (!is_string($webhookSecret) ||
    !preg_match('/^whsk_[A-Za-z0-9_-]{8,}$/D', $webhookSecret) ||
    !is_string($signatureHeader)) {
    paymongo_webhook_respond(503, ['error' => 'webhook_not_configured']);
}
$signatureParts = [];
foreach (explode(',', $signatureHeader) as $part) {
    $pair = explode('=', trim($part), 2);
    if (count($pair) === 2) {
        $signatureParts[$pair[0]] = $pair[1];
    }
}
$timestamp = $signatureParts['t'] ?? null;
$signatureKey = str_starts_with($config['paymongo_secret_key'] ?? '', 'sk_live_')
    ? 'li'
    : 'te';
$providedSignature = $signatureParts[$signatureKey] ?? null;
if (!is_string($timestamp) ||
    !ctype_digit($timestamp) ||
    !is_string($providedSignature) ||
    !preg_match('/^[a-f0-9]{64}$/iD', $providedSignature)) {
    paymongo_webhook_respond(401, ['error' => 'invalid_signature']);
}
$expectedSignature = hash_hmac(
    'sha256',
    $timestamp . '.' . $rawBody,
    $webhookSecret
);
if (!hash_equals($expectedSignature, strtolower($providedSignature))) {
    paymongo_webhook_respond(401, ['error' => 'invalid_signature']);
}
try {
    $event = json_decode($rawBody, true, 16, JSON_THROW_ON_ERROR);
} catch (JsonException) {
    paymongo_webhook_respond(400, ['error' => 'invalid_json']);
}
if (!is_array($event)) {
    paymongo_webhook_respond(400, ['error' => 'invalid_event']);
}
$attributes = $event['data']['attributes'] ?? null;
if (!is_array($attributes)) {
    paymongo_webhook_respond(400, ['error' => 'invalid_event']);
}
$eventType = $attributes['type'] ?? null;
if (!in_array($eventType, [
    'accounts.identity_verifications.passed',
    'accounts.identity_verifications.failed',
    'account.identity_verification.passed',
    'account.identity_verification.failed',
], true)) {
    paymongo_webhook_respond(200, ['received' => true, 'ignored' => true]);
}
$eventId = $event['data']['id'] ?? null;
$verification = $attributes['data'] ?? null;
$verificationAttributes = is_array($verification)
    ? ($verification['attributes'] ?? [])
    : [];
$accountId = is_array($verificationAttributes)
    ? ($verificationAttributes['account_id'] ?? null)
    : null;
if (!is_string($accountId) && is_array($verification)) {
    $accountId = $verification['account_id'] ?? null;
}
$verificationId = is_array($verification) ? ($verification['id'] ?? null) : null;
$result = is_array($verificationAttributes)
    ? ($verificationAttributes['result'] ?? null)
    : null;
if (!is_string($result) && is_array($verification)) {
    $result = $verification['result'] ?? null;
}
if (!is_string($eventId) ||
    !preg_match('/^evt_[A-Za-z0-9]+$/D', $eventId) ||
    !is_string($accountId) ||
    !preg_match('/^org_[A-Za-z0-9]+$/D', $accountId) ||
    !is_string($verificationId) ||
    !preg_match('/^verif_[A-Za-z0-9]+$/D', $verificationId) ||
    !in_array($result, ['passed', 'failed', 'invalid'], true)) {
    paymongo_webhook_respond(400, ['error' => 'invalid_event']);
}
$identityStatus = $result === 'passed' ? 'passed' : 'failed';
$db = fleet_db_connection($config);
try {
    $db->beginTransaction();
    $owner = fleet_db_execute(
        $db,
        'SELECT account_id FROM fleet_accounts
         WHERE paymongo_account_id = ? AND paymongo_identity_verification_id = ?
         FOR UPDATE',
        [$accountId, $verificationId]
    )->fetch();
    if (!is_array($owner)) {
        $db->commit();
        paymongo_webhook_respond(200, ['received' => true, 'ignored' => true]);
    }
    $insert = fleet_db_execute(
        $db,
        'INSERT IGNORE INTO fleet_paymongo_webhook_events
         (event_id, account_id, processed_at) VALUES (?, ?, ?)',
        [$eventId, $accountId, time()]
    );
    if ($insert->rowCount() > 0) {
        fleet_db_execute(
            $db,
            'UPDATE fleet_accounts
             SET paymongo_identity_status = ?, paymongo_updated_at = ?
             WHERE account_id = ? AND paymongo_account_id = ?
               AND paymongo_identity_verification_id = ?',
            [$identityStatus, time(), $owner['account_id'], $accountId, $verificationId]
        );
    }
    $db->commit();
} catch (Throwable $error) {
    if ($db->inTransaction()) {
        $db->rollBack();
    }
    if ($error instanceof PDOException) {
        error_log('PayMongo identity webhook database operation failed (' .
            (string)$error->getCode() . ').');
        paymongo_webhook_respond(503, ['error' => 'webhook_processing_unavailable']);
    }
    throw $error;
}
paymongo_webhook_respond(200, ['received' => true]);
