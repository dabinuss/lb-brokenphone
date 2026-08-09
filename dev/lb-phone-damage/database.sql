CREATE TABLE IF NOT EXISTS `phone_damage` (
    `phone_number` VARCHAR(32) NOT NULL,
    `damage_level` TINYINT UNSIGNED NOT NULL,
    `damage_seed` INT UNSIGNED NOT NULL,
    PRIMARY KEY (`phone_number`),
    CONSTRAINT `phone_damage_level` CHECK (`damage_level` BETWEEN 1 AND 3)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
