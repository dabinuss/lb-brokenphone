Config = {}

-- Enables additional diagnostic output in the client and server consoles.
Config.Debug = false

-- Global crack color for every player. Allowed values: 'black' or 'white'.
Config.DamageColor = 'white'

-- The hack is stored separately from crack damage. Asset paths are relative
-- to the resource's html directory.
Config.Hack = {
    image = 'hack/ahahah.gif', -- Animation shown in the center of the blocked phone display.
    text = 'AH AH AH!',        -- Text shown under the image.
    sound = 'hack/ahahah.ogg', -- Sound played when the blocked display is clicked.
    soundVolume = 0.65,        -- Playback volume from 0.0 (silent) to 1.0 (full volume).
    soundCooldown = 300,       -- Minimum milliseconds between click sounds.
    defaultDuration = 300000,  -- Default hack duration in ms (300000 = 5 minutes, 0 = permanent).
    maxDuration = 86400000     -- Largest accepted export duration in ms (86400000 = 24 hours).
}

Config.Database = {
    tableName = 'phone_damage',              -- SQL table used for persistent phone damage.
    jsonFile = 'data/phone_damage.json',     -- Resource-relative fallback file when oxmysql is unavailable.
    allowJsonFallback = true                 -- Use the JSON file instead of failing when oxmysql is not started.
}

-- Bulk persistence settings for large events affecting hundreds of phones.
Config.Persistence = {
    batchSize = 50,       -- Maximum phone records written by one multi-row query.
    readBatchSize = 200,  -- Maximum phone numbers loaded by one cache hydration query.
    batchDelay = 25,      -- Milliseconds yielded between database/client batches.
    resolveYieldEvery = 100 -- Yield after resolving this many equipped phone numbers.
}

-- Protect the client-triggered initial phone sync from duplicate requests.
Config.Sync = {
    networkRateLimit = 1000 -- Minimum milliseconds between sync requests per player.
}

-- Time in milliseconds before opening/closing transitions are considered complete.
Config.Transition = {
    openDuration = 500, -- Delay before the overlay enters its fully open state.
    closeDuration = 500 -- Keep the overlay during the phone's closing animation.
}

-- Simulated touch interruptions start at medium damage. A random interval and
-- duration between the configured minimum and maximum is chosen each time.
Config.Touch = {
    enabled = true, -- Set to false to disable all touch interruptions while keeping visual damage.
    medium = {
        intervalMin = 1500, -- Minimum time in milliseconds before the next touch interruption.
        intervalMax = 4500, -- Maximum time in milliseconds before the next touch interruption.
        durationMin = 120,  -- Minimum duration of a touch interruption in milliseconds.
        durationMax = 300   -- Maximum duration of a touch interruption in milliseconds.
    },
    severe = {
        intervalMin = 250, -- Minimum time in milliseconds before the next touch interruption.
        intervalMax = 900, -- Maximum time in milliseconds before the next touch interruption.
        durationMin = 350, -- Minimum duration of a touch interruption in milliseconds.
        durationMax = 850  -- Maximum duration of a touch interruption in milliseconds.
    }
}

