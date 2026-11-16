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
$paymongoAccountId = $deviceAccount['accountId'];
$paymentMethodApiKey = $paymongoAccountId === null
    ? $config['paymongo_public_key']
    : $config['paymongo_secret_key'];
$idempotencyKey = $request['idempotencyKey'] ?? null;
if (!is_string($idempotencyKey) ||
    !preg_match('/^[a-f0-9]{32}$/D', $idempotencyKey)) {
    ganap_respond(400, ['error' => 'invalid_checkout_details']);
}
$amountPesos = $request['amountPesos'] ?? null;
if (!paymongo_valid_amount_pesos($amountPesos)) {
    ganap_respond(400, [
        'error' => 'invalid_payment_amount',
        'minimumAmountPesos' => 1,
        'maximumAmountPesos' => 100000,
    ]);
}
$amountCentavos = $amountPesos * 100;

$ownerId = $deviceAccount['ownerId'];
$reservation = paymongo_update_orders(function (array &$orders) use ($idempotencyKey, $deviceId, $ownerId, $amountCentavos, $paymongoAccountId): array {
    $existing = $orders[$idempotencyKey] ?? null;
    if (is_array($existing)) {
        if (($existing['deviceId'] ?? null) !== $deviceId ||
            (isset($existing['ownerId']) && $existing['ownerId'] !== $ownerId) ||
            ($existing['paymongoAccountId'] ?? null) !== $paymongoAccountId) {
            ganap_respond(409, ['error' => 'idempotency_key_conflict']);
        }
        if (($existing['status'] ?? null) === 'pending' &&
            is_string($existing['qrImageBase64'] ?? null)) {
            $existingAmount = $existing['amountCentavos'] ?? PAYMONGO_DEFAULT_AMOUNT_CENTAVOS;
            if ($existingAmount !== $amountCentavos) {
                ganap_respond(409, ['error' => 'checkout_amount_conflict']);
            }
            return ['state' => 'existing', 'order' => $existing];
        }
        if (($existing['status'] ?? null) === 'creating' &&
            ($existing['reservationExpiresAt'] ?? 0) > time()) {
            return ['state' => 'creating'];
        }
    }
    $orders[$idempotencyKey] = [
        'deviceId' => $deviceId,
        'ownerId' => $ownerId,
        'paymongoAccountId' => $paymongoAccountId,
        'status' => 'creating',
        'createdAt' => time(),
        'reservationExpiresAt' => time() + 90,
    ];
    return ['state' => 'reserved'];
});
if ($reservation['state'] === 'existing') {
    $order = $reservation['order'];
    $testMode = str_starts_with($config['paymongo_public_key'], 'pk_test_');
    if ($testMode && !is_string($order['testUrl'] ?? null)) {
        ganap_respond(502, ['error' => 'invalid_paymongo_test_response']);
    }
    ganap_respond(200, [
        'referenceNumber' => $order['paymentIntentId'],
        'qrImageBase64' => $order['qrImageBase64'],
        'testUrl' => $order['testUrl'] ?? null,
        'amountPesos' => intdiv(
            $order['amountCentavos'] ?? PAYMONGO_DEFAULT_AMOUNT_CENTAVOS,
            100
        ),
    ]);
}
if ($reservation['state'] === 'creating') {
    ganap_respond(409, ['error' => 'checkout_in_progress']);
}

$releaseReservation = static function () use ($idempotencyKey): void {
    paymongo_update_orders(function (array &$orders) use ($idempotencyKey): void {
        if (($orders[$idempotencyKey]['status'] ?? null) === 'creating') {
            unset($orders[$idempotencyKey]);
        }
    });
};

try {
    $createdIntent = paymongo_request(
        'POST',
        '/v1/payment_intents',
        [
            'data' => [
                'attributes' => [
                    'amount' => $amountCentavos,
                    'currency' => 'PHP',
                    'payment_method_allowed' => ['qrph'],
                    'description' => 'Photobooth session ₱' . $amountPesos,
                ],
            ],
        ],
        $config['paymongo_secret_key'],
        $paymongoAccountId
    );
    $intentId = $createdIntent['data']['id'] ?? null;
    $clientKey = $createdIntent['data']['attributes']['client_key'] ?? null;
    if (!is_string($intentId) ||
        !preg_match('/^pi_[A-Za-z0-9]+$/D', $intentId) ||
        !is_string($clientKey) ||
        $clientKey === '' ||
        strlen($clientKey) > 256) {
        $releaseReservation();
        paymongo_invalid_checkout_response('create_intent', $createdIntent);
    }

    $paymentMethod = paymongo_request(
        'POST',
        '/v1/payment_methods',
        [
            'data' => [
                'attributes' => [
                    'type' => 'qrph',
                    'expiry_seconds' => PAYMONGO_QR_EXPIRY_SECONDS,
                ],
            ],
        ],
        $paymentMethodApiKey,
        $paymongoAccountId
    );
    $paymentMethodId = $paymentMethod['data']['id'] ?? null;
    if (!is_string($paymentMethodId) ||
        !preg_match('/^pm_[A-Za-z0-9]+$/D', $paymentMethodId)) {
        $releaseReservation();
        paymongo_invalid_checkout_response('create_payment_method', $paymentMethod);
    }

    $attachedIntent = paymongo_request(
        'POST',
        '/v1/payment_intents/' . rawurlencode($intentId) . '/attach',
        [
            'data' => [
                'attributes' => [
                    'payment_method' => $paymentMethodId,
                    'client_key' => $clientKey,
                ],
            ],
        ],
        $paymentMethodApiKey,
        $paymongoAccountId
    );
    $responseIntentId = $attachedIntent['data']['id'] ?? null;
    $attributes = $attachedIntent['data']['attributes'] ?? null;
    $qrImageBase64 = is_array($attachedIntent)
        ? paymongo_qr_image($attachedIntent)
        : null;
    if ($responseIntentId !== $intentId ||
        !is_array($attributes) ||
        ($attributes['amount'] ?? null) !== $amountCentavos ||
        ($attributes['currency'] ?? null) !== 'PHP' ||
        ($attributes['status'] ?? null) !== 'awaiting_next_action' ||
        $qrImageBase64 === null) {
        $releaseReservation();
        paymongo_invalid_checkout_response('attach_qr', $attachedIntent);
    }
    $testUrl = str_starts_with($config['paymongo_public_key'], 'pk_test_')
        ? paymongo_test_url($attachedIntent)
        : null;
    if (str_starts_with($config['paymongo_public_key'], 'pk_test_') &&
        $testUrl === null) {
        $releaseReservation();
        ganap_respond(502, ['error' => 'invalid_paymongo_test_response']);
    }
} catch (JsonException) {
    $releaseReservation();
    ganap_respond(502, ['error' => 'invalid_paymongo_checkout_response']);
}

$order = [
    'deviceId' => $deviceId,
    'ownerId' => $ownerId,
    'paymongoAccountId' => $paymongoAccountId,
    'paymentIntentId' => $intentId,
    'qrImageBase64' => $qrImageBase64,
    'testUrl' => $testUrl,
    'amountCentavos' => $amountCentavos,
    'status' => 'pending',
    'createdAt' => time(),
    'expiresAt' => time() + PAYMONGO_QR_EXPIRY_SECONDS,
];
paymongo_update_orders(function (array &$orders) use ($idempotencyKey, $order): void {
    $orders[$idempotencyKey] = $order;
});

ganap_respond(200, [
    'referenceNumber' => $intentId,
    'qrImageBase64' => $qrImageBase64,
    'testUrl' => $order['testUrl'],
    'amountPesos' => $amountPesos,
]);
