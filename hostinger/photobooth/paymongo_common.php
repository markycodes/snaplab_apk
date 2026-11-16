<?php
require_once __DIR__ . '/ganap_common.php';
require_once __DIR__ . '/fleet_db.php';

const PAYMONGO_DEFAULT_AMOUNT_CENTAVOS = 2000;
const PAYMONGO_MINIMUM_AMOUNT_CENTAVOS = 100;
const PAYMONGO_MAXIMUM_AMOUNT_CENTAVOS = 10000000;
const PAYMONGO_QR_EXPIRY_SECONDS = 300;

function paymongo_valid_amount_pesos(mixed $amount): bool
{
    return is_int($amount) && $amount >= 1 && $amount <= 100000;
}

function paymongo_require_enabled(array $config): void
{
    if (($config['paymongo_enabled'] ?? false) !== true) {
        ganap_respond(503, ['error' => 'paymongo_disabled']);
    }
}

function paymongo_missing_configuration(array $config): array
{
    $missing = [];
    if (!is_string($config['activation_public_key'] ?? null) ||
        !preg_match('/^[a-f0-9]{64}$/iD', $config['activation_public_key'])) {
        $missing[] = 'activation_public_key';
    }
    foreach (['paymongo_public_key' => 'pk', 'paymongo_secret_key' => 'sk'] as $key => $prefix) {
        if (!is_string($config[$key] ?? null) ||
            !preg_match('/^' . $prefix . '_(?:test|live)_[A-Za-z0-9_-]{8,}$/D', $config[$key])) {
            $missing[] = $key;
        }
    }
    $publicMode = is_string($config['paymongo_public_key'] ?? null)
        ? (str_starts_with($config['paymongo_public_key'], 'pk_test_') ? 'test' : 'live')
        : null;
    $secretMode = is_string($config['paymongo_secret_key'] ?? null)
        ? (str_starts_with($config['paymongo_secret_key'], 'sk_test_') ? 'test' : 'live')
        : null;
    if ($publicMode !== null && $secretMode !== null && $publicMode !== $secretMode) {
        $missing[] = 'paymongo_key_mode_mismatch';
    }
    return $missing;
}

function paymongo_configuration_error(array $config): never
{
    ganap_respond(503, [
        'error' => 'paymongo_not_configured',
        'missing' => paymongo_missing_configuration($config),
    ]);
}

function paymongo_update_orders(callable $callback): mixed
{
    $path = __DIR__ . '/photobooth_private/paymongo_orders.json';
    $file = fopen($path, 'c+');
    if ($file === false || !flock($file, LOCK_EX)) {
        if (is_resource($file)) fclose($file);
        ganap_respond(503, ['error' => 'payment_storage_unavailable']);
    }

    try {
        rewind($file);
        $contents = stream_get_contents($file);
        $orders = $contents === '' || $contents === false
            ? []
            : json_decode($contents, true);
        if (!is_array($orders)) {
            ganap_respond(500, ['error' => 'payment_storage_invalid']);
        }
        $retentionCutoff = time() - 2 * 24 * 60 * 60;
        foreach ($orders as $key => $order) {
            if (!is_array($order) ||
                !is_int($order['createdAt'] ?? null) ||
                $order['createdAt'] <= $retentionCutoff) {
                unset($orders[$key]);
            }
        }
        $result = $callback($orders);
        rewind($file);
        if (!ftruncate($file, 0) ||
            fwrite($file, json_encode($orders, JSON_THROW_ON_ERROR)) === false ||
            !fflush($file)) {
            ganap_respond(503, ['error' => 'payment_storage_unavailable']);
        }
        return $result;
    } catch (JsonException) {
        ganap_respond(500, ['error' => 'payment_storage_invalid']);
    } finally {
        flock($file, LOCK_UN);
        fclose($file);
    }
}

function paymongo_request(
    string $method,
    string $path,
    ?array $body,
    string $apiKey,
    ?string $accountId = null
): array {
    if (!function_exists('curl_init')) {
        ganap_respond(503, ['error' => 'server_http_client_unavailable']);
    }
    $curl = curl_init('https://api.paymongo.com' . $path);
    $options = [
        CURLOPT_CUSTOMREQUEST => $method,
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_CONNECTTIMEOUT => 10,
        CURLOPT_TIMEOUT => 25,
        CURLOPT_SSL_VERIFYPEER => true,
        CURLOPT_SSL_VERIFYHOST => 2,
        CURLOPT_HTTPHEADER => array_merge([
            'Authorization: Basic ' . base64_encode($apiKey . ':'),
            'Content-Type: application/json',
        ], $accountId === null ? [] : ['Account-ID: ' . $accountId]),
    ];
    if ($body !== null) {
        $options[CURLOPT_POSTFIELDS] = json_encode(
            $body,
            JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR
        );
    }
    curl_setopt_array($curl, $options);
    $responseBody = curl_exec($curl);
    $httpStatus = curl_getinfo($curl, CURLINFO_RESPONSE_CODE);
    $curlError = curl_errno($curl);
    curl_close($curl);
    if ($responseBody === false || $curlError !== 0) {
        error_log('PayMongo API transport failed; cURL error code ' . $curlError . '.');
        ganap_respond(502, ['error' => 'paymongo_transport_error']);
    }
    try {
        $response = json_decode($responseBody, true, 32, JSON_THROW_ON_ERROR);
    } catch (JsonException) {
        if ($httpStatus < 200 || $httpStatus >= 300) {
            error_log('PayMongo API rejected a request with HTTP ' . $httpStatus . '.');
            ganap_respond(502, [
                'error' => 'paymongo_request_failed',
                'providerStatus' => $httpStatus,
            ]);
        }
        ganap_respond(502, ['error' => 'invalid_paymongo_checkout_response']);
    }
    if ($httpStatus < 200 || $httpStatus >= 300) {
        error_log('PayMongo API rejected a request with HTTP ' . $httpStatus . '.');
        ganap_respond(502, [
            'error' => 'paymongo_request_failed',
            'providerStatus' => $httpStatus,
        ]);
    }
    if (!is_array($response)) {
        ganap_respond(502, ['error' => 'invalid_paymongo_checkout_response']);
    }
    return $response;
}

