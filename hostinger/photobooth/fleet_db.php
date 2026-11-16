<?php

function fleet_db_respond(int $status, array $body): never
{
    if (function_exists('fleet_api_respond')) {
        fleet_api_respond($status, $body);
    }
    if (function_exists('fleet_ingest_respond')) {
        fleet_ingest_respond($status, $body);
    }
    http_response_code($status);
    echo json_encode($body, JSON_UNESCAPED_SLASHES);
    exit;
}

function fleet_db_connection(array $config): PDO
{
    foreach (['fleet_db_host', 'fleet_db_name', 'fleet_db_user', 'fleet_db_password'] as $key) {
        if (!is_string($config[$key] ?? null) || $config[$key] === '') {
            fleet_db_respond(503, ['error' => 'fleet_database_not_configured']);
        }
    }
    if (!preg_match('/^[A-Za-z0-9_.-]+$/D', $config['fleet_db_host']) ||
        !preg_match('/^[A-Za-z0-9_$-]+$/D', $config['fleet_db_name'])) {
        fleet_db_respond(503, ['error' => 'fleet_database_not_configured']);
    }
    try {
        return new PDO(
            'mysql:host=' . $config['fleet_db_host'] .
                ';dbname=' . $config['fleet_db_name'] . ';charset=utf8mb4',
            $config['fleet_db_user'],
            $config['fleet_db_password'],
            [
                PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
                PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
                PDO::ATTR_EMULATE_PREPARES => false,
                PDO::ATTR_TIMEOUT => 5,
            ]
        );
    } catch (PDOException $error) {
        error_log('Fleet MySQL connection failed (' . (string)$error->getCode() . ')');
        fleet_db_respond(503, ['error' => 'fleet_database_unavailable']);
    }
}

function fleet_db_execute(PDO $db, string $sql, array $parameters = []): PDOStatement
{
    try {
        $statement = $db->prepare($sql);
        $statement->execute($parameters);
        return $statement;
    } catch (PDOException $error) {
        error_log('Fleet MySQL query failed (' . (string)$error->getCode() . ')');
        fleet_db_respond(503, ['error' => 'fleet_database_unavailable']);
    }
}

function fleet_db_login_attempts(
    PDO $db,
    bool $recordFailure = false,
    bool $clear = false,
    string $scope = 'login'
): array {
    $ip = $_SERVER['REMOTE_ADDR'] ?? '';
    $ipHash = hash('sha256', is_string($ip) ? $ip : '');
    $now = time();

    try {
        $db->beginTransaction();
        fleet_db_execute(
            $db,
            'DELETE FROM fleet_rate_limits WHERE window_started < ?',
            [$now - 900]
        );
        fleet_db_execute(
            $db,
            'INSERT INTO fleet_rate_limits (scope, ip_hash, attempt_count, window_started)
             VALUES (?, ?, 0, ?)
             ON DUPLICATE KEY UPDATE ip_hash = VALUES(ip_hash)',
            [$scope, $ipHash, $now]
        );
        $statement = fleet_db_execute(
            $db,
            'SELECT attempt_count, window_started FROM fleet_rate_limits
             WHERE scope = ? AND ip_hash = ? FOR UPDATE',
            [$scope, $ipHash]
        );
        $entry = $statement->fetch();
        if (!is_array($entry)) {
            throw new RuntimeException('Rate-limit row could not be locked.');
        }
        $count = (int)$entry['attempt_count'];
        $windowStarted = (int)$entry['window_started'];
        if ($windowStarted < $now - 900) {
            $count = 0;
            $windowStarted = $now;
        }
        if ($clear) {
            fleet_db_execute(
                $db,
                'DELETE FROM fleet_rate_limits WHERE scope = ? AND ip_hash = ?',
                [$scope, $ipHash]
            );
        } else {
            if ($recordFailure) {
                $count++;
            }
            fleet_db_execute(
                $db,
                'UPDATE fleet_rate_limits SET attempt_count = ?, window_started = ?
                 WHERE scope = ? AND ip_hash = ?',
                [$count, $windowStarted, $scope, $ipHash]
            );
        }
        $db->commit();
        return ['count' => $count, 'windowStarted' => $windowStarted];
    } catch (Throwable $error) {
        if ($db->inTransaction()) {
            $db->rollBack();
        }
        if ($error instanceof PDOException) {
            error_log('Fleet MySQL rate-limit operation failed (' . (string)$error->getCode() . ')');
            fleet_db_respond(503, ['error' => 'fleet_database_unavailable']);
        }
        throw $error;
    }
}

function fleet_db_account(PDO $db, string $email): ?array
{
    $statement = fleet_db_execute(
        $db,
        'SELECT account_id AS accountId, password_hash AS passwordHash
         FROM fleet_accounts WHERE email = ?',
        [$email]
    );
    $account = $statement->fetch();
    return is_array($account) ? $account : null;
}
