local attemptCooldowns = {}
local lastSuccessfulDamage = {}
local lastNetworkReport = {}
local pendingDamage = {}
local lastFireAttempt = {}
local lastFireNetworkReport = {}
local pendingFireDamage = {}
local vitalitySnapshots = {}
local damageEvidence = {}
local fireEvidence = {}
local recentExplosions = {}

local function debugLog(message, ...)
    if not Config.AutoDamage.debug then return end
    print(('[lb-brokenphone][auto] ' .. message):format(...))
end

local function fireDebugLog(message, ...)
    if not Config.AutoFireDamage.debug then return end
    print(('[lb-brokenphone][auto-fire] ' .. message):format(...))
end

local function elapsed(now, previous)
    if not previous or now < previous then return math.huge end
    return now - previous
end

local function normalizeSeverity(value)
    value = tonumber(value) or 0.0
    if value ~= value then return 0.0 end
    return math.max(0.0, math.min(1.0, value))
end

local function readPlayerSnapshot(playerSource, now)
    local ok, snapshot = pcall(function()
        local ped = GetPlayerPed(playerSource)
        if not ped or ped <= 0 or not DoesEntityExist(ped) then return nil end
        local health = math.max(0, GetEntityHealth(ped) - 100)
        local armour = math.max(0, GetPedArmour(ped))
        local vehicle = GetVehiclePedIsIn(ped, false)
        local speed = vehicle and vehicle > 0 and GetEntitySpeed(vehicle) or 0.0
        return {
            at = now,
            ped = ped,
            health = health,
            vitality = health + armour,
            vehicle = vehicle and vehicle > 0 and vehicle or 0,
            speed = tonumber(speed) or 0.0
        }
    end)
    return ok and snapshot or nil
end

local function samplePlayer(playerSource, now)
    now = now or GetGameTimer()
    local current = readPlayerSnapshot(playerSource, now)
    local previous = vitalitySnapshots[playerSource]
    vitalitySnapshots[playerSource] = current
    if not current or not previous or current.ped ~= previous.ped
        or elapsed(now, previous.at) > Config.AutoDamage.evidenceWindow then return current end

    local vitalityLoss = math.max(0, previous.vitality - current.vitality)
    local healthLoss = math.max(0, previous.health - current.health)
    local speedLoss = previous.vehicle > 0 and previous.vehicle == current.vehicle
        and math.max(0.0, previous.speed - current.speed) or 0.0
    if vitalityLoss > 0 or speedLoss >= Config.AutoDamage.vehicle.minSpeedLoss then
        local evidence = damageEvidence[playerSource]
        if not evidence or elapsed(now, evidence.at) > Config.AutoDamage.evidenceWindow then
            evidence = { vitalityLoss = 0, healthLoss = 0, speedLoss = 0, inVehicle = false }
            damageEvidence[playerSource] = evidence
        end
        evidence.at = now
        evidence.vitalityLoss = evidence.vitalityLoss + vitalityLoss
        evidence.healthLoss = evidence.healthLoss + healthLoss
        evidence.speedLoss = math.max(evidence.speedLoss, speedLoss)
        evidence.inVehicle = evidence.inVehicle or previous.vehicle > 0 or current.vehicle > 0
    end

    if healthLoss > 0 then
        local evidence = fireEvidence[playerSource]
        local fireWindow = math.max(Config.AutoDamage.evidenceWindow,
            Config.AutoFireDamage.medium.minBurnDuration + Config.AutoFireDamage.incidentEndGrace + 1000)
        if not evidence or elapsed(now, evidence.at) > fireWindow then
            evidence = { healthLoss = 0, firstAt = now }
            fireEvidence[playerSource] = evidence
        end
        evidence.at = now
        evidence.healthLoss = evidence.healthLoss + healthLoss
    end
    return current
end

