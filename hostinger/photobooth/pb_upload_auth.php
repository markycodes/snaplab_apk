<?php

function pb_upload_authorization_claims(
    string $authorization,
    string $signingKey
): ?array
{
    if (!preg_match(
        '/^Bearer\s+([A-Za-z0-9_-]+\.[A-Za-z0-9_-]+)$/i',
        $authorization,
        $matches
    )) {
        return null;
    }

    $tokenParts = explode('.', $matches[1], 2);
    $tokenPayload = base64_decode(
        strtr($tokenParts[0], '-_', '+/') .
            str_repeat('=', (4 - strlen($tokenParts[0]) % 4) % 4),
        true
    );
    $tokenSignature = base64_decode(
        strtr($tokenParts[1], '-_', '+/') .
            str_repeat('=', (4 - strlen($tokenParts[1]) % 4) % 4),
        true
    );
    $expectedSignature = hash_hmac('sha256', $tokenParts[0], $signingKey, true);
    $claims = $tokenPayload === false ? null : json_decode($tokenPayload, true);

    if ($tokenSignature === false ||
        !hash_equals($expectedSignature, $tokenSignature) ||
        !is_array($claims) ||
        ($claims['aud'] ?? null) !== 'pb_upload' ||
        !is_int($claims['exp'] ?? null) ||
        $claims['exp'] <= time() ||
        $claims['exp'] > time() + 600) {
        return null;
    }

    return $claims;
}
