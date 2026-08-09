Config = {}

Config.Debug = false
-- LB Phone raises its focused NUI to 99999 while opening. Keep the transparent
-- crack resource above it without taking focus or intercepting input.
Config.NuiZIndex = 100000

Config.Database = {
    tableName = 'phone_damage',
    jsonFile = 'data/phone_damage.json',
    allowJsonFallback = true
}

-- LB Phone 2.8.x uses a 29rem x 58.5rem phone at bottom/right 1rem.
-- These values mask only its inner .phone-container display.
Config.Display = {
    width = '28.13rem',
    height = '57.68rem',
    right = '1.44rem',
    bottom = '1.41rem',
    radius = '3.44rem'
}

Config.Motion = {
    openDuration = 500,
    closeDuration = 500,
    closedY = '62rem',
    openY = '0rem',
    easing = 'cubic-bezier(0.22, 1, 0.36, 1)'
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
    repair = 'phonerepair',
    legacySetDamage = 'brokenphone',
    legacyRepair = 'brokenphonerepair'
}

Config.MaxPhoneNumberLength = 32