local function hasRecentExplosionNearby(playerSource, now)
    local ped = GetPlayerPed(playerSource)
    if not ped or ped <= 0 or not DoesEntityExist(ped) then return false end
    local coords = GetEntityCoords(ped)
    local radiusSquared = Config.AutoDamage.explosionEvidenceRadius ^ 2
    local retained = {}
    local matched = false
    for i = 1, #recentExplosions do
        local explosion = recentExplosions[i]
        if elapsed(now, explosion.at) <= Config.AutoDamage.evidenceWindow then
            retained[#retained + 1] = explosion
            local dx, dy, dz = coords.x - explosion.x, coords.y - explosion.y, coords.z - explosion.z
            if dx * dx + dy * dy + dz * dz <= radiusSquared then matched = true end
        end
    end
    recentExplosions = retained
    return matched
end

local function validateDamageEvidence(playerSource, cause, clientSeverity)
    local now = GetGameTimer()
    samplePlayer(playerSource, now)
    local evidence = damageEvidence[playerSource]
    if not evidence or elapsed(now, evidence.at) > Config.AutoDamage.evidenceWindow then
        return nil, 'missing_server_evidence'
    end

    local observedSeverity = evidence.vitalityLoss / Config.AutoDamage.damageReference
    if cause == 'explosion' and not hasRecentExplosionNearby(playerSource, now) then
        return nil, 'missing_explosion_evidence'
    elseif cause == 'vehicle_crash' then
        if not evidence.inVehicle or (evidence.speedLoss < Config.AutoDamage.vehicle.minSpeedLoss
            and evidence.vitalityLoss <= 0) then return nil, 'implausible_vehicle_crash' end
        observedSeverity = math.max(observedSeverity,
            evidence.speedLoss / Config.AutoDamage.vehicle.speedLossReference)
    elseif evidence.vitalityLoss <= 0 then
        return nil, 'missing_vitality_loss'
    end

    local severity = math.min(normalizeSeverity(clientSeverity), normalizeSeverity(observedSeverity))
    if severity < Config.AutoDamage.events[cause].minSeverity then return nil, 'severity_too_low' end
    damageEvidence[playerSource] = nil
    return severity
end

AddEventHandler('explosionEvent', function(_, event)
    if type(event) ~= 'table' then return end
    local x, y, z = tonumber(event.posX), tonumber(event.posY), tonumber(event.posZ)
    if not x or not y or not z then return end
    recentExplosions[#recentExplosions + 1] = { at = GetGameTimer(), x = x, y = y, z = z }
    if #recentExplosions > 256 then table.remove(recentExplosions, 1) end
end)

local function calculateChance(eventConfig, severity)
    local chance = eventConfig.chance
    if Config.AutoDamage.dynamicChance then
        chance = chance * (0.5 + severity)
    end
    return math.max(0.0, math.min(100.0, chance))
end

local function tryAutoDamage(playerSource, cause, severity)
    if not Config.AutoDamage.enabled then return false, 'auto_damage_disabled' end

    playerSource = tonumber(playerSource)
    if not playerSource or playerSource <= 0 or not GetPlayerName(playerSource) then
        return false, 'invalid_player'
    end

    if type(cause) ~= 'string' then return false, 'invalid_cause' end
    local eventConfig = Config.AutoDamage.events[cause]
    if not eventConfig then return false, 'invalid_cause' end
    if not eventConfig.enabled then return false, 'event_disabled' end

    severity = normalizeSeverity(severity)
    if severity < eventConfig.minSeverity then return false, 'severity_too_low' end

    local now = GetGameTimer()
    if elapsed(now, lastSuccessfulDamage[playerSource]) < Config.AutoDamage.successCooldown then
        return false, 'success_cooldown'
    end
    if pendingDamage[playerSource] then return false, 'damage_pending' end

    local playerCooldowns = attemptCooldowns[playerSource]
    if not playerCooldowns then
        playerCooldowns = {}
        attemptCooldowns[playerSource] = playerCooldowns
    end
    if elapsed(now, playerCooldowns[cause]) < eventConfig.cooldown then
        return false, 'event_cooldown'
    end

    -- Consume the attempt before rolling so repeated failed reports cannot brute-force the chance.
    playerCooldowns[cause] = now
    local chance = calculateChance(eventConfig, severity)
    local roll = math.random() * 100.0
    if roll >= chance then
        debugLog('source=%d cause=%s severity=%.2f chance=%.2f roll=%.2f result=miss',
            playerSource, cause, severity, chance, roll)
        return false, 'chance_failed'
    end

    if not LBBrokenPhoneCore or type(LBBrokenPhoneCore.applyPhoneDamageDelta) ~= 'function' then
        return false, 'core_unavailable'
    end

    pendingDamage[playerSource] = true
    local invoked, success, err, state, changed = pcall(
        LBBrokenPhoneCore.applyPhoneDamageDelta,
        playerSource,
        eventConfig.escalation,
        eventConfig.maxResultLevel,
        ('auto_%s'):format(cause)
    )
    pendingDamage[playerSource] = nil

    if not invoked then
        print(('^1[lb-brokenphone][auto] Damage failed for source %d: %s^7'):format(
            playerSource, tostring(success)
        ))
        return false, 'core_error'
    end
    if not success then return false, err end

    if changed then lastSuccessfulDamage[playerSource] = GetGameTimer() end
    debugLog('source=%d cause=%s severity=%.2f chance=%.2f roll=%.2f result=%s level=%s',
        playerSource, cause, severity, chance, roll, changed and 'damage' or 'unchanged',
        tostring(state and state.damageLevel))
    return true, nil, state, changed
end

RegisterNetEvent('lb-brokenphone:server:autoDamageEvent', function(cause, severity)
    local playerSource = source
    if not Config.AutoDamage.enabled then return end

    local now = GetGameTimer()
    if elapsed(now, lastNetworkReport[playerSource]) < Config.AutoDamage.networkRateLimit then return end
    lastNetworkReport[playerSource] = now
    if type(cause) ~= 'string' or not Config.AutoDamage.events[cause] then return end
    local verifiedSeverity, evidenceError = validateDamageEvidence(playerSource, cause, severity)
    if not verifiedSeverity then
        debugLog('source=%d cause=%s result=%s', playerSource, cause, evidenceError)
        return
    end
    tryAutoDamage(playerSource, cause, verifiedSeverity)
end)

local function normalizeFireMeasurement(value, maximum)
    value = tonumber(value) or 0
    if value ~= value then return 0 end
    return math.max(0, math.min(maximum, value))
end

local function classifyFireDamage(healthLoss, burnDuration)
    local medium = Config.AutoFireDamage.medium
    if healthLoss >= medium.minHealthLoss or burnDuration >= medium.minBurnDuration then
        return 2, medium
    end

    local light = Config.AutoFireDamage.light
    if healthLoss >= light.minHealthLoss or burnDuration >= light.minBurnDuration then
        return 1, light
    end
    return nil
end

local function tryAutoFireDamage(playerSource, healthLoss, burnDuration)
    if not Config.AutoFireDamage.enabled then return false, 'auto_fire_damage_disabled' end

    playerSource = tonumber(playerSource)
    if not playerSource or playerSource <= 0 or not GetPlayerName(playerSource) then
        return false, 'invalid_player'
    end

    healthLoss = normalizeFireMeasurement(healthLoss, 1000)
    burnDuration = math.floor(normalizeFireMeasurement(burnDuration, 120000))
    local targetLevel, levelConfig = classifyFireDamage(healthLoss, burnDuration)
    if not targetLevel then return false, 'fire_injury_too_low' end

    local now = GetGameTimer()
    if elapsed(now, lastFireAttempt[playerSource]) < Config.AutoFireDamage.cooldown then
        return false, 'fire_cooldown'
    end
    if pendingFireDamage[playerSource] then return false, 'fire_damage_pending' end

    -- Consume the incident before rolling so repeated reports cannot brute-force the chance.
    lastFireAttempt[playerSource] = now
    local roll = math.random() * 100.0
    if roll >= levelConfig.chance then
        fireDebugLog('source=%d healthLoss=%.1f duration=%d target=%d chance=%.1f roll=%.2f result=miss',
            playerSource, healthLoss, burnDuration, targetLevel, levelConfig.chance, roll)
        return false, 'chance_failed'
    end

    if not LBBrokenPhoneCore or type(LBBrokenPhoneCore.applyPhoneFire) ~= 'function' then
        return false, 'core_unavailable'
    end

    pendingFireDamage[playerSource] = true
    local invoked, success, err, state, changed = pcall(
        LBBrokenPhoneCore.applyPhoneFire,
        playerSource,
        targetLevel,
        'auto_fire_injury'
    )
    pendingFireDamage[playerSource] = nil

    if not invoked then
        print(('^1[lb-brokenphone][auto-fire] Damage failed for source %d: %s^7'):format(
            playerSource, tostring(success)
        ))
        return false, 'core_error'
    end
    if not success then return false, err end

    fireDebugLog('source=%d healthLoss=%.1f duration=%d target=%d chance=%.1f roll=%.2f result=%s level=%s',
        playerSource, healthLoss, burnDuration, targetLevel, levelConfig.chance, roll,
        changed and 'damage' or 'unchanged', tostring(state and state.fireLevel))
    return true, nil, state, changed
end

RegisterNetEvent('lb-brokenphone:server:autoFireDamageEvent', function(healthLoss, burnDuration)
    local playerSource = source
    if not Config.AutoFireDamage.enabled then return end

    local now = GetGameTimer()
    if elapsed(now, lastFireNetworkReport[playerSource]) < Config.AutoFireDamage.networkRateLimit then return end
    lastFireNetworkReport[playerSource] = now
    samplePlayer(playerSource, now)
    local evidence = fireEvidence[playerSource]
    local fireWindow = math.max(Config.AutoDamage.evidenceWindow,
        Config.AutoFireDamage.medium.minBurnDuration + Config.AutoFireDamage.incidentEndGrace + 1000)
    if not evidence or elapsed(now, evidence.at) > fireWindow then
        fireDebugLog('source=%d result=missing_server_evidence', playerSource)
        return
    end
    local observedLoss = math.min(normalizeFireMeasurement(healthLoss, 1000), evidence.healthLoss)
    local observedDuration = math.min(normalizeFireMeasurement(burnDuration, 120000),
        math.max(Config.AutoDamage.snapshotInterval, evidence.at - evidence.firstAt + Config.AutoDamage.snapshotInterval))
    fireEvidence[playerSource] = nil
    tryAutoFireDamage(playerSource, observedLoss, observedDuration)
end)

CreateThread(function()
    while true do
        local players = GetPlayers()
        local now = GetGameTimer()
        for i = 1, #players do samplePlayer(tonumber(players[i]), now) end
        Wait(Config.AutoDamage.snapshotInterval)
    end
end)

AddEventHandler('playerDropped', function()
    local playerSource = source
    attemptCooldowns[playerSource] = nil
    lastSuccessfulDamage[playerSource] = nil
    lastNetworkReport[playerSource] = nil
    pendingDamage[playerSource] = nil
    lastFireAttempt[playerSource] = nil
    lastFireNetworkReport[playerSource] = nil
    pendingFireDamage[playerSource] = nil
    vitalitySnapshots[playerSource] = nil
    damageEvidence[playerSource] = nil
    fireEvidence[playerSource] = nil
end)

exports('TryAutoDamage', tryAutoDamage)
exports('TryAutoFireDamage', tryAutoFireDamage)
