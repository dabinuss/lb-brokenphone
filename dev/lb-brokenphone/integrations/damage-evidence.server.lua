-- Server-side evidence store for the auto-damage/auto-fire integrations.
--
-- physical-damage.client.lua / fire-damage.client.lua only ever *report* that
-- something happened (a hit landed, a fire started). Nothing they say is
-- trusted on its own -- a modified client could trigger those network events
-- with fabricated causes/severities at will. This module independently
-- observes the same moment through server-authoritative game state (health
-- deltas measured here, vehicle body health, weaponDamageEvent/explosionEvent
-- natives) and only lets a report through if the server's own observation
-- agrees with it. physical-damage.server.lua / fire-damage.server.lua then
-- decide *whether* that verified severity actually results in phone damage
-- (chance roll, cooldowns); this file only decides *whether the claim is real*.
local Shared = LBBrokenPhoneDamageShared
local weaponEvidence = {}
local pendingWeaponSamples = {}
local fireSessions = {}
local vehicleBaselines = {}
local recentFireWeaponAt = {}
local recentExplosions = {}

LBBrokenPhoneDamageEvidence = LBBrokenPhoneDamageEvidence or {}

-- joaat() hashes can come back as values Lua reads as negative (32-bit
-- wraparound); normalise into a plain 0..4294967295 range so weapon hashes
-- always land on the same table key regardless of sign interpretation.
local function canonicalHash(value)
    value = tonumber(value)
    if not value then return nil end
    value = value % 4294967296
    if value < 0 then value = value + 4294967296 end
    return value
end

-- Builds a { [canonicalHash(joaat(name))] = true } lookup set from a list of
-- weapon model names, so classifyWeapon() below can test membership in O(1).
local function hashSet(names)
    local values = {}
    for i = 1, #names do values[canonicalHash(joaat(names[i]))] = true end
    return values
end

-- Weapon classification lists. These decide which Config.AutoDamage.events
-- key (or 'fire' for the separate fire-damage integration) a given weapon
-- maps to. Rockstar adds new weapons with DLC updates -- if a new weapon
-- isn't in the right list here, hits with it are simply never classified and
-- never reported. Keep this in sync with the equivalent lists in
-- physical-damage.client.lua (duplicated there because the client cannot
-- require a *.server.lua file; there is no shared source of truth for these).
local meleeWeapons = hashSet({
    'WEAPON_UNARMED', 'WEAPON_KNIFE', 'WEAPON_NIGHTSTICK', 'WEAPON_HAMMER',
    'WEAPON_BAT', 'WEAPON_GOLFCLUB', 'WEAPON_CROWBAR', 'WEAPON_BOTTLE',
    'WEAPON_DAGGER', 'WEAPON_HATCHET', 'WEAPON_KNUCKLE', 'WEAPON_MACHETE',
    'WEAPON_FLASHLIGHT', 'WEAPON_SWITCHBLADE', 'WEAPON_POOLCUE',
    'WEAPON_WRENCH', 'WEAPON_BATTLEAXE', 'WEAPON_STONE_HATCHET',
    'WEAPON_CANDYCANE', 'WEAPON_ANIMAL', 'WEAPON_COUGAR'
})

local fireWeapons = hashSet({
    'WEAPON_FIRE', 'WEAPON_MOLOTOV', 'WEAPON_PETROLCAN',
    'WEAPON_HAZARDCAN', 'WEAPON_FERTILIZERCAN', 'WEAPON_FLARE', 'WEAPON_FLAREGUN'
})

local explosiveWeapons = hashSet({
    'WEAPON_GRENADE', 'WEAPON_GRENADELAUNCHER', 'WEAPON_COMPACTLAUNCHER',
    'WEAPON_STICKYBOMB', 'WEAPON_PROXMINE', 'WEAPON_PIPEBOMB', 'WEAPON_RPG',
    'WEAPON_HOMINGLAUNCHER', 'WEAPON_RAILGUN', 'WEAPON_RAILGUNXM3',
    'WEAPON_EXPLOSION', 'WEAPON_VEHICLE_ROCKET', 'WEAPON_AIRSTRIKE_ROCKET',
    'WEAPON_PASSENGER_ROCKET', 'WEAPON_HELI_CRASH', 'WEAPON_FIREWORK',
    'WEAPON_EMPLAUNCHER'
})

