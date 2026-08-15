if not Config.AutoDamage.enabled and not Config.AutoFireDamage.enabled then return end

local lastReportedAt = {}
local lastCombatVitality = nil

local function clamp(value)
    return math.max(0.0, math.min(1.0, value))
end

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

local explosiveWeapons = hashSet({
    'WEAPON_GRENADE',
    'WEAPON_GRENADELAUNCHER',
    'WEAPON_COMPACTLAUNCHER',
    'WEAPON_STICKYBOMB',
    'WEAPON_PROXMINE',
    'WEAPON_PIPEBOMB',
    'WEAPON_RPG',
    'WEAPON_HOMINGLAUNCHER',
    'WEAPON_RAILGUN',
    'WEAPON_RAILGUNXM3',
    'WEAPON_EXPLOSION',
    'WEAPON_VEHICLE_ROCKET',
    'WEAPON_AIRSTRIKE_ROCKET',
    'WEAPON_PASSENGER_ROCKET',
    'WEAPON_HELI_CRASH'
})

local meleeGroups = hashSet({ 'GROUP_UNARMED', 'GROUP_MELEE' })
local firearmGroups = hashSet({
    'GROUP_PISTOL',
    'GROUP_SMG',
    'GROUP_RIFLE',
    'GROUP_MG',
    'GROUP_SHOTGUN',
    'GROUP_SNIPER',
    'GROUP_HEAVY'
})

local function readVitality(ped)
    return math.max(0, GetEntityHealth(ped) - 100) + math.max(0, GetPedArmour(ped))
end

local function reportEvent(cause, severity)
    local eventConfig = Config.AutoDamage.events[cause]
    if not eventConfig or not eventConfig.enabled then return end

    local now = GetGameTimer()
    local previous = lastReportedAt[cause]
    if previous and now >= previous and now - previous < Config.AutoDamage.clientDebounce then return end
    lastReportedAt[cause] = now
    TriggerServerEvent('lb-brokenphone:server:autoDamageEvent', cause, clamp(severity))
end

local function resolveDamageWeapon(args)
    for _, index in ipairs({ 7, 5 }) do
        local candidate = tonumber(args[index])
        if candidate and candidate ~= 0 and IsWeaponValid(candidate) then return candidate end
    end

    local attacker = tonumber(args[2]) or 0
    if attacker > 0 and DoesEntityExist(attacker) and IsEntityAPed(attacker) then
        local weapon = GetSelectedPedWeapon(attacker)
        if weapon and weapon ~= 0 and IsWeaponValid(weapon) then return weapon end
    end
    return nil
end

local function classifyWeapon(weapon)
    if not weapon then return nil end
    if explosiveWeapons[canonicalHash(weapon)] then return 'explosion' end

    local group = canonicalHash(GetWeapontypeGroup(weapon))
    if meleeGroups[group] then return 'melee' end
    if firearmGroups[group] then return 'gunshot' end
    return nil
end

AddEventHandler('gameEventTriggered', function(name, args)
    if not Config.AutoDamage.enabled then return end
    if name ~= 'CEventNetworkEntityDamage' then return end

    local ped = PlayerPedId()
    if tonumber(args[1]) ~= ped then return end
    local cause = classifyWeapon(resolveDamageWeapon(args))
    if not cause then return end

    local before = lastCombatVitality or readVitality(ped)
    SetTimeout(0, function()
        if ped ~= PlayerPedId() then return end
        local after = readVitality(ped)
        lastCombatVitality = after
        local vitalityLoss = before - after
        if vitalityLoss <= 0 then return end
        reportEvent(cause, vitalityLoss / Config.AutoDamage.damageReference)
    end)
end)

