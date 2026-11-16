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
ganap_require_sodium();
$request = ganap_read_request();
$activation = ganap_activation_claims($request, $config);
if ($activation === null) {
    ganap_respond(401, ['error' => 'invalid_device_activation']);
}
if (!in_array('ganap_qrph', $activation['features'], true)) {
    ganap_respond(403, ['error' => 'activation_feature_not_included']);
}
$deviceId = $activation['deviceId'];
$idempotencyKey = $request['idempotencyKey'] ?? null;
if (!is_string($idempotencyKey) || !preg_match('/^[a-f0-9]{32}$/D', $idempotencyKey)) {
    ganap_respond(400, ['error' => 'invalid_payment_reference']);
}

$order = ganap_update_orders(function (array &$orders) use ($idempotencyKey, $deviceId): ?array {
    $order = $orders[$idempotencyKey] ?? null;
    if (!is_array($order)) return null;
    if (($order['deviceId'] ?? null) !== $deviceId) {
        ganap_respond(404, ['error' => 'payment_not_found']);
    }
    return $order;
});
if ($order === null) {
    ganap_respond(404, ['error' => 'payment_not_found']);
}
if (($order['status'] ?? null) === 'pending' && ($order['expiresAt'] ?? 0) <= time()) {
    $order['status'] = 'expired';
    ganap_update_orders(function (array &$orders) use ($idempotencyKey, $order): void {
        $orders[$idempotencyKey] = $order;
    });
}

ganap_respond(200, ['status' => $order['status']]);