local firearmWeapons = hashSet({
    'WEAPON_PISTOL', 'WEAPON_PISTOL_MK2', 'WEAPON_COMBATPISTOL', 'WEAPON_APPISTOL',
    'WEAPON_PISTOL50', 'WEAPON_SNSPISTOL', 'WEAPON_SNSPISTOL_MK2', 'WEAPON_HEAVYPISTOL',
    'WEAPON_VINTAGEPISTOL', 'WEAPON_MARKSMANPISTOL', 'WEAPON_REVOLVER',
    'WEAPON_REVOLVER_MK2', 'WEAPON_DOUBLEACTION', 'WEAPON_RAYPISTOL',
    'WEAPON_CERAMICPISTOL', 'WEAPON_NAVYREVOLVER', 'WEAPON_GADGETPISTOL',
    'WEAPON_PISTOLXM3', 'WEAPON_TECPISTOL', 'WEAPON_STUNGUN', 'WEAPON_STUNGUN_MP',
    'WEAPON_MICROSMG', 'WEAPON_SMG', 'WEAPON_SMG_MK2', 'WEAPON_ASSAULTSMG',
    'WEAPON_COMBATPDW', 'WEAPON_MACHINEPISTOL', 'WEAPON_MINISMG', 'WEAPON_RAYCARBINE',
    'WEAPON_PUMPSHOTGUN', 'WEAPON_PUMPSHOTGUN_MK2', 'WEAPON_SAWNOFFSHOTGUN',
    'WEAPON_ASSAULTSHOTGUN', 'WEAPON_BULLPUPSHOTGUN', 'WEAPON_MUSKET',
    'WEAPON_HEAVYSHOTGUN', 'WEAPON_DBSHOTGUN', 'WEAPON_AUTOSHOTGUN',
    'WEAPON_COMBATSHOTGUN', 'WEAPON_ASSAULTRIFLE', 'WEAPON_ASSAULTRIFLE_MK2',
    'WEAPON_CARBINERIFLE', 'WEAPON_CARBINERIFLE_MK2', 'WEAPON_ADVANCEDRIFLE',
    'WEAPON_SPECIALCARBINE', 'WEAPON_SPECIALCARBINE_MK2', 'WEAPON_BULLPUPRIFLE',
    'WEAPON_BULLPUPRIFLE_MK2', 'WEAPON_COMPACTRIFLE', 'WEAPON_MILITARYRIFLE',
    'WEAPON_HEAVYRIFLE', 'WEAPON_TACTICALRIFLE', 'WEAPON_MG', 'WEAPON_COMBATMG',
    'WEAPON_COMBATMG_MK2', 'WEAPON_GUSENBERG', 'WEAPON_SNIPERRIFLE',
    'WEAPON_HEAVYSNIPER', 'WEAPON_HEAVYSNIPER_MK2', 'WEAPON_MARKSMANRIFLE',
    'WEAPON_MARKSMANRIFLE_MK2', 'WEAPON_PRECISIONRIFLE', 'WEAPON_MINIGUN',
    'WEAPON_RAYMINIGUN'
})

-- Maps a weapon hash to the Config.AutoDamage.events cause it counts as, or
-- 'fire' (handled by the separate fire-damage integration instead). Returns
-- nil for unclassified/unknown weapons -- those hits are silently ignored.
local function classifyWeapon(weaponType)
    local weapon = canonicalHash(weaponType)
    if not weapon or weapon == 0 then return nil end
    if fireWeapons[weapon] then return 'fire' end
    if explosiveWeapons[weapon] then return 'explosion' end
    if meleeWeapons[weapon] then return 'melee' end
    if firearmWeapons[weapon] then return 'gunshot' end
    return nil
end

