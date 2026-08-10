Config = {}

-- Enables additional diagnostic output in the client and server consoles.
Config.Debug = false

-- Global crack color for every player. Allowed values: 'black' or 'white'.
Config.DamageColor = 'white'

Config.Database = {
    tableName = 'phone_damage',              -- SQL table used for persistent phone damage.
    jsonFile = 'data/phone_damage.json',     -- Resource-relative fallback file when oxmysql is unavailable.
    allowJsonFallback = true                 -- Use the JSON file instead of failing when oxmysql is not started.
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

Config.Commands = {
    enabled = true,                         -- Register test/admin commands; production exports remain available when false.
    restricted = false,                    -- Require matching ACE permissions for damage and repair commands.
    setDamage = 'phonedamage',              -- Command used to set damage level 1-3.
    setDamageColor = 'phonedamagecolor',    -- Global color command; always requires command.phonedamagecolor ACE.
    repair = 'phonerepair',                 -- Command used to remove all damage from a phone.
    legacySetDamage = 'brokenphone',        -- Backward-compatible damage alias; set to false to disable.
    legacyRepair = 'brokenphonerepair'      -- Backward-compatible repair alias; set to false to disable.
}

-- Maximum accepted phone-number length. Keep this aligned with VARCHAR(32) in database.sql.
Config.MaxPhoneNumberLength = 32

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

assert(Config.DamageColor == 'black' or Config.DamageColor == 'white',
    "Config.DamageColor must be 'black' or 'white'")
assert(type(Config.Debug) == 'boolean', 'Config.Debug must be true or false')
assert(type(Config.Database) == 'table', 'Config.Database must be a table')
assert(type(Config.Database.tableName) == 'string' and Config.Database.tableName:match('^[%w_]+$'),
    'Config.Database.tableName may only contain letters, numbers, and underscores')
assert(type(Config.Database.jsonFile) == 'string' and Config.Database.jsonFile ~= '',
    'Config.Database.jsonFile must be a non-empty resource-relative path')
assert(type(Config.Database.allowJsonFallback) == 'boolean',
    'Config.Database.allowJsonFallback must be true or false')
assert(type(Config.Transition) == 'table', 'Config.Transition must be a table')
assertInteger('Config.Transition.openDuration', Config.Transition.openDuration, 0)
assertInteger('Config.Transition.closeDuration', Config.Transition.closeDuration, 0)
assert(type(Config.Touch) == 'table', 'Config.Touch must be a table')
assert(type(Config.Touch.enabled) == 'boolean', 'Config.Touch.enabled must be true or false')
validateTouchProfile('medium', Config.Touch.medium)
validateTouchProfile('severe', Config.Touch.severe)
assert(type(Config.Commands) == 'table', 'Config.Commands must be a table')
assert(type(Config.Commands.enabled) == 'boolean', 'Config.Commands.enabled must be true or false')
assert(type(Config.Commands.restricted) == 'boolean', 'Config.Commands.restricted must be true or false')
validateCommandName('Config.Commands.setDamage', Config.Commands.setDamage)
validateCommandName('Config.Commands.setDamageColor', Config.Commands.setDamageColor)
validateCommandName('Config.Commands.repair', Config.Commands.repair)
validateCommandName('Config.Commands.legacySetDamage', Config.Commands.legacySetDamage, true)
validateCommandName('Config.Commands.legacyRepair', Config.Commands.legacyRepair, true)
assertInteger('Config.MaxPhoneNumberLength', Config.MaxPhoneNumberLength, 1)
assert(Config.MaxPhoneNumberLength <= 32,
    'Config.MaxPhoneNumberLength must not exceed the VARCHAR(32) database schema')
