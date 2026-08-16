CREATE TABLE IF NOT EXISTS `phone_damage` (
    `phone_number` VARCHAR(32) NOT NULL,
    `damage_level` TINYINT UNSIGNED NOT NULL DEFAULT 0,
    `damage_seed` INT UNSIGNED NOT NULL DEFAULT 0,
    `fire_level` TINYINT UNSIGNED NOT NULL DEFAULT 0,
    `fire_seed` INT UNSIGNED NOT NULL DEFAULT 0,
    `is_hacked` TINYINT(1) UNSIGNED NOT NULL DEFAULT 0,
    `hack_expires_at` BIGINT UNSIGNED NOT NULL DEFAULT 0,
    `hack_message` VARCHAR(512) NULL DEFAULT NULL,
    PRIMARY KEY (`phone_number`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