-- Snapshot of a player's current health/armour/position (and optionally
-- their vehicle's body health), read directly from natives. Wrapped in pcall
-- because the ped/vehicle can disappear between the check and the read.
local function readPlayerState(playerSource, includeVehicle)
    local ok, state = pcall(function()
        local ped = GetPlayerPed(playerSource)
        if not ped or ped <= 0 or not DoesEntityExist(ped) then return nil end

        local health = math.max(0, GetEntityHealth(ped) - 100)
        local armour = math.max(0, GetPedArmour(ped))
        local result = {
            ped = ped,
            health = health,
            vitality = health + armour,
            coords = GetEntityCoords(ped)
        }
        if includeVehicle then
            local vehicle = GetVehiclePedIsIn(ped, false)
            result.vehicle = vehicle and vehicle > 0 and vehicle or 0
            result.vehicleBodyHealth = result.vehicle > 0 and GetVehicleBodyHealth(result.vehicle) or 1000.0
        end
        return result
    end)
    return ok and state or nil
end

-- weaponDamageEvent reports the victim as a network ID, not a player source.
-- Resolves it back to a player source, and only if that network ID's owning
-- entity really is a player ped (rules out NPCs/props sharing the same id
-- space).
local function resolveVictimSource(networkId)
    networkId = tonumber(networkId)
    if not networkId or networkId <= 0 then return nil end

    local ok, playerSource = pcall(function()
        local entity = NetworkGetEntityFromNetworkId(networkId)
        if not entity or entity <= 0 or not DoesEntityExist(entity) then return nil end
        local owner = NetworkGetEntityOwner(entity)
        if not owner or owner <= 0 or GetPlayerPed(owner) ~= entity then return nil end
        return owner
    end)
    return ok and tonumber(playerSource) or nil
end

