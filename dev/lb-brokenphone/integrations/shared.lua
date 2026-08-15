LBBrokenPhoneDamageShared = LBBrokenPhoneDamageShared or {}

function LBBrokenPhoneDamageShared.elapsed(now, previous)
    if not previous or now < previous then return math.huge end
    return now - previous
end

function LBBrokenPhoneDamageShared.clampNumber(value, minimum, maximum)
    value = tonumber(value) or minimum
    if value ~= value then return minimum end
    return math.max(minimum, math.min(maximum, value))
end

function LBBrokenPhoneDamageShared.normalizeSeverity(value)
    return LBBrokenPhoneDamageShared.clampNumber(value, 0.0, 1.0)
end
