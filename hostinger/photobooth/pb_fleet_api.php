<?php
header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');
header('X-Content-Type-Options: nosniff');

require_once __DIR__ . '/ganap_common.php';
require_once __DIR__ . '/fleet_mailer.php';

function fleet_api_respond(int $status, array $body): never
{
    http_response_code($status);
    echo json_encode($body, JSON_UNESCAPED_SLASHES);
    exit;
}

require_once __DIR__ . '/fleet_db.php';

const FLEET_ONLINE_WINDOW_SECONDS = 90;

function fleet_require_turnstile(
    array $config,
    mixed $token,
    string $expectedAction
): void {
    $secret = $config['fleet_turnstile_secret_key'] ?? null;
    if (!is_string($secret) || $secret === '') {
        fleet_api_respond(503, ['error' => 'turnstile_not_configured']);
    }
    if (!is_string($token) || $token === '' || strlen($token) > 2048) {
        fleet_api_respond(400, ['error' => 'turnstile_verification_failed']);
    }
    if (!function_exists('curl_init')) {
        fleet_api_respond(503, ['error' => 'turnstile_verification_unavailable']);
    }

    $curl = curl_init('https://challenges.cloudflare.com/turnstile/v0/siteverify');
    curl_setopt_array($curl, [
        CURLOPT_POST => true,
        CURLOPT_POSTFIELDS => http_build_query([
            'secret' => $secret,
            'response' => $token,
        ]),
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_CONNECTTIMEOUT => 5,
        CURLOPT_TIMEOUT => 10,
        CURLOPT_SSL_VERIFYPEER => true,
        CURLOPT_SSL_VERIFYHOST => 2,
    ]);
    $responseBody = curl_exec($curl);
    $httpStatus = curl_getinfo($curl, CURLINFO_RESPONSE_CODE);
    $curlError = curl_errno($curl);
    curl_close($curl);
    if (!is_string($responseBody) || $curlError !== 0 || $httpStatus !== 200) {
        error_log('Cloudflare Turnstile verification request failed (cURL ' . $curlError .
            ', HTTP ' . $httpStatus . ').');
        fleet_api_respond(503, ['error' => 'turnstile_verification_unavailable']);
    }

    try {
        $verification = json_decode($responseBody, true, 8, JSON_THROW_ON_ERROR);
    } catch (JsonException) {
        error_log('Cloudflare Turnstile returned invalid JSON.');
        fleet_api_respond(503, ['error' => 'turnstile_verification_unavailable']);
    }
    $expectedHostname = parse_url(
        'https://' . (string)($_SERVER['HTTP_HOST'] ?? ''),
        PHP_URL_HOST
    );
    if (!is_array($verification) ||
        ($verification['success'] ?? false) !== true ||
        ($verification['action'] ?? null) !== $expectedAction ||
        !is_string($expectedHostname) ||
        !is_string($verification['hostname'] ?? null) ||
        strtolower($verification['hostname']) !== strtolower($expectedHostname)) {
        $errorCodes = is_array($verification)
            ? ($verification['error-codes'] ?? [])
            : [];
        if (is_array($errorCodes) && $errorCodes !== []) {
            error_log('Cloudflare Turnstile rejected a challenge: ' .
                implode(',', array_filter($errorCodes, 'is_string')));
        }
        fleet_api_respond(400, ['error' => 'turnstile_verification_failed']);
    }
}

$https = strtolower((string)($_SERVER['HTTPS'] ?? ''));
if ($https !== 'on' && $https !== '1') {
    fleet_api_respond(403, ['error' => 'https_required']);
}
header('Strict-Transport-Security: max-age=31536000');
header('Referrer-Policy: no-referrer');
if (session_status() !== PHP_SESSION_ACTIVE) {
    session_set_cookie_params([
        'lifetime' => 0,
        'path' => '/',
        'secure' => true,
        'httponly' => true,
        'samesite' => 'Strict',
    ]);
    session_start();
}

$config = require __DIR__ . '/photobooth_private/photobooth_config.php';
$db = fleet_db_connection($config);
$passwordHash = $config['fleet_admin_password_hash'] ?? '';

