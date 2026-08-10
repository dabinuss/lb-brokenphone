Config = {}

Config.Debug = false

Config.Database = {
    tableName = 'phone_damage',
    jsonFile = 'data/phone_damage.json',
    allowJsonFallback = true
}

Config.Transition = {
    openDuration = 500,
    closeDuration = 500
}

Config.Touch = {
    enabled = true,
    medium = { intervalMin = 1500, intervalMax = 4500, durationMin = 120, durationMax = 300 },
    severe = { intervalMin = 250, intervalMax = 900, durationMin = 350, durationMax = 850 }
}

Config.Commands = {
    enabled = true,
    restricted = false,
    setDamage = 'phonedamage',
    setDamageColor = 'phonedamagecolor',
    repair = 'phonerepair',
    legacySetDamage = 'brokenphone',
    legacyRepair = 'brokenphonerepair'
}

-- 1 = black cracks, 2 = white cracks. The command selection is stored per client.
Config.DefaultDamageColor = 1

Config.MaxPhoneNumberLength = 32
