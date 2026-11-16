<?php
$config = require __DIR__ . '/photobooth_private/photobooth_config.php';
$signingKey = $config['credential_signing_key'] ?? '';
if (!is_string($signingKey) ||
    strlen($signingKey) < 32 ||
    strpos($signingKey, 'REPLACE_WITH_') === 0) {
    http_response_code(503);
    exit('Photo downloads are not configured.');
}

$id = $_GET['id'] ?? '';
if (!is_string($id) || !preg_match('/^[a-f0-9]{32}$/', $id)) {
    http_response_code(404);
    exit('Photo not found or expired.');
}

$matches = glob($config['storage_dir'] . '/' . $id . '_*.*') ?: [];
if (count($matches) !== 1 ||
    !preg_match('/^[a-f0-9]{32}_([0-9]{10})\.(jpg|png|gif|mp4)$/', basename($matches[0]), $parts) ||
    (int)$parts[1] <= time()) {
    foreach ($matches as $expiredFile) {
        @unlink($expiredFile);
    }
    http_response_code(404);
    exit('Photo not found or expired.');
}

$path = $matches[0];
$mime = match ($parts[2]) {
    'jpg' => 'image/jpeg',
    'png' => 'image/png',
    'gif' => 'image/gif',
    'mp4' => 'video/mp4',
};
header('Content-Type: ' . $mime);
header('Content-Length: ' . filesize($path));
header('Content-Disposition: attachment; filename="photobooth-' . $id . '.' . $parts[2] . '"');
header('Cache-Control: private, no-store, max-age=0');
header('X-Content-Type-Options: nosniff');
readfile($path);
