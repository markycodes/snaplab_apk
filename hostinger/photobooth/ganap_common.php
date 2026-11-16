<?php
header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');
header('X-Content-Type-Options: nosniff');

const GANAP_SESSION_PRICE_PESOS = 20;
const GANAP_MINIMUM_AMOUNT_PESOS = 200;

function ganap_respond(int $status, array $body): void
{
    http_response_code($status);
    echo json_encode($body, JSON_UNESCAPED_SLASHES);
    exit;
}

function ganap_config(): array
{
    return require __DIR__ . '/photobooth_private/photobooth_config.php';
}

function ganap_is_configured(array $config): bool
{
    return ganap_missing_configuration($config) === [];
}

function ganap_missing_configuration(array $config): array
{
    $missing = [];
    if (!is_string($config['activation_public_key'] ?? null) ||
        !preg_match('/^[a-f0-9]{64}$/i', $config['activation_public_key'])) {
        $missing[] = 'activation_public_key';
    }
    if (!is_string($config['ganap_project_uuid'] ?? null) ||
        !preg_match('/^[a-f0-9-]{36}$/i', $config['ganap_project_uuid'])) {
        $missing[] = 'ganap_project_uuid';
    }
    if (!is_string($config['ganap_signing_secret'] ?? null) ||
        strlen($config['ganap_signing_secret']) < 32 ||
        strpos($config['ganap_signing_secret'], 'REPLACE_WITH_') === 0) {
        $missing[] = 'ganap_signing_secret';
    }
    if (!is_int($config['ganap_amount'] ?? null) ||
        $config['ganap_amount'] !== GANAP_SESSION_PRICE_PESOS) {
        $missing[] = 'ganap_amount';
    }
    if (!is_string($config['ganap_customer_email'] ?? null) ||
        !filter_var($config['ganap_customer_email'], FILTER_VALIDATE_EMAIL) ||
        strlen($config['ganap_customer_email']) > 254) {
        $missing[] = 'ganap_customer_email';
    }
    return $missing;
}

function ganap_configuration_error(array $config): never
{
    ganap_respond(503, [
        'error' => 'ganap_not_configured',
        'missing' => ganap_missing_configuration($config),
    ]);
}

function ganap_require_sodium(): void
{
    if (!function_exists('sodium_crypto_sign_verify_detached')) {
        ganap_respond(503, ['error' => 'server_ed25519_support_unavailable']);
    }
}

function ganap_valid_device(array $request, array $config): ?string
{
    $activation = ganap_activation_claims($request, $config);
    return $activation['deviceId'] ?? null;
}

function ganap_activation_claims(array $request, array $config): ?array
{
    $deviceId = $request['deviceId'] ?? null;
    $activationCode = $request['activationCode'] ?? null;
    if (is_string($activationCode)) {
        $activationCode = preg_replace('/\s+/', '', $activationCode);
        $activationCode = is_string($activationCode)
            ? preg_replace('/=+$/', '', $activationCode)
            : null;
    }
    if (!is_string($deviceId) ||
        !preg_match('/^[A-Za-z0-9._:-]{8,128}$/D', $deviceId) ||
        !is_string($activationCode) ||
        strlen($activationCode) > 512) {
        return null;
    }

    $parts = explode('.', $activationCode);
    if (count($parts) === 1 &&
        preg_match('/^3([0-3])([A-Za-z0-9_-]{86})$/D', $parts[0], $matches)) {
        $featureMask = (int)$matches[1];
        $signature = ganap_decode_base64url($matches[2]);
        $message = 'photobooth-kiosk-activation-v3:' .
            $deviceId . ':' . $featureMask;
        $features = [];
        if (($featureMask & 1) !== 0) $features[] = 'paymongo_qrph';
        if (($featureMask & 2) !== 0) $features[] = 'ganap_qrph';
    } elseif (count($parts) === 1 &&
        preg_match('/^[A-Za-z0-9_-]{86}$/D', $parts[0])) {
        $signature = ganap_decode_base64url($parts[0]);
        $message = 'photobooth-kiosk-activation-v1:' . $deviceId;
        $features = [];
    } elseif (count($parts) === 2 &&
        preg_match('/^[A-Za-z0-9_-]+$/D', $parts[0]) &&
        preg_match('/^[A-Za-z0-9_-]{86}$/D', $parts[1])) {
        $payloadBytes = ganap_decode_base64url($parts[0]);
        $payload = $payloadBytes === false
            ? null
            : json_decode($payloadBytes);
        if (!is_object($payload) ||
            ($payload->version ?? null) !== 2 ||
            ($payload->deviceId ?? null) !== $deviceId ||
            !is_array($payload->features ?? null)) {
            return null;
        }
        $allowedFeatures = ['ganap_qrph', 'paymongo_qrph'];
        $features = $payload->features;
        $expectedIndex = 0;
        foreach ($features as $index => $feature) {
            if ($index !== $expectedIndex++ || !is_string($feature)) {
                return null;
            }
        }
        if (count(array_unique($features)) !== count($features)) return null;
        foreach ($features as $feature) {
            if (!in_array($feature, $allowedFeatures, true)) {
                return null;
            }
        }
        $signature = ganap_decode_base64url($parts[1]);
        $message = 'photobooth-kiosk-activation-v2:' . $parts[0];
    } else {
        return null;
    }
    $publicKey = hex2bin($config['activation_public_key']);
    if ($signature === false ||
        strlen($signature) !== SODIUM_CRYPTO_SIGN_BYTES ||
        $publicKey === false ||
        !sodium_crypto_sign_verify_detached($signature, $message, $publicKey)) {
        return null;
    }
    return ['deviceId' => $deviceId, 'features' => $features];
}

function ganap_decode_base64url(string $value): string|false
{
    $normalized = strtr($value, '-_', '+/');
    $normalized .= str_repeat('=', (4 - strlen($normalized) % 4) % 4);
    return base64_decode($normalized, true);
}

function ganap_read_request(): array
{
    $contentLength = $_SERVER['CONTENT_LENGTH'] ?? null;
    if (is_string($contentLength) &&
        ctype_digit($contentLength) &&
        (int)$contentLength > 8192) {
        ganap_respond(413, ['error' => 'request_too_large']);
    }
    $raw = file_get_contents('php://input');
    if ($raw === false || strlen($raw) > 8192) {
        ganap_respond(413, ['error' => 'request_too_large']);
    }
    try {
        $request = json_decode($raw, true, 16, JSON_THROW_ON_ERROR);
    } catch (JsonException) {
        ganap_respond(400, ['error' => 'invalid_json']);
    }
    if (!is_array($request)) {
        ganap_respond(400, ['error' => 'invalid_request']);
    }
    return $request;
}

function ganap_update_orders(callable $callback): mixed
{
    $path = __DIR__ . '/photobooth_private/ganap_orders.json';
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

function ganap_find_value(array $data, array $keys): mixed
{
    foreach ($keys as $key) {
        if (array_key_exists($key, $data)) return $data[$key];
    }
    foreach ($data as $value) {
        if (is_array($value)) {
            $found = ganap_find_value($value, $keys);
            if ($found !== null) return $found;
        }
    }
    return null;
}