-- Optional gameplay integration. Clients only detect possible impacts; all
-- cooldowns, probability rolls, level changes, and persistence remain server-side.
Config.AutoDamage = {
    enabled = true,          -- Set to false to disable only automatic gameplay damage.
    debug = false,           -- Print accepted/rejected automatic damage attempts on the server.
    dynamicChance = true,    -- Scale each base chance from 50% to 150% using event severity.
    networkRateLimit = 250,  -- Minimum milliseconds between raw client reports per player.
    successCooldown = 30000, -- Block every automatic cause after one successful phone damage.
    clientDebounce = 1000,   -- Minimum milliseconds between reports of the same cause on a client.
    damageReference = 100,   -- Health/armour loss treated as severity 1.0 for combat damage.

    vehicle = {
        pollInterval = 100,           -- Vehicle crash sampling interval in milliseconds.
        idlePollInterval = 750,       -- Sampling interval while the player is not in a vehicle.
        impactWindow = 500,           -- Time allowed for collision and body damage to arrive in adjacent samples.
        minSpeed = 18.0,              -- Minimum pre-impact speed in m/s (18 m/s is about 65 km/h).
        minSpeedLoss = 8.0,           -- Required speed loss between samples in m/s.
        minBodyHealthLoss = 5.0,      -- Required vehicle body-health loss to confirm a collision.
        speedLossReference = 35.0,    -- Speed loss in m/s treated as severity 1.0.
        bodyHealthLossReference = 250.0 -- Body-health loss treated as severity 1.0.
    },

    -- Event values define: enabled state, base chance (%), attempt cooldown (ms),
    -- minimum severity (0.0-1.0), added levels, and the highest permitted result.
    events = {
        gunshot = {
            enabled = true,
            chance = 8,          -- Base probability in percent.
            cooldown = 30000,    -- Minimum time between gunshot rolls for one player.
            minSeverity = 0.03,  -- Minimum normalized health/armour loss.
            escalation = 1,      -- Maximum damage levels added by one successful roll.
            maxResultLevel = 2   -- Gunshots can produce at most medium phone damage.
        },
        melee = {
            enabled = true,
            chance = 5,
            cooldown = 30000,
            minSeverity = 0.05,
            escalation = 1,
            maxResultLevel = 1
        },
        vehicle_crash = {
            enabled = true,
            chance = 25,
            cooldown = 45000,
            minSeverity = 0.35,
            escalation = 1,
            maxResultLevel = 3
        },
        explosion = {
            enabled = true,
            chance = 70,
            cooldown = 60000,
            minSeverity = 0.05,
            escalation = 2,
            maxResultLevel = 3
        }
    }
}

Config.Commands = {
    enabled = false,                        -- Register test/admin commands; production exports remain available when false.
    restricted = true,                     -- Require matching ACE permissions for damage and repair commands.
    setDamage = 'phonedamage',              -- Command used to set crack level 1-3 or activate the separate hack with 4.
    escalateDamage = 'phoneescalate',       -- Command used to increase damage by exactly one level.
    setDamageAll = 'phonedamageall',        -- ACE-only command that damages every player's currently equipped phone.
    setDamageArea = 'phonedamagearea',      -- ACE-only command that damages equipped phones around the executing player.
    setDamageColor = 'phonedamagecolor',    -- Global color command; always requires command.phonedamagecolor ACE.
    repair = 'phonerepair',                 -- Command used to remove physical crack damage while preserving a hack.
    unhack = 'phoneunhack',                 -- Command that removes only the hack and preserves physical display damage.
    repairAll = 'phonerepairall',           -- ACE-only command that repairs physical damage on all equipped phones.
    legacySetDamage = 'brokenphone',        -- Backward-compatible damage alias; set to false to disable.
    legacyRepair = 'brokenphonerepair'      -- Backward-compatible repair alias; set to false to disable.
}

-- Maximum accepted phone-number length. Keep this aligned with VARCHAR(32) in database.sql.
Config.MaxPhoneNumberLength = 32

-- Safety limit in game units/metres for /phonedamagearea and area exports.
Config.MaxDamageAreaRadius = 10000

local function assertInteger(name, value, minimum)
    assert(type(value) == 'number' and value % 1 == 0 and value >= minimum,
        ('%s must be an integer greater than or equal to %d'):format(name, minimum))
end

local function validateTouchProfile(name, profile)
    assert(type(profile) == 'table', ('Config.Touch.%s must be a table'):format(name))
    assertInteger(('Config.Touch.%s.intervalMin'):format(name), profile.intervalMin, 1)
    assertInteger(('Config.Touch.%s.intervalMax'):format(name), profile.intervalMax, 1)
    assertInteger(('Config.Touch.%s.durationMin'):format(name), profile.durationMin, 1)
    assertInteger(('Config.Touch.%s.durationMax'):format(name), profile.durationMax, 1)
    assert(profile.intervalMin <= profile.intervalMax,
        ('Config.Touch.%s.intervalMin must not exceed intervalMax'):format(name))
    assert(profile.durationMin <= profile.durationMax,
        ('Config.Touch.%s.durationMin must not exceed durationMax'):format(name))
end

local function validateCommandName(name, value, optional)
    if optional and (value == false or value == nil) then return end
    assert(type(value) == 'string' and value ~= '', ('%s must be a non-empty string'):format(name))
