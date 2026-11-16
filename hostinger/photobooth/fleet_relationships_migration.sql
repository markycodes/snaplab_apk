CREATE TABLE IF NOT EXISTS fleet_owners (
    owner_id CHAR(32) NOT NULL,
    owner_type ENUM('administrator', 'account', 'legacy') NOT NULL,
    PRIMARY KEY (owner_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT IGNORE INTO fleet_owners (owner_id, owner_type)
VALUES ('admin', 'administrator');

INSERT IGNORE INTO fleet_owners (owner_id, owner_type)
SELECT account_id, 'account' FROM fleet_accounts;

INSERT IGNORE INTO fleet_owners (owner_id, owner_type)
SELECT DISTINCT r.owner_id, 'legacy'
FROM fleet_registered_devices r
LEFT JOIN fleet_owners o ON o.owner_id = r.owner_id
WHERE o.owner_id IS NULL;

ALTER TABLE fleet_accounts
    ADD CONSTRAINT fk_fleet_accounts_owner
    FOREIGN KEY (account_id) REFERENCES fleet_owners (owner_id)
    ON UPDATE CASCADE ON DELETE RESTRICT;

ALTER TABLE fleet_registered_devices
    MODIFY owner_id CHAR(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
    ADD CONSTRAINT fk_fleet_registered_devices_owner
    FOREIGN KEY (owner_id) REFERENCES fleet_owners (owner_id)
    ON UPDATE CASCADE ON DELETE RESTRICT;

ALTER TABLE fleet_device_telemetry
    ADD CONSTRAINT fk_fleet_device_telemetry_device
    FOREIGN KEY (device_id) REFERENCES fleet_registered_devices (device_id)
    ON UPDATE CASCADE ON DELETE CASCADE;

ALTER TABLE fleet_device_settings
    ADD CONSTRAINT fk_fleet_device_settings_device
    FOREIGN KEY (device_id) REFERENCES fleet_registered_devices (device_id)
    ON UPDATE CASCADE ON DELETE CASCADE;

ALTER TABLE fleet_device_commands
    ADD CONSTRAINT fk_fleet_device_commands_device
    FOREIGN KEY (device_id) REFERENCES fleet_registered_devices (device_id)
    ON UPDATE CASCADE ON DELETE CASCADE;

ALTER TABLE fleet_password_resets
    ADD CONSTRAINT fk_fleet_password_resets_account
    FOREIGN KEY (account_id) REFERENCES fleet_accounts (account_id)
    ON UPDATE CASCADE ON DELETE CASCADE;

ALTER TABLE fleet_device_alerts
    ADD CONSTRAINT fk_fleet_device_alerts_device
    FOREIGN KEY (device_id) REFERENCES fleet_registered_devices (device_id)
    ON UPDATE CASCADE ON DELETE CASCADE;

ALTER TABLE fleet_email_reports
    ADD CONSTRAINT fk_fleet_email_reports_owner
    FOREIGN KEY (owner_id) REFERENCES fleet_accounts (account_id)
    ON UPDATE CASCADE ON DELETE CASCADE;

ALTER TABLE fleet_paymongo_webhook_events
    ADD CONSTRAINT fk_fleet_paymongo_webhook_account
    FOREIGN KEY (account_id) REFERENCES fleet_accounts (paymongo_account_id)
    ON UPDATE CASCADE ON DELETE CASCADE;
