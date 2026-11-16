<?php
header('Cache-Control: no-store');
header('X-Content-Type-Options: nosniff');

require_once __DIR__ . '/pb_upload_auth.php';

function cartoon_respond(int $status, array $body): never
{
    http_response_code($status);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode($body, JSON_UNESCAPED_SLASHES);
    exit;
}

function cartoon_replicate_request(
    string $method,
    string $url,
    string $token,
    ?string $body = null,
    ?string $accept = null,
    int $timeoutSeconds = 90
): array {
    $curl = curl_init($url);
    $headers = ['Authorization: Bearer ' . $token];
    if ($body !== null) {
        $headers[] = 'Content-Type: application/json';
        $headers[] = 'Prefer: wait=60';
    }
    if ($accept !== null) $headers[] = 'Accept: ' . $accept;
    curl_setopt_array($curl, [
        CURLOPT_CUSTOMREQUEST => $method,
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_CONNECTTIMEOUT => 10,
        CURLOPT_TIMEOUT => $timeoutSeconds,
        CURLOPT_SSL_VERIFYPEER => true,
        CURLOPT_SSL_VERIFYHOST => 2,
        CURLOPT_PROTOCOLS => CURLPROTO_HTTPS,
        CURLOPT_HTTPHEADER => $headers,
    ]);
    if ($body !== null) curl_setopt($curl, CURLOPT_POSTFIELDS, $body);
    $response = curl_exec($curl);
    $status = (int)curl_getinfo($curl, CURLINFO_RESPONSE_CODE);
    $contentType = (string)curl_getinfo($curl, CURLINFO_CONTENT_TYPE);
    $error = curl_error($curl);
    curl_close($curl);
    if (!is_string($response)) {
        error_log('AI cartoon Replicate request failed: ' . $error);
        cartoon_respond(502, ['error' => 'replicate_request_failed']);
    }
    return [
        'status' => $status,
        'contentType' => $contentType,
        'body' => $response,
    ];
}

function cartoon_read_prediction(array $response): array
{
    if ($response['status'] < 200 || $response['status'] >= 300) {
        error_log('AI cartoon Replicate API returned HTTP ' . $response['status']);
        cartoon_respond(502, ['error' => 'replicate_prediction_failed']);
    }
    try {
        $prediction = json_decode($response['body'], true, 16, JSON_THROW_ON_ERROR);
    } catch (JsonException) {
        cartoon_respond(502, ['error' => 'replicate_response_invalid']);
    }
    if (!is_array($prediction) || !is_string($prediction['status'] ?? null)) {
        cartoon_respond(502, ['error' => 'replicate_response_invalid']);
    }
    return $prediction;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    header('Allow: POST');
    cartoon_respond(405, ['error' => 'method_not_allowed']);
}

$config = require __DIR__ . '/photobooth_private/photobooth_config.php';
if (($config['replicate_cartoon_enabled'] ?? false) !== true) {
    cartoon_respond(503, ['error' => 'cartoon_generation_temporarily_disabled']);
}
$signingKey = $config['credential_signing_key'] ?? '';
$apiToken = $config['replicate_api_token'] ?? '';
$model = $config['replicate_cartoon_model'] ?? 'black-forest-labs/flux-kontext-pro';
if (!is_string($signingKey) ||
    strlen($signingKey) < 32 ||
    strpos($signingKey, 'REPLACE_WITH_') === 0) {
    cartoon_respond(503, ['error' => 'photo_authorization_not_configured']);
}
if (!is_string($apiToken) || !preg_match('/^r8_[A-Za-z0-9_-]{20,}$/D', $apiToken)) {
    cartoon_respond(503, ['error' => 'replicate_api_token_not_configured']);
}
if (!is_string($model) ||
    !preg_match('/^[a-z0-9-]+\/[a-z0-9._-]+$/D', $model)) {
    cartoon_respond(503, ['error' => 'replicate_model_not_configured']);
}
if (!function_exists('curl_init')) {
    cartoon_respond(503, ['error' => 'server_http_client_unavailable']);
}

$claims = pb_upload_authorization_claims(
    $_SERVER['HTTP_AUTHORIZATION'] ?? '',
    $signingKey
);
$deviceId = $claims['deviceId'] ?? null;
if (!is_string($deviceId) ||
    !preg_match('/^[A-Za-z0-9._:-]{8,128}$/D', $deviceId)) {
    cartoon_respond(401, ['error' => 'unauthorized']);
}