CreateThread(function()
    if not Config.AutoDamage.enabled then return end
    local vehicleState = nil

    while true do
        local ped = PlayerPedId()
        lastCombatVitality = readVitality(ped)

        if not IsPedInAnyVehicle(ped, false) then
            vehicleState = nil
            Wait(Config.AutoDamage.vehicle.idlePollInterval)
        else
            local vehicle = GetVehiclePedIsIn(ped, false)
            local speed = GetEntitySpeed(vehicle)
            local bodyHealth = GetVehicleBodyHealth(vehicle)
            local vitality = readVitality(ped)
            local impact = vehicleState and vehicleState.vehicle == vehicle and vehicleState.impact or nil

            if vehicleState and vehicleState.vehicle == vehicle then
                local now = GetGameTimer()
                local speedLoss = math.max(0.0, vehicleState.speed - speed)
                if vehicleState.speed >= Config.AutoDamage.vehicle.minSpeed
                    and speedLoss >= Config.AutoDamage.vehicle.minSpeedLoss
                    and HasEntityCollidedWithAnything(vehicle) then
                    impact = {
                        expiresAt = now + Config.AutoDamage.vehicle.impactWindow,
                        speedLoss = speedLoss,
                        bodyHealth = vehicleState.bodyHealth,
                        vitality = vehicleState.vitality
                    }
                end

                if impact and now <= impact.expiresAt then
                    impact.speedLoss = math.max(impact.speedLoss, speedLoss)
                    local bodyHealthLoss = math.max(0.0, impact.bodyHealth - bodyHealth)
                    local vitalityLoss = math.max(0.0, impact.vitality - vitality)
                    if bodyHealthLoss >= Config.AutoDamage.vehicle.minBodyHealthLoss then
                        local severity = math.max(
                            impact.speedLoss / Config.AutoDamage.vehicle.speedLossReference,
                            bodyHealthLoss / Config.AutoDamage.vehicle.bodyHealthLossReference,
                            vitalityLoss / Config.AutoDamage.damageReference
                        )
                        reportEvent('vehicle_crash', severity)
                        impact = nil
                    end
                elseif impact then
                    impact = nil
                end
            end

            vehicleState = {
                vehicle = vehicle,
                speed = speed,
                bodyHealth = bodyHealth,
                vitality = vitality,
                impact = impact
            }
            Wait(Config.AutoDamage.vehicle.pollInterval)
        end
    end
end)

local function reportFireIncident(incident)
    local healthLoss = math.max(0, incident.startHealth - incident.minimumHealth)
    local duration = math.max(0,
        incident.lastOnFireAt - incident.startedAt + Config.AutoFireDamage.pollInterval)
    TriggerServerEvent('lb-brokenphone:server:autoFireDamageEvent', healthLoss, duration)
end

CreateThread(function()
    if not Config.AutoFireDamage.enabled then return end
    local incident = nil
    local previousPed = nil
    local previousHealth = nil

    while true do
        local now = GetGameTimer()
        local ped = PlayerPedId()
        local pedExists = ped and ped > 0 and DoesEntityExist(ped)
        local onFire = pedExists and IsEntityOnFire(ped)
        local health = pedExists and math.max(0, GetEntityHealth(ped)) or 0

        if onFire then
            if not incident or incident.ped ~= ped or now < incident.startedAt then
                if incident then reportFireIncident(incident) end
                incident = {
                    ped = ped,
                    startedAt = now,
                    lastOnFireAt = now,
                    startHealth = previousPed == ped and math.max(health, previousHealth or health) or health,
                    minimumHealth = health
                }
            else
                incident.lastOnFireAt = now
                incident.minimumHealth = math.min(incident.minimumHealth, health)
            end
        elseif incident then
            if incident.ped == ped then
                incident.minimumHealth = math.min(incident.minimumHealth, health)
            end
            if incident.ped ~= ped or now < incident.lastOnFireAt
                or now - incident.lastOnFireAt >= Config.AutoFireDamage.incidentEndGrace then
                reportFireIncident(incident)
                incident = nil
            end
        end

        previousPed = pedExists and ped or nil
        previousHealth = pedExists and health or nil
        Wait(Config.AutoFireDamage.pollInterval)
    end
end)