$action = is_string($_GET['action'] ?? null) ? $_GET['action'] : '';
if (in_array($action, ['password_reset_request', 'password_reset_complete'], true)) {
    if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
        header('Allow: POST');
        fleet_api_respond(405, ['error' => 'method_not_allowed']);
    }
    $attempts = fleet_db_login_attempts($db, scope: 'password_reset');
    if (($attempts['count'] ?? 0) >= 5) {
        header('Retry-After: 900');
        fleet_api_respond(429, ['error' => 'too_many_reset_attempts']);
    }
    $raw = file_get_contents('php://input');
    try {
        $request = $raw === false || strlen($raw) > 8192
            ? null
            : json_decode($raw, true, 8, JSON_THROW_ON_ERROR);
    } catch (JsonException) {
        $request = null;
    }
    if (!is_array($request)) {
        fleet_api_respond(400, ['error' => 'invalid_request']);
    }

    if ($action === 'password_reset_request') {
        fleet_require_turnstile(
            $config,
            $request['turnstileToken'] ?? null,
            'fleet_password_reset'
        );
        $email = is_string($request['email'] ?? null)
            ? strtolower(trim($request['email']))
            : '';
        if (!filter_var($email, FILTER_VALIDATE_EMAIL) || strlen($email) > 254) {
            fleet_api_respond(400, ['error' => 'invalid_reset_request']);
        }
        fleet_db_login_attempts($db, recordFailure: true, scope: 'password_reset');
        $account = fleet_db_execute(
            $db,
            'SELECT account_id FROM fleet_accounts WHERE email = ?',
            [$email]
        )->fetch();
        $genericResponse = [
            'ok' => true,
            'message' => 'If an owner account exists for that email, password reset instructions will be sent.',
        ];
        if (!is_array($account)) {
            fleet_api_respond(200, $genericResponse);
        }

        require_once __DIR__ . '/fleet_mailer.php';
        $accountId = (string)$account['account_id'];
        $token = bin2hex(random_bytes(32));
        $tokenHash = hash('sha256', $token);
        $now = time();
        fleet_db_execute(
            $db,
            'DELETE FROM fleet_password_resets WHERE account_id = ?',
            [$accountId]
        );
        fleet_db_execute(
            $db,
            'INSERT INTO fleet_password_resets
             (token_hash, account_id, created_at, expires_at)
             VALUES (?, ?, ?, ?)',
            [$tokenHash, $accountId, $now, $now + 3600]
        );
        $baseUrl = $config['base_url'] ?? null;
        if (!is_string($baseUrl) ||
            filter_var($baseUrl, FILTER_VALIDATE_URL) === false ||
            strtolower((string)parse_url($baseUrl, PHP_URL_SCHEME)) !== 'https') {
            error_log('Fleet password reset email unavailable: HTTPS base URL is not configured.');
            fleet_db_execute(
                $db,
                'UPDATE fleet_password_resets SET used_at = ? WHERE token_hash = ?',
                [$now, $tokenHash]
            );
            fleet_api_respond(503, ['error' => 'reset_email_unavailable']);
        }
        $resetUrl = rtrim($baseUrl, '/') . '/login?reset=' . rawurlencode($token);
        $safeResetUrl = htmlspecialchars($resetUrl, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
        $plainBody = "A password reset was requested for your SnapLab Fleet account.\n\n" .
            "Open this link within one hour to choose a new password:\n" .
            $resetUrl . "\n\nIf you did not request this, you can ignore this email.";
        $htmlBody = '<p>A password reset was requested for your SnapLab Fleet account.</p>' .
            '<p><a href="' . $safeResetUrl . '">Set a new password</a></p>' .
            '<p>This link expires in one hour. If you did not request this, ignore this email.</p>';
        try {
            fleet_send_email(
                $config,
                $email,
                'Reset your SnapLab Fleet password',
                $plainBody,
                $htmlBody
            );
        } catch (RuntimeException) {
            fleet_db_execute(
                $db,
                'UPDATE fleet_password_resets SET used_at = ? WHERE token_hash = ?',
                [$now, $tokenHash]
            );
            fleet_api_respond(503, ['error' => 'reset_email_unavailable']);
        }
        fleet_api_respond(200, $genericResponse);
    }

    $token = $request['token'] ?? null;
    $password = $request['password'] ?? null;
    if (!is_string($token) || !preg_match('/^[a-f0-9]{64}$/D', $token) ||
        !is_string($password) || strlen($password) < 12 || strlen($password) > 72) {
        fleet_api_respond(400, ['error' => 'invalid_or_expired_reset']);
    }
    fleet_db_login_attempts($db, recordFailure: true, scope: 'password_reset');
    $tokenHash = hash('sha256', $token);
    $now = time();
    try {
        $db->beginTransaction();
        $reset = fleet_db_execute(
            $db,
            'SELECT account_id, expires_at, used_at FROM fleet_password_resets
             WHERE token_hash = ? FOR UPDATE',
            [$tokenHash]
        )->fetch();
        if (!is_array($reset) ||
            $reset['used_at'] !== null ||
            (int)$reset['expires_at'] < $now) {
            $db->rollBack();
            fleet_api_respond(400, ['error' => 'invalid_or_expired_reset']);
        }
        fleet_db_execute(
            $db,
            'UPDATE fleet_accounts SET password_hash = ? WHERE account_id = ?',
            [password_hash($password, PASSWORD_DEFAULT), $reset['account_id']]
        );
        fleet_db_execute(
            $db,
            'UPDATE fleet_password_resets SET used_at = ?
             WHERE account_id = ? AND used_at IS NULL',
            [$now, $reset['account_id']]
        );
        $db->commit();
    } catch (Throwable $error) {
        if ($db->inTransaction()) {
            $db->rollBack();
        }
        if ($error instanceof PDOException) {
            error_log('Fleet password reset failed (' . (string)$error->getCode() . ').');
            fleet_api_respond(503, ['error' => 'fleet_database_unavailable']);
        }
        throw $error;
    }
    fleet_api_respond(200, ['ok' => true]);
}

if ($action === 'signup') {
    if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
        header('Allow: POST');
        fleet_api_respond(405, ['error' => 'method_not_allowed']);
    }
    $attempts = fleet_db_login_attempts($db, recordFailure: true, scope: 'signup');
    if (($attempts['count'] ?? 0) > 5) {
        header('Retry-After: 900');
        fleet_api_respond(429, ['error' => 'too_many_login_attempts']);
    }
    $raw = file_get_contents('php://input');
    try {
        $request = $raw === false || strlen($raw) > 8192
            ? null
            : json_decode($raw, true, 8, JSON_THROW_ON_ERROR);
    } catch (JsonException) {
        $request = null;
    }
    $email = is_array($request) && is_string($request['email'] ?? null)
        ? strtolower(trim($request['email']))
        : '';
    $password = is_array($request) ? ($request['password'] ?? null) : null;
    if (!filter_var($email, FILTER_VALIDATE_EMAIL) ||
        strlen($email) > 254 ||
        !is_string($password) ||
        strlen($password) < 12 ||
        strlen($password) > 72) {
        fleet_api_respond(400, ['error' => 'invalid_signup']);
    }
    fleet_require_turnstile(
        $config,
        is_array($request) ? ($request['turnstileToken'] ?? null) : null,
        'fleet_signup'
    );

    $accountId = bin2hex(random_bytes(16));
    $accountCount = (int)fleet_db_execute($db, 'SELECT COUNT(*) FROM fleet_accounts')->fetchColumn();
    if ($accountCount >= 10000) {
        fleet_api_respond(503, ['error' => 'account_limit_reached']);
    }
    try {
        $db->beginTransaction();
        $ownerInsert = $db->prepare(
            'INSERT INTO fleet_owners (owner_id, owner_type) VALUES (?, ?)'
        );
        $ownerInsert->execute([$accountId, 'account']);
        $accountInsert = $db->prepare(
            'INSERT INTO fleet_accounts (account_id, email, password_hash, created_at)
             VALUES (?, ?, ?, ?)'
        );
        $accountInsert->execute([
            $accountId,
            $email,
            password_hash($password, PASSWORD_DEFAULT),
            time(),
        ]);
        $db->commit();
    } catch (PDOException $error) {
        if ($db->inTransaction()) {
            $db->rollBack();
        }
        if ($error->getCode() === '23000') {
            fleet_api_respond(409, ['error' => 'account_already_exists']);
        }
        error_log('Fleet account creation failed (' . (string)$error->getCode() . ')');
        fleet_api_respond(503, ['error' => 'fleet_database_unavailable']);
    }
    $welcomeEmailSent = true;
    try {
        fleet_send_welcome_email($config, $email);
    } catch (RuntimeException | Error $error) {
        $welcomeEmailSent = false;
        error_log('Fleet welcome email could not be delivered: ' . $error->getMessage());
        $welcomeEmailError = $error instanceof Error
            ? 'email_dependency_unavailable'
            : match ($error->getCode()) {
                FLEET_EMAIL_CONFIGURATION_ERROR => 'email_smtp_not_configured',
                FLEET_EMAIL_DEPENDENCY_ERROR => 'email_dependency_unavailable',
                default => 'email_delivery_failed',
            };
    }
    fleet_db_login_attempts($db, clear: true, scope: 'signup');
    session_regenerate_id(true);
    $_SESSION['fleet_authenticated'] = true;
    $_SESSION['fleet_role'] = 'user';
    $_SESSION['fleet_account_id'] = $accountId;
    $_SESSION['fleet_csrf'] = bin2hex(random_bytes(32));
    $_SESSION['fleet_last_activity'] = time();
    fleet_api_respond(201, [
        'ok' => true,
        'role' => 'user',
        'csrfToken' => $_SESSION['fleet_csrf'],
        'welcomeEmailSent' => $welcomeEmailSent,
        'welcomeEmailError' => $welcomeEmailSent ? null : $welcomeEmailError,
    ]);
}