function paymongo_request_multipart(
    string $path,
    array $fields,
    string $apiKey,
    string $accountId
): array {
    if (!function_exists('curl_init') || !function_exists('curl_file_create')) {
        ganap_respond(503, ['error' => 'server_http_client_unavailable']);
    }
    $curl = curl_init('https://api.paymongo.com' . $path);
    curl_setopt_array($curl, [
        CURLOPT_POST => true,
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_CONNECTTIMEOUT => 10,
        CURLOPT_TIMEOUT => 45,
        CURLOPT_SSL_VERIFYPEER => true,
        CURLOPT_SSL_VERIFYHOST => 2,
        CURLOPT_HTTPHEADER => [
            'Authorization: Basic ' . base64_encode($apiKey . ':'),
            'Accept: application/json',
            'Account-ID: ' . $accountId,
        ],
        CURLOPT_POSTFIELDS => $fields,
    ]);
    $responseBody = curl_exec($curl);
    $httpStatus = curl_getinfo($curl, CURLINFO_RESPONSE_CODE);
    $curlError = curl_errno($curl);
    curl_close($curl);
    if ($responseBody === false || $curlError !== 0) {
        error_log('PayMongo identity verification transport failed; cURL error code ' .
            $curlError . '.');
        ganap_respond(502, ['error' => 'paymongo_transport_error']);
    }
    try {
        $response = json_decode($responseBody, true, 32, JSON_THROW_ON_ERROR);
    } catch (JsonException) {
        error_log('PayMongo identity verification returned invalid JSON (HTTP ' .
            $httpStatus . ').');
        ganap_respond(502, [
            'error' => 'paymongo_invalid_response',
            'providerStatus' => $httpStatus,
        ]);
    }
    if ($httpStatus < 200 || $httpStatus >= 300 || !is_array($response)) {
        $providerError = is_array($response) &&
            is_array($response['errors'][0] ?? null)
            ? $response['errors'][0]
            : [];
        $providerErrorCode = $providerError['code'] ?? null;
        if (!is_string($providerErrorCode) ||
            !preg_match('/^[A-Za-z0-9_.-]{1,100}$/D', $providerErrorCode)) {
            $providerErrorCode = null;
        }
        $providerDetail = $providerError['detail'] ?? null;
        if (!is_string($providerDetail)) {
            $providerDetail = null;
        } else {
            $providerDetail = preg_replace('/[\x00-\x1F\x7F]+/u', ' ', $providerDetail);
            $providerDetail = is_string($providerDetail)
                ? substr(trim($providerDetail), 0, 300)
                : null;
        }
        $providerPointer = $providerError['source']['pointer'] ?? null;
        if (!is_string($providerPointer) ||
            !preg_match('/^\/[A-Za-z0-9_\/.-]{1,120}$/D', $providerPointer)) {
            $providerPointer = null;
        }
        error_log('PayMongo identity verification request failed (HTTP ' .
            $httpStatus . ', provider code ' . ($providerErrorCode ?? 'unavailable') . ').');
        ganap_respond(502, [
            'error' => 'paymongo_request_failed',
            'providerStatus' => $httpStatus,
            'providerCode' => $providerErrorCode,
            'providerDetail' => $providerDetail,
            'providerPointer' => $providerPointer,
        ]);
    }
    return $response;
}

function paymongo_device_account(PDO $db, string $deviceId): ?array
{
    $registration = fleet_db_execute(
        $db,
        'SELECT r.owner_id, a.paymongo_account_id, a.paymongo_account_status
         FROM fleet_registered_devices r
         LEFT JOIN fleet_accounts a ON a.account_id = r.owner_id
         WHERE r.device_id = ? AND r.active = 1',
        [$deviceId]
    )->fetch();
    if (!is_array($registration)) {
        return [
            'ownerId' => 'parent:' . $deviceId,
            'accountId' => null,
        ];
    }
    $accountId = is_string($registration['paymongo_account_id'] ?? null) &&
            preg_match('/^org_[A-Za-z0-9]+$/D', $registration['paymongo_account_id']) &&
            ($registration['paymongo_account_status'] ?? null) === 'activated'
        ? $registration['paymongo_account_id']
        : null;
    return [
        'ownerId' => (string)$registration['owner_id'],
        'accountId' => $accountId,
    ];
}

