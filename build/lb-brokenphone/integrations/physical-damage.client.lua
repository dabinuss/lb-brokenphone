-- Purely a passive observer, same contract as fire-damage.client.lua: it
-- watches for combat hits and vehicle crashes and reports them, but never
-- decides anything. physical-damage.server.lua re-verifies every report
-- against damage-evidence.server.lua's own observations before applying any
-- phone damage.
if not Config.AutoDamage.enabled then return end

local Shared = LBBrokenPhoneDamageShared
local lastReportedAt = {}
-- Cache of the player's own vitality, refreshed every vehicle-poll tick, so
-- the CEventNetworkEntityDamage handler below has a recent "before" value
-- without needing its own separate polling loop.
local lastCombatVitality = nil

-- joaat() hashes can come back as values Lua reads as negative (32-bit
-- wraparound); normalise into a plain 0..4294967295 range so weapon/group
-- hashes always land on the same table key regardless of sign
-- interpretation. Duplicated from damage-evidence.server.lua -- the client
-- cannot require a *.server.lua file, so there is no shared source of truth
-- for this or the weapon lists below; keep both in sync by hand.
local function canonicalHash(value)
    value = tonumber(value)
    if not value then return nil end
    value = value % 4294967296
    if value < 0 then value = value + 4294967296 end
    return value
end

local function hashSet(names)
    local values = {}
    for i = 1, #names do values[canonicalHash(joaat(names[i]))] = true end
    return values
end

-- Individually-named weapons that always count as explosive regardless of
-- their weapon group (see damage-evidence.server.lua for the full weapon
-- classification and its DLC-maintenance caveat).
local explosiveWeapons = hashSet({
    'WEAPON_GRENADE',
    'WEAPON_GRENADELAUNCHER',
    'WEAPON_COMPACTLAUNCHER',
    'WEAPON_STICKYBOMB',
    'WEAPON_PROXMINE',
    'WEAPON_PIPEBOMB',
    'WEAPON_RPG',
    'WEAPON_HOMINGLAUNCHER',
    'WEAPON_RAILGUN',
    'WEAPON_RAILGUNXM3',
    'WEAPON_EXPLOSION',
    'WEAPON_VEHICLE_ROCKET',
    'WEAPON_AIRSTRIKE_ROCKET',
    'WEAPON_PASSENGER_ROCKET',
    'WEAPON_HELI_CRASH',
    'WEAPON_FIREWORK',
    'WEAPON_EMPLAUNCHER'
})

-- Everything else is classified by GetWeapontypeGroup() instead of by name,
-- since the client only needs a rough melee/gunshot split here -- the
-- server does the authoritative, per-weapon classification independently.
local meleeGroups = hashSet({ 'GROUP_UNARMED', 'GROUP_MELEE' })
local firearmGroups = hashSet({
    'GROUP_PISTOL',
    'GROUP_SMG',
    'GROUP_RIFLE',
    'GROUP_MG',
    'GROUP_SHOTGUN',
    'GROUP_SNIPER',
    'GROUP_HEAVY'
})

local function readVitality(ped)
    return math.max(0, GetEntityHealth(ped) - 100) + math.max(0, GetPedArmour(ped))
end

-- Sends a raw damage report to the server. Debounced per cause
-- (Config.AutoDamage.clientDebounce) purely to avoid flooding the network
-- with reports the server would just rate-limit anyway -- this is a
-- courtesy limit, not a security one; physical-damage.server.lua enforces
-- its own limits independently.
local function reportPhysicalDamage(cause, severity)
    local eventConfig = Config.AutoDamage.events[cause]
    if not eventConfig or not eventConfig.enabled then return end

    local now = GetGameTimer()
    local previous = lastReportedAt[cause]
    if previous and now >= previous and now - previous < Config.AutoDamage.clientDebounce then return end
    lastReportedAt[cause] = now
    TriggerServerEvent(
        'lb-brokenphone:server:physicalDamage',
        cause,
        Shared.normalizeSeverity(severity)
    )
end

-- CEventNetworkEntityDamage's args carry the weapon hash at different
-- indices depending on the damage type; index 7 covers most cases, 5 is the
-- fallback for the rest. If neither is a valid weapon, falls back to
-- whatever weapon the attacking ped currently has selected (best-effort for
-- damage types that don't report a weapon at all, e.g. some melee/vehicle
-- impacts).
local function resolveDamageWeapon(args)
    for _, index in ipairs({ 7, 5 }) do
        local candidate = tonumber(args[index])
        if candidate and candidate ~= 0 and IsWeaponValid(candidate) then return candidate end
    end

    local attacker = tonumber(args[2]) or 0
    if attacker > 0 and DoesEntityExist(attacker) and IsEntityAPed(attacker) then
        local weapon = GetSelectedPedWeapon(attacker)
        if weapon and weapon ~= 0 and IsWeaponValid(weapon) then return weapon end
    end
    return nil