end

local function assertNumberRange(name, value, minimum, maximum)
    assert(type(value) == 'number' and value >= minimum and value <= maximum,
        ('%s must be a number between %s and %s'):format(name, minimum, maximum))
end

local function validateAutoDamageEvent(name, eventConfig)
    local path = ('Config.AutoDamage.events.%s'):format(name)
    assert(type(eventConfig) == 'table', ('%s must be a table'):format(path))
    assert(type(eventConfig.enabled) == 'boolean', ('%s.enabled must be true or false'):format(path))
    assertNumberRange(('%s.chance'):format(path), eventConfig.chance, 0, 100)
    assertInteger(('%s.cooldown'):format(path), eventConfig.cooldown, 0)
    assertNumberRange(('%s.minSeverity'):format(path), eventConfig.minSeverity, 0, 1)
    assertInteger(('%s.escalation'):format(path), eventConfig.escalation, 1)
    assert(eventConfig.escalation <= 3, ('%s.escalation must not exceed 3'):format(path))
    assertInteger(('%s.maxResultLevel'):format(path), eventConfig.maxResultLevel, 1)
    assert(eventConfig.maxResultLevel <= 3, ('%s.maxResultLevel must not exceed 3'):format(path))
end

assert(Config.DamageColor == 'black' or Config.DamageColor == 'white',
    "Config.DamageColor must be 'black' or 'white'")
assert(type(Config.Hack) == 'table', 'Config.Hack must be a table')
assert(type(Config.Hack.image) == 'string' and Config.Hack.image ~= '',
    'Config.Hack.image must be a non-empty html-relative path')
assert(type(Config.Hack.sound) == 'string' and Config.Hack.sound ~= '',
    'Config.Hack.sound must be a non-empty html-relative path')
assertNumberRange('Config.Hack.soundVolume', Config.Hack.soundVolume, 0, 1)
assertInteger('Config.Hack.soundCooldown', Config.Hack.soundCooldown, 0)
assertInteger('Config.Hack.defaultDuration', Config.Hack.defaultDuration, 0)
assertInteger('Config.Hack.maxDuration', Config.Hack.maxDuration, 0)
assert(Config.Hack.defaultDuration <= Config.Hack.maxDuration,
    'Config.Hack.defaultDuration must not exceed Config.Hack.maxDuration')
assert(type(Config.Debug) == 'boolean', 'Config.Debug must be true or false')
assert(type(Config.Database) == 'table', 'Config.Database must be a table')
assert(type(Config.Database.tableName) == 'string' and Config.Database.tableName:match('^[%w_]+$'),
    'Config.Database.tableName may only contain letters, numbers, and underscores')
assert(type(Config.Database.jsonFile) == 'string' and Config.Database.jsonFile ~= '',
    'Config.Database.jsonFile must be a non-empty resource-relative path')
assert(type(Config.Database.allowJsonFallback) == 'boolean',
    'Config.Database.allowJsonFallback must be true or false')