if ($action === 'login') {
    if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
        header('Allow: POST');
        fleet_api_respond(405, ['error' => 'method_not_allowed']);
    }
    $raw = file_get_contents('php://input');
    if ($raw === false || strlen($raw) > 8192) {
        fleet_api_respond(400, ['error' => 'invalid_request']);
    }
    $attempts = fleet_db_login_attempts($db);
    if (($attempts['count'] ?? 0) >= 5) {
        header('Retry-After: 900');
        fleet_api_respond(429, ['error' => 'too_many_login_attempts']);
    }
    try {
        $request = json_decode($raw, true, 8, JSON_THROW_ON_ERROR);
    } catch (JsonException) {
        fleet_api_respond(400, ['error' => 'invalid_request']);
    }
    $password = is_array($request) ? ($request['password'] ?? null) : null;
    $email = is_array($request) && is_string($request['email'] ?? null)
        ? strtolower(trim($request['email']))
        : '';
    fleet_require_turnstile(
        $config,
        is_array($request) ? ($request['turnstileToken'] ?? null) : null,
        'fleet_login'
    );
    $role = '';
    $accountId = null;
    if (is_string($password) && strlen($password) <= 1024 && $email !== '') {
        $account = $email === '' ? null : fleet_db_account($db, $email);
        if (is_array($account) &&
            is_string($account['accountId'] ?? null) &&
            is_string($account['passwordHash'] ?? null) &&
            password_verify($password, $account['passwordHash'])) {
            $role = 'user';
            $accountId = $account['accountId'];
        }
    } elseif (is_string($password) && strlen($password) <= 1024 &&
        is_string($passwordHash) && $passwordHash !== '' &&
        password_verify($password, $passwordHash)) {
        $role = 'admin';
    }
    if ($role === '') {
        fleet_db_login_attempts($db, recordFailure: true);
        usleep(350000);
        fleet_api_respond(401, ['error' => 'invalid_credentials']);
    }
    fleet_db_login_attempts($db, clear: true);
    session_regenerate_id(true);
    $_SESSION['fleet_authenticated'] = true;
    $_SESSION['fleet_role'] = $role;
    if ($accountId !== null) {
        $_SESSION['fleet_account_id'] = $accountId;
    }
    $_SESSION['fleet_csrf'] = bin2hex(random_bytes(32));
    $_SESSION['fleet_last_activity'] = time();
    fleet_api_respond(200, [
        'ok' => true,
        'role' => $role,
        'csrfToken' => $_SESSION['fleet_csrf'],
    ]);
}

if (($_SESSION['fleet_authenticated'] ?? false) !== true ||
    !is_int($_SESSION['fleet_last_activity'] ?? null) ||
    $_SESSION['fleet_last_activity'] < time() - 1800) {
    $_SESSION = [];
    session_destroy();
    fleet_api_respond(401, ['error' => 'authentication_required']);
}
$role = $_SESSION['fleet_role'] ?? 'admin';
if (!in_array($role, ['admin', 'user'], true) ||
    ($role === 'user' && !is_string($_SESSION['fleet_account_id'] ?? null))) {
    $_SESSION = [];
    session_destroy();
    fleet_api_respond(401, ['error' => 'authentication_required']);
}
$ownerId = $role === 'admin' ? 'admin' : $_SESSION['fleet_account_id'];
$_SESSION['fleet_last_activity'] = time();

