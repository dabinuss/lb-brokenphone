if not Config.AutoFireDamage.enabled then return end

local function reportFireIncident(incident)
    local healthLoss = math.max(0, incident.startHealth - incident.minimumHealth)
    local duration = math.max(
        0,
        incident.lastOnFireAt - incident.startedAt + Config.AutoFireDamage.pollInterval
    )
    TriggerServerEvent('lb-brokenphone:server:fireDamage', healthLoss, duration)
end

CreateThread(function()
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
                TriggerServerEvent('lb-brokenphone:server:fireStarted')
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
        Wait((onFire or incident) and Config.AutoFireDamage.pollInterval
            or Config.AutoFireDamage.idlePollInterval)
    end
end)