assert(type(Config.Persistence) == 'table', 'Config.Persistence must be a table')
assertInteger('Config.Persistence.batchSize', Config.Persistence.batchSize, 1)
assertInteger('Config.Persistence.readBatchSize', Config.Persistence.readBatchSize, 1)
assertInteger('Config.Persistence.batchDelay', Config.Persistence.batchDelay, 0)
assertInteger('Config.Persistence.resolveYieldEvery', Config.Persistence.resolveYieldEvery, 1)
assert(type(Config.Sync) == 'table', 'Config.Sync must be a table')
assertInteger('Config.Sync.networkRateLimit', Config.Sync.networkRateLimit, 0)
assert(type(Config.Transition) == 'table', 'Config.Transition must be a table')
assertInteger('Config.Transition.openDuration', Config.Transition.openDuration, 0)
assertInteger('Config.Transition.closeDuration', Config.Transition.closeDuration, 0)
assert(type(Config.Touch) == 'table', 'Config.Touch must be a table')
assert(type(Config.Touch.enabled) == 'boolean', 'Config.Touch.enabled must be true or false')
validateTouchProfile('medium', Config.Touch.medium)
validateTouchProfile('severe', Config.Touch.severe)
assert(type(Config.AutoDamage) == 'table', 'Config.AutoDamage must be a table')
assert(type(Config.AutoDamage.enabled) == 'boolean', 'Config.AutoDamage.enabled must be true or false')
assert(type(Config.AutoDamage.debug) == 'boolean', 'Config.AutoDamage.debug must be true or false')
assert(type(Config.AutoDamage.dynamicChance) == 'boolean', 'Config.AutoDamage.dynamicChance must be true or false')
assertInteger('Config.AutoDamage.networkRateLimit', Config.AutoDamage.networkRateLimit, 0)
assertInteger('Config.AutoDamage.successCooldown', Config.AutoDamage.successCooldown, 0)
assertInteger('Config.AutoDamage.clientDebounce', Config.AutoDamage.clientDebounce, 0)
assertNumberRange('Config.AutoDamage.damageReference', Config.AutoDamage.damageReference, 1, 10000)
assert(type(Config.AutoDamage.vehicle) == 'table', 'Config.AutoDamage.vehicle must be a table')
assertInteger('Config.AutoDamage.vehicle.pollInterval', Config.AutoDamage.vehicle.pollInterval, 50)
assertInteger('Config.AutoDamage.vehicle.idlePollInterval', Config.AutoDamage.vehicle.idlePollInterval, 100)
assertInteger('Config.AutoDamage.vehicle.impactWindow', Config.AutoDamage.vehicle.impactWindow, 100)
assertNumberRange('Config.AutoDamage.vehicle.minSpeed', Config.AutoDamage.vehicle.minSpeed, 0, 200)
assertNumberRange('Config.AutoDamage.vehicle.minSpeedLoss', Config.AutoDamage.vehicle.minSpeedLoss, 0.1, 200)
assertNumberRange('Config.AutoDamage.vehicle.minBodyHealthLoss', Config.AutoDamage.vehicle.minBodyHealthLoss, 0, 1000)
assertNumberRange('Config.AutoDamage.vehicle.speedLossReference', Config.AutoDamage.vehicle.speedLossReference, 0.1, 200)
assertNumberRange('Config.AutoDamage.vehicle.bodyHealthLossReference', Config.AutoDamage.vehicle.bodyHealthLossReference, 0.1, 1000)
assert(type(Config.AutoDamage.events) == 'table', 'Config.AutoDamage.events must be a table')
validateAutoDamageEvent('gunshot', Config.AutoDamage.events.gunshot)
validateAutoDamageEvent('melee', Config.AutoDamage.events.melee)
validateAutoDamageEvent('vehicle_crash', Config.AutoDamage.events.vehicle_crash)
validateAutoDamageEvent('explosion', Config.AutoDamage.events.explosion)
assert(type(Config.Commands) == 'table', 'Config.Commands must be a table')
assert(type(Config.Commands.enabled) == 'boolean', 'Config.Commands.enabled must be true or false')
assert(type(Config.Commands.restricted) == 'boolean', 'Config.Commands.restricted must be true or false')
validateCommandName('Config.Commands.setDamage', Config.Commands.setDamage)
validateCommandName('Config.Commands.escalateDamage', Config.Commands.escalateDamage)
validateCommandName('Config.Commands.setDamageAll', Config.Commands.setDamageAll)
validateCommandName('Config.Commands.setDamageArea', Config.Commands.setDamageArea)
validateCommandName('Config.Commands.setDamageColor', Config.Commands.setDamageColor)
validateCommandName('Config.Commands.repair', Config.Commands.repair)
validateCommandName('Config.Commands.unhack', Config.Commands.unhack)
validateCommandName('Config.Commands.repairAll', Config.Commands.repairAll)
validateCommandName('Config.Commands.legacySetDamage', Config.Commands.legacySetDamage, true)
validateCommandName('Config.Commands.legacyRepair', Config.Commands.legacyRepair, true)
assertInteger('Config.MaxPhoneNumberLength', Config.MaxPhoneNumberLength, 1)
assert(Config.MaxPhoneNumberLength <= 32,
    'Config.MaxPhoneNumberLength must not exceed the VARCHAR(32) database schema')
assertInteger('Config.MaxDamageAreaRadius', Config.MaxDamageAreaRadius, 1)