if (str_starts_with($action, 'paymongo_')) {
    if ($role !== 'user') {
        fleet_api_respond(403, ['error' => 'owner_account_required']);
    }
    if (!in_array($action, [
        'paymongo_account_status',
        'paymongo_create_account',
        'paymongo_identity_verification',
        'paymongo_update_account',
        'paymongo_activate_account',
    ], true)) {
        fleet_api_respond(404, ['error' => 'not_found']);
    }
    if ($action === 'paymongo_account_status') {
        if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
            header('Allow: GET');
            fleet_api_respond(405, ['error' => 'method_not_allowed']);
        }
        $account = fleet_db_execute(
            $db,
            'SELECT paymongo_account_status, paymongo_identity_status,
                    paymongo_profile_submitted
             FROM fleet_accounts WHERE account_id = ?',
            [$ownerId]
        )->fetch();
        if (!is_array($account)) {
            fleet_api_respond(404, ['error' => 'fleet_account_not_found']);
        }
        fleet_api_respond(200, [
            'accountStatus' => $account['paymongo_account_status'],
            'identityStatus' => $account['paymongo_identity_status'],
            'profileSubmitted' => (bool)$account['paymongo_profile_submitted'],
        ]);
    }
    if ($_SERVER['REQUEST_METHOD'] !== 'POST' ||
        !hash_equals(
            (string)($_SESSION['fleet_csrf'] ?? ''),
            (string)($_SERVER['HTTP_X_CSRF_TOKEN'] ?? '')
        )) {
        fleet_api_respond(403, ['error' => 'csrf_validation_failed']);
    }
    require_once __DIR__ . '/paymongo_common.php';
    paymongo_require_enabled($config);
    if (paymongo_missing_configuration($config) !== []) {
        paymongo_configuration_error($config);
    }
    $account = fleet_db_execute(
        $db,
        'SELECT paymongo_account_id, paymongo_account_status,
                paymongo_identity_verification_id, paymongo_identity_status,
                paymongo_profile_submitted
         FROM fleet_accounts WHERE account_id = ?',
        [$ownerId]
    )->fetch();
    if (!is_array($account)) {
        fleet_api_respond(404, ['error' => 'fleet_account_not_found']);
    }
    if ($action === 'paymongo_create_account') {
        if (is_string($account['paymongo_account_id'] ?? null)) {
            fleet_api_respond(200, [
                'accountStatus' => $account['paymongo_account_status'],
                'identityStatus' => $account['paymongo_identity_status'],
            ]);
        }
        if (($account['paymongo_account_status'] ?? null) === 'creating') {
            $updatedAt = (int)fleet_db_execute(
                $db,
                'SELECT paymongo_updated_at FROM fleet_accounts WHERE account_id = ?',
                [$ownerId]
            )->fetchColumn();
            if ($updatedAt > time() - 600) {
                fleet_api_respond(409, ['error' => 'paymongo_account_creation_in_progress']);
            }
        }
        $reserved = fleet_db_execute(
            $db,
            'UPDATE fleet_accounts
             SET paymongo_account_status = ?, paymongo_updated_at = ?
             WHERE account_id = ? AND paymongo_account_id IS NULL',
            ['creating', time(), $ownerId]
        )->rowCount();
        if ($reserved !== 1) {
            fleet_api_respond(409, ['error' => 'paymongo_account_creation_in_progress']);
        }
        $created = paymongo_request(
            'POST',
            '/v2/accounts',
            ['type' => 'merchant'],
            $config['paymongo_secret_key']
        );
        $childId = $created['data']['id'] ?? null;
        if (!is_string($childId) || !preg_match('/^org_[A-Za-z0-9]+$/D', $childId)) {
            fleet_api_respond(502, ['error' => 'invalid_paymongo_account_response']);
        }
        fleet_db_execute(
            $db,
            'UPDATE fleet_accounts
             SET paymongo_account_id = ?, paymongo_account_status = ?,
                 paymongo_identity_status = ?, paymongo_updated_at = ?
             WHERE account_id = ? AND paymongo_account_id IS NULL',
            [$childId, 'pending', 'not_started', time(), $ownerId]
        );
        fleet_api_respond(201, [
            'accountStatus' => 'pending',
            'identityStatus' => 'not_started',
        ]);
    }

    $childId = $account['paymongo_account_id'] ?? null;
    if (!is_string($childId) || !preg_match('/^org_[A-Za-z0-9]+$/D', $childId)) {
        fleet_api_respond(409, ['error' => 'paymongo_account_not_created']);
    }
    if ($action === 'paymongo_identity_verification') {
        if (($_SERVER['CONTENT_LENGTH'] ?? '') !== '' &&
            ctype_digit((string)$_SERVER['CONTENT_LENGTH']) &&
            (int)$_SERVER['CONTENT_LENGTH'] > 22 * 1024 * 1024) {
            fleet_api_respond(413, ['error' => 'identity_upload_too_large']);
        }
        $documentType = $_POST['document_type'] ?? null;
        if (!is_string($documentType) ||
            !preg_match('/^[a-z0-9_]{3,80}$/D', $documentType)) {
            fleet_api_respond(400, ['error' => 'invalid_document_type']);
        }
        if (in_array($account['paymongo_identity_status'], ['pending', 'in_progress'], true)) {
            fleet_api_respond(409, ['error' => 'identity_verification_in_progress']);
        }
        $fileFields = [];
        foreach (['document_front', 'selfie', 'document_back'] as $field) {
            $upload = $_FILES[$field] ?? null;
            if ($field === 'document_back' &&
                (!is_array($upload) || ($upload['error'] ?? UPLOAD_ERR_NO_FILE) === UPLOAD_ERR_NO_FILE)) {
                continue;
            }
            if (!is_array($upload) ||
                ($upload['error'] ?? null) !== UPLOAD_ERR_OK ||
                !is_string($upload['tmp_name'] ?? null) ||
                !is_uploaded_file($upload['tmp_name']) ||
                !is_int($upload['size'] ?? null) ||
                $upload['size'] < 1 ||
                $upload['size'] > 10 * 1024 * 1024) {
                fleet_api_respond(400, ['error' => 'invalid_identity_upload']);
            }
            $mime = (new finfo(FILEINFO_MIME_TYPE))->file($upload['tmp_name']);
            if (!in_array($mime, ['image/jpeg', 'image/png'], true)) {
                fleet_api_respond(400, ['error' => 'unsupported_identity_image']);
            }
            $fileFields[$field] = curl_file_create(
                $upload['tmp_name'],
                $mime,
                $field . ($mime === 'image/png' ? '.png' : '.jpg')
            );
        }
        if (!isset($fileFields['document_front'], $fileFields['selfie'])) {
            fleet_api_respond(400, ['error' => 'identity_documents_required']);
        }
        $fileFields['document_type'] = $documentType;
        $verification = paymongo_request_multipart(
            '/v2/accounts/' . rawurlencode($childId) . '/identity_verification_api',
            $fileFields,
            $config['paymongo_secret_key'],
            $childId
        );
        $verificationId = $verification['data']['id'] ?? null;
        if (!is_string($verificationId) ||
            !preg_match('/^verif_[A-Za-z0-9]+$/D', $verificationId)) {
            fleet_api_respond(502, ['error' => 'invalid_paymongo_verification_response']);
        }
        fleet_db_execute(
            $db,
            'UPDATE fleet_accounts
             SET paymongo_identity_verification_id = ?, paymongo_identity_status = ?,
                 paymongo_updated_at = ?
             WHERE account_id = ?',
            [$verificationId, 'pending', time(), $ownerId]
        );
        fleet_api_respond(201, [
            'accountStatus' => $account['paymongo_account_status'],
            'identityStatus' => 'pending',
        ]);
    }

    $raw = file_get_contents('php://input');
    if ($raw === false || strlen($raw) > 16384) {
        fleet_api_respond(400, ['error' => 'invalid_request']);
    }
    try {
        $request = json_decode($raw, true, 16, JSON_THROW_ON_ERROR);
    } catch (JsonException) {
        fleet_api_respond(400, ['error' => 'invalid_request']);
    }
    if (!is_array($request)) {
        fleet_api_respond(400, ['error' => 'invalid_request']);
    }
    if ($action === 'paymongo_update_account') {
        if (($account['paymongo_identity_status'] ?? null) !== 'passed') {
            fleet_api_respond(409, ['error' => 'identity_verification_not_passed']);
        }
        $personInput = $request['person'] ?? null;
        $businessInput = $request['business'] ?? null;
        $personEnums = [
            'nature_of_work' => [
                'employed_locally', 'retired', 'pensioner', 'ofw', 'ofw_beneficiary',
                'student', 'self_employed', 'unemployed_spouse_income', 'unemployed_other_income',
            ],
            'source_of_funds' => ['allowance', 'commission', 'donation', 'other', 'pension', 'salary'],
        ];
        if (!is_array($personInput) ||
            !is_array($businessInput) ||
            !is_string($personInput['first_name'] ?? null) ||
            trim($personInput['first_name']) === '' ||
            strlen($personInput['first_name']) > 80 ||
            !is_string($personInput['last_name'] ?? null) ||
            trim($personInput['last_name']) === '' ||
            strlen($personInput['last_name']) > 80 ||
            !is_string($personInput['mobile_number'] ?? null) ||
            !preg_match('/^\+[1-9][0-9]{4,14}$/D', $personInput['mobile_number']) ||
            !is_string($personInput['email_address'] ?? null) ||
            !filter_var($personInput['email_address'], FILTER_VALIDATE_EMAIL) ||
            strlen($personInput['email_address']) > 254 ||
            !is_array($personInput['date_of_birth'] ?? null) ||
            !is_int($personInput['date_of_birth']['day'] ?? null) ||
            !is_int($personInput['date_of_birth']['month'] ?? null) ||
            !is_int($personInput['date_of_birth']['year'] ?? null) ||
            !checkdate(
                $personInput['date_of_birth']['month'],
                $personInput['date_of_birth']['day'],
                $personInput['date_of_birth']['year']
            ) ||
            $personInput['date_of_birth']['year'] > (int)date('Y') - 18 ||
            !is_string($personInput['nationality'] ?? null) ||
            !preg_match('/^[A-Z]{3}$/D', $personInput['nationality']) ||
            !is_string($personInput['nature_of_work'] ?? null) ||
            !in_array($personInput['nature_of_work'], $personEnums['nature_of_work'], true) ||
            !is_string($personInput['source_of_funds'] ?? null) ||
            !in_array($personInput['source_of_funds'], $personEnums['source_of_funds'], true)) {
            fleet_api_respond(400, ['error' => 'invalid_person_details']);
        }
        $addressInput = $personInput['address'] ?? null;
        $businessAddressInput = $businessInput['address'] ?? null;
        $cleanAddress = static function (mixed $value): ?array {
            if (!is_array($value)) return null;
            foreach (['line1' => 120, 'city' => 80, 'state' => 32, 'country' => 2, 'postal_code' => 16] as $key => $max) {
                if (!is_string($value[$key] ?? null) ||
                    trim($value[$key]) === '' ||
                    strlen($value[$key]) > $max) return null;
            }
            if (strtoupper($value['country']) !== 'PH') return null;
            $address = [
                'line1' => trim($value['line1']),
                'city' => trim($value['city']),
                'state' => trim($value['state']),
                'country' => 'PH',
                'postal_code' => trim($value['postal_code']),
            ];
            if (is_string($value['line2'] ?? null) && trim($value['line2']) !== '') {
                if (strlen($value['line2']) > 120) return null;
                $address['line2'] = trim($value['line2']);
            }
            return $address;
        };
        $address = $cleanAddress($addressInput);
        $businessAddress = $cleanAddress($businessAddressInput);
        if ($address === null || $businessAddress === null) {
            fleet_api_respond(400, ['error' => 'invalid_address']);
        }
        $businessEnums = [
            'age' => ['between_1_and_2_years', 'between_2_and_5_years', 'greater_than_5_years', 'less_than_1_year'],
            'size' => ['between_10_and_50', 'between_51_and_250', 'greater_than_250', 'less_than_10'],
            'estimated_monthly_volume' => [
                'less_than_100K', 'between_100K_and_300K', 'between_300K_and_500K',
                'between_500K_and_1M', 'between_1M_and_3M', 'greater_than_3M',
            ],
        ];
        foreach ($businessEnums as $key => $values) {
            if (!is_string($businessInput[$key] ?? null) ||
                !in_array($businessInput[$key], $values, true)) {
                fleet_api_respond(400, ['error' => 'invalid_business_details']);
            }
        }
        foreach (['description' => 255, 'industry' => 4, 'trade_name' => 120] as $key => $max) {
            if (!is_string($businessInput[$key] ?? null) ||
                trim($businessInput[$key]) === '' ||
                strlen($businessInput[$key]) > $max) {
                fleet_api_respond(400, ['error' => 'invalid_business_details']);
            }
        }
        if (!preg_match('/^[0-9]{4}$/D', $businessInput['industry']) ||
            !is_bool($businessInput['physical_store'] ?? null)) {
            fleet_api_respond(400, ['error' => 'invalid_business_details']);
        }
        $person = [
            'first_name' => trim($personInput['first_name']),
            'last_name' => trim($personInput['last_name']),
            'mobile_number' => $personInput['mobile_number'],
            'email_address' => strtolower($personInput['email_address']),
            'date_of_birth' => [
                'day' => $personInput['date_of_birth']['day'],
                'month' => $personInput['date_of_birth']['month'],
                'year' => $personInput['date_of_birth']['year'],
            ],
            'nationality' => $personInput['nationality'],
            'nature_of_work' => $personInput['nature_of_work'],
            'place_of_birth' => ['city' => trim((string)($personInput['birth_city'] ?? '')), 'country' => 'PH'],
            'source_of_funds' => $personInput['source_of_funds'],
            'address' => $address,
            'permanent_address' => $address,
        ];
        foreach (['middle_name' => 80, 'tin' => 32, 'source_of_funds_other' => 120, 'source_of_funds_salary' => 120] as $key => $max) {
            if (is_string($personInput[$key] ?? null) && trim($personInput[$key]) !== '') {
                if (strlen($personInput[$key]) > $max) {
                    fleet_api_respond(400, ['error' => 'invalid_person_details']);
                }
                $person[$key] = trim($personInput[$key]);
            }
        }
        if (strlen($person['place_of_birth']['city']) > 80 ||
            $person['place_of_birth']['city'] === '' ||
            ($person['source_of_funds'] === 'other' &&
                !is_string($person['source_of_funds_other'] ?? null)) ||
            ($person['source_of_funds'] === 'salary' &&
                !is_string($person['source_of_funds_salary'] ?? null))) {
            fleet_api_respond(400, ['error' => 'invalid_person_details']);
        }
        $business = [
            'address' => $businessAddress,
            'age' => $businessInput['age'],
            'description' => trim($businessInput['description']),
            'estimated_monthly_volume' => $businessInput['estimated_monthly_volume'],
            'industry' => $businessInput['industry'],
            'physical_store' => $businessInput['physical_store'],
            'size' => $businessInput['size'],
            'trade_name' => trim($businessInput['trade_name']),
        ];
        if (is_string($businessInput['tin'] ?? null) && trim($businessInput['tin']) !== '') {
            if (strlen($businessInput['tin']) > 32) {
                fleet_api_respond(400, ['error' => 'invalid_business_details']);
            }
            $business['tin'] = trim($businessInput['tin']);
        }
        paymongo_request(
            'PATCH',
            '/v2/accounts/' . rawurlencode($childId),
            ['person' => $person, 'business' => $business],
            $config['paymongo_secret_key'],
            $childId
        );
        fleet_db_execute(
            $db,
            'UPDATE fleet_accounts
             SET paymongo_profile_submitted = 1, paymongo_updated_at = ?
             WHERE account_id = ?',
            [time(), $ownerId]
        );
        fleet_api_respond(200, ['ok' => true]);
    }
    if ($action === 'paymongo_activate_account') {
        if (($account['paymongo_identity_status'] ?? null) !== 'passed' ||
            !(bool)($account['paymongo_profile_submitted'] ?? false)) {
            fleet_api_respond(409, ['error' => 'paymongo_onboarding_incomplete']);
        }
        $activated = paymongo_request(
            'POST',
            '/v2/accounts/' . rawurlencode($childId) . '/activate',
            null,
            $config['paymongo_secret_key'],
            $childId
        );
        $activationStatus = $activated['data']['activation_status'] ?? null;
        if (!is_string($activationStatus) ||
            !in_array($activationStatus, ['activated', 'pending'], true)) {
            fleet_api_respond(502, ['error' => 'invalid_paymongo_account_response']);
        }
        fleet_db_execute(
            $db,
            'UPDATE fleet_accounts
             SET paymongo_account_status = ?, paymongo_updated_at = ?
             WHERE account_id = ?',
            [$activationStatus, time(), $ownerId]
        );
        fleet_api_respond(200, [
            'accountStatus' => $activationStatus,
            'identityStatus' => 'passed',
        ]);
    }
}

