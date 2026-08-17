-- Turns a *verified* fire-injury report into an actual chance-based phone
-- fire-damage attempt. Structurally the fire counterpart to
-- physical-damage.server.lua: damage-evidence.server.lua decides whether a
-- report is real, this file decides whether it results in fire damage
-- (classification into light/medium, cooldown, probability roll).
local Shared = LBBrokenPhoneDamageShared
local Evidence = LBBrokenPhoneDamageEvidence
local lastFireAttempt = {}
local lastNetworkReport = {}
local lastSessionStart = {}
local pendingFireDamage = {}

local function debugLog(message, ...)
    if not Config.AutoFireDamage.debug then return end
    print(('[lb-brokenphone][fire-damage] ' .. message):format(...))
end

-- Fired by fire-damage.client.lua the instant the player catches fire.
-- Opens the evidence session (see Evidence.beginFire) that later
-- Evidence.verifyFire calls diff against; rate-limited so flickering
-- on-fire states can't reopen the session repeatedly.
RegisterNetEvent('lb-brokenphone:server:fireStarted', function()
    local playerSource = source
    if not Config.AutoFireDamage.enabled then return end

    local now = GetGameTimer()
    if Shared.elapsed(now, lastSessionStart[playerSource]) < Config.AutoFireDamage.cooldown then return end
    if Evidence.beginFire(playerSource) then lastSessionStart[playerSource] = now end
end)

-- Light and medium are mutually exclusive outcomes, not additive levels:
-- either threshold set (health lost OR time spent burning) being met is
-- enough, and medium is checked first so a burn severe enough for both
-- always classifies as medium. Returns (nil) if neither threshold is met.
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

-- Core gate, mirroring physical-damage.server.lua's tryAutoDamage: given an
-- already-trusted (playerSource, healthLoss, burnDuration), classifies the
-- burn severity, checks the cooldown, rolls the level's chance, and applies
-- fire damage through LBBrokenPhoneCore if it hits. Returns (true) on
-- success, or (false, reasonString) otherwise.
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

-- Client-reported "I just finished burning, here's what it cost me". Never
-- trusted directly: rate-limited per player (cancelling the open evidence
-- session if the report itself is being rate-limited, so it can't be reused
-- for a later unrelated fire), then handed to Evidence.verifyFire for
-- independent confirmation before tryAutoFireDamage() ever sees it.
RegisterNetEvent('lb-brokenphone:server:fireDamage', function(healthLoss, burnDuration)
    local playerSource = source
    if not Config.AutoFireDamage.enabled then return end

    local now = GetGameTimer()
    if Shared.elapsed(now, lastNetworkReport[playerSource]) < Config.AutoFireDamage.networkRateLimit then
        Evidence.cancelFire(playerSource)
        return
    end
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
    lastSessionStart[playerSource] = nil
    pendingFireDamage[playerSource] = nil
end)

-- Trusted server integrations can use this export without going through a client report.
exports('TryAutoFireDamage', tryAutoFireDamage)
