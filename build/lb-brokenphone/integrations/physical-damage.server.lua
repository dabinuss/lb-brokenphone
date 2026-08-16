local Shared = LBBrokenPhoneDamageShared
local Evidence = LBBrokenPhoneDamageEvidence
local attemptCooldowns = {}
local lastSuccessfulDamage = {}
local lastNetworkReport = {}
local lastVehicleBaseline = {}
local lastVerificationByCause = {}
local pendingDamage = {}

local function debugLog(message, ...)
    if not Config.AutoDamage.debug then return end
    print(('[lb-brokenphone][physical-damage] ' .. message):format(...))
end

local function calculateChance(eventConfig, severity)
    local chance = eventConfig.chance
    if Config.AutoDamage.dynamicChance then chance = chance * (0.5 + severity) end
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

    severity = Shared.normalizeSeverity(severity)
    if severity < eventConfig.minSeverity then return false, 'severity_too_low' end

    local now = GetGameTimer()
    if Shared.elapsed(now, lastSuccessfulDamage[playerSource]) < Config.AutoDamage.successCooldown then
        return false, 'success_cooldown'
    end
    if pendingDamage[playerSource] then return false, 'damage_pending' end

    local playerCooldowns = attemptCooldowns[playerSource]
    if not playerCooldowns then
        playerCooldowns = {}
        attemptCooldowns[playerSource] = playerCooldowns
    end
    if Shared.elapsed(now, playerCooldowns[cause]) < eventConfig.cooldown then
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
        print(('^1[lb-brokenphone][physical-damage] Damage failed for source %d: %s^7'):format(
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

RegisterNetEvent('lb-brokenphone:server:vehicleEntered', function()
    local playerSource = source
    if not Config.AutoDamage.enabled or not Config.AutoDamage.events.vehicle_crash.enabled then return end

    local now = GetGameTimer()
    if Shared.elapsed(now, lastVehicleBaseline[playerSource])
        < Config.AutoDamage.vehicle.baselineRateLimit then return end
    lastVehicleBaseline[playerSource] = now
    Evidence.beginVehicle(playerSource)
end)

RegisterNetEvent('lb-brokenphone:server:physicalDamage', function(cause, severity)
    local playerSource = source
    if not Config.AutoDamage.enabled then return end

    local now = GetGameTimer()
    if Shared.elapsed(now, lastNetworkReport[playerSource]) < Config.AutoDamage.networkRateLimit then return end
    lastNetworkReport[playerSource] = now

    local eventConfig = type(cause) == 'string' and Config.AutoDamage.events[cause] or nil
    if not eventConfig or not eventConfig.enabled then return end
    local verificationCooldowns = lastVerificationByCause[playerSource]
    if not verificationCooldowns then
        verificationCooldowns = {}
        lastVerificationByCause[playerSource] = verificationCooldowns
    end
    if Shared.elapsed(now, verificationCooldowns[cause]) < eventConfig.cooldown then return end
    verificationCooldowns[cause] = now

    local verifiedSeverity, evidenceError = Evidence.verifyPhysical(playerSource, cause, severity)
    if not verifiedSeverity then
        debugLog('source=%d cause=%s result=%s', playerSource, tostring(cause), evidenceError)
        return
    end
    tryAutoDamage(playerSource, cause, verifiedSeverity)
end)

AddEventHandler('playerDropped', function()
    local playerSource = source
    attemptCooldowns[playerSource] = nil
    lastSuccessfulDamage[playerSource] = nil
    lastNetworkReport[playerSource] = nil
    lastVehicleBaseline[playerSource] = nil
    lastVerificationByCause[playerSource] = nil
    pendingDamage[playerSource] = nil
end)

-- Trusted server integrations can use this export without going through a client report.
exports('TryAutoDamage', tryAutoDamage)