if ($action === 'logout') {
    if ($_SERVER['REQUEST_METHOD'] !== 'POST' ||
        !hash_equals(
            (string)($_SESSION['fleet_csrf'] ?? ''),
            (string)($_SERVER['HTTP_X_CSRF_TOKEN'] ?? '')
        )) {
        fleet_api_respond(403, ['error' => 'csrf_validation_failed']);
    }
    $_SESSION = [];
    session_destroy();
    fleet_api_respond(200, ['ok' => true]);
}

if ($action === 'register' || $action === 'unregister') {
    if ($_SERVER['REQUEST_METHOD'] !== 'POST' ||
        !hash_equals(
            (string)($_SESSION['fleet_csrf'] ?? ''),
            (string)($_SERVER['HTTP_X_CSRF_TOKEN'] ?? '')
        )) {
        fleet_api_respond(403, ['error' => 'csrf_validation_failed']);
    }
    $raw = file_get_contents('php://input');
    if ($raw === false || strlen($raw) > 2048) {
        fleet_api_respond(400, ['error' => 'invalid_request']);
    }
    try {
        $request = json_decode($raw, true, 8, JSON_THROW_ON_ERROR);
    } catch (JsonException) {
        fleet_api_respond(400, ['error' => 'invalid_request']);
    }
    $deviceId = is_array($request) ? ($request['deviceId'] ?? null) : null;
    if (!is_string($deviceId) ||
        !preg_match('/^[A-Za-z0-9._:-]{8,128}$/D', $deviceId)) {
        fleet_api_respond(400, ['error' => 'invalid_device_id']);
    }

    if ($action === 'register' && $role === 'user') {
        if (!function_exists('sodium_crypto_sign_verify_detached')) {
            fleet_api_respond(503, ['error' => 'server_ed25519_support_unavailable']);
        }
        $activation = ganap_activation_claims($request, $config);
        if ($activation === null || $activation['deviceId'] !== $deviceId) {
            fleet_api_respond(401, ['error' => 'activation_required']);
        }
    }

    try {
        $db->beginTransaction();
        if ($action === 'unregister') {
            $existing = fleet_db_execute(
                $db,
                'SELECT owner_id, registered_at, active FROM fleet_registered_devices
                 WHERE device_id = ? FOR UPDATE',
                [$deviceId]
            )->fetch();
            if (!is_array($existing)) {
                $db->rollBack();
                fleet_api_respond(404, ['error' => 'device_not_registered']);
            }
            if ($role !== 'admin' && $existing['owner_id'] !== $ownerId) {
                $db->rollBack();
                fleet_api_respond(409, ['error' => 'device_already_registered']);
            }
            fleet_db_execute(
                $db,
                'UPDATE fleet_registered_devices SET active = 0 WHERE device_id = ?',
                [$deviceId]
            );
        } else {
            fleet_db_execute(
                $db,
                'INSERT IGNORE INTO fleet_registered_devices
                 (device_id, owner_id, registered_at, active) VALUES (?, ?, ?, 1)',
                [$deviceId, $ownerId, time()]
            );
            $existing = fleet_db_execute(
                $db,
                'SELECT owner_id, registered_at, active FROM fleet_registered_devices
                 WHERE device_id = ? FOR UPDATE',
                [$deviceId]
            )->fetch();
            if (!is_array($existing)) {
                $db->rollBack();
                fleet_api_respond(500, ['error' => 'fleet_database_invalid']);
            }
            if (is_array($existing) &&
                $role !== 'admin' &&
                $existing['owner_id'] !== $ownerId) {
                $db->rollBack();
                fleet_api_respond(409, ['error' => 'device_already_registered']);
            }
            $deviceCount = (int)fleet_db_execute(
                $db,
                'SELECT COUNT(*) FROM fleet_registered_devices'
            )->fetchColumn();
            if ($deviceCount > 1000) {
                $db->rollBack();
                fleet_api_respond(503, ['error' => 'fleet_device_limit_reached']);
            }
            fleet_db_execute(
                $db,
                'UPDATE fleet_registered_devices SET owner_id = ?, active = 1
                 WHERE device_id = ?',
                [$ownerId, $deviceId]
            );
        }
        $db->commit();
    } catch (PDOException $error) {
        if ($db->inTransaction()) {
            $db->rollBack();
        }
        error_log('Fleet registration update failed (' . (string)$error->getCode() . ')');
        fleet_api_respond(503, ['error' => 'fleet_database_unavailable']);
    }
    fleet_api_respond(200, ['ok' => true]);
}