$maxUploadBytes = 6 * 1024 * 1024;
if (!isset($_FILES['photo']) ||
    ($_FILES['photo']['error'] ?? UPLOAD_ERR_NO_FILE) !== UPLOAD_ERR_OK) {
    cartoon_respond(400, ['error' => 'photo_upload_required']);
}
$upload = $_FILES['photo'];
if (!is_int($upload['size'] ?? null) ||
    $upload['size'] < 1 ||
    $upload['size'] > $maxUploadBytes) {
    cartoon_respond(413, ['error' => 'photo_size_not_supported']);
}
$image = @getimagesize($upload['tmp_name']);
if ($image === false ||
    !in_array($image[2], [IMAGETYPE_JPEG, IMAGETYPE_PNG], true)) {
    cartoon_respond(415, ['error' => 'only_jpeg_and_png_are_supported']);
}
if ($image[0] > 4096 || $image[1] > 4096) {
    cartoon_respond(413, ['error' => 'photo_dimensions_not_supported']);
}
$style = $_POST['style'] ?? 'cartoon_3d';
$stylePrompts = [
    'anime' => 'ANIME STYLE LOCK: Render the same person as a clear 2D Japanese anime illustration with hand-drawn contours, simplified features, and clean cel shading. Match the source eye state exactly and independently: every eye that is open in the photo MUST remain visibly open, with a visible iris and pupil and the same gaze direction; only eyes already closed, winking, or squinting stay closed, winking, or squinting. Do not close, blink, or hide source-open eyes. Keep the same expression, head direction, pose, and framing. Do not turn the image into a new character portrait.',
    'pencil_sketch' => 'PENCIL SKETCH STYLE LOCK: Redraw the ENTIRE input photograph, including the person AND every part of the background, as one monochrome graphite pencil sketch. Use visible pencil strokes, varied line weight, cross-hatching, and natural grayscale shading throughout; no photographic areas may remain. Preserve the person’s exact original head size, body size, position, pose, and visible proportions. Preserve the source expression and eye state exactly: open eyes stay open with the iris, pupil, and original gaze; closed or winking eyes stay that way only where they are closed or winking in the source. Keep every object, pattern, and background feature in its original place. No color, blank-paper replacement, CGI, or 3D.',
    'cartoon_3d' => '3D CARTOON STYLE LOCK: Find and convert EVERY human person visible in the photo, not only the main or foreground person. This includes all people in the background and people who are partially visible. Convert each person’s ENTIRE visible body—not just the face or head—into the same polished, softly detailed 3D animated style. Apply the style consistently to each person’s face, hair, neck, torso, arms, hands, legs, feet, clothing, and accessories wherever visible; no person or body part may remain photographic or realistic. Keep the original number of people and each person’s identity, relative size, position, spacing, pose, and interaction; do not omit, merge, duplicate, or replace anyone. Render clothing and accessories as 3D materials while preserving their source design, colors, and coverage. Use natural materials and gentle cinematic lighting. Aim for the general polished, friendly 3D-animation finish of the supplied style references, without copying a specific character. For each masculine-presenting person, use a warm, approachable, gently defined face and natural brows; for each feminine-presenting person, use soft, warm facial shading and a graceful, friendly expression. Keep every face attractive and naturally polished while retaining that person’s recognizable identity, age, and distinctive facial features. Keep the eyes NORMAL and close to each person’s source photo in size, shape, spacing, and iris-to-eye proportion; do not enlarge the eyes or irises, and do not use exaggerated anime-like features. Do not add glasses, freckles, makeup, or other identifying details that are absent from the source. Preserve each person’s source expression and eye state exactly. Every eye visibly open in the source MUST remain open in the output, with the iris and pupil visible and the original gaze preserved. Only an eye already closed, winking, or squinting in the source may appear closed, winking, or squinting. Do not blink, close, or hide source-open eyes. Preserve each person’s original body proportions, clothing, pose, head size, and framing; do not crop, zoom, or create a headshot or new portrait.',
    'chibi' => 'CHIBI STYLE LOCK: Convert ONLY the actual person or people in the uploaded photo into cute, polished 2D anime chibi versions of themselves. Give each source person a clearly oversized rounded head (about one third of the full figure height when the full body is visible), a compact small body, short limbs, soft rounded cheeks, a tiny nose, a small expressive mouth, large glossy anime eyes where the source eyes are open, warm clean outlines, soft colors, gentle cel shading, and light cheek blush. Redraw the person’s entire visible body, face, hair, clothing, and accessories in this consistent chibi style; do not leave any part of the person photographic. Preserve the person’s recognizable identity, hair, skin tone, actual clothing, expression, and source pose. Keep each person in the same position, direction, and crop as in the photo; do not add people, duplicate the subject, invent unseen body parts, or turn the image into a collage or portrait. Redraw the existing background in a matching soft illustrated style, preserving its original contents, colors, and layout. Never replace the background with white or blank space. Do not copy any sample character, clothing, or watermark.',
    'pop_art' => 'POP ART STYLE LOCK: Create an unmistakable 2D pop-art comic print with bold flat contrasting colors, thick graphic outlines, halftone dot texture, and energetic printed shapes. Use a screen-printed/comic illustration appearance; do not use realistic photography, soft 3D rendering, or muted painterly shading.',
    'line_art' => 'LINE ART STYLE LOCK: Create a clean 2D black-ink line-art illustration using confident smooth outlines, simple facial details, and a plain white background. Keep the image predominantly black linework on white with no realistic skin texture, painterly color, halftone pop art, graphite shading, or 3D rendering.',
];
if (!is_string($style) || !array_key_exists($style, $stylePrompts)) {
    cartoon_respond(400, ['error' => 'invalid_photo_style']);
}

