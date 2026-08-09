local activePhoneBySource = {}
local fallbackData = {}
local databaseMode = nil
local databaseReady = false
local databaseStarting = false
local databaseWaiters = {}

local tableName = tostring(Config.Database.tableName or 'phone_damage')
local fallbackPath = tostring(Config.Database.jsonFile or 'data/phone_damage.json')

assert(tableName:match('^[%w_]+$'), 'Config.Database.tableName contains invalid characters')

local function debugLog(...)
    if Config.Debug then print('[lb-phone-damage]', ...) end
end

local function normalizePhoneNumber(phoneNumber)
    if phoneNumber == nil then return nil end
    local value = tostring(phoneNumber):gsub('%s+', '')
    if value == '' or #value > Config.MaxPhoneNumberLength then return nil end
    if value:find('[%c]') then return nil end
    return value
end

local function normalizeLevel(level)
    level = tonumber(level)
    if not level or level % 1 ~= 0 or level < 1 or level > 3 then return nil end
    return level
end

local function loadFallbackData()
    local raw = LoadResourceFile(GetCurrentResourceName(), fallbackPath)
    if not raw or raw == '' then
        fallbackData = {}
        return
    end

    local ok, data = pcall(json.decode, raw)
    fallbackData = ok and type(data) == 'table' and data or {}
end

local function saveFallbackData()
    local ok = SaveResourceFile(GetCurrentResourceName(), fallbackPath, json.encode(fallbackData), -1)
    if not ok then print(('[lb-phone-damage] Failed to save %s'):format(fallbackPath)) end
    return ok
end

local function finishDatabaseStart(mode)
    databaseMode = mode
    databaseReady = true
    databaseStarting = false
    for i = 1, #databaseWaiters do databaseWaiters[i]() end
    databaseWaiters = {}
    print(('[lb-phone-damage] Persistence ready (%s).'):format(mode))
end

