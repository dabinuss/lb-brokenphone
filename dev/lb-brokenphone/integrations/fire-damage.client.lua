-- Purely a passive observer: watches whether the local player is on fire and
-- reports finished burn "incidents" to the server. It never decides
-- anything -- fire-damage.server.lua re-verifies everything against its own
-- observations (see damage-evidence.server.lua) before any phone damage is
-- applied, so a modified client sending fabricated reports here gains
-- nothing.
if not Config.AutoFireDamage.enabled then return end

-- Reports one finished burn incident: total health lost since it started
-- (using the lowest health seen during the burn, since natural regen/healing
-- items could otherwise mask the real loss) and how long the player was
-- actually on fire for (padded by one poll interval so the last tick before
-- the flames went out is still counted).
local function reportFireIncident(incident)
    local healthLoss = math.max(0, incident.startHealth - incident.minimumHealth)
    local duration = math.max(
        0,
        incident.lastOnFireAt - incident.startedAt + Config.AutoFireDamage.pollInterval
    )
    TriggerServerEvent('lb-brokenphone:server:fireDamage', healthLoss, duration)
end

-- Polls IsEntityOnFire() at Config.AutoFireDamage.pollInterval while burning
-- (falling back to the slower idlePollInterval otherwise). A single
-- "incident" spans from the first tick on fire until
-- Config.AutoFireDamage.incidentEndGrace milliseconds have passed without
-- being on fire again, so brief flame flicker doesn't get reported as many
-- tiny separate incidents.
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