if (in_array($action, ['remote_command', 'remote_settings'], true)) {
    if ($_SERVER['REQUEST_METHOD'] !== 'POST' ||
        !hash_equals(
            (string)($_SESSION['fleet_csrf'] ?? ''),
            (string)($_SERVER['HTTP_X_CSRF_TOKEN'] ?? '')
        )) {
        fleet_api_respond(403, ['error' => 'csrf_validation_failed']);
    }
    $raw = file_get_contents('php://input');
    if ($raw === false || strlen($raw) > 8192) {
        fleet_api_respond(400, ['error' => 'invalid_request']);
    }
    try {
        $request = json_decode($raw, true, 12, JSON_THROW_ON_ERROR);
    } catch (JsonException) {
        fleet_api_respond(400, ['error' => 'invalid_request']);
    }
    $deviceId = is_array($request) ? ($request['deviceId'] ?? null) : null;
    if (!is_string($deviceId) ||
        !preg_match('/^[A-Za-z0-9._:-]{8,128}$/D', $deviceId)) {
        fleet_api_respond(400, ['error' => 'invalid_device_id']);
    }
    $device = fleet_db_execute(
        $db,
        'SELECT r.owner_id, t.last_seen, t.status_json
         FROM fleet_registered_devices r
         LEFT JOIN fleet_device_telemetry t ON t.device_id = r.device_id
         WHERE r.device_id = ? AND r.active = 1',
        [$deviceId]
    )->fetch();
    if (!is_array($device) ||
        ($role !== 'admin' && $device['owner_id'] !== $ownerId)) {
        fleet_api_respond(404, ['error' => 'device_not_found']);
    }

    if ($action === 'remote_command') {
        $latestStatus = is_array($device) && is_string($device['status_json'] ?? null)
            ? json_decode($device['status_json'], true, 16)
            : null;
        if (!is_array($latestStatus) ||
            !is_numeric($device['last_seen'] ?? null) ||
            (int)$device['last_seen'] < time() - FLEET_ONLINE_WINDOW_SECONDS ||
            ($latestStatus['appForeground'] ?? false) !== true) {
            fleet_api_respond(409, ['error' => 'device_not_online']);
        }
        $command = $request['command'] ?? null;
        $allowedCommands = [
            'restart_app',
            'reboot_device',
            'pause_booth',
            'resume_booth',
            'enable_kiosk',
            'disable_kiosk',
            'check_app_update',
            'test_print',
        ];
        if (!in_array($command, $allowedCommands, true)) {
            fleet_api_respond(400, ['error' => 'invalid_remote_command']);
        }
        $now = time();
        fleet_db_execute(
            $db,
            'UPDATE fleet_device_commands
             SET status = ?, result_text = ?, updated_at = ?
             WHERE device_id = ? AND status IN (?, ?) AND created_at < ?',
            [
                'failed',
                'command_ack_timeout',
                $now,
                $deviceId,
                'pending',
                'delivered',
                $now - 600,
            ]
        );
        $unconfirmedCommand = fleet_db_execute(
            $db,
            'SELECT command_id FROM fleet_device_commands
             WHERE device_id = ? AND status IN (?, ?)
             ORDER BY command_id DESC LIMIT 1',
            [$deviceId, 'pending', 'delivered']
        )->fetch();
        if (is_array($unconfirmedCommand)) {
            fleet_api_respond(409, ['error' => 'command_pending']);
        }
        fleet_db_execute(
            $db,
            'INSERT INTO fleet_device_commands
             (device_id, command_name, status, created_at, updated_at)
             VALUES (?, ?, ?, ?, ?)',
            [$deviceId, $command, 'pending', $now, $now]
        );
        fleet_api_respond(200, [
            'ok' => true,
            'commandId' => (int)$db->lastInsertId(),
            'status' => 'pending',
        ]);
    }

    $settings = $request['settings'] ?? null;
    if (!is_array($settings) ||
        !is_string($settings['eventTheme'] ?? null) ||
        !in_array($settings['eventTheme'], [
            'classic', 'birthday', 'wedding', 'graduation', 'holiday',
            'summer', 'coffeeBeans', 'coffeeCup', 'latteArt', 'valentines',
        ], true) ||
        !is_string($settings['welcomeMessage'] ?? null) ||
        trim($settings['welcomeMessage']) === '' ||
        strlen($settings['welcomeMessage']) > 36 ||
        !is_int($settings['idleTimeoutSeconds'] ?? null) ||
        !in_array($settings['idleTimeoutSeconds'], [30, 60, 120, 300], true) ||
        !is_array($settings['photoCounts'] ?? null) ||
        count($settings['photoCounts']) < 1 ||
        count($settings['photoCounts']) > 5 ||
        array_filter(
            $settings['photoCounts'],
            static fn($count): bool => !is_int($count) || $count < 1 || $count > 5
        ) !== [] ||
        count(array_unique($settings['photoCounts'])) !== count($settings['photoCounts']) ||
        !is_string($settings['printerAddress'] ?? null) ||
        ($settings['printerAddress'] !== '' &&
            !preg_match('/^[0-9A-Fa-f:]{17}$/D', $settings['printerAddress'])) ||
        !is_string($settings['cameraDirection'] ?? null) ||
        !in_array($settings['cameraDirection'], ['front', 'back'], true) ||
        !is_int($settings['countdownDuration'] ?? null) ||
        !in_array($settings['countdownDuration'], [1, 2, 3, 4, 5], true) ||
        !is_int($settings['previewDuration'] ?? null) ||
        !in_array($settings['previewDuration'], [3, 5, 8, 10, 15], true) ||
        !is_string($settings['photoBorderStyle'] ?? null) ||
        !in_array($settings['photoBorderStyle'], [
            'none', 'classic', 'party', 'elegant', 'christmas',
            'valentinesDay', 'halloween', 'newYear', 'birthday',
            'wedding', 'easter', 'summer', 'graduation', 'mothersDay',
            'lunarNewYear', 'diwali', 'babyShower', 'anniversary', 'custom',
        ], true) ||
        !is_string($settings['liveEffect'] ?? null) ||
        !in_array($settings['liveEffect'], [
            'original', 'vivid', 'warm', 'monochrome', 'vintage',
            'cartoon', 'soft', 'cool', 'rose', 'matte', 'sepia',
            'cinematic', 'pastel', 'fade',
        ], true) ||
        !is_bool($settings['voiceGuidanceEnabled'] ?? null) ||
        !is_string($settings['brandLogoAnimation'] ?? null) ||
        !in_array($settings['brandLogoAnimation'], [
            'none', 'jump', 'pump', 'sway', 'float',
        ], true) ||
        !is_string($settings['printerType'] ?? null) ||
        !in_array($settings['printerType'], ['receipt', 'color'], true) ||
        !is_int($settings['receiptWidthDots'] ?? null) ||
        !in_array($settings['receiptWidthDots'], [384, 576], true) ||
        (!is_int($settings['receiptBrightness'] ?? null) &&
            !is_float($settings['receiptBrightness'] ?? null)) ||
        $settings['receiptBrightness'] < 0.2 ||
        $settings['receiptBrightness'] > 0.5 ||
        !is_string($settings['receiptCutMode'] ?? null) ||
        !in_array($settings['receiptCutMode'], ['full', 'partial'], true) ||
        !is_int($settings['printCopies'] ?? null) ||
        !in_array($settings['printCopies'], [1, 2, 3], true) ||
        !is_bool($settings['walletPaymentEnabled'] ?? null) ||
        !is_bool($settings['payMongoPaymentsEnabled'] ?? null) ||
        !is_int($settings['coinPricePesos'] ?? null) ||
        $settings['coinPricePesos'] < 1 ||
        $settings['coinPricePesos'] > 100000 ||
        !is_int($settings['payMongoAmountPesos'] ?? null) ||
        $settings['payMongoAmountPesos'] < 1 ||
        $settings['payMongoAmountPesos'] > 100000 ||
        !is_bool($settings['liveWallpaperEnabled'] ?? null) ||
        !is_bool($settings['idleVideoLoop'] ?? null) ||
        !is_bool($settings['fleetLocationSharingEnabled'] ?? null) ||
        !is_int($settings['chargeStartPercent'] ?? null) ||
        $settings['chargeStartPercent'] < 0 ||
        $settings['chargeStartPercent'] > 99 ||
        !is_int($settings['chargeStopPercent'] ?? null) ||
        $settings['chargeStopPercent'] < 1 ||
        $settings['chargeStopPercent'] > 100 ||
        $settings['chargeStartPercent'] >= $settings['chargeStopPercent']) {
        fleet_api_respond(400, ['error' => 'invalid_remote_settings']);
    }
    sort($settings['photoCounts']);
    $now = time();
    fleet_db_execute(
        $db,
        'INSERT INTO fleet_device_settings (device_id, settings_json, updated_at)
         VALUES (?, ?, ?)
         ON DUPLICATE KEY UPDATE
           settings_json = VALUES(settings_json), updated_at = VALUES(updated_at)',
        [
            $deviceId,
            json_encode([
                'eventTheme' => $settings['eventTheme'],
                'welcomeMessage' => trim($settings['welcomeMessage']),
                'idleTimeoutSeconds' => $settings['idleTimeoutSeconds'],
                'photoCounts' => array_values($settings['photoCounts']),
                'printerAddress' => strtoupper($settings['printerAddress']),
                'cameraDirection' => $settings['cameraDirection'],
                'countdownDuration' => $settings['countdownDuration'],
                'previewDuration' => $settings['previewDuration'],
                'photoBorderStyle' => $settings['photoBorderStyle'],
                'liveEffect' => $settings['liveEffect'],
                'voiceGuidanceEnabled' => $settings['voiceGuidanceEnabled'],
                'brandLogoAnimation' => $settings['brandLogoAnimation'],
                'printerType' => $settings['printerType'],
                'receiptWidthDots' => $settings['receiptWidthDots'],
                'receiptBrightness' => (float)$settings['receiptBrightness'],
                'receiptCutMode' => $settings['receiptCutMode'],
                'printCopies' => $settings['printCopies'],
                'walletPaymentEnabled' => $settings['walletPaymentEnabled'],
                'payMongoPaymentsEnabled' => $settings['payMongoPaymentsEnabled'],
                'coinPricePesos' => $settings['coinPricePesos'],
                'payMongoAmountPesos' => $settings['payMongoAmountPesos'],
                'liveWallpaperEnabled' => $settings['liveWallpaperEnabled'],
                'idleVideoLoop' => $settings['idleVideoLoop'],
                'fleetLocationSharingEnabled' => $settings['fleetLocationSharingEnabled'],
                'chargeStartPercent' => $settings['chargeStartPercent'],
                'chargeStopPercent' => $settings['chargeStopPercent'],
            ], JSON_THROW_ON_ERROR),
            $now,
        ]
    );
    fleet_api_respond(200, ['ok' => true, 'updatedAt' => $now]);
}