$limit = $config['replicate_cartoon_hourly_limit'] ?? 20;
if (!is_int($limit) || $limit < 1 || $limit > 1000) {
    cartoon_respond(503, ['error' => 'replicate_rate_limit_not_configured']);
}
$rateLimitPath = __DIR__ . '/photobooth_private/ai_cartoon_limits.json';
$rateLimitFile = fopen($rateLimitPath, 'c+');
if ($rateLimitFile === false || !flock($rateLimitFile, LOCK_EX)) {
    if (is_resource($rateLimitFile)) fclose($rateLimitFile);
    cartoon_respond(503, ['error' => 'cartoon_service_unavailable']);
}
rewind($rateLimitFile);
$rateLimitContents = stream_get_contents($rateLimitFile);
$rateLimits = $rateLimitContents === '' || $rateLimitContents === false
    ? []
    : json_decode($rateLimitContents, true);
if (!is_array($rateLimits)) {
    flock($rateLimitFile, LOCK_UN);
    fclose($rateLimitFile);
    cartoon_respond(503, ['error' => 'cartoon_rate_limit_storage_invalid']);
}
$now = time();
$cutoff = $now - 3600;
foreach ($rateLimits as $key => $timestamps) {
    if (!is_array($timestamps)) {
        unset($rateLimits[$key]);
        continue;
    }
    $rateLimits[$key] = array_values(array_filter(
        $timestamps,
        static fn($timestamp): bool => is_int($timestamp) && $timestamp > $cutoff
    ));
    if ($rateLimits[$key] === []) unset($rateLimits[$key]);
}
$deviceKey = hash('sha256', $deviceId);
$deviceRequests = $rateLimits[$deviceKey] ?? [];
if (count($deviceRequests) >= $limit) {
    flock($rateLimitFile, LOCK_UN);
    fclose($rateLimitFile);
    header('Retry-After: 3600');
    cartoon_respond(429, ['error' => 'cartoon_hourly_limit_reached']);
}
$deviceRequests[] = $now;
$rateLimits[$deviceKey] = $deviceRequests;
rewind($rateLimitFile);
if (!ftruncate($rateLimitFile, 0) ||
    fwrite($rateLimitFile, json_encode($rateLimits, JSON_THROW_ON_ERROR)) === false ||
    !fflush($rateLimitFile)) {
    flock($rateLimitFile, LOCK_UN);
    fclose($rateLimitFile);
    cartoon_respond(503, ['error' => 'cartoon_rate_limit_storage_unavailable']);
}
flock($rateLimitFile, LOCK_UN);
fclose($rateLimitFile);

$photoBytes = file_get_contents($upload['tmp_name']);
if ($photoBytes === false) {
    cartoon_respond(500, ['error' => 'photo_read_failed']);
}
$mimeType = $image['mime'];
$imageData = 'data:' . $mimeType . ';base64,' . base64_encode($photoBytes);
$isChibi = $style === 'chibi';
$appearancePrompt = $style === 'cartoon_3d'
    ? 'Apply the requested attractive, polished 3D-cartoon appearance without changing the source expression or identity. '
    : 'Do not beautify, symmetrize, or reinterpret the source expression. ';
