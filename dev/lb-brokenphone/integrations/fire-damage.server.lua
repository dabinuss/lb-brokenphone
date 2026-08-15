local Shared = LBBrokenPhoneDamageShared
local Evidence = LBBrokenPhoneDamageEvidence
local lastFireAttempt = {}
local lastNetworkReport = {}
local pendingFireDamage = {}

local function debugLog(message, ...)
    if not Config.AutoFireDamage.debug then return end
    print(('[lb-brokenphone][fire-damage] ' .. message):format(...))
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

    healthLoss = Shared.clampNumber(healthLoss, 0, 1000)
    burnDuration = math.floor(Shared.clampNumber(burnDuration, 0, 120000))
    local targetLevel, levelConfig = classifyFireDamage(healthLoss, burnDuration)
    if not targetLevel then return false, 'fire_injury_too_low' end

    local now = GetGameTimer()
    if Shared.elapsed(now, lastFireAttempt[playerSource]) < Config.AutoFireDamage.cooldown then
        return false, 'fire_cooldown'
    end
    if pendingFireDamage[playerSource] then return false, 'fire_damage_pending' end

    -- Consume the incident before rolling so repeated reports cannot brute-force the chance.
    lastFireAttempt[playerSource] = now
    local roll = math.random() * 100.0
    if roll >= levelConfig.chance then
        debugLog('source=%d healthLoss=%.1f duration=%d target=%d chance=%.1f roll=%.2f result=miss',
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
        print(('^1[lb-brokenphone][fire-damage] Damage failed for source %d: %s^7'):format(
            playerSource, tostring(success)
        ))
        return false, 'core_error'
    end
    if not success then return false, err end

    debugLog('source=%d healthLoss=%.1f duration=%d target=%d chance=%.1f roll=%.2f result=%s level=%s',
        playerSource, healthLoss, burnDuration, targetLevel, levelConfig.chance, roll,
        changed and 'damage' or 'unchanged', tostring(state and state.fireLevel))
    return true, nil, state, changed
end

RegisterNetEvent('lb-brokenphone:server:fireDamage', function(healthLoss, burnDuration)
    local playerSource = source
    if not Config.AutoFireDamage.enabled then return end

    local now = GetGameTimer()
    if Shared.elapsed(now, lastNetworkReport[playerSource]) < Config.AutoFireDamage.networkRateLimit then return end
    lastNetworkReport[playerSource] = now

    local observedLoss, observedDuration, evidenceError = Evidence.verifyFire(
        playerSource,
        healthLoss,
        burnDuration
    )
    if not observedLoss then
        debugLog('source=%d result=%s', playerSource, evidenceError)
        return
    end
    tryAutoFireDamage(playerSource, observedLoss, observedDuration)
end)

AddEventHandler('playerDropped', function()
    local playerSource = source
    lastFireAttempt[playerSource] = nil
    lastNetworkReport[playerSource] = nil
    pendingFireDamage[playerSource] = nil
end)

-- Trusted server integrations can use this export without going through a client report.
exports('TryAutoFireDamage', tryAutoFireDamage)