-- weaponDamageEvent can report either a single hitGlobalId or a
-- hitGlobalIds array (e.g. explosions/shotguns hitting multiple peds in one
-- event); this normalises both shapes into a deduplicated list of player
-- sources.
local function collectVictimSources(event)
    local sources = {}
    local seen = {}
    local ids = type(event.hitGlobalIds) == 'table' and event.hitGlobalIds or nil
    if not ids or #ids == 0 then ids = { event.hitGlobalId } end
    for i = 1, #ids do
        local playerSource = resolveVictimSource(ids[i])
        if playerSource and not seen[playerSource] then
            seen[playerSource] = true
            sources[#sources + 1] = playerSource
        end
    end
    return sources
end

-- Tracks how many in-flight before/after samples are pending for a given
-- (player, cause) pair, so recordWeaponHit() below can skip starting a new
-- sample while one is already running instead of stacking timers.
local function changePendingWeaponSamples(playerSource, cause, delta)
    local byCause = pendingWeaponSamples[playerSource]
    if not byCause then
        if delta <= 0 then return end
        byCause = {}
        pendingWeaponSamples[playerSource] = byCause
    end
    byCause[cause] = math.max(0, (byCause[cause] or 0) + delta)
    if byCause[cause] == 0 then byCause[cause] = nil end
    if not next(byCause) then pendingWeaponSamples[playerSource] = nil end
end

-- Called from the weaponDamageEvent handler below when a gunshot/melee hit
-- lands. Rather than trusting the hit event alone (it fires even for blocked/
-- armour-absorbed hits with zero real damage), this takes a health+armour
-- snapshot now, waits Config.AutoDamage.snapshotInterval, then takes another
-- snapshot and only records evidence if vitality actually dropped. 'fire'
-- causes are handled separately (see recentFireWeaponAt) since fire damage
-- accrues over time rather than in a single hit.
local function recordWeaponHit(playerSource, cause)
    local now = GetGameTimer()
    if cause == 'fire' then
        recentFireWeaponAt[playerSource] = now
        return
    end
    if cause ~= 'gunshot' and cause ~= 'melee' then return end

    local pending = pendingWeaponSamples[playerSource]
    if pending and pending[cause] then return end
    local before = readPlayerState(playerSource, false)
    if not before then return end

    changePendingWeaponSamples(playerSource, cause, 1)
    SetTimeout(Config.AutoDamage.snapshotInterval, function()
        local after = readPlayerState(playerSource, false)
        changePendingWeaponSamples(playerSource, cause, -1)
        if not after or after.ped ~= before.ped then return end

        local vitalityLoss = math.max(0, before.vitality - after.vitality)
        if vitalityLoss <= 0 then return end
        local byCause = weaponEvidence[playerSource]
        if not byCause then
            byCause = {}
            weaponEvidence[playerSource] = byCause
        end
        local previous = byCause[cause]
        byCause[cause] = {
            at = GetGameTimer(),
            vitalityLoss = math.max(vitalityLoss, previous and previous.vitalityLoss or 0)
        }
    end)
end

-- Finds the closest recorded explosion within `radius` of `coords` that
-- happened between `earliestAt` and `maximumAge` ago. Explosions are kept
-- around longer than `maximumAge` when fire-cause-evidence is enabled
-- (`retention`), because a fire started by an explosion can be reported by
-- the client noticeably later than the explosion itself; this also doubles
-- as the list's garbage collection, dropping anything older than retention
-- on every call.
local function findRecentExplosionAt(coords, earliestAt, maximumAge)
    local now = GetGameTimer()
    local radius = Config.AutoDamage.explosionEvidenceRadius
    maximumAge = maximumAge or Config.AutoDamage.evidenceWindow
    local retention = Config.AutoFireDamage.enabled
        and Config.AutoFireDamage.requireCauseEvidence and 120000
        or Config.AutoDamage.evidenceWindow
    local retained = {}
    local best, bestDistanceSquared = nil, math.huge
    for i = 1, #recentExplosions do
        local explosion = recentExplosions[i]
        if Shared.elapsed(now, explosion.at) <= retention then
            retained[#retained + 1] = explosion
            if Shared.elapsed(now, explosion.at) <= maximumAge
                and (not earliestAt or explosion.at >= earliestAt) then
                local dx = coords.x - explosion.x
                local dy = coords.y - explosion.y
                local dz = coords.z - explosion.z
                local distanceSquared = dx * dx + dy * dy + dz * dz
                if distanceSquared <= radius * radius and distanceSquared < bestDistanceSquared then
                    best, bestDistanceSquared = explosion, distanceSquared
                end
            end
        end
    end
    recentExplosions = retained
    if not best then return nil end
    best.distance = math.sqrt(bestDistanceSquared)
    return best
end

-- Same as findRecentExplosionAt, but resolves the player's current position
-- first (used when checking "was this player near an explosion just now?").
local function findRecentExplosion(playerSource, earliestAt, maximumAge)
    local state = readPlayerState(playerSource, false)
    if not state then return nil end
    return findRecentExplosionAt(state.coords, earliestAt, maximumAge)
end

-- Blocks (in small polling steps) until recordWeaponHit()'s before/after
-- sample for this (player, cause) either lands in weaponEvidence or times
-- out. Used by verifyPhysical so a physicalDamage report doesn't have to
-- race the snapshot timer -- it just waits for the verdict.
local function waitForWeaponEvidence(playerSource, cause)
    local deadline = GetGameTimer() + Config.AutoDamage.snapshotInterval + 100
    while true do
        local evidence = weaponEvidence[playerSource] and weaponEvidence[playerSource][cause]
        if evidence and Shared.elapsed(GetGameTimer(), evidence.at) <= Config.AutoDamage.evidenceWindow then
            return evidence
        end
        local pending = pendingWeaponSamples[playerSource]
        if not pending or not pending[cause] or GetGameTimer() >= deadline then return nil end
        Wait(25)
    end
end

-- Public API -----------------------------------------------------------

-- Verifies a physicalDamage report (see physical-damage.server.lua).
-- Cross-checks the client-reported severity against server-observed
-- evidence for the given cause (gunshot/melee hit evidence, a nearby
-- explosion, or vehicle body-health loss) and returns the *lower* of the two
-- as the trusted severity -- so a client can only ever under-report, never
-- inflate. Returns nil plus a short reason string if no matching evidence
-- exists or the verified severity doesn't clear the event's minSeverity.
function LBBrokenPhoneDamageEvidence.verifyPhysical(playerSource, cause, clientSeverity)
    local eventConfig = type(cause) == 'string' and Config.AutoDamage.events[cause] or nil
    if not eventConfig then return nil, 'invalid_cause' end

    local observedSeverity
    if cause == 'gunshot' or cause == 'melee' then
        local evidence = waitForWeaponEvidence(playerSource, cause)
        if not evidence then return nil, 'missing_weapon_evidence' end
        observedSeverity = evidence.vitalityLoss / Config.AutoDamage.damageReference
        weaponEvidence[playerSource][cause] = nil
        if not next(weaponEvidence[playerSource]) then weaponEvidence[playerSource] = nil end
    elseif cause == 'explosion' then
        local explosion = findRecentExplosion(playerSource, nil, Config.AutoDamage.evidenceWindow)
        if not explosion then return nil, 'missing_explosion_evidence' end
        local proximity = math.max(0.0, 1.0 - explosion.distance / Config.AutoDamage.explosionEvidenceRadius)
        observedSeverity = proximity * explosion.damageScale
    elseif cause == 'vehicle_crash' then
        local state = readPlayerState(playerSource, true)
        if not state or state.vehicle <= 0 then return nil, 'player_not_in_vehicle' end
        local bodyHealth = tonumber(state.vehicleBodyHealth) or 1000.0
        local baseline = vehicleBaselines[playerSource]
        if not baseline or baseline.vehicle ~= state.vehicle then
            vehicleBaselines[playerSource] = { vehicle = state.vehicle, bodyHealth = bodyHealth }
            return nil, 'missing_vehicle_baseline'
        end

        local bodyHealthLoss = math.max(0.0, baseline.bodyHealth - bodyHealth)
        -- Consume every observed delta so old vehicle damage cannot be replayed.
        baseline.bodyHealth = bodyHealth
        if bodyHealthLoss < Config.AutoDamage.vehicle.minBodyHealthLoss then
            return nil, 'vehicle_damage_too_low'
        end
        observedSeverity = bodyHealthLoss / Config.AutoDamage.vehicle.bodyHealthLossReference
    else
        return nil, 'invalid_cause'
    end

    local severity = math.min(
        Shared.normalizeSeverity(clientSeverity),
        Shared.normalizeSeverity(observedSeverity)
    )
    if severity < eventConfig.minSeverity then return nil, 'severity_too_low' end
    return severity
end

-- Records a fresh vehicle body-health baseline for the player, to diff
-- against later. Called both when the client reports entering a vehicle and
-- lazily from verifyPhysical() the first time a vehicle_crash report arrives
-- without one.
function LBBrokenPhoneDamageEvidence.beginVehicle(playerSource)
    local state = readPlayerState(playerSource, true)
    if not state or state.vehicle <= 0 then return false end
    vehicleBaselines[playerSource] = {
        vehicle = state.vehicle,
        bodyHealth = tonumber(state.vehicleBodyHealth) or 1000.0
    }
    return true
end

-- Opens a fire-tracking session for the player (health/coords baseline at
-- the moment fire started). A session that's still open and under two
-- minutes old is left alone so a flickering on-fire state doesn't reset the
-- baseline mid-burn.
function LBBrokenPhoneDamageEvidence.beginFire(playerSource)
    local now = GetGameTimer()
    local session = fireSessions[playerSource]
    if session and Shared.elapsed(now, session.startedAt) <= 120000 then return false end

    local state = readPlayerState(playerSource, false)
    if not state then return false end
    fireSessions[playerSource] = {
        ped = state.ped,
        startedAt = now,
        startHealth = state.health,
        startCoords = state.coords
    }
    return true
end

-- Verifies a fireDamage report (see fire-damage.server.lua) against the
-- session opened by beginFire(). Closes the session either way (a session
-- can only be verified once). Returns the trusted (healthLoss, duration)
-- pair -- each clamped to whatever the server itself observed, so a report
-- can only ever be discounted, never inflated -- or nil plus a reason string.
-- When Config.AutoFireDamage.requireCauseEvidence is set, also demands a
-- recent fire weapon hit or nearby explosion as the fire's origin.
function LBBrokenPhoneDamageEvidence.verifyFire(playerSource, reportedHealthLoss, reportedDuration)
    local session = fireSessions[playerSource]
    fireSessions[playerSource] = nil
    if not session then return nil, nil, 'missing_fire_session' end

    local now = GetGameTimer()
    local state = readPlayerState(playerSource, false)
    if not state or state.ped ~= session.ped then return nil, nil, 'invalid_fire_session' end

    local sessionDuration = Shared.elapsed(now, session.startedAt)
    if sessionDuration > 120000 then return nil, nil, 'fire_session_expired' end
    local observedLoss = math.max(0, session.startHealth - state.health)
    if observedLoss <= 0 then return nil, nil, 'missing_health_loss' end

    if Config.AutoFireDamage.requireCauseEvidence then
        local causeTolerance = Config.AutoFireDamage.idlePollInterval + Config.AutoDamage.snapshotInterval
        local weaponAt = recentFireWeaponAt[playerSource]
        local hasFireWeapon = weaponAt and weaponAt >= session.startedAt - causeTolerance
            and Shared.elapsed(now, weaponAt) <= 120000
        local hasExplosion = findRecentExplosionAt(
            session.startCoords,
            session.startedAt - causeTolerance,
            120000
        ) ~= nil
        if not hasFireWeapon and not hasExplosion then return nil, nil, 'missing_fire_cause_evidence' end
    end

    recentFireWeaponAt[playerSource] = nil
    local healthLoss = math.min(Shared.clampNumber(reportedHealthLoss, 0, 1000), observedLoss)
    local duration = math.min(Shared.clampNumber(reportedDuration, 0, 120000), sessionDuration)
    return healthLoss, math.floor(duration)
end

-- Discards an open fire session without verifying it (used when a report is
-- rejected upstream, e.g. by fire-damage.server.lua's network rate limit, so
-- a stale session can't later be verified against a newer, unrelated fire).
function LBBrokenPhoneDamageEvidence.cancelFire(playerSource)
    fireSessions[playerSource] = nil
end

-- Drops all per-player evidence state. Called on playerDropped below;
-- exported implicitly through the handler rather than directly.
function LBBrokenPhoneDamageEvidence.clearPlayer(playerSource)
    weaponEvidence[playerSource] = nil
    pendingWeaponSamples[playerSource] = nil
    fireSessions[playerSource] = nil
    vehicleBaselines[playerSource] = nil
    recentFireWeaponAt[playerSource] = nil
end

-- Global FiveM native events -- every resource on the server receives these,
-- this handler just listens passively and never trusts anything the client
-- says about them.
AddEventHandler('weaponDamageEvent', function(_, event)
    if type(event) ~= 'table' then return end
    local cause = classifyWeapon(event.weaponType)
    if not cause then return end
    if cause == 'fire' and (not Config.AutoFireDamage.enabled
        or not Config.AutoFireDamage.requireCauseEvidence) then return end
    if cause ~= 'fire' and not Config.AutoDamage.enabled then return end
    local victims = collectVictimSources(event)
    for i = 1, #victims do recordWeaponHit(victims[i], cause) end
end)

AddEventHandler('explosionEvent', function(_, event)
    local trackFireEvidence = Config.AutoFireDamage.enabled
        and Config.AutoFireDamage.requireCauseEvidence
    if (not Config.AutoDamage.enabled and not trackFireEvidence)
        or type(event) ~= 'table' then return end
    local x, y, z = tonumber(event.posX), tonumber(event.posY), tonumber(event.posZ)
    if not x or not y or not z then return end

    recentExplosions[#recentExplosions + 1] = {
        at = GetGameTimer(),
        x = x,
        y = y,
        z = z,
        damageScale = Shared.clampNumber(event.damageScale, 0.0, 1.0)
    }
    if #recentExplosions > 256 then table.remove(recentExplosions, 1) end
end)

AddEventHandler('playerDropped', function()
    LBBrokenPhoneDamageEvidence.clearPlayer(source)
end)