end

local function classifyWeapon(weapon)
    if not weapon then return nil end
    if explosiveWeapons[canonicalHash(weapon)] then return 'explosion' end

    local group = canonicalHash(GetWeapontypeGroup(weapon))
    if meleeGroups[group] then return 'melee' end
    if firearmGroups[group] then return 'gunshot' end
    return nil
end

-- Fires on every damage event the game engine reports for any entity;
-- filtered down to "did this happen to my own ped". Vitality is sampled
-- once right away (SetTimeout(0), i.e. next tick, so the engine has applied
-- the damage) and again after Config.AutoDamage.snapshotInterval + 50ms --
-- matching the delay damage-evidence.server.lua uses for its own before/
-- after sample -- so the severity reported here lines up with the window
-- the server will check evidence against.
AddEventHandler('gameEventTriggered', function(name, args)
    if name ~= 'CEventNetworkEntityDamage' then return end

    local ped = PlayerPedId()
    if tonumber(args[1]) ~= ped then return end
    local cause = classifyWeapon(resolveDamageWeapon(args))
    if not cause then return end

    local before = lastCombatVitality or readVitality(ped)
    SetTimeout(0, function()
        if ped ~= PlayerPedId() then return end
        local after = readVitality(ped)
        lastCombatVitality = after
        local vitalityLoss = before - after
        if vitalityLoss <= 0 then return end
        SetTimeout(Config.AutoDamage.snapshotInterval + 50, function()
            reportPhysicalDamage(cause, vitalityLoss / Config.AutoDamage.damageReference)
        end)
    end)
end)

-- Vehicle crash detection loop. While in a vehicle, polls speed and body
-- health each tick to spot a sudden speed loss combined with an actual
-- collision (HasEntityCollidedWithAnything) -- that opens a short "impact
-- window" (Config.AutoDamage.vehicle.impactWindow). Only once body health
-- has dropped enough within that window is it treated as a real crash and
-- reported; this two-step check (collision + speed loss, then confirmed
-- body damage) avoids reporting e.g. hard braking or scraping a wall
-- without real damage as a crash. Severity is the worst of speed loss, body
-- damage, and the player's own vitality loss, each normalised against its
-- own configured reference value.
CreateThread(function()
    local vehicleState = nil
    while true do
        local ped = PlayerPedId()
        lastCombatVitality = readVitality(ped)

        if not IsPedInAnyVehicle(ped, false) then
            vehicleState = nil
            Wait(Config.AutoDamage.vehicle.idlePollInterval)
        else
            local vehicle = GetVehiclePedIsIn(ped, false)
            if not vehicleState or vehicleState.vehicle ~= vehicle then
                TriggerServerEvent('lb-brokenphone:server:vehicleEntered')
            end
            local speed = GetEntitySpeed(vehicle)
            local bodyHealth = GetVehicleBodyHealth(vehicle)
            local vitality = readVitality(ped)
            local impact = vehicleState and vehicleState.vehicle == vehicle and vehicleState.impact or nil

            if vehicleState and vehicleState.vehicle == vehicle then
                local now = GetGameTimer()
                local speedLoss = math.max(0.0, vehicleState.speed - speed)
                if vehicleState.speed >= Config.AutoDamage.vehicle.minSpeed
                    and speedLoss >= Config.AutoDamage.vehicle.minSpeedLoss
                    and HasEntityCollidedWithAnything(vehicle) then
                    impact = {
                        expiresAt = now + Config.AutoDamage.vehicle.impactWindow,
                        speedLoss = speedLoss,
                        bodyHealth = vehicleState.bodyHealth,
                        vitality = vehicleState.vitality
                    }
                end

                if impact and now <= impact.expiresAt then
                    impact.speedLoss = math.max(impact.speedLoss, speedLoss)
                    local bodyHealthLoss = math.max(0.0, impact.bodyHealth - bodyHealth)
                    local vitalityLoss = math.max(0.0, impact.vitality - vitality)
                    if bodyHealthLoss >= Config.AutoDamage.vehicle.minBodyHealthLoss then
                        local severity = math.max(
                            impact.speedLoss / Config.AutoDamage.vehicle.speedLossReference,
                            bodyHealthLoss / Config.AutoDamage.vehicle.bodyHealthLossReference,
                            vitalityLoss / Config.AutoDamage.damageReference
                        )
                        reportPhysicalDamage('vehicle_crash', severity)
                        impact = nil
                    end
                elseif impact then
                    impact = nil
                end
            end

            vehicleState = {
                vehicle = vehicle,
                speed = speed,
                bodyHealth = bodyHealth,
                vitality = vitality,
                impact = impact
            }
            Wait(Config.AutoDamage.vehicle.pollInterval)
        end
    end
end)
