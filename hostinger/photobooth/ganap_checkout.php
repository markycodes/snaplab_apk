<?php
require __DIR__ . '/ganap_common.php';

const GANAP_CHECKOUT_ENDPOINT_VERSION = '202611-qrph-v1';
header('X-Photobooth-Endpoint-Version: ' . GANAP_CHECKOUT_ENDPOINT_VERSION);

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    header('Allow: POST');
    ganap_respond(405, [
        'error' => 'method_not_allowed',
        'endpointVersion' => GANAP_CHECKOUT_ENDPOINT_VERSION,
    ]);
}

$config = ganap_config();
if (!ganap_is_configured($config)) {
    ganap_configuration_error($config);
}
if (GANAP_SESSION_PRICE_PESOS < GANAP_MINIMUM_AMOUNT_PESOS) {
    ganap_respond(503, [
        'error' => 'ganap_minimum_exceeds_session_price',
        'minimumAmount' => GANAP_MINIMUM_AMOUNT_PESOS,
        'sessionPrice' => GANAP_SESSION_PRICE_PESOS,
    ]);
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
if (!is_string($idempotencyKey) ||
    !preg_match('/^[a-f0-9]{32}$/D', $idempotencyKey)) {
    ganap_respond(400, ['error' => 'invalid_checkout_details']);
}

$existing = ganap_update_orders(function (array &$orders) use ($idempotencyKey, $deviceId): ?array {
    $order = $orders[$idempotencyKey] ?? null;
    if (!is_array($order)) return null;
    if (($order['deviceId'] ?? null) !== $deviceId) {
        ganap_respond(409, ['error' => 'idempotency_key_conflict']);
    }
    return $order;
});
if ($existing !== null) {
    if (!is_string($existing['qrType'] ?? null) ||
        !is_string($existing['qrContent'] ?? null)) {
        ganap_respond(409, ['error' => 'legacy_payment_requires_new_checkout']);
    }
    ganap_respond(200, [
        'referenceNumber' => $existing['referenceNumber'],
        'qrType' => $existing['qrType'],
        'qrContent' => $existing['qrContent'],
    ]);
}

if (!function_exists('curl_init')) {
    ganap_respond(503, ['error' => 'server_http_client_unavailable']);
}

$body = json_encode([
    'projectUuid' => $config['ganap_project_uuid'],
    'amount' => GANAP_SESSION_PRICE_PESOS,
    'idempotencyKey' => $idempotencyKey,
    'customerName' => $config['ganap_customer_name'] ?? 'Photobooth Guest',
    'customerEmail' => $config['ganap_customer_email'],
    'externalReference' => $idempotencyKey,
], JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR);
$signature = hash_hmac('sha256', $body, $config['ganap_signing_secret']);
$curl = curl_init('https://api.ganap.net/v1/checkout');
curl_setopt_array($curl, [
    CURLOPT_POST => true,
    CURLOPT_POSTFIELDS => $body,
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_CONNECTTIMEOUT => 10,
    CURLOPT_TIMEOUT => 25,
    CURLOPT_SSL_VERIFYPEER => true,
    CURLOPT_SSL_VERIFYHOST => 2,
    CURLOPT_HTTPHEADER => [
        'Content-Type: application/json',
        'X-Ganap-Signature: ' . $signature,
    ],
]);
$responseBody = curl_exec($curl);
$httpStatus = curl_getinfo($curl, CURLINFO_RESPONSE_CODE);
$curlError = curl_errno($curl);
curl_close($curl);
if ($responseBody === false || $curlError !== 0) {
    error_log('Ganap checkout transport failed; curl error code ' . $curlError . '.');
    ganap_respond(502, [
        'error' => 'ganap_transport_error',
        'curlCode' => $curlError,
    ]);
}
if ($httpStatus < 200 || $httpStatus >= 300) {
    $providerResponse = json_decode($responseBody, true);
    $providerCode = is_array($providerResponse)
        ? ($providerResponse['code'] ?? $providerResponse['error'] ?? null)
        : null;
    if (is_array($providerCode)) {
        $providerCode = $providerCode['code'] ?? null;
    }
    if (!is_string($providerCode) ||
        !preg_match('/^[A-Za-z0-9_.-]{1,80}$/D', $providerCode)) {
        $providerCode = null;
    }
    $safeFields = [
        'projectUuid',
        'amount',
        'idempotencyKey',
        'customerName',
        'customerEmail',
        'externalReference',
        'metadata',
        'returnUrl',
        'paymentType',
    ];
    $providerField = null;
    $findSafeField = static function (mixed $value) use (&$findSafeField, &$providerField, $safeFields): void {
        if (!is_array($value) || $providerField !== null) return;
        foreach ($value as $key => $child) {
            if (is_string($key) && in_array($key, $safeFields, true)) {
                $providerField = $key;
                return;
            }
            if (is_string($key) &&
                in_array(strtolower($key), ['field', 'param', 'parameter'], true) &&
                is_string($child) &&
                in_array($child, $safeFields, true)) {
                $providerField = $child;
                return;
            }
            if (is_string($key) &&
                in_array(strtolower($key), ['loc', 'location', 'path', 'param'], true) &&
                is_array($child)) {
                foreach ($child as $part) {
                    if (is_string($part) && in_array($part, $safeFields, true)) {
                        $providerField = $part;
                        return;
                    }
                }
            }
            if (is_array($child)) $findSafeField($child);
            if ($providerField !== null) return;
        }
    };
    if (is_array($providerResponse)) $findSafeField($providerResponse);
    $providerMessage = null;
    $findMessage = static function (mixed $value) use (&$findMessage): ?string {
        if (!is_array($value)) return null;
        foreach ($value as $key => $child) {
            if (is_string($key) &&
                in_array(
                    strtolower($key),
                    ['message', 'msg', 'detail', 'description', 'error_description', 'error'],
                    true
                ) &&
                is_string($child) &&
                trim($child) !== '') {
                return trim($child);
            }
            if (is_array($child)) {
                $found = $findMessage($child);
                if ($found !== null) return $found;
            }
        }
        return null;
    };
    if (is_array($providerResponse)) {
        $providerMessage = $findMessage($providerResponse);
    }
    if (is_string($providerMessage)) {
        foreach ([
            $config['ganap_signing_secret'],
            $config['ganap_customer_email'],
            $config['ganap_customer_name'] ?? 'Photobooth Guest',
            $idempotencyKey,
        ] as $privateValue) {
            if (is_string($privateValue) && $privateValue !== '') {
                $providerMessage = str_replace($privateValue, '[redacted]', $providerMessage);
            }
        }
        $providerMessage = preg_replace('/[\x00-\x1F\x7F]/', ' ', $providerMessage);
        $providerMessage = preg_replace(
            '/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/i',
            '[email redacted]',
            (string)$providerMessage
        );
        $providerMessage = preg_replace(
            '/\b[A-Za-z0-9_-]{32,}\b/',
            '[token redacted]',
            (string)$providerMessage
        );
        $providerMessage = trim(substr((string)$providerMessage, 0, 240));
        if ($providerMessage === '') $providerMessage = null;
    }
    error_log(
        'Ganap checkout rejected with HTTP ' . $httpStatus .
        ($providerCode === null ? '' : ' (provider code ' . $providerCode . ')') .
        ($providerField === null ? '' : ' (field ' . $providerField . ')') .
        ($providerMessage === null ? '.' : ': ' . $providerMessage)
    );
    ganap_respond(502, [
        'error' => 'ganap_checkout_rejected',
        'ganapStatus' => $httpStatus,
        'providerCode' => $providerCode,
        'providerField' => $providerField,
        'providerMessage' => $providerMessage,
    ]);
}

try {
    $response = json_decode($responseBody, true, 16, JSON_THROW_ON_ERROR);
} catch (JsonException) {
    ganap_respond(502, [
        'error' => 'invalid_ganap_checkout_response',
        'responseProblem' => 'response_not_json',
    ]);
}
$referenceNumber = is_array($response)
    ? ganap_find_value($response, ['referenceNumber', 'reference_number'])
    : null;
$redirectUrl = is_array($response)
    ? ganap_find_value($response, [
        'redirectUrl',
        'redirect_url',
        'checkoutUrl',
        'checkout_url',
        'paymentUrl',
        'payment_url',
    ])
    : null;
$explicitQrImage = false;
$qrImage = is_array($response)
    ? ganap_find_value($response, [
        'qrImageUrl',
        'qr_image_url',
        'qrCodeImage',
        'qr_code_image',
    ])
    : null;
if (is_string($qrImage) && $qrImage !== '') {
    $redirectUrl = $qrImage;
    $explicitQrImage = true;
}
$redirectUrl = is_string($redirectUrl) ? trim($redirectUrl) : $redirectUrl;
$qrType = null;
$qrContentProblem = null;
if (is_string($redirectUrl) &&
    preg_match('~^data:image/~i', $redirectUrl) === 1) {
    $qrType = 'image_data';
    if (preg_match(
        '~^data:image/(png|jpeg|webp);base64,([A-Za-z0-9+/]+={0,2})$~D',
        $redirectUrl,
        $imageData
    ) !== 1) {
        $qrContentProblem = 'qr_image_data_invalid';
    } else {
        $decodedImage = base64_decode($imageData[2], true);
        if ($decodedImage === false ||
            strlen($decodedImage) === 0 ||
            strlen($decodedImage) > 524288) {
            $qrContentProblem = 'qr_image_data_invalid';
        }
    }
} elseif (is_string($redirectUrl) &&
    preg_match(
        '~^(?:https?:)?//|^(?:[a-z0-9-]+\.)+[a-z]{2,}(?::[0-9]{1,5})?(?:[/?#]|$)~i',
        $redirectUrl
    ) !== 1) {
    $qrType = 'payload';
    if (strlen($redirectUrl) > 4096 ||
        preg_match('/^[\x20-\x7E]+$/D', $redirectUrl) !== 1) {
        $qrContentProblem = 'qr_payload_invalid';
    }
}
if (is_string($redirectUrl) && $qrType === null) {
    $urlSeparatorWhitespace = '[\s\p{Z}\x{200B}\x{FEFF}]*';
    $redirectUrl = preg_replace(
        '~https' . $urlSeparatorWhitespace . ':' .
        $urlSeparatorWhitespace . '/' . $urlSeparatorWhitespace . '/' .
        $urlSeparatorWhitespace . '~iu',
        'https://',
        $redirectUrl
    );
    for ($normalizationPass = 0; $normalizationPass < 3; $normalizationPass++) {
        $previousUrl = $redirectUrl;
        $redirectUrl = str_replace('\\/', '/', $redirectUrl);
        $decodedJsonUrl = json_decode($redirectUrl);
        if (is_string($decodedJsonUrl) && $decodedJsonUrl !== $redirectUrl) {
            $redirectUrl = $decodedJsonUrl;
        } elseif (preg_match(
            '~^https?(?:%(?:25)*3a|:)(?:%(?:25)*2f|/){2}~i',
            $redirectUrl
        ) === 1) {
            $redirectUrl = rawurldecode($redirectUrl);
        }
        $redirectUrl = trim($redirectUrl);
        if ($redirectUrl === $previousUrl) break;
    }
    $containsWhitespace = preg_match('/[\s\p{Z}\x{200B}\x{FEFF}]/u', $redirectUrl) === 1;
    if ($containsWhitespace &&
        preg_match_all(
            '~https://[^\s\p{Z}\x{200B}\x{FEFF}<>"\'`]+~iu',
            $redirectUrl,
            $embeddedUrls
        ) > 0) {
        $ganapUrls = [];
        foreach ($embeddedUrls[0] as $embeddedUrl) {
            $embeddedUrl = rtrim($embeddedUrl, '.,;:!?)');
            $embeddedParsedUrl = parse_url($embeddedUrl);
            $embeddedHost = is_array($embeddedParsedUrl)
                ? strtolower($embeddedParsedUrl['host'] ?? '')
                : '';
            if (is_array($embeddedParsedUrl) &&
                strtolower($embeddedParsedUrl['scheme'] ?? '') === 'https' &&
                $embeddedHost !== '' &&
                !isset($embeddedParsedUrl['user']) &&
                !isset($embeddedParsedUrl['pass']) &&
                ($embeddedHost === 'ganap.net' || str_ends_with($embeddedHost, '.ganap.net'))) {
                $ganapUrls[$embeddedUrl] = true;
            }
        }
        if (count($ganapUrls) === 1) {
            $redirectUrl = array_key_first($ganapUrls);
        }
    }
}
if (is_string($redirectUrl) && $qrType === null) {
    $qrType = $explicitQrImage ||
        preg_match('/\.(?:png|jpe?g|webp)(?:[?#].*)?$/i', $redirectUrl) === 1
        ? 'image_url'
        : 'checkout_url';
}
$qrContent = $redirectUrl;
$providerHostWithoutScheme = is_string($redirectUrl) &&
    in_array($qrType, ['checkout_url', 'image_url'], true) &&
    preg_match(
        '~^(?:[a-z0-9-]+\.)*ganap\.net(?::[0-9]{1,5})?(?:[/?#]|$)~i',
        $redirectUrl
    ) === 1;
if (is_string($redirectUrl) && str_starts_with($redirectUrl, '//')) {
    $redirectUrl = 'https:' . $redirectUrl;
} elseif ($providerHostWithoutScheme) {
    $redirectUrl = 'https://' . $redirectUrl;
}
$parsedUrl = is_string($redirectUrl) &&
    in_array($qrType, ['checkout_url', 'image_url'], true)
    ? parse_url($redirectUrl)
    : false;
$host = is_array($parsedUrl) ? strtolower($parsedUrl['host'] ?? '') : '';
$scheme = is_array($parsedUrl) ? strtolower($parsedUrl['scheme'] ?? '') : '';
$candidateHost = null;
$checkoutCandidateHosts = [];
$checkoutUrlMatchCount = 0;
if (is_string($redirectUrl) &&
    in_array($qrType, ['checkout_url', 'image_url'], true) &&
    preg_match_all(
        '~https://([^/\s\p{Z}\x{200B}\x{FEFF}<>:"\'`?#]+)~iu',
        $redirectUrl,
        $urlCandidates
    ) > 0) {
    $checkoutUrlMatchCount = count($urlCandidates[0]);
    foreach ($urlCandidates[1] as $urlCandidateHost) {
        $normalizedCandidateHost = strtolower(rtrim($urlCandidateHost, '.'));
        if (preg_match(
            '/^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$/i',
            $normalizedCandidateHost
        ) === 1) {
            $checkoutCandidateHosts[$normalizedCandidateHost] = true;
        }
    }
    $checkoutCandidateHosts = array_keys($checkoutCandidateHosts);
}
if (is_string($redirectUrl) &&
    in_array($qrType, ['checkout_url', 'image_url'], true) &&
    preg_match(
        '~^([a-z0-9](?:[a-z0-9.-]{0,251}[a-z0-9])?)(?::[0-9]{1,5})?(?:[/?#]|$)~i',
        $redirectUrl,
        $candidateMatch
    ) === 1 &&
    str_contains($candidateMatch[1], '.')) {
    $candidateHost = strtolower($candidateMatch[1]);
}
$checkoutUrlShape = 'unknown';
if (is_string($redirectUrl) &&
    in_array($qrType, ['checkout_url', 'image_url'], true)) {
    if (str_starts_with($redirectUrl, '//')) {
        $checkoutUrlShape = 'scheme_relative';
    } elseif (str_starts_with($redirectUrl, '/')) {
        $checkoutUrlShape = 'relative_path';
    } elseif (str_starts_with($redirectUrl, '?')) {
        $checkoutUrlShape = 'relative_query';
    } elseif (str_starts_with($redirectUrl, '#')) {
        $checkoutUrlShape = 'relative_fragment';
    } elseif (preg_match('/^[a-z][a-z0-9+.-]*:/i', $redirectUrl) === 1) {
        $checkoutUrlShape = 'other_scheme';
    } elseif (preg_match('~^[a-z0-9-]+(?:\.[a-z0-9-]+)+(?::[0-9]{1,5})?(?:[/?#]|$)~i', $redirectUrl) === 1) {
        $checkoutUrlShape = 'bare_hostname';
    } elseif (preg_match('/^[a-z0-9_-]+$/i', $redirectUrl) === 1) {
        $checkoutUrlShape = 'opaque_token';
    } elseif (str_starts_with($redirectUrl, '{')) {
        $checkoutUrlShape = 'json_object_text';
    } elseif (str_starts_with($redirectUrl, '[')) {
        $checkoutUrlShape = 'json_array_text';
    } elseif (str_starts_with($redirectUrl, '<')) {
        $checkoutUrlShape = 'html_or_markup';
    } elseif (preg_match('~^https?%~i', $redirectUrl) === 1) {
        $checkoutUrlShape = 'percent_encoded_url';
    } elseif (preg_match('/[\s\p{Z}\x{200B}\x{FEFF}]/u', $redirectUrl) === 1) {
        $checkoutUrlShape = 'text_with_whitespace';
    } elseif (preg_match('/[^\x00-\x7F]/', $redirectUrl) === 1) {
        $checkoutUrlShape = 'non_ascii_text';
    } elseif (str_contains($redirectUrl, '://')) {
        $checkoutUrlShape = 'embedded_url_text';
    } else {
        $checkoutUrlShape = 'unrecognized_text';
    }
}
$responseProblem = null;
if (!is_array($response)) {
    $responseProblem = 'response_not_object';
} elseif (!is_string($referenceNumber) ||
    $referenceNumber === '' ||
    strlen($referenceNumber) > 128) {
    $responseProblem = 'reference_number_missing_or_invalid';
} elseif ($qrContentProblem !== null) {
    $responseProblem = $qrContentProblem;
} elseif (!in_array(
    $qrType,
    ['checkout_url', 'payload', 'image_data', 'image_url'],
    true
)) {
    $responseProblem = 'qr_content_missing_or_invalid';
} elseif (in_array($qrType, ['payload', 'image_data'], true)) {
    $responseProblem = null;
} elseif (!is_string($redirectUrl) || $redirectUrl === '') {
    $responseProblem = 'qr_content_missing_or_invalid';
} elseif (!is_array($parsedUrl)) {
    $responseProblem = 'checkout_url_invalid_format';
} elseif ($scheme !== 'https') {
    $responseProblem = 'checkout_url_scheme_not_https';
} elseif ($host === '') {
    $responseProblem = 'checkout_url_host_missing';
} elseif (isset($parsedUrl['user']) || isset($parsedUrl['pass'])) {
    $responseProblem = 'checkout_url_credentials_not_allowed';
} elseif (!($host === 'ganap.net' || str_ends_with($host, '.ganap.net'))) {
    $responseProblem = 'checkout_url_host_not_allowed';
}
if ($responseProblem !== null) {
    $responseKeys = [];
    $collectKeys = static function (mixed $value, int $depth = 0) use (&$collectKeys, &$responseKeys): void {
        if (!is_array($value) || $depth > 4 || count($responseKeys) >= 24) return;
        foreach ($value as $key => $child) {
            if (is_string($key) &&
                preg_match('/^[A-Za-z][A-Za-z0-9_-]{0,39}$/D', $key)) {
                $responseKeys[$key] = true;
            }
            if (is_array($child)) $collectKeys($child, $depth + 1);
            if (count($responseKeys) >= 24) break;
        }
    };
    $collectKeys($response);
    ganap_respond(502, [
        'error' => 'invalid_ganap_checkout_response',
        'endpointVersion' => GANAP_CHECKOUT_ENDPOINT_VERSION,
        'responseProblem' => $responseProblem,
        'responseKeys' => array_keys($responseKeys),
        'checkoutScheme' => $scheme !== '' ? $scheme : null,
        'checkoutHost' => $host !== ''
            ? $host
            : ($candidateHost ?? (count($checkoutCandidateHosts) === 1 ? $checkoutCandidateHosts[0] : null)),
        'checkoutUrlShape' => $checkoutUrlShape,
        'checkoutUrlMatchCount' => $checkoutUrlMatchCount,
        'checkoutCandidateHosts' => $checkoutCandidateHosts,
    ]);
}

$order = [
    'deviceId' => $deviceId,
    'referenceNumber' => $referenceNumber,
    'redirectUrl' => $redirectUrl,
    'qrType' => $qrType,
    'qrContent' => $qrContent,
    'amount' => GANAP_SESSION_PRICE_PESOS,
    'status' => 'pending',
    'createdAt' => time(),
    'expiresAt' => time() + 1800,
];
ganap_update_orders(function (array &$orders) use ($idempotencyKey, $order): void {
    $orders[$idempotencyKey] = $order;
});

ganap_respond(200, [
    'referenceNumber' => $referenceNumber,
    'qrType' => $qrType,
    'qrContent' => $qrContent,
    'endpointVersion' => GANAP_CHECKOUT_ENDPOINT_VERSION,
]);