$clothingPrompt = 'CLOTHING-STATE LOCK — applies to every style and person. Preserve the clothing and coverage actually visible in the source: do not add clothing or accessories to a person shown without them, and do not remove or alter clothing that is present. Do not extend the crop or invent unseen body areas. ';
$glassesPrompt = 'EYEWEAR PRESERVATION — For every person wearing glasses or sunglasses in the source, keep the eyewear clearly visible in the output, in the same position, shape, color, and style. Preserve the frames and lenses, including how they sit over the eyes; stylize them to match the selected art style, but do not remove, omit, replace, or obscure them. Do not add eyewear if none is present in the source. ';
$eyeStatePrompt = 'EYE-STATE LOCK — applies to EVERY style and every person. Inspect each source eye separately. If an eye is open in the photo, it MUST remain visibly open in the output with the iris and pupil visible and the same gaze direction; never close it, blink it, squint it, or hide it. Draw an eye closed, winking, or squinting only when that same eye has that exact state in the source. Preserve left/right asymmetry. Stylize the eye to match the selected medium without changing its open/closed state. ';
$identityPrompt = $isChibi
    ? 'IDENTITY FIDELITY: The result must clearly depict the same individual from the reference. Retain their distinctive face shape, facial-feature spacing and placement, eyebrows, nose, mouth, skin tone, age cues, hairstyle, hairline, and facial hair or other identifying details. Simplify these features for illustration without replacing them with conventional or generic anime features. Preserve the exact expression, gaze, smile shape, and whether the mouth is open or closed. '
    : 'Preserve every subject’s identity and facial structure, including face shape, eye shape and direction, nose, mouth, skin tone, hairstyle, perceived age, and distinctive features. Faithfully retain the exact expression visible in the input, including eyelid position, eyebrow position, gaze, smile shape, and whether the mouth is open or closed. Preserve facial hair and other identifying details if present. ';
