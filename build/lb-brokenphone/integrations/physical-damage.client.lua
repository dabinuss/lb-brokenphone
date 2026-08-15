if not Config.AutoDamage.enabled then return end

local Shared = LBBrokenPhoneDamageShared
local lastReportedAt = {}
local lastCombatVitality = nil

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
    'WEAPON_HELI_CRASH',
    'WEAPON_FIREWORK',
    'WEAPON_EMPLAUNCHER'
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

local function reportPhysicalDamage(cause, severity)
    local eventConfig = Config.AutoDamage.events[cause]
    if not eventConfig or not eventConfig.enabled then return end

    local now = GetGameTimer()
    local previous = lastReportedAt[cause]
    if previous and now >= previous and now - previous < Config.AutoDamage.clientDebounce then return end
    lastReportedAt[cause] = now
    TriggerServerEvent(
        'lb-brokenphone:server:physicalDamage',
        cause,
        Shared.normalizeSeverity(severity)
    )
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
        SetTimeout(Config.AutoDamage.snapshotInterval + 50, function()
            reportPhysicalDamage(cause, vitalityLoss / Config.AutoDamage.damageReference)
        end)
    end)
end)

CreateThread(function()
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
                        reportPhysicalDamage('vehicle_crash', severity)
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
