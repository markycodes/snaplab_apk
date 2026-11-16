<?php
require __DIR__ . '/ganap_common.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    header('Allow: POST');
    ganap_respond(405, ['error' => 'method_not_allowed']);
}

$config = ganap_config();
if (!ganap_is_configured($config)) {
    ganap_configuration_error($config);
}

$contentLength = $_SERVER['CONTENT_LENGTH'] ?? null;
if (is_string($contentLength) &&
    ctype_digit($contentLength) &&
    (int)$contentLength > 65536) {
    ganap_respond(413, ['error' => 'request_too_large']);
}
$rawBody = file_get_contents('php://input');
if ($rawBody === false || strlen($rawBody) > 65536) {
    ganap_respond(413, ['error' => 'request_too_large']);
}

$providedSignature = $_SERVER['HTTP_X_GANAP_SIGNATURE'] ?? '';
$expectedSignature = hash_hmac('sha256', $rawBody, $config['ganap_signing_secret']);
if (!is_string($providedSignature) ||
    !preg_match('/^[a-f0-9]{64}$/iD', $providedSignature) ||
    !hash_equals($expectedSignature, strtolower($providedSignature))) {
    ganap_respond(401, ['error' => 'invalid_signature']);
}

try {
    $event = json_decode($rawBody, true, 16, JSON_THROW_ON_ERROR);
} catch (JsonException) {
    ganap_respond(400, ['error' => 'invalid_json']);
}
if (!is_array($event)) {
    ganap_respond(400, ['error' => 'invalid_event']);
}

if (($event['event'] ?? null) !== 'transaction.paid') {
    ganap_respond(422, ['error' => 'unsupported_payment_status']);
}

$referenceNumber = ganap_find_value($event, ['referenceNumber', 'reference_number']);
$amount = ganap_find_value($event, ['amount']);
$currency = ganap_find_value($event, ['currency']);
if (!is_string($referenceNumber) ||
    $referenceNumber === '' ||
    $currency !== 'PHP' ||
    (!is_int($amount) && !is_float($amount) && !is_string($amount)) ||
    !is_numeric($amount) ||
    (float)$amount !== (float)GANAP_SESSION_PRICE_PESOS) {
    ganap_respond(422, ['error' => 'invalid_payment_details']);
}

$updated = ganap_update_orders(function (array &$orders) use ($referenceNumber): bool {
    foreach ($orders as &$order) {
        if (($order['referenceNumber'] ?? null) !== $referenceNumber) continue;
        if (($order['status'] ?? null) === 'paid') return true;
        if (($order['status'] ?? null) !== 'pending' ||
            ($order['expiresAt'] ?? 0) <= time()) {
            return false;
        }
        $order['status'] = 'paid';
        $order['paidAt'] = time();
        return true;
    }
    return false;
});
if (!$updated) {
    ganap_respond(404, ['error' => 'payment_not_found_or_expired']);
}

ganap_respond(200, ['received' => true]);