if ($action !== 'devices' || $_SERVER['REQUEST_METHOD'] !== 'GET') {
    header('Allow: GET, POST');
    fleet_api_respond(404, ['error' => 'not_found']);
}

$now = time();
$ownerFilter = $role === 'admin' ? '' : ' AND r.owner_id = ?';
$parameters = $role === 'admin' ? [] : [$ownerId];
$rows = fleet_db_execute(
    $db,
    'SELECT r.device_id AS deviceId, r.registered_at AS registeredAt,
            t.first_seen AS firstSeen, t.last_seen AS lastSeen,
            t.status_json AS statusJson, t.sales_json AS salesJson,
            (SELECT s.settings_json FROM fleet_device_settings s
             WHERE s.device_id = r.device_id) AS settingsJson,
            (SELECT CONCAT(c.command_name, \':\', c.status, \':\', c.result_text)
             FROM fleet_device_commands c WHERE c.device_id = r.device_id
             ORDER BY c.command_id DESC LIMIT 1) AS commandSummary
     FROM fleet_registered_devices r
     LEFT JOIN fleet_device_telemetry t ON t.device_id = r.device_id
     WHERE r.active = 1' . $ownerFilter . '
     ORDER BY t.last_seen DESC',
    $parameters
)->fetchAll();
$result = [];
foreach ($rows as $row) {
    $result[] = [
        'deviceId' => $row['deviceId'],
        'registeredAt' => (int)$row['registeredAt'],
        'firstSeen' => $row['firstSeen'] === null ? null : (int)$row['firstSeen'],
        'lastSeen' => $row['lastSeen'] === null ? null : (int)$row['lastSeen'],
        'status' => $row['statusJson'] === null ? [] : json_decode($row['statusJson'], true, 16, JSON_THROW_ON_ERROR),
        'sales' => $row['salesJson'] === null ? [] : json_decode($row['salesJson'], true, 16, JSON_THROW_ON_ERROR),
        'remoteSettings' => $row['settingsJson'] === null
            ? []
            : json_decode($row['settingsJson'], true, 16, JSON_THROW_ON_ERROR),
        'commandSummary' => $row['commandSummary'],
        'online' => $row['lastSeen'] !== null &&
            (int)$row['lastSeen'] >= $now - FLEET_ONLINE_WINDOW_SECONDS,
    ];
}

fleet_api_respond(200, [
    'devices' => $result,
    'serverTime' => $now,
    'role' => $role,
    'csrfToken' => $_SESSION['fleet_csrf'],
    'paymongo' => $role === 'user'
        ? (function () use ($db, $ownerId): array {
            $account = fleet_db_execute(
                $db,
                'SELECT paymongo_account_status, paymongo_identity_status,
                        paymongo_profile_submitted
                 FROM fleet_accounts WHERE account_id = ?',
                [$ownerId]
            )->fetch();
            if (!is_array($account)) {
                fleet_api_respond(404, ['error' => 'fleet_account_not_found']);
            }
            return [
                'accountStatus' => $account['paymongo_account_status'],
                'identityStatus' => $account['paymongo_identity_status'],
                'profileSubmitted' => (bool)$account['paymongo_profile_submitted'],
            ];
        })()
        : null,
]);

/**
 * Handle password reset request with owner notification.
 *
 * This should be called when a password reset request is made via the API.
 * It sends a password reset notification email to the owner.
 *
 * @param array $config SMTP configuration
 * @param string $email Owner's email address
 * @param string $resetUrl URL for password reset
 * @param string $ownerName Owner's name (optional)
 * @return void
 */
function fleet_handle_password_reset_request(array $config, string $email, string $resetUrl, string $ownerName = ''): void {
    fleet_send_password_reset_notification($config, $email, $resetUrl, $ownerName);
}

/**
 * Handle weekly sales report generation and email.
 *
 * This should be called as a cron job or scheduled task to send weekly sales reports to owners.
 *
 * @param array $config SMTP configuration
 * @param string $email Owner's email address
 * @param string $ownerName Owner's name (optional)
 * @param int $periodStart Unix timestamp for the start of the reporting period
 * @param int $periodEnd Unix timestamp for the end of the reporting period
 * @param array $salesData Aggregated sales data by payment method and device
 * @param array $deviceNames Human-readable device names
 * @return void
 */
function fleet_handle_weekly_sales_report(array $config, string $email, string $ownerName, int $periodStart, int $periodEnd, array $salesData, array $deviceNames = []): void {
    fleet_send_weekly_sales_report($config, $email, $ownerName, $periodStart, $periodEnd, $salesData, $deviceNames);
}

/**
 * Handle system problem notification to the owner.
 *
 * This should be called when system problems are detected (offline devices, errors, etc.).
 *
 * @param array $config SMTP configuration
 * @param string $email Owner's email address
 * @param string $ownerName Owner's name (optional)
 * @param string $problem Description of the problem
 * @param string $affectedDevice Device identifier affected (optional)
 * @param string $severity Severity level (info, warning, critical)
 * @return void
 */
function fleet_handle_problem_notification(array $config, string $email, string $ownerName, string $problem, string $affectedDevice = '', string $severity = 'warning'): void {
    fleet_send_problem_notification($config, $email, $ownerName, $problem, $affectedDevice, $severity);
}
