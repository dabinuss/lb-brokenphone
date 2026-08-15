local Shared = LBBrokenPhoneDamageShared
local vitalitySnapshots = {}
local physicalEvidence = {}
local fireEvidence = {}
local recentExplosions = {}

LBBrokenPhoneDamageEvidence = LBBrokenPhoneDamageEvidence or {}

local function fireEvidenceWindow()
    return math.max(
        Config.AutoDamage.evidenceWindow,
        Config.AutoFireDamage.medium.minBurnDuration + Config.AutoFireDamage.incidentEndGrace + 1000
    )
end

local function readPlayerSnapshot(playerSource, now)
    local ok, snapshot = pcall(function()
        local ped = GetPlayerPed(playerSource)
        if not ped or ped <= 0 or not DoesEntityExist(ped) then return nil end

        local health = math.max(0, GetEntityHealth(ped) - 100)
        local armour = math.max(0, GetPedArmour(ped))
        local vehicle, speed = 0, 0.0
        if Config.AutoDamage.enabled then
            vehicle = GetVehiclePedIsIn(ped, false)
            if vehicle and vehicle > 0 then speed = tonumber(GetEntitySpeed(vehicle)) or 0.0 end
        end
        return {
            at = now,
            ped = ped,
            health = health,
            vitality = health + armour,
            vehicle = vehicle and vehicle > 0 and vehicle or 0,
            speed = speed
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
        or Shared.elapsed(now, previous.at) > Config.AutoDamage.evidenceWindow then
        return current
    end

    local vitalityLoss = math.max(0, previous.vitality - current.vitality)
    local healthLoss = math.max(0, previous.health - current.health)
    local speedLoss = previous.vehicle > 0 and previous.vehicle == current.vehicle
        and math.max(0.0, previous.speed - current.speed) or 0.0

    if Config.AutoDamage.enabled
        and (vitalityLoss > 0 or speedLoss >= Config.AutoDamage.vehicle.minSpeedLoss) then
        local evidence = physicalEvidence[playerSource]
        if not evidence or Shared.elapsed(now, evidence.at) > Config.AutoDamage.evidenceWindow then
            evidence = { vitalityLoss = 0, speedLoss = 0, inVehicle = false }
            physicalEvidence[playerSource] = evidence
        end
        evidence.at = now
        evidence.vitalityLoss = evidence.vitalityLoss + vitalityLoss
        evidence.speedLoss = math.max(evidence.speedLoss, speedLoss)
        evidence.inVehicle = evidence.inVehicle or previous.vehicle > 0 or current.vehicle > 0
    end

    if Config.AutoFireDamage.enabled and healthLoss > 0 then
        local evidence = fireEvidence[playerSource]
        if not evidence or Shared.elapsed(now, evidence.at) > fireEvidenceWindow() then
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
        if Shared.elapsed(now, explosion.at) <= Config.AutoDamage.evidenceWindow then
            retained[#retained + 1] = explosion
            local dx, dy, dz = coords.x - explosion.x, coords.y - explosion.y, coords.z - explosion.z
            if dx * dx + dy * dy + dz * dz <= radiusSquared then matched = true end
        end
    end
    recentExplosions = retained
    return matched
end

function LBBrokenPhoneDamageEvidence.verifyPhysical(playerSource, cause, clientSeverity)
    local eventConfig = type(cause) == 'string' and Config.AutoDamage.events[cause] or nil
    if not eventConfig then return nil, 'invalid_cause' end

    local now = GetGameTimer()
    samplePlayer(playerSource, now)
    local evidence = physicalEvidence[playerSource]
    if not evidence or Shared.elapsed(now, evidence.at) > Config.AutoDamage.evidenceWindow then
        return nil, 'missing_server_evidence'
    end

    local observedSeverity = evidence.vitalityLoss / Config.AutoDamage.damageReference
    if cause == 'explosion' and not hasRecentExplosionNearby(playerSource, now) then
        return nil, 'missing_explosion_evidence'
    elseif cause == 'vehicle_crash' then
        if not evidence.inVehicle or (evidence.speedLoss < Config.AutoDamage.vehicle.minSpeedLoss
            and evidence.vitalityLoss <= 0) then
            return nil, 'implausible_vehicle_crash'
        end
        observedSeverity = math.max(
            observedSeverity,
            evidence.speedLoss / Config.AutoDamage.vehicle.speedLossReference
        )
    elseif evidence.vitalityLoss <= 0 then
        return nil, 'missing_vitality_loss'
    end

    local severity = math.min(
        Shared.normalizeSeverity(clientSeverity),
        Shared.normalizeSeverity(observedSeverity)
    )
    if severity < eventConfig.minSeverity then return nil, 'severity_too_low' end
    physicalEvidence[playerSource] = nil
    return severity
end

function LBBrokenPhoneDamageEvidence.verifyFire(playerSource, reportedHealthLoss, reportedDuration)
    local now = GetGameTimer()
    samplePlayer(playerSource, now)
    local evidence = fireEvidence[playerSource]
    if not evidence or Shared.elapsed(now, evidence.at) > fireEvidenceWindow() then
        return nil, nil, 'missing_server_evidence'
    end

    local healthLoss = math.min(
        Shared.clampNumber(reportedHealthLoss, 0, 1000),
        evidence.healthLoss
    )
    local duration = math.min(
        Shared.clampNumber(reportedDuration, 0, 120000),
        math.max(Config.AutoDamage.snapshotInterval,
            evidence.at - evidence.firstAt + Config.AutoDamage.snapshotInterval)
    )
    fireEvidence[playerSource] = nil
    return healthLoss, math.floor(duration)
end

function LBBrokenPhoneDamageEvidence.clearPlayer(playerSource)
    vitalitySnapshots[playerSource] = nil
    physicalEvidence[playerSource] = nil
    fireEvidence[playerSource] = nil
end

AddEventHandler('explosionEvent', function(_, event)
    if not Config.AutoDamage.enabled or type(event) ~= 'table' then return end
    local x, y, z = tonumber(event.posX), tonumber(event.posY), tonumber(event.posZ)
    if not x or not y or not z then return end

    recentExplosions[#recentExplosions + 1] = { at = GetGameTimer(), x = x, y = y, z = z }
    if #recentExplosions > 256 then table.remove(recentExplosions, 1) end
end)

AddEventHandler('playerDropped', function()
    LBBrokenPhoneDamageEvidence.clearPlayer(source)
end)

CreateThread(function()
    if not Config.AutoDamage.enabled and not Config.AutoFireDamage.enabled then return end
    while true do
        local players = GetPlayers()
        local now = GetGameTimer()
        for i = 1, #players do samplePlayer(tonumber(players[i]), now) end
        Wait(Config.AutoDamage.snapshotInterval)
    end
end)
