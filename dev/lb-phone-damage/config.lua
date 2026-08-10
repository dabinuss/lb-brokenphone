Config = {}

-- Enables additional diagnostic output in the client and server consoles.
Config.Debug = false

-- Global crack color for every player. Allowed values: 'black' or 'white'.
Config.DamageColor = 'black'

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
