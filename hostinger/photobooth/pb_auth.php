<?php
header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');

require_once __DIR__ . '/ganap_common.php';

function respond(int $status, array $body): void
{
    http_response_code($status);
    echo json_encode($body, JSON_UNESCAPED_SLASHES);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    header('Allow: POST');
    respond(405, ['error' => 'method_not_allowed']);
}

$config = ganap_config();
$signingKey = $config['credential_signing_key'] ?? '';
$publicKeyHex = $config['activation_public_key'] ?? '';
if (!is_string($signingKey) ||
    strlen($signingKey) < 32 ||
    strpos($signingKey, 'REPLACE_WITH_') === 0 ||
    !is_string($publicKeyHex) ||
    !preg_match('/^[a-f0-9]{64}$/i', $publicKeyHex)) {
    respond(503, ['error' => 'credential_signing_key_not_configured']);
}

if (!function_exists('sodium_crypto_sign_verify_detached')) {
    respond(503, ['error' => 'server_ed25519_support_unavailable']);
}

try {
    $rawRequest = file_get_contents('php://input');
    if ($rawRequest === false || strlen($rawRequest) > 4096) {
        respond(400, ['error' => 'invalid_request']);
    }
    $request = json_decode($rawRequest, true, 8, JSON_THROW_ON_ERROR);
} catch (JsonException) {
    respond(400, ['error' => 'invalid_request']);
}

if (!is_array($request)) {
    respond(400, ['error' => 'invalid_request']);
}

$activation = ganap_activation_claims($request, $config);
if ($activation === null) {
    respond(400, ['error' => 'activation_required']);
}

$payload = json_encode([
    'aud' => 'pb_upload',
    'deviceId' => $activation['deviceId'],
    'exp' => time() + 300,
], JSON_UNESCAPED_SLASHES);
$encodedPayload = rtrim(strtr(base64_encode($payload), '+/', '-_'), '=');
$signature = hash_hmac('sha256', $encodedPayload, $signingKey, true);
$encodedSignature = rtrim(strtr(base64_encode($signature), '+/', '-_'), '=');

respond(200, [
    'accessToken' => $encodedPayload . '.' . $encodedSignature,
    'expiresIn' => 300,
]);
