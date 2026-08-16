local Shared = LBBrokenPhoneDamageShared
local weaponEvidence = {}
local pendingWeaponSamples = {}
local fireSessions = {}
local vehicleBaselines = {}
local recentFireWeaponAt = {}
local recentExplosions = {}

LBBrokenPhoneDamageEvidence = LBBrokenPhoneDamageEvidence or {}

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

local function classifyWeapon(weaponType)
    local weapon = canonicalHash(weaponType)
    if not weapon or weapon == 0 then return nil end
    if fireWeapons[weapon] then return 'fire' end
    if explosiveWeapons[weapon] then return 'explosion' end
    if meleeWeapons[weapon] then return 'melee' end
    if firearmWeapons[weapon] then return 'gunshot' end
    return nil
end

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

local function findRecentExplosion(playerSource, earliestAt, maximumAge)
    local state = readPlayerState(playerSource, false)
    if not state then return nil end
    return findRecentExplosionAt(state.coords, earliestAt, maximumAge)
end

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

function LBBrokenPhoneDamageEvidence.beginVehicle(playerSource)
    local state = readPlayerState(playerSource, true)
    if not state or state.vehicle <= 0 then return false end
    vehicleBaselines[playerSource] = {
        vehicle = state.vehicle,
        bodyHealth = tonumber(state.vehicleBodyHealth) or 1000.0
    }
    return true
end

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

function LBBrokenPhoneDamageEvidence.cancelFire(playerSource)
    fireSessions[playerSource] = nil
end

function LBBrokenPhoneDamageEvidence.clearPlayer(playerSource)
    weaponEvidence[playerSource] = nil
    pendingWeaponSamples[playerSource] = nil
    fireSessions[playerSource] = nil
    vehicleBaselines[playerSource] = nil
    recentFireWeaponAt[playerSource] = nil
end

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
