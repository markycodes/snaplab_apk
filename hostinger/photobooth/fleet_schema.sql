CREATE TABLE IF NOT EXISTS fleet_owners (
    owner_id CHAR(32) NOT NULL,
    owner_type ENUM('administrator', 'account', 'legacy') NOT NULL,
    PRIMARY KEY (owner_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT IGNORE INTO fleet_owners (owner_id, owner_type) VALUES ('admin', 'administrator');

CREATE TABLE IF NOT EXISTS fleet_accounts (
    account_id CHAR(32) NOT NULL,
    email VARCHAR(254) NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    created_at BIGINT UNSIGNED NOT NULL,
    paymongo_account_id VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NULL,
    paymongo_account_status VARCHAR(24) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'not_started',
    paymongo_identity_verification_id VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NULL,
    paymongo_identity_status VARCHAR(24) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'not_started',
    paymongo_profile_submitted TINYINT(1) NOT NULL DEFAULT 0,
    paymongo_updated_at BIGINT UNSIGNED NOT NULL DEFAULT 0,
    PRIMARY KEY (account_id),
    UNIQUE KEY uq_fleet_accounts_paymongo_id (paymongo_account_id),
    UNIQUE KEY uq_fleet_accounts_email (email),
    CONSTRAINT fk_fleet_accounts_owner
        FOREIGN KEY (account_id) REFERENCES fleet_owners (owner_id)
        ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS fleet_registered_devices (
    device_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    owner_id CHAR(32) NOT NULL,
    registered_at BIGINT UNSIGNED NOT NULL,
    active TINYINT(1) NOT NULL DEFAULT 1,
    PRIMARY KEY (device_id),
    KEY ix_fleet_registered_devices_owner_active (owner_id, active),
    CONSTRAINT fk_fleet_registered_devices_owner
        FOREIGN KEY (owner_id) REFERENCES fleet_owners (owner_id)
        ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS fleet_device_telemetry (
    device_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    first_seen BIGINT UNSIGNED NOT NULL,
    last_seen BIGINT UNSIGNED NOT NULL,
    status_json JSON NOT NULL,
    sales_json JSON NOT NULL,
    PRIMARY KEY (device_id),
    KEY ix_fleet_device_telemetry_last_seen (last_seen),
    CONSTRAINT fk_fleet_device_telemetry_device
        FOREIGN KEY (device_id) REFERENCES fleet_registered_devices (device_id)
        ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS fleet_device_settings (
    device_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    settings_json JSON NOT NULL,
    updated_at BIGINT UNSIGNED NOT NULL,
    PRIMARY KEY (device_id),
    CONSTRAINT fk_fleet_device_settings_device
        FOREIGN KEY (device_id) REFERENCES fleet_registered_devices (device_id)
        ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS fleet_device_commands (
    command_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    device_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    command_name VARCHAR(32) NOT NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'pending',
    created_at BIGINT UNSIGNED NOT NULL,
    updated_at BIGINT UNSIGNED NOT NULL,
    result_text VARCHAR(160) NULL,
    PRIMARY KEY (command_id),
    KEY ix_fleet_device_commands_pending (device_id, status, command_id),
    CONSTRAINT fk_fleet_device_commands_device
        FOREIGN KEY (device_id) REFERENCES fleet_registered_devices (device_id)
        ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS fleet_rate_limits (
    scope VARCHAR(16) NOT NULL,
    ip_hash CHAR(64) NOT NULL,
    attempt_count INT UNSIGNED NOT NULL DEFAULT 0,
    window_started BIGINT UNSIGNED NOT NULL,
    PRIMARY KEY (scope, ip_hash),
    KEY ix_fleet_rate_limits_window (window_started)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS fleet_password_resets (
    token_hash CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    account_id CHAR(32) NOT NULL,
    created_at BIGINT UNSIGNED NOT NULL,
    expires_at BIGINT UNSIGNED NOT NULL,
    used_at BIGINT UNSIGNED NULL,
    PRIMARY KEY (token_hash),
    KEY ix_fleet_password_resets_account (account_id, expires_at),
    CONSTRAINT fk_fleet_password_resets_account
        FOREIGN KEY (account_id) REFERENCES fleet_accounts (account_id)
        ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS fleet_device_alerts (
    device_id VARCHAR(128) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    alert_key VARCHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    active TINYINT(1) NOT NULL DEFAULT 1,
    notification_status VARCHAR(16) NOT NULL DEFAULT 'pending',
    opened_at BIGINT UNSIGNED NOT NULL,
    updated_at BIGINT UNSIGNED NOT NULL,
    resolved_at BIGINT UNSIGNED NULL,
    PRIMARY KEY (device_id, alert_key),
    KEY ix_fleet_device_alerts_active (active, notification_status),
    CONSTRAINT fk_fleet_device_alerts_device
        FOREIGN KEY (device_id) REFERENCES fleet_registered_devices (device_id)
        ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS fleet_email_reports (
    owner_id CHAR(32) NOT NULL,
    report_type VARCHAR(24) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    period_start DATE NOT NULL,
    sent_at BIGINT UNSIGNED NOT NULL,
    PRIMARY KEY (owner_id, report_type, period_start),
    CONSTRAINT fk_fleet_email_reports_owner
        FOREIGN KEY (owner_id) REFERENCES fleet_accounts (account_id)
        ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS fleet_paymongo_webhook_events (
    event_id VARCHAR(80) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    account_id VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    processed_at BIGINT UNSIGNED NOT NULL,
    PRIMARY KEY (event_id),
    KEY ix_fleet_paymongo_webhook_account (account_id, processed_at),
    CONSTRAINT fk_fleet_paymongo_webhook_account
        FOREIGN KEY (account_id) REFERENCES fleet_accounts (paymongo_account_id)
        ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
