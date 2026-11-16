ALTER TABLE fleet_accounts
    ADD COLUMN paymongo_account_id VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NULL,
    ADD COLUMN paymongo_account_status VARCHAR(24) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'not_started',
    ADD COLUMN paymongo_identity_verification_id VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NULL,
    ADD COLUMN paymongo_identity_status VARCHAR(24) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'not_started',
    ADD COLUMN paymongo_profile_submitted TINYINT(1) NOT NULL DEFAULT 0,
    ADD COLUMN paymongo_updated_at BIGINT UNSIGNED NOT NULL DEFAULT 0,
    ADD UNIQUE KEY uq_fleet_accounts_paymongo_id (paymongo_account_id);

CREATE TABLE IF NOT EXISTS fleet_paymongo_webhook_events (
    event_id VARCHAR(80) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    account_id VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    processed_at BIGINT UNSIGNED NOT NULL,
    PRIMARY KEY (event_id),
    KEY ix_fleet_paymongo_webhook_account (account_id, processed_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