$compositionPrompt = match ($style) {
    'chibi' => 'CHIBI POSE AND COMPOSITION: Preserve each source person’s pose and placement—facing direction, head tilt, torso angle, arm and leg positions, hand placement, gesture, and interaction with others or props—while converting the whole visible person into chibi proportions. When the source shows a full body, use the larger head and compact short-limbed body proportions described in the Chibi style. Keep the same camera angle, crop, visible body area, subject positions, spacing, and overlaps. Do not zoom, recenter, expand the canvas, add unseen body parts, or add or duplicate people. ',
    'cartoon_3d' => '3D PERSON-SIZE AND COMPOSITION LOCK: Stylize every person in place without resizing, enlarging, shrinking, stretching, repositioning, or changing their body or head proportions. Match each person’s original apparent height and width, silhouette, occupied area, distance from image edges, and relative size to every other person. Preserve exact positions, spacing, overlaps, pose, crop, camera distance, and framing. Do not zoom, recenter, crop, expand the canvas, or invent unseen body parts. Change only the rendering style to 3D cartoon. ',
    'pencil_sketch' => 'PENCIL SCALE AND COMPOSITION LOCK: Preserve the complete source canvas, camera viewpoint, crop, perspective, and framing exactly. Keep each person the same apparent height and width, head-to-body ratio, position, pose, and distance from the image edges. Keep all background features, objects, and their positions unchanged. Do not zoom, crop, recenter, resize, or redraw the person at a different scale. ',
    default => 'CRITICAL SCALE AND COMPOSITION CONSTRAINT: Keep the camera viewpoint, distance, crop, and framing from the source. Keep every person, pet, and important object at the same apparent size and in the same position in the frame; match their relative height and width, head-to-body proportions, and occupied image area. Preserve the same amount of visible body (for example, do not turn a waist-up portrait into a full-body portrait or a close-up into a distant subject). Keep the same spacing and relative sizes between multiple subjects and objects, and retain background placement. Do not zoom in or out, recenter, resize, or change subject proportions to make the composition more attractive. ',
};
$scenePrompt = match ($style) {
    'chibi' => 'Redraw the existing background in the same soft Chibi illustration style while keeping all original scene contents, colors, and layout; do not leave it photographic, make it white, or add characters. ',
    'pencil_sketch' => 'PENCIL BACKGROUND LOCK: Convert the entire existing background into the same monochrome pencil sketch as the person. Draw all existing scenery, objects, textures, and patterns in graphite at their original positions and scale. Do not leave the background photographic, omit it, or replace it with blank white paper. ',
    default => 'Stylize the actual people, pets, clothing, pose, gestures, props, and scene in place. ',
};
$prompt = 'SOURCE-FIDELITY RULE — The uploaded photo is the only source of truth for the people, pose, expression, and composition. ' . $stylePrompts[$style] . ' ' . $eyeStatePrompt . $glassesPrompt . $clothingPrompt . $appearancePrompt . $identityPrompt . $compositionPrompt . $scenePrompt . 'Do not copy or recreate any style-example character, pose, clothing, props, or watermark. Do not blend styles. Preserve the original framing, aspect ratio, number and arrangement of subjects. Do not add, omit, merge, or duplicate people, animals, or props. Return only the transformed image.';
$predictionBody = json_encode([
    'input' => [
        'input_image' => $imageData,
        'prompt' => $prompt,
        'output_format' => 'jpg',
    ],
], JSON_THROW_ON_ERROR | JSON_UNESCAPED_SLASHES);
set_time_limit(110);
$predictionResponse = cartoon_replicate_request(
    'POST',
    'https://api.replicate.com/v1/models/' . $model . '/predictions',
    $apiToken,
    $predictionBody,
    timeoutSeconds: 65
);
$prediction = cartoon_read_prediction($predictionResponse);
if (in_array($prediction['status'], ['starting', 'processing'], true)) {
    $pollUrl = $prediction['urls']['get'] ?? null;
    if (!is_string($pollUrl) ||
        !preg_match(
            '#^https://api\.replicate\.com/v1/predictions/[A-Za-z0-9_-]+$#D',
            $pollUrl
        )) {
        cartoon_respond(502, ['error' => 'replicate_poll_url_invalid']);
    }
    for ($attempt = 0; $attempt < 5; $attempt++) {
        sleep(2);
        $prediction = cartoon_read_prediction(
            cartoon_replicate_request(
                'GET',
                $pollUrl,
                $apiToken,
                timeoutSeconds: 5
            )
        );
        if (!in_array($prediction['status'], ['starting', 'processing'], true)) {
            break;
        }
    }
}
if (($prediction['status'] ?? null) !== 'succeeded') {
    error_log('AI cartoon prediction ended with status ' .
        (string)($prediction['status'] ?? 'unknown'));
    cartoon_respond(502, ['error' => 'replicate_prediction_' .
        preg_replace('/[^a-z_]/', '', (string)($prediction['status'] ?? 'failed'))]);
}
$output = $prediction['output'] ?? null;
$outputUrl = is_string($output) ? $output : (is_array($output) ? ($output[0] ?? null) : null);
if (!is_string($outputUrl)) {
    cartoon_respond(502, ['error' => 'replicate_output_missing']);
}
$outputUri = parse_url($outputUrl);
$outputHost = is_array($outputUri) ? ($outputUri['host'] ?? '') : '';
if (!is_array($outputUri) ||
    ($outputUri['scheme'] ?? null) !== 'https' ||
    !is_string($outputHost) ||
    !($outputHost === 'replicate.delivery' ||
        str_ends_with($outputHost, '.replicate.delivery'))) {
    cartoon_respond(502, ['error' => 'replicate_output_url_invalid']);
}
$outputCurl = curl_init($outputUrl);
$outputBytes = '';
curl_setopt_array($outputCurl, [
    CURLOPT_RETURNTRANSFER => false,
    CURLOPT_CONNECTTIMEOUT => 10,
    CURLOPT_TIMEOUT => 15,
    CURLOPT_SSL_VERIFYPEER => true,
    CURLOPT_SSL_VERIFYHOST => 2,
    CURLOPT_PROTOCOLS => CURLPROTO_HTTPS,
    CURLOPT_WRITEFUNCTION => static function ($curl, string $chunk) use (&$outputBytes): int {
        if (strlen($outputBytes) + strlen($chunk) > 15 * 1024 * 1024) return 0;
        $outputBytes .= $chunk;
        return strlen($chunk);
    },
]);
$outputDownloaded = curl_exec($outputCurl);
$outputStatus = (int)curl_getinfo($outputCurl, CURLINFO_RESPONSE_CODE);
$outputMime = strtolower(trim(explode(';', (string)curl_getinfo(
    $outputCurl,
    CURLINFO_CONTENT_TYPE
))[0]));
$outputError = curl_error($outputCurl);
curl_close($outputCurl);
if ($outputDownloaded !== true ||
    $outputStatus !== 200 ||
    $outputMime !== 'image/jpeg' ||
    $outputBytes === '') {
    error_log('AI cartoon output download failed: HTTP ' .
        $outputStatus . ' ' . $outputError);
    cartoon_respond(502, ['error' => 'replicate_output_download_failed']);
}
header('Content-Type: image/jpeg');
header('X-SnapLab-AI-Style: ' . $style);
header('Content-Length: ' . strlen($outputBytes));
echo $outputBytes;
