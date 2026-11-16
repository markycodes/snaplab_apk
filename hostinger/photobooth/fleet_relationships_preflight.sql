SELECT 'owner_id exceeds 32 characters' AS issue, device_id AS record_key
FROM fleet_registered_devices
WHERE owner_id IS NULL OR CHAR_LENGTH(owner_id) > 32
UNION ALL
SELECT 'telemetry has no registered device', device_id
FROM fleet_device_telemetry t
LEFT JOIN fleet_registered_devices r USING (device_id)
WHERE r.device_id IS NULL
UNION ALL
SELECT 'settings have no registered device', device_id
FROM fleet_device_settings s
LEFT JOIN fleet_registered_devices r USING (device_id)
WHERE r.device_id IS NULL
UNION ALL
SELECT 'command has no registered device', CAST(command_id AS CHAR)
FROM fleet_device_commands c
LEFT JOIN fleet_registered_devices r USING (device_id)
WHERE r.device_id IS NULL
UNION ALL
SELECT 'alert has no registered device', CONCAT(device_id, ':', alert_key)
FROM fleet_device_alerts a
LEFT JOIN fleet_registered_devices r USING (device_id)
WHERE r.device_id IS NULL
UNION ALL
SELECT 'password reset has no account', token_hash
FROM fleet_password_resets p
LEFT JOIN fleet_accounts a ON a.account_id = p.account_id
WHERE a.account_id IS NULL
UNION ALL
SELECT 'email report has no account', CONCAT(owner_id, ':', report_type, ':', period_start)
FROM fleet_email_reports e
LEFT JOIN fleet_accounts a ON a.account_id = e.owner_id
WHERE a.account_id IS NULL
UNION ALL
SELECT 'PayMongo webhook event has no account', event_id
FROM fleet_paymongo_webhook_events w
LEFT JOIN fleet_accounts a ON a.paymongo_account_id = w.account_id
WHERE a.account_id IS NULL;
