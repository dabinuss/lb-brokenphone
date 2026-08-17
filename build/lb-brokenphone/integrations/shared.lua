-- Tiny helpers shared between damage-evidence.server.lua and the
-- physical/fire damage integrations (client and server). Kept dependency-free
-- so it can be loaded as a shared_script and used from either side.
LBBrokenPhoneDamageShared = LBBrokenPhoneDamageShared or {}

-- Milliseconds since `previous` (a GetGameTimer() timestamp), or math.huge if
-- `previous` is nil/unset or lies in the future (e.g. after a timer reset).
-- Used everywhere a cooldown/rate-limit needs "has enough time passed?".
function LBBrokenPhoneDamageShared.elapsed(now, previous)
    if not previous or now < previous then return math.huge end
    return now - previous
end

-- Coerces `value` to a number and clamps it into [minimum, maximum].
-- Falls back to `minimum` for anything non-numeric, including NaN (the
-- `value ~= value` check), so callers never have to sanity-check input first.
function LBBrokenPhoneDamageShared.clampNumber(value, minimum, maximum)
    value = tonumber(value) or minimum
    if value ~= value then return minimum end
    return math.max(minimum, math.min(maximum, value))
end

-- clampNumber specialised to the 0.0-1.0 severity range used throughout the
-- auto-damage/auto-fire integrations (client-reported and server-observed).
function LBBrokenPhoneDamageShared.normalizeSeverity(value)
    return LBBrokenPhoneDamageShared.clampNumber(value, 0.0, 1.0)
end