local function ensureDatabase(callback)
    if databaseReady then return callback() end
    databaseWaiters[#databaseWaiters + 1] = callback
    if databaseStarting then return end
    databaseStarting = true

    if GetResourceState('oxmysql') == 'started' then
        local sql = ([=[
            CREATE TABLE IF NOT EXISTS `%s` (
                `phone_number` VARCHAR(32) NOT NULL,
                `damage_level` TINYINT UNSIGNED NOT NULL,
                `damage_seed` INT UNSIGNED NOT NULL,
                PRIMARY KEY (`phone_number`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
        ]=]):format(tableName)

        exports.oxmysql:query(sql, {}, function()
            finishDatabaseStart('oxmysql')
        end)
        return
    end

    if not Config.Database.allowJsonFallback then
        error('oxmysql is not started and JSON fallback is disabled')
    end

    loadFallbackData()
    finishDatabaseStart('json')
end

local function query(sql, params, callback)
    exports.oxmysql:query(sql, params or {}, callback)
end

local function getDamage(phoneNumber, callback)
    phoneNumber = normalizePhoneNumber(phoneNumber)
    if not phoneNumber then return callback(nil, 'invalid_phone_number') end

    ensureDatabase(function()
        if databaseMode == 'json' then
            local row = fallbackData[phoneNumber]
            if not row then return callback(nil) end
            return callback({
                damageLevel = tonumber(row.damageLevel) or 0,
                damageSeed = tonumber(row.damageSeed) or 0
            })
        end

        query(('SELECT damage_level AS damageLevel, damage_seed AS damageSeed FROM `%s` WHERE phone_number = ? LIMIT 1'):format(tableName), { phoneNumber }, function(rows)
            local row = rows and rows[1]
            if not row then return callback(nil) end
            callback({ damageLevel = tonumber(row.damageLevel) or 0, damageSeed = tonumber(row.damageSeed) or 0 })
        end)
    end)
end

local function applyDamage(phoneNumber, level, cause, callback)
    phoneNumber = normalizePhoneNumber(phoneNumber)
    level = normalizeLevel(level)
    if not phoneNumber then return callback(false, 'invalid_phone_number') end
    if not level then return callback(false, 'invalid_damage_level') end

    local seed = math.random(1, 2147483647)
    ensureDatabase(function()
        if databaseMode == 'json' then
            local current = fallbackData[phoneNumber]
            if not current then
                fallbackData[phoneNumber] = { damageLevel = level, damageSeed = seed }
                if not saveFallbackData() then return callback(false, 'persistence_failed') end
            elseif level > (tonumber(current.damageLevel) or 0) then
                current.damageLevel = level
                if not saveFallbackData() then return callback(false, 'persistence_failed') end
            end
            local result = fallbackData[phoneNumber]
            debugLog('Damage applied', phoneNumber, level, cause or 'unknown')
            return callback(true, nil, result)
        end

        local sql = ([=[
            INSERT INTO `%s` (`phone_number`, `damage_level`, `damage_seed`) VALUES (?, ?, ?)
            ON DUPLICATE KEY UPDATE
                `damage_level` = GREATEST(`damage_level`, VALUES(`damage_level`))
        ]=]):format(tableName)
        query(sql, { phoneNumber, level, seed }, function()
            debugLog('Damage applied', phoneNumber, level, cause or 'unknown')
            getDamage(phoneNumber, function(result)
                callback(true, nil, result)
            end)
        end)
    end)
end

local function repairDamage(phoneNumber, callback)
    phoneNumber = normalizePhoneNumber(phoneNumber)
    if not phoneNumber then return callback(false, 'invalid_phone_number') end

    ensureDatabase(function()
        if databaseMode == 'json' then
            fallbackData[phoneNumber] = nil
            if not saveFallbackData() then return callback(false, 'persistence_failed') end
            return callback(true)
        end

        query(('DELETE FROM `%s` WHERE phone_number = ?'):format(tableName), { phoneNumber }, function()
            callback(true)
        end)
    end)
end

local function resolveEquippedPhone(playerSource)
    playerSource = tonumber(playerSource)
    if not playerSource or playerSource <= 0 or GetResourceState('lb-phone') ~= 'started' then return nil end
    local ok, phoneNumber = pcall(function()
        return exports['lb-phone']:GetEquippedPhoneNumber(playerSource)
    end)
    return ok and normalizePhoneNumber(phoneNumber) or nil
end

local function sendDamage(playerSource, phoneNumber)
    getDamage(phoneNumber, function(result)
        TriggerClientEvent(
            'lb-phone-damage:client:receiveDamage',
            playerSource,
            phoneNumber,
            result and result.damageLevel or 0,
            result and result.damageSeed or 0
        )
    end)
end

local function notifyPhoneUsers(phoneNumber)
    phoneNumber = normalizePhoneNumber(phoneNumber)
    if not phoneNumber then return end

    for playerSource, trackedPhone in pairs(activePhoneBySource) do
        if trackedPhone == phoneNumber then sendDamage(playerSource, phoneNumber) end
    end
end

local function awaitResult(startOperation)
    local pending = promise.new()
    startOperation(function(...)
        pending:resolve(table.pack(...))
    end)
    local result = Citizen.Await(pending)
    return table.unpack(result, 1, result.n)
end

local function applyByNumber(phoneNumber, level, cause)
    phoneNumber = normalizePhoneNumber(phoneNumber)
    local success, err, result = awaitResult(function(done)
        applyDamage(phoneNumber, level, cause, done)
    end)
    if success then notifyPhoneUsers(phoneNumber) end
    return success, err, result
end

local function repairByNumber(phoneNumber)
    phoneNumber = normalizePhoneNumber(phoneNumber)
    local success, err = awaitResult(function(done)
        repairDamage(phoneNumber, done)
    end)
    if success then notifyPhoneUsers(phoneNumber) end
    return success, err
end

local function escalateByNumber(phoneNumber, cause)
    phoneNumber = normalizePhoneNumber(phoneNumber)
    if not phoneNumber then return false, 'invalid_phone_number' end

    local current, err = awaitResult(function(done)
        getDamage(phoneNumber, done)
    end)
    if err then return false, err end

    local currentLevel = current and (tonumber(current.damageLevel) or 0) or 0
    if currentLevel >= 3 then return true, nil, current end
    return applyByNumber(phoneNumber, currentLevel + 1, cause or 'escalation')
end

local function commandReply(playerSource, message, success)
    print(('[lb-phone-damage] %s'):format(message))
    if playerSource and playerSource > 0 then
        TriggerClientEvent('lb-phone-damage:client:commandResult', playerSource, message, success)
        TriggerClientEvent('chat:addMessage', playerSource, {
            args = { success == false and '^1[lb-phone-damage]' or '^2[lb-phone-damage]', message }
        })
    end
end

local function hasTestCommandPermission(playerSource)
    if playerSource == 0 then return true end
    if not Config.Commands.restricted then return true end
    return IsPlayerAceAllowed(playerSource, ('command.%s'):format(Config.Commands.setDamage))
        or IsPlayerAceAllowed(playerSource, ('command.%s'):format(Config.Commands.repair))
        or (Config.Commands.legacySetDamage and IsPlayerAceAllowed(playerSource, ('command.%s'):format(Config.Commands.legacySetDamage)))
        or (Config.Commands.legacyRepair and IsPlayerAceAllowed(playerSource, ('command.%s'):format(Config.Commands.legacyRepair)))
end

RegisterNetEvent('lb-phone-damage:server:testDamage', function(level, requestedPhoneNumber)
    local playerSource = source
    if not hasTestCommandPermission(playerSource) then
        return commandReply(playerSource, 'You do not have permission to use this command.', false)
    end

    level = normalizeLevel(level)
    local equippedPhone = resolveEquippedPhone(playerSource)
    local requestedPhone = normalizePhoneNumber(requestedPhoneNumber)
    if not Config.Commands.restricted and requestedPhone and requestedPhone ~= equippedPhone then
        return commandReply(playerSource, 'You can only test the phone you currently have equipped.', false)
    end
    local phoneNumber = requestedPhone or equippedPhone
    if not level then return commandReply(playerSource, 'Damage level must be 1, 2, or 3.', false) end
    if not phoneNumber then return commandReply(playerSource, 'No equipped phone found.', false) end

    activePhoneBySource[playerSource] = resolveEquippedPhone(playerSource)
    local success, err, result = applyByNumber(phoneNumber, level, 'test_command')
    commandReply(playerSource, success
        and ('%s is damage level %d (seed %d).'):format(phoneNumber, result.damageLevel, result.damageSeed)
        or ('Damage failed: %s'):format(err or 'unknown_error'), success)
end)

RegisterNetEvent('lb-phone-damage:server:testRepair', function(requestedPhoneNumber)
    local playerSource = source
    if not hasTestCommandPermission(playerSource) then
        return commandReply(playerSource, 'You do not have permission to use this command.', false)
    end

    local equippedPhone = resolveEquippedPhone(playerSource)
    local requestedPhone = normalizePhoneNumber(requestedPhoneNumber)
    if not Config.Commands.restricted and requestedPhone and requestedPhone ~= equippedPhone then
        return commandReply(playerSource, 'You can only repair the phone you currently have equipped.', false)
    end
    local phoneNumber = requestedPhone or equippedPhone
    if not phoneNumber then return commandReply(playerSource, 'No equipped phone found.', false) end

    activePhoneBySource[playerSource] = resolveEquippedPhone(playerSource)
    local success, err = repairByNumber(phoneNumber)
    commandReply(playerSource, success
        and ('Repaired %s.'):format(phoneNumber)
        or ('Repair failed: %s'):format(err or 'unknown_error'), success)
end)

RegisterNetEvent('lb-phone-damage:server:syncPhone', function()
    local playerSource = source
    local phoneNumber = resolveEquippedPhone(playerSource)
    activePhoneBySource[playerSource] = phoneNumber
    if phoneNumber then sendDamage(playerSource, phoneNumber) end
end)

AddEventHandler('lb-phone:numberChanged', function(playerSource)
    playerSource = tonumber(playerSource)
    if not playerSource then return end
    local phoneNumber = resolveEquippedPhone(playerSource)
    activePhoneBySource[playerSource] = phoneNumber
    if phoneNumber then sendDamage(playerSource, phoneNumber) end
end)

AddEventHandler('playerDropped', function()
    activePhoneBySource[source] = nil
end)

exports('ApplyPhoneDamage', function(playerSource, level, cause)
    local phoneNumber = resolveEquippedPhone(playerSource)
    if not phoneNumber then return false, 'no_equipped_phone' end
    activePhoneBySource[tonumber(playerSource)] = phoneNumber
    return applyByNumber(phoneNumber, level, cause)
end)

exports('ApplyPhoneDamageByNumber', applyByNumber)

exports('EscalatePhoneDamage', function(playerSource, cause)
    local phoneNumber = resolveEquippedPhone(playerSource)
    if not phoneNumber then return false, 'no_equipped_phone' end
    activePhoneBySource[tonumber(playerSource)] = phoneNumber
    return escalateByNumber(phoneNumber, cause)
end)

exports('EscalatePhoneDamageByNumber', escalateByNumber)

exports('GetPhoneDamage', function(phoneNumber)
    local result, err = awaitResult(function(done)
        getDamage(phoneNumber, done)
    end)
    if err then return nil, err end
    return result or { damageLevel = 0, damageSeed = 0 }
end)

exports('RepairPhone', function(playerSource)
    local phoneNumber = resolveEquippedPhone(playerSource)
    if not phoneNumber then return false, 'no_equipped_phone' end
    activePhoneBySource[tonumber(playerSource)] = phoneNumber
    return repairByNumber(phoneNumber)
end)

exports('RepairPhoneByNumber', repairByNumber)

if Config.Commands.enabled then
    local function damageCommand(playerSource, args)
        local level = normalizeLevel(args[1])
        local phoneNumber = normalizePhoneNumber(args[2])
        if not level then
            commandReply(playerSource, ('Usage: /%s <1-3> [phoneNumber]'):format(Config.Commands.setDamage), false)
            return
        end
        if not phoneNumber then phoneNumber = resolveEquippedPhone(playerSource) end
        if not phoneNumber then
            commandReply(playerSource, 'No equipped phone; console usage requires a phone number.', false)
            return
        end

        local success, err, result = applyByNumber(phoneNumber, level, 'test_command')
        commandReply(playerSource, success
            and ('%s is damage level %d (seed %d).'):format(phoneNumber, result.damageLevel, result.damageSeed)
            or ('Damage failed: %s'):format(err or 'unknown_error'), success)
    end

    local function repairCommand(playerSource, args)
        local phoneNumber = normalizePhoneNumber(args[1]) or resolveEquippedPhone(playerSource)
        if not phoneNumber then
            commandReply(playerSource, ('Usage: /%s [phoneNumber]'):format(Config.Commands.repair), false)
            return
        end
        local success, err = repairByNumber(phoneNumber)
        commandReply(playerSource, success
            and ('Repaired %s.'):format(phoneNumber)
            or ('Repair failed: %s'):format(err or 'unknown_error'), success)
    end

    RegisterCommand(Config.Commands.setDamage, damageCommand, Config.Commands.restricted)
    RegisterCommand(Config.Commands.repair, repairCommand, Config.Commands.restricted)

    if Config.Commands.legacySetDamage and Config.Commands.legacySetDamage ~= Config.Commands.setDamage then
        RegisterCommand(Config.Commands.legacySetDamage, damageCommand, Config.Commands.restricted)
    end
    if Config.Commands.legacyRepair and Config.Commands.legacyRepair ~= Config.Commands.repair then
        RegisterCommand(Config.Commands.legacyRepair, repairCommand, Config.Commands.restricted)
    end
end

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    math.randomseed(os.time())
    ensureDatabase(function() end)
end)
