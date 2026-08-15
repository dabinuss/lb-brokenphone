local attemptCooldowns = {}
local lastSuccessfulDamage = {}
local lastNetworkReport = {}
local pendingDamage = {}
local lastFireAttempt = {}
local lastFireNetworkReport = {}
local pendingFireDamage = {}

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
    tryAutoDamage(playerSource, cause, severity)
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
    tryAutoFireDamage(playerSource, healthLoss, burnDuration)
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
end)

exports('TryAutoDamage', tryAutoDamage)
exports('TryAutoFireDamage', tryAutoFireDamage)
