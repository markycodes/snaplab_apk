<?php
require __DIR__ . '/paymongo_common.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    header('Allow: POST');
    ganap_respond(405, ['error' => 'method_not_allowed']);
}

$config = ganap_config();
paymongo_require_enabled($config);
if (paymongo_missing_configuration($config) !== []) {
    paymongo_configuration_error($config);
}
ganap_require_sodium();
$db = fleet_db_connection($config);
$request = ganap_read_request();
$activation = ganap_activation_claims($request, $config);
if ($activation === null) {
    ganap_respond(401, ['error' => 'invalid_device_activation']);
}
if (!in_array('paymongo_qrph', $activation['features'], true)) {
    ganap_respond(403, ['error' => 'activation_feature_not_included']);
}
$deviceId = $activation['deviceId'];
$deviceAccount = paymongo_device_account($db, $deviceId);
if ($deviceAccount === null) {
    ganap_respond(409, ['error' => 'device_not_registered']);
}
$ownerId = $deviceAccount['ownerId'];
$idempotencyKey = $request['idempotencyKey'] ?? null;
if (!is_string($idempotencyKey) ||
    !preg_match('/^[a-f0-9]{32}$/D', $idempotencyKey)) {
    ganap_respond(400, ['error' => 'invalid_payment_reference']);
}
$order = paymongo_update_orders(function (array &$orders) use ($idempotencyKey, $deviceId, $ownerId): ?array {
    $order = $orders[$idempotencyKey] ?? null;
    if (!is_array($order)) return null;
    if (($order['deviceId'] ?? null) !== $deviceId ||
        (isset($order['ownerId']) && $order['ownerId'] !== $ownerId)) {
        ganap_respond(404, ['error' => 'payment_not_found']);
    }
    return $order;
});
if ($order === null || !is_string($order['paymentIntentId'] ?? null)) {
    ganap_respond(404, ['error' => 'payment_not_found']);
}
if (($order['status'] ?? null) === 'paid') {
    ganap_respond(200, ['status' => 'paid']);
}
if (($order['status'] ?? null) === 'expired') {
    ganap_respond(200, ['status' => 'expired']);
}

$paymongoAccountId = is_string($order['paymongoAccountId'] ?? null)
    ? $order['paymongoAccountId']
    : null;
$intent = paymongo_request(
    'GET',
    '/v1/payment_intents/' . rawurlencode($order['paymentIntentId']),
    null,
    $config['paymongo_secret_key'],
    $paymongoAccountId
);
$intentId = $intent['data']['id'] ?? null;
$attributes = $intent['data']['attributes'] ?? null;
$expectedAmount = $order['amountCentavos'] ?? PAYMONGO_DEFAULT_AMOUNT_CENTAVOS;
if ($intentId !== $order['paymentIntentId'] ||
    !is_array($attributes) ||
    !is_int($expectedAmount) ||
    $expectedAmount < PAYMONGO_MINIMUM_AMOUNT_CENTAVOS ||
    $expectedAmount > PAYMONGO_MAXIMUM_AMOUNT_CENTAVOS ||
    ($attributes['amount'] ?? null) !== $expectedAmount ||
    ($attributes['currency'] ?? null) !== 'PHP' ||
    !is_string($attributes['status'] ?? null)) {
    ganap_respond(502, ['error' => 'invalid_paymongo_checkout_response']);
}

$status = $attributes['status'];
if ($status === 'succeeded') {
    paymongo_update_orders(function (array &$orders) use ($idempotencyKey, $order): void {
        $current = $orders[$idempotencyKey] ?? null;
        if (!is_array($current) ||
            ($current['deviceId'] ?? null) !== $order['deviceId'] ||
            ($current['paymentIntentId'] ?? null) !== $order['paymentIntentId']) {
            ganap_respond(409, ['error' => 'payment_order_changed']);
        }
        $current['status'] = 'paid';
        $current['paidAt'] = time();
        $orders[$idempotencyKey] = $current;
    });
    ganap_respond(200, ['status' => 'paid']);
}

if (!in_array($status, ['awaiting_payment_method', 'awaiting_next_action', 'processing'], true)) {
    paymongo_update_orders(function (array &$orders) use ($idempotencyKey, $order): void {
        $current = $orders[$idempotencyKey] ?? null;
        if (is_array($current) &&
            ($current['paymentIntentId'] ?? null) === $order['paymentIntentId'] &&
            ($current['status'] ?? null) === 'pending') {
            $current['status'] = 'expired';
            $orders[$idempotencyKey] = $current;
        }
    });
    ganap_respond(200, ['status' => 'expired']);
}
if (($order['expiresAt'] ?? 0) <= time()) {
    paymongo_update_orders(function (array &$orders) use ($idempotencyKey, $order): void {
        $current = $orders[$idempotencyKey] ?? null;
        if (is_array($current) &&
            ($current['paymentIntentId'] ?? null) === $order['paymentIntentId'] &&
            ($current['status'] ?? null) === 'pending') {
            $current['status'] = 'expired';
            $orders[$idempotencyKey] = $current;
        }
    });
    ganap_respond(200, ['status' => 'expired']);
}
ganap_respond(200, ['status' => 'pending']);