function paymongo_qr_image(array $intent): ?string
{
    $image = $intent['data']['attributes']['next_action']['code']['image_url'] ?? null;
    if (!is_string($image)) return null;
    $image = trim($image);
    $declaredMime = null;
    if (preg_match(
        '~^data:image/(png|jpeg|webp);base64,([A-Za-z0-9+/]+={0,2})$~Di',
        $image,
        $match
    ) === 1) {
        $declaredMime = strtolower($match[1]);
        $image = $match[2];
    }
    if (strlen($image) > 700000 ||
        preg_match('~^[A-Za-z0-9+/]+={0,2}$~D', $image) !== 1) {
        return null;
    }
    $decoded = base64_decode($image, true);
    if ($decoded === false || strlen($decoded) > 524288) {
        return null;
    }
    $actualMime = null;
    if (strlen($decoded) >= 8 &&
        substr($decoded, 0, 8) === "\x89PNG\r\n\x1a\n") {
        $actualMime = 'png';
    } elseif (strlen($decoded) >= 3 &&
        substr($decoded, 0, 3) === "\xFF\xD8\xFF") {
        $actualMime = 'jpeg';
    } elseif (strlen($decoded) >= 12 &&
        substr($decoded, 0, 4) === 'RIFF' &&
        substr($decoded, 8, 4) === 'WEBP') {
        $actualMime = 'webp';
    }
    if ($actualMime === null ||
        ($declaredMime !== null && $declaredMime !== $actualMime)) {
        return null;
    }
    return $image;
}

function paymongo_invalid_checkout_response(string $step, array $response): never
{
    $data = $response['data'] ?? null;
    $attributes = is_array($data) ? ($data['attributes'] ?? null) : null;
    $nextAction = is_array($attributes)
        ? ($attributes['next_action'] ?? null)
        : null;
    $code = is_array($nextAction) ? ($nextAction['code'] ?? null) : null;
    $image = is_array($code) ? ($code['image_url'] ?? null) : null;
    $imageKind = 'missing';
    $imageLength = null;
    if (is_string($image)) {
        $imageLength = strlen($image);
        if (preg_match('~^data:image/([a-z0-9.+-]+);base64,~i', $image, $match) === 1) {
            $imageKind = 'data_uri_' . strtolower($match[1]);
        } elseif (preg_match('/^[A-Za-z0-9+\/\r\n]+={0,2}$/D', $image) === 1) {
            $imageKind = 'base64';
        } elseif (preg_match('~^https://~i', $image) === 1) {
            $imageKind = 'https_url';
        } else {
            $imageKind = 'other_string';
        }
    } elseif ($image !== null) {
        $imageKind = get_debug_type($image);
    }
    ganap_respond(502, [
        'error' => 'invalid_paymongo_checkout_response',
        'providerStep' => $step,
        'responseKeys' => is_array($response) ? array_slice(array_map('strval', array_keys($response)), 0, 20) : [],
        'dataKeys' => is_array($data) ? array_slice(array_map('strval', array_keys($data)), 0, 20) : [],
        'attributeKeys' => is_array($attributes) ? array_slice(array_map('strval', array_keys($attributes)), 0, 30) : [],
        'nextActionKeys' => is_array($nextAction) ? array_slice(array_map('strval', array_keys($nextAction)), 0, 20) : [],
        'codeKeys' => is_array($code) ? array_slice(array_map('strval', array_keys($code)), 0, 20) : [],
        'intentStatus' => is_array($attributes) && is_string($attributes['status'] ?? null)
            ? $attributes['status']
            : null,
        'amount' => is_array($attributes) &&
            (is_int($attributes['amount'] ?? null) || is_float($attributes['amount'] ?? null))
            ? $attributes['amount']
            : null,
        'currency' => is_array($attributes) && is_string($attributes['currency'] ?? null)
            ? $attributes['currency']
            : null,
        'qrImageKind' => $imageKind,
        'qrImageLength' => $imageLength,
    ]);
}

function paymongo_test_url(mixed $value): ?string
{
    if (!is_array($value)) return null;
    foreach ($value as $key => $child) {
        if (is_string($key) &&
            strtolower($key) === 'test_url' &&
            is_string($child) &&
            strlen($child) <= 2048) {
            $url = parse_url($child);
            $host = is_array($url) ? strtolower($url['host'] ?? '') : '';
            if (is_array($url) &&
                strtolower($url['scheme'] ?? '') === 'https' &&
                $host !== '' &&
                ($host === 'paymongo.com' || str_ends_with($host, '.paymongo.com')) &&
                !isset($url['user']) &&
                !isset($url['pass'])) {
                return $child;
            }
        }
        if (is_array($child)) {
            $found = paymongo_test_url($child);
            if ($found !== null) return $found;
        }
    }
    return null;
}
