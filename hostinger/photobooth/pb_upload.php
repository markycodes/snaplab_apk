<?php
header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');

require_once __DIR__ . '/pb_upload_auth.php';

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

$config = require __DIR__ . '/photobooth_private/photobooth_config.php';
$signingKey = $config['credential_signing_key'] ?? '';
if (!is_string($signingKey) ||
    strlen($signingKey) < 32 ||
    strpos($signingKey, 'REPLACE_WITH_') === 0) {
    respond(500, ['error' => 'credential_signing_key_not_configured']);
}

if (pb_upload_authorization_claims(
    $_SERVER['HTTP_AUTHORIZATION'] ?? '',
    $signingKey
) === null) {
    respond(401, ['error' => 'unauthorized']);
}

if (!isset($_FILES['photo']) || $_FILES['photo']['error'] !== UPLOAD_ERR_OK) {
    respond(400, ['error' => 'photo_upload_required']);
}

$upload = $_FILES['photo'];
if ($upload['size'] < 1 || $upload['size'] > $config['max_upload_bytes']) {
    respond(413, ['error' => 'photo_size_not_supported']);
}

$image = @getimagesize($upload['tmp_name']);
$imageExtensions = [
    IMAGETYPE_JPEG => 'jpg',
    IMAGETYPE_PNG => 'png',
    IMAGETYPE_GIF => 'gif',
];
$extension = $image !== false ? ($imageExtensions[$image[2]] ?? null) : null;
if ($extension === null) {
    $mime = (new finfo(FILEINFO_MIME_TYPE))->file($upload['tmp_name']);
    $file = @fopen($upload['tmp_name'], 'rb');
    $header = $file === false ? false : fread($file, 12);
    if ($file !== false) {
        fclose($file);
    }
    if ($mime !== 'video/mp4' ||
        !is_string($header) ||
        strlen($header) < 12 ||
        substr($header, 4, 4) !== 'ftyp') {
        respond(415, ['error' => 'only_jpeg_png_gif_and_mp4_are_supported']);
    }
    $extension = 'mp4';
}

$storage = $config['storage_dir'];
if (!is_dir($storage) && !mkdir($storage, 0700, true) && !is_dir($storage)) {
    respond(500, ['error' => 'storage_unavailable']);
}

foreach (glob($storage . '/*_*.*') ?: [] as $oldFile) {
    if (preg_match('/^[a-f0-9]{32}_([0-9]{10})\.(jpg|png|gif|mp4)$/', basename($oldFile), $oldMatch) &&
        (int)$oldMatch[1] <= time()) {
        @unlink($oldFile);
    }
}

$id = bin2hex(random_bytes(16));
$expiresAt = time() + $config['retention_seconds'];
$filename = $id . '_' . $expiresAt . '.' . $extension;
if (!move_uploaded_file($upload['tmp_name'], $storage . '/' . $filename)) {
    respond(500, ['error' => 'could_not_store_photo']);
}

respond(200, [
    'downloadUrl' => rtrim($config['base_url'], '/') . '/pb_download?id=' . $id,
    'expiresAt' => gmdate(DATE_ATOM, $expiresAt),
]);
