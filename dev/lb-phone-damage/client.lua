local state = {
    phoneNumber = nil,
    damageLevel = 0,
    damageSeed = 0,
    phoneOpen = false,
    phoneOnScreen = false,
    visualState = 'closed'
}

local transitionToken = 0
local touchToken = 0
local touchFaultActive = false

local function debugLog(message)
    if Config.Debug then
        print(('^3[lb-phone-damage]^7 %s'):format(tostring(message)))
    end
end

local function commandLog(message)
    print(('^3[lb-phone-damage]^7 %s'):format(tostring(message)))
end

local function lbExport(name, ...)
    if GetResourceState('lb-phone') ~= 'started' then
        return false, nil
    end

    local args = table.pack(...)
    return pcall(function()
        local resourceExports = exports['lb-phone']
        return resourceExports[name](resourceExports, table.unpack(args, 1, args.n))
    end)
end

local function sendNuiUpdate()
    TriggerEvent('lb-phone-damage:lbui:update', {
        action = 'lb-phone-damage:update',
        state = state.visualState,
        damageLevel = state.damageLevel,
        damageSeed = state.damageSeed,
        display = Config.Display,
        motion = Config.Motion
    })
end

local function setVisualState(value)
    if state.visualState == value then return end
    state.visualState = value
    sendNuiUpdate()
end

local function stopTouchFaults()
    touchToken = touchToken + 1
    if touchFaultActive then
        TriggerEvent('lb-phone-damage:lbui:update', {
            action = 'lb-phone-damage:touchFault',
            active = false
        })
        touchFaultActive = false
    end
    -- Recover from older versions that used LB Phone's global disabled state.
    lbExport('ToggleDisabled', false)
end

local function touchFaultsNeeded()
    return Config.Touch.enabled == true and state.damageLevel >= 2 and state.phoneOpen and state.phoneOnScreen
end

local function startTouchFaults()
    stopTouchFaults()
    if not touchFaultsNeeded() then return end

    local token = touchToken
    CreateThread(function()
        while token == touchToken and touchFaultsNeeded() do
            local profile = state.damageLevel >= 3 and Config.Touch.severe or Config.Touch.medium
            Wait(math.random(profile.intervalMin, profile.intervalMax))

            if token ~= touchToken or not touchFaultsNeeded() then break end

            touchFaultActive = true
            TriggerEvent('lb-phone-damage:lbui:update', {
                action = 'lb-phone-damage:touchFault',
                active = true
            })
            Wait(math.random(profile.durationMin, profile.durationMax))
            if touchFaultActive then
                TriggerEvent('lb-phone-damage:lbui:update', {
                    action = 'lb-phone-damage:touchFault',
                    active = false
                })
                touchFaultActive = false
            end
        end
    end)
end

local function refreshTouchFaults()
    if touchFaultsNeeded() then
        startTouchFaults()
    else
        stopTouchFaults()
    end
end

local function updateVisibility()
    transitionToken = transitionToken + 1
    local token = transitionToken
    local shouldShow = state.phoneOpen and state.phoneOnScreen and state.damageLevel > 0

    if shouldShow then
        setVisualState('opening')
        SetTimeout(Config.Motion.openDuration, function()
            if token == transitionToken and state.phoneOpen and state.phoneOnScreen and state.damageLevel > 0 then
                setVisualState('open')
            end
        end)
    elseif state.visualState ~= 'closed' then
        setVisualState('closing')
        SetTimeout(Config.Motion.closeDuration, function()
            if token == transitionToken and not (state.phoneOpen and state.phoneOnScreen and state.damageLevel > 0) then
                setVisualState('closed')
            end
        end)
    else
        sendNuiUpdate()
    end

    refreshTouchFaults()
end

local function setActivePhone(phoneNumber)
    if phoneNumber ~= nil then phoneNumber = tostring(phoneNumber) end
    if phoneNumber == '' then phoneNumber = nil end
    state.phoneNumber = phoneNumber
    state.damageLevel = 0
    state.damageSeed = 0
    updateVisibility()
    TriggerServerEvent('lb-phone-damage:server:syncPhone')
end

local function readLbPhoneState()
    -- Recover if a resource reload interrupted a short simulated touch fault.
    lbExport('ToggleDisabled', false)
    local okNumber, number = lbExport('GetEquippedPhoneNumber')
    local okOpen, isOpen = lbExport('IsOpen')
    local okScreen, onScreen = lbExport('IsPhoneOnScreen')

    state.phoneOpen = okOpen and isOpen == true
    state.phoneOnScreen = okScreen and onScreen == true
    setActivePhone(okNumber and number or nil)
    updateVisibility()
end

RegisterNetEvent('lb-phone-damage:client:receiveDamage', function(phoneNumber, damageLevel, damageSeed)
    if phoneNumber ~= state.phoneNumber then return end
    state.damageLevel = math.max(0, math.min(3, tonumber(damageLevel) or 0))
    state.damageSeed = tonumber(damageSeed) or 0
    updateVisibility()
end)

RegisterNetEvent('lb-phone-damage:client:commandResult', function(message, success)
    local color = success == false and '^1' or '^2'
    print(('%s[lb-phone-damage]^7 %s'):format(color, tostring(message)))
end)

RegisterNetEvent('lb-phone:numberChanged', function(newNumber)
    setActivePhone(newNumber)
end)

RegisterNetEvent('lb-phone:phoneToggled', function(open)
    state.phoneOpen = open == true
    updateVisibility()
end)

RegisterNetEvent('lb-phone:setOnScreen', function(onScreen)
    state.phoneOnScreen = onScreen == true
    updateVisibility()
end)

local function damageCommand(_, args)
    local level = tonumber(args[1])
    if not level or level % 1 ~= 0 or level < 1 or level > 3 then
        commandLog(('Usage: %s <1-3> [phoneNumber]'):format(Config.Commands.setDamage))
        return
    end
    TriggerServerEvent('lb-phone-damage:server:testDamage', level, args[2])
end

local function repairCommand(_, args)
    TriggerServerEvent('lb-phone-damage:server:testRepair', args[1])
end

if Config.Commands.enabled then
    RegisterCommand(Config.Commands.setDamage, damageCommand, false)
    RegisterCommand(Config.Commands.repair, repairCommand, false)
    if Config.Commands.legacySetDamage and Config.Commands.legacySetDamage ~= Config.Commands.setDamage then
        RegisterCommand(Config.Commands.legacySetDamage, damageCommand, false)
    end
    if Config.Commands.legacyRepair and Config.Commands.legacyRepair ~= Config.Commands.repair then
        RegisterCommand(Config.Commands.legacyRepair, repairCommand, false)
    end
end

AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() and resourceName ~= 'lb-phone' then return end
    SetTimeout(resourceName == 'lb-phone' and 500 or 0, readLbPhoneState)
end)

AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() or resourceName == 'lb-phone' then
        stopTouchFaults()
        state.phoneOpen = false
        state.phoneOnScreen = false
        setVisualState('closed')
    end
end)

exports('GetDamageState', function()
    return {
        phoneNumber = state.phoneNumber,
        damageLevel = state.damageLevel,
        damageSeed = state.damageSeed,
        phoneOpen = state.phoneOpen,
        phoneOnScreen = state.phoneOnScreen
    }
end)

debugLog('Client loaded')
