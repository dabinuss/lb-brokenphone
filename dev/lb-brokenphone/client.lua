local state = {
    phoneNumber = nil,
    damageLevel = 0,
    damageSeed = 0,
    fireLevel = 0,
    fireSeed = 0,
    isHacked = false,
    hackExpiresAt = 0,
    damageColor = 'black',
    phoneOpen = false,
    phoneOnScreen = false,
    visualState = 'closed'
}

local transitionToken = 0
local touchToken = 0
local touchFaultActive = false
local lastNuiStateKey = nil

local function normalizeDamageColor(value)
    return value == 'white' and 'white' or 'black'
end

local function debugLog(message)
    if Config.Debug then
        print(('^3[lb-brokenphone]^7 %s'):format(tostring(message)))
    end
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

local function sendNuiUpdate(force)
    local stateKey = table.concat({
        state.visualState,
        state.damageLevel,
        state.damageSeed,
        state.fireLevel,
        state.fireSeed,
        state.isHacked and 1 or 0,
        state.hackExpiresAt,
        state.damageColor,
        Config.Hack.image,
        Config.Hack.text,
        Config.Hack.sound,
        Config.Hack.soundVolume,
        Config.Hack.soundCooldown,
        json.encode(Config.Fire.images),
        Config.Fire.blockInput and 1 or 0,
        Config.Fire.inputBlockThreshold
    }, ':')
    if not force and stateKey == lastNuiStateKey then return end
    lastNuiStateKey = stateKey

    SendNUIMessage({
        action = 'lb-brokenphone:update',
        state = state.visualState,
        damageLevel = state.damageLevel,
        damageSeed = state.damageSeed,
        fireLevel = state.fireLevel,
        fireSeed = state.fireSeed,
        fireImages = Config.Fire.images,
        fireBlockInput = Config.Fire.blockInput,
        fireInputBlockThreshold = Config.Fire.inputBlockThreshold,
        isHacked = state.isHacked,
        hackExpiresAt = state.hackExpiresAt,
        damageColor = state.damageColor,
        hackImage = Config.Hack.image,
        hackText = Config.Hack.text,
        hackSound = Config.Hack.sound,
        hackSoundVolume = Config.Hack.soundVolume,
        hackSoundCooldown = Config.Hack.soundCooldown
    })
end

RegisterNUICallback('ready', function(_, callback)
    sendNuiUpdate(true)
    callback({ ok = true })
end)

local function setVisualState(value)
    if state.visualState == value then return end
    state.visualState = value
    sendNuiUpdate()
end

local function stopTouchFaults()
    touchToken = touchToken + 1
    if touchFaultActive then
        SendNUIMessage({
            action = 'lb-brokenphone:touchFault',
            active = false
        })
        touchFaultActive = false
    end
    -- Recover from older versions that used LB Phone's global disabled state.
    lbExport('ToggleDisabled', false)
end

local function touchFaultsNeeded()
    return Config.Touch.enabled == true
        and state.damageLevel >= 2
        and state.damageLevel <= 3
        and state.phoneOpen
        and state.phoneOnScreen
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
            SendNUIMessage({
                action = 'lb-brokenphone:touchFault',
                active = true
            })
            Wait(math.random(profile.durationMin, profile.durationMax))
            if touchFaultActive then
                SendNUIMessage({
                    action = 'lb-brokenphone:touchFault',
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
    local shouldShow = state.phoneOpen and state.phoneOnScreen
        and (state.damageLevel > 0 or state.fireLevel > 0 or state.isHacked)

    if shouldShow then
        setVisualState('opening')
        SetTimeout(Config.Transition.openDuration, function()
            if token == transitionToken and state.phoneOpen and state.phoneOnScreen
                and (state.damageLevel > 0 or state.fireLevel > 0 or state.isHacked) then
                setVisualState('open')
            end
        end)
    elseif state.visualState ~= 'closed' then
        setVisualState('closing')
        SetTimeout(Config.Transition.closeDuration, function()
            if token == transitionToken and not (state.phoneOpen and state.phoneOnScreen
                and (state.damageLevel > 0 or state.fireLevel > 0 or state.isHacked)) then
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
    state.fireLevel = 0
    state.fireSeed = 0
    state.isHacked = false
    state.hackExpiresAt = 0
    updateVisibility()
    TriggerServerEvent('lb-brokenphone:server:syncPhone')
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
end

RegisterNetEvent('lb-brokenphone:client:receiveDamage', function(
    phoneNumber, damageLevel, damageSeed, fireLevel, fireSeed, isHacked, hackExpiresAt
)
    if phoneNumber ~= state.phoneNumber then return end
    state.damageLevel = math.max(0, math.min(3, tonumber(damageLevel) or 0))
    state.damageSeed = tonumber(damageSeed) or 0
    state.fireLevel = math.max(0, math.min(2, tonumber(fireLevel) or 0))
    state.fireSeed = tonumber(fireSeed) or 0
    state.isHacked = isHacked == true
    state.hackExpiresAt = state.isHacked and math.max(0, tonumber(hackExpiresAt) or 0) or 0
    updateVisibility()
end)

RegisterNetEvent('lb-brokenphone:client:setDamageColor', function(damageColor)
    local nextColor = normalizeDamageColor(damageColor)
    if state.damageColor == nextColor then return end
    state.damageColor = nextColor
    sendNuiUpdate()
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
        fireLevel = state.fireLevel,
        fireSeed = state.fireSeed,
        isHacked = state.isHacked,
        hackExpiresAt = state.hackExpiresAt,
        damageColor = state.damageColor,
        phoneOpen = state.phoneOpen,
        phoneOnScreen = state.phoneOnScreen
    }
end)

debugLog('Client loaded')
