local activePhoneBySource = {}
local activeSourcesByPhone = {}
local damageByPhone = {}
local fallbackData = {}
local databaseMode = nil
local databaseReady = false
local databaseStarting = false
local databaseWaiters = {}
local managerQueue = {}
local managerQueueHead = 1
local managerRunning = false
local damageColor = Config.DamageColor == 'white' and 'white' or 'black'

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

local function normalizeDamageColor(value)
    value = type(value) == 'string' and value:lower() or nil
    if value == 'black' or value == 'white' then return value end
    return nil
end

local function sendDamageColor(playerSource)
    TriggerClientEvent('lb-phone-damage:client:setDamageColor', playerSource, damageColor)
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
    local waiters = databaseWaiters
    databaseWaiters = {}
    for i = 1, #waiters do waiters[i](true) end
    print(('[lb-phone-damage] Persistence ready (%s).'):format(mode))
end

local function failDatabaseStart(err)
    databaseStarting = false
    local message = tostring(err or 'database_initialization_failed')
    print(('^1[lb-phone-damage] Persistence initialization failed: %s^7'):format(message))
    local waiters = databaseWaiters
    databaseWaiters = {}
    for i = 1, #waiters do waiters[i](false, message) end
end

local function ensureDatabase(callback)
    if databaseReady then return callback(true) end
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

        local invoked, invokeError = pcall(function()
            exports.oxmysql.query(nil, sql, {}, function(result, err)
                if err or result == nil then
                    return failDatabaseStart(err or 'database_initialization_failed')
                end
                finishDatabaseStart('oxmysql')
            end, GetCurrentResourceName(), true)
        end)
        if not invoked then failDatabaseStart(invokeError) end
        return
    end

    if not Config.Database.allowJsonFallback then
        return failDatabaseStart('oxmysql_not_started')
    end

    loadFallbackData()
    finishDatabaseStart('json')
end

local function query(sql, params, callback)
    local invoked, invokeError = pcall(function()
        exports.oxmysql.query(nil, sql, params or {}, callback, GetCurrentResourceName(), true)
    end)
    if not invoked then callback(nil, tostring(invokeError)) end
end

local function loadDamageFromStorage(phoneNumber, callback)
    phoneNumber = normalizePhoneNumber(phoneNumber)
    if not phoneNumber then return callback(nil, 'invalid_phone_number') end

    ensureDatabase(function(ready, databaseError)
        if not ready then return callback(nil, databaseError or 'database_unavailable') end
        if databaseMode == 'json' then
            local row = fallbackData[phoneNumber]
            if not row then return callback(nil) end
            return callback({
                damageLevel = tonumber(row.damageLevel) or 0,
                damageSeed = tonumber(row.damageSeed) or 0
            })
        end

        query(('SELECT damage_level AS damageLevel, damage_seed AS damageSeed FROM `%s` WHERE phone_number = ? LIMIT 1'):format(tableName), { phoneNumber }, function(rows, err)
            if err then return callback(nil, 'database_query_failed') end
            local row = rows and rows[1]
            if not row then return callback(nil) end
            callback({ damageLevel = tonumber(row.damageLevel) or 0, damageSeed = tonumber(row.damageSeed) or 0 })
        end)
    end)
end

local function persistDamageState(phoneNumber, state, callback)
    ensureDatabase(function(ready, databaseError)
        if not ready then return callback(false, databaseError or 'database_unavailable') end
        if databaseMode == 'json' then
            fallbackData[phoneNumber] = {
                damageLevel = state.damageLevel,
                damageSeed = state.damageSeed
            }
            local saved = saveFallbackData()
            return callback(saved, saved and nil or 'persistence_failed')
        end

        local sql = ([=[
            INSERT INTO `%s` (`phone_number`, `damage_level`, `damage_seed`) VALUES (?, ?, ?)
            ON DUPLICATE KEY UPDATE
                `damage_level` = GREATEST(`damage_level`, VALUES(`damage_level`)),
                `damage_seed` = CASE
                    WHEN `damage_seed` = 0 THEN VALUES(`damage_seed`)
                    ELSE `damage_seed`
                END
        ]=]):format(tableName)
        query(sql, { phoneNumber, state.damageLevel, state.damageSeed }, function(_, err)
            if err then return callback(false, 'database_query_failed') end
            callback(true)
        end)
    end)
end

local function persistRepair(phoneNumber, callback)
    ensureDatabase(function(ready, databaseError)
        if not ready then return callback(false, databaseError or 'database_unavailable') end
        if databaseMode == 'json' then
            fallbackData[phoneNumber] = nil
            if not saveFallbackData() then return callback(false, 'persistence_failed') end
            return callback(true)
        end

        query(('DELETE FROM `%s` WHERE phone_number = ?'):format(tableName), { phoneNumber }, function(_, err)
            if err then return callback(false, 'database_query_failed') end
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

local function awaitResult(startOperation)
    local pending = promise.new()
    startOperation(function(...)
        pending:resolve(table.pack(...))
    end)
    local result = Citizen.Await(pending)
    return table.unpack(result, 1, result.n)
end

local function copyDamageState(state)
    return {
        damageLevel = tonumber(state and state.damageLevel) or 0,
        damageSeed = tonumber(state and state.damageSeed) or 0
    }
end

local function processManagerQueue()
    if managerRunning then return end
    managerRunning = true

    CreateThread(function()
        while managerQueueHead <= #managerQueue do
            local job = managerQueue[managerQueueHead]
            managerQueueHead = managerQueueHead + 1
            local ok, result = pcall(function()
                return table.pack(job.operation())
            end)
            job.pending:resolve({ ok = ok, result = result })
        end
        managerQueue = {}
        managerQueueHead = 1
        managerRunning = false
    end)
end

local function runManaged(operation)
    local pending = promise.new()
    managerQueue[#managerQueue + 1] = { operation = operation, pending = pending }
    processManagerQueue()

    local response = Citizen.Await(pending)
    if not response.ok then error(response.result, 2) end
    return table.unpack(response.result, 1, response.result.n)
end

local function setActivePhone(playerSource, phoneNumber)
    playerSource = tonumber(playerSource)
    if not playerSource or playerSource <= 0 then return end
    phoneNumber = normalizePhoneNumber(phoneNumber)

    local previousPhone = activePhoneBySource[playerSource]
    if previousPhone == phoneNumber then return end
    if previousPhone then
        local previousSources = activeSourcesByPhone[previousPhone]
        if previousSources then
            previousSources[playerSource] = nil
            if not next(previousSources) then activeSourcesByPhone[previousPhone] = nil end
        end
    end

    activePhoneBySource[playerSource] = phoneNumber
    if phoneNumber then
        local sources = activeSourcesByPhone[phoneNumber]
        if not sources then
            sources = {}
            activeSourcesByPhone[phoneNumber] = sources
        end
        sources[playerSource] = true
    end
end

local function sendDamageState(playerSource, phoneNumber, state)
    TriggerClientEvent(
        'lb-phone-damage:client:receiveDamage',
        playerSource,
        phoneNumber,
        state.damageLevel,
        state.damageSeed
    )
end

local function notifyPhoneUsers(phoneNumber, state)
    local sources = activeSourcesByPhone[phoneNumber]
    if not sources then return end
    for playerSource in pairs(sources) do
        sendDamageState(playerSource, phoneNumber, state)
    end
end

local function getCachedDamageUnlocked(phoneNumber)
    phoneNumber = normalizePhoneNumber(phoneNumber)
    if not phoneNumber then return nil, 'invalid_phone_number' end
    if damageByPhone[phoneNumber] then return copyDamageState(damageByPhone[phoneNumber]) end

    local result, err = awaitResult(function(done)
        loadDamageFromStorage(phoneNumber, done)
    end)
    if err then return nil, err end

    local state = copyDamageState(result)
    damageByPhone[phoneNumber] = state
    return copyDamageState(state)
end

local function syncPhoneUnlocked(playerSource, phoneNumber)
    local state, err = getCachedDamageUnlocked(phoneNumber)
    if err then
        print(('^1[lb-phone-damage] Failed to load damage for %s: %s^7'):format(
            tostring(phoneNumber), tostring(err)
        ))
        return false, err
    end
    sendDamageState(playerSource, phoneNumber, state)
    return true
end

local function applyByNumberUnlocked(phoneNumber, level, cause)
    phoneNumber = normalizePhoneNumber(phoneNumber)
    level = normalizeLevel(level)
    if not phoneNumber then return false, 'invalid_phone_number' end
    if not level then return false, 'invalid_damage_level' end

    local current, loadError = getCachedDamageUnlocked(phoneNumber)
    if loadError then return false, loadError end
    if level <= current.damageLevel then
        notifyPhoneUsers(phoneNumber, current)
        return true, nil, current
    end

    local state = {
        damageLevel = level,
        damageSeed = current.damageSeed > 0 and current.damageSeed or math.random(1, 2147483647)
    }
    local success, err = awaitResult(function(done)
        persistDamageState(phoneNumber, state, done)
    end)
    if not success then return false, err end

    damageByPhone[phoneNumber] = state
    notifyPhoneUsers(phoneNumber, state)
    debugLog('Damage applied', phoneNumber, level, cause or 'unknown')
    return true, nil, copyDamageState(state)
end

local function repairByNumberUnlocked(phoneNumber)
    phoneNumber = normalizePhoneNumber(phoneNumber)
    if not phoneNumber then return false, 'invalid_phone_number' end
    local success, err = awaitResult(function(done)
        persistRepair(phoneNumber, done)
    end)
    if not success then return false, err end

    local state = { damageLevel = 0, damageSeed = 0 }
    damageByPhone[phoneNumber] = state
    notifyPhoneUsers(phoneNumber, state)
    return true
end

local function escalateByNumberUnlocked(phoneNumber, cause)
    phoneNumber = normalizePhoneNumber(phoneNumber)
    if not phoneNumber then return false, 'invalid_phone_number' end

    local current, err = getCachedDamageUnlocked(phoneNumber)
    if err then return false, err end

    if current.damageLevel >= 3 then return true, nil, current end
    return applyByNumberUnlocked(phoneNumber, current.damageLevel + 1, cause or 'escalation')
end

local function applyDamageDeltaByNumberUnlocked(phoneNumber, escalation, maxResultLevel, cause)
    phoneNumber = normalizePhoneNumber(phoneNumber)
    escalation = tonumber(escalation)
    maxResultLevel = tonumber(maxResultLevel or 3)
    if not phoneNumber then return false, 'invalid_phone_number' end
    if not escalation or escalation % 1 ~= 0 or escalation < 1 or escalation > 3 then
        return false, 'invalid_escalation'
    end
    if not maxResultLevel or maxResultLevel % 1 ~= 0 or maxResultLevel < 1 or maxResultLevel > 3 then
        return false, 'invalid_max_result_level'
    end

    local current, err = getCachedDamageUnlocked(phoneNumber)
    if err then return false, err end
    if current.damageLevel >= maxResultLevel then
        notifyPhoneUsers(phoneNumber, current)
        return true, nil, current, false
    end

    local targetLevel = math.min(3, maxResultLevel, current.damageLevel + escalation)
    local success, applyError, state = applyByNumberUnlocked(phoneNumber, targetLevel, cause or 'damage_delta')
    return success, applyError, state, success == true and targetLevel > current.damageLevel
end

local function applyByNumber(phoneNumber, level, cause)
    return runManaged(function()
        return applyByNumberUnlocked(phoneNumber, level, cause)
    end)
end

local function repairByNumber(phoneNumber)
    return runManaged(function()
        return repairByNumberUnlocked(phoneNumber)
    end)
end

local function escalateByNumber(phoneNumber, cause)
    return runManaged(function()
        return escalateByNumberUnlocked(phoneNumber, cause)
    end)
end

local function applyDamageDeltaByNumber(phoneNumber, escalation, maxResultLevel, cause)
    return runManaged(function()
        return applyDamageDeltaByNumberUnlocked(phoneNumber, escalation, maxResultLevel, cause)
    end)
end

local function applyPhoneDamageDelta(playerSource, escalation, maxResultLevel, cause)
    local phoneNumber = resolveEquippedPhone(playerSource)
    if not phoneNumber then return false, 'no_equipped_phone' end
    setActivePhone(playerSource, phoneNumber)
    return applyDamageDeltaByNumber(phoneNumber, escalation, maxResultLevel, cause)
end

local function collectBulkPhones(sources)
    if type(sources) ~= 'table' then return nil, { requested = 0, invalidSources = 1 }, 'invalid_sources' end

    local phones = {}
    local seenPhones = {}
    local summary = { requested = 0, resolved = 0, invalidSources = 0, noPhone = 0, uniquePhones = 0 }
    for _, rawSource in ipairs(sources) do
        summary.requested = summary.requested + 1
        local playerSource = tonumber(rawSource)
        if not playerSource or playerSource <= 0 then
            summary.invalidSources = summary.invalidSources + 1
        else
            local phoneNumber = resolveEquippedPhone(playerSource)
            if not phoneNumber then
                summary.noPhone = summary.noPhone + 1
            else
                summary.resolved = summary.resolved + 1
                setActivePhone(playerSource, phoneNumber)
                if not seenPhones[phoneNumber] then
                    seenPhones[phoneNumber] = true
                    phones[#phones + 1] = phoneNumber
                end
            end
        end

        if summary.requested % Config.Persistence.resolveYieldEvery == 0 then Wait(0) end
    end

    table.sort(phones)
    summary.uniquePhones = #phones
    return phones, summary
end

local function hydrateDamageCacheUnlocked(phoneNumbers)
    local missing = {}
    for i = 1, #phoneNumbers do
        local phoneNumber = phoneNumbers[i]
        if not damageByPhone[phoneNumber] then missing[#missing + 1] = phoneNumber end
    end
    if #missing == 0 then return true end

    local ready, databaseError = awaitResult(function(done)
        ensureDatabase(done)
    end)
    if not ready then return false, databaseError or 'database_unavailable' end

    if databaseMode == 'json' then
        for i = 1, #missing do
            local phoneNumber = missing[i]
            damageByPhone[phoneNumber] = copyDamageState(fallbackData[phoneNumber])
        end
        return true
    end

    local readBatchSize = Config.Persistence.readBatchSize
    for first = 1, #missing, readBatchSize do
        local last = math.min(first + readBatchSize - 1, #missing)
        local placeholders = {}
        local params = {}
        local found = {}
        for index = first, last do
            placeholders[#placeholders + 1] = '?'
            params[#params + 1] = missing[index]
        end

        local sql = ('SELECT phone_number AS phoneNumber, damage_level AS damageLevel, damage_seed AS damageSeed FROM `%s` WHERE phone_number IN (%s)')
            :format(tableName, table.concat(placeholders, ', '))
        local rows, queryError = awaitResult(function(done)
            query(sql, params, done)
        end)
        if queryError then return false, 'database_query_failed' end

        for _, row in ipairs(rows or {}) do
            local phoneNumber = normalizePhoneNumber(row.phoneNumber)
            if phoneNumber then
                damageByPhone[phoneNumber] = copyDamageState(row)
                found[phoneNumber] = true
            end
        end
        for index = first, last do
            local phoneNumber = missing[index]
            if not found[phoneNumber] then damageByPhone[phoneNumber] = { damageLevel = 0, damageSeed = 0 } end
        end

        if last < #missing and Config.Persistence.batchDelay > 0 then Wait(Config.Persistence.batchDelay) end
    end
    return true
end

local function persistBulkDamageUnlocked(changes)
    if #changes == 0 then return true, nil, 0 end

    local ready, databaseError = awaitResult(function(done)
        ensureDatabase(done)
    end)
    if not ready then return false, databaseError or 'database_unavailable', 0 end

    if databaseMode == 'json' then
        for i = 1, #changes do
            local change = changes[i]
            fallbackData[change.phoneNumber] = copyDamageState(change.state)
        end
        if not saveFallbackData() then return false, 'persistence_failed', 0 end
        for i = 1, #changes do
            local change = changes[i]
            damageByPhone[change.phoneNumber] = change.state
            notifyPhoneUsers(change.phoneNumber, change.state)
        end
        return true, nil, #changes
    end

    local applied = 0
    local batchSize = Config.Persistence.batchSize
    for first = 1, #changes, batchSize do
        local last = math.min(first + batchSize - 1, #changes)
        local values = {}
        local params = {}
        for index = first, last do
            local change = changes[index]
            values[#values + 1] = '(?, ?, ?)'
            params[#params + 1] = change.phoneNumber
            params[#params + 1] = change.state.damageLevel
            params[#params + 1] = change.state.damageSeed
        end

        local sql = ([=[
            INSERT INTO `%s` (`phone_number`, `damage_level`, `damage_seed`) VALUES %s
            ON DUPLICATE KEY UPDATE
                `damage_level` = GREATEST(`damage_level`, VALUES(`damage_level`)),
                `damage_seed` = CASE
                    WHEN `damage_seed` = 0 THEN VALUES(`damage_seed`)
                    ELSE `damage_seed`
                END
        ]=]):format(tableName, table.concat(values, ', '))
        local _, queryError = awaitResult(function(done)
            query(sql, params, done)
        end)
        if queryError then return false, 'database_query_failed', applied end

        for index = first, last do
            local change = changes[index]
            damageByPhone[change.phoneNumber] = change.state
            notifyPhoneUsers(change.phoneNumber, change.state)
            applied = applied + 1
        end
        if last < #changes and Config.Persistence.batchDelay > 0 then Wait(Config.Persistence.batchDelay) end
    end
    return true, nil, applied
end

local function persistBulkRepairUnlocked(phoneNumbers)
    if #phoneNumbers == 0 then return true, nil, 0 end

    local ready, databaseError = awaitResult(function(done)
        ensureDatabase(done)
    end)
    if not ready then return false, databaseError or 'database_unavailable', 0 end

    if databaseMode == 'json' then
        for i = 1, #phoneNumbers do fallbackData[phoneNumbers[i]] = nil end
        if not saveFallbackData() then return false, 'persistence_failed', 0 end
        for i = 1, #phoneNumbers do
            local phoneNumber = phoneNumbers[i]
            local state = { damageLevel = 0, damageSeed = 0 }
            damageByPhone[phoneNumber] = state
            notifyPhoneUsers(phoneNumber, state)
        end
        return true, nil, #phoneNumbers
    end

    local applied = 0
    local batchSize = Config.Persistence.batchSize
    for first = 1, #phoneNumbers, batchSize do
        local last = math.min(first + batchSize - 1, #phoneNumbers)
        local placeholders = {}
        local params = {}
        for index = first, last do
            placeholders[#placeholders + 1] = '?'
            params[#params + 1] = phoneNumbers[index]
        end

        local sql = ('DELETE FROM `%s` WHERE phone_number IN (%s)'):format(tableName, table.concat(placeholders, ', '))
        local _, queryError = awaitResult(function(done)
            query(sql, params, done)
        end)
        if queryError then return false, 'database_query_failed', applied end

        for index = first, last do
            local phoneNumber = phoneNumbers[index]
            local state = { damageLevel = 0, damageSeed = 0 }
            damageByPhone[phoneNumber] = state
            notifyPhoneUsers(phoneNumber, state)
            applied = applied + 1
        end
        if last < #phoneNumbers and Config.Persistence.batchDelay > 0 then Wait(Config.Persistence.batchDelay) end
    end
    return true, nil, applied
end

local function processBulkDamage(sources, level, cause, escalate)
    return runManaged(function()
        local phones, summary, collectError = collectBulkPhones(sources)
        if collectError then return false, collectError, summary end
        local hydrated, hydrateError = hydrateDamageCacheUnlocked(phones)
        if not hydrated then return false, hydrateError, summary end

        local changes = {}
        summary.unchanged = 0
        for i = 1, #phones do
            local phoneNumber = phones[i]
            local current = damageByPhone[phoneNumber]
            local nextLevel = escalate and math.min(3, current.damageLevel + 1) or level
            if nextLevel > current.damageLevel then
                changes[#changes + 1] = {
                    phoneNumber = phoneNumber,
                    state = {
                        damageLevel = nextLevel,
                        damageSeed = current.damageSeed > 0 and current.damageSeed or math.random(1, 2147483647)
                    }
                }
            else
                summary.unchanged = summary.unchanged + 1
                notifyPhoneUsers(phoneNumber, current)
            end
        end

        local success, persistError, applied = persistBulkDamageUnlocked(changes)
        summary.changed = applied
        summary.pending = #changes - applied
        summary.mode = escalate and 'escalate' or 'set_level'
        debugLog('Bulk damage', cause or 'unknown', summary.uniquePhones, 'phones', applied, 'changed', summary.mode)
        return success, persistError, summary
    end)
end

local function applyBulkDamage(sources, level, cause)
    level = normalizeLevel(level)
    if not level then return false, 'invalid_damage_level' end
    return processBulkDamage(sources, level, cause, false)
end

local function escalateBulkDamage(sources, cause)
    return processBulkDamage(sources, nil, cause or 'escalation', true)
end

local function repairBulkDamage(sources)
    return runManaged(function()
        local phones, summary, collectError = collectBulkPhones(sources)
        if collectError then return false, collectError, summary end
        local success, persistError, applied = persistBulkRepairUnlocked(phones)
        summary.repaired = applied
        summary.pending = #phones - applied
        return success, persistError, summary
    end)
end

local function applyPhoneDamageToAll(level, cause)
    return applyBulkDamage(GetPlayers(), level, cause or 'all_players')
end

local function escalatePhoneDamageForAll(cause)
    return escalateBulkDamage(GetPlayers(), cause or 'all_players_escalation')
end

local function repairAllPhones()
    return repairBulkDamage(GetPlayers())
end

local function normalizeAreaCenter(coords)
    if coords == nil then return nil end
    local ok, x, y, z = pcall(function()
        return tonumber(coords.x or coords[1]), tonumber(coords.y or coords[2]), tonumber(coords.z or coords[3])
    end)
    if not ok or not x or not y or not z then return nil end
    if x ~= x or y ~= y or z ~= z then return nil end
    if math.abs(x) == math.huge or math.abs(y) == math.huge or math.abs(z) == math.huge then return nil end
    return { x = x, y = y, z = z }
end

local function normalizeAreaRadius(radius)
    radius = tonumber(radius)
    if not radius or radius ~= radius or radius <= 0 or radius > Config.MaxDamageAreaRadius then return nil end
    return radius
end

local function applyPhoneDamageInArea(coords, radius, level, cause)
    local center = normalizeAreaCenter(coords)
    radius = normalizeAreaRadius(radius)
    local escalate = level == nil
    if not escalate then level = normalizeLevel(level) end
    if not center then return false, 'invalid_area_center' end
    if not radius then return false, 'invalid_area_radius' end
    if not escalate and not level then return false, 'invalid_damage_level' end

    local radiusSquared = radius * radius
    local nearbySources = {}
    local checked = 0
    for _, rawSource in ipairs(GetPlayers()) do
        local playerSource = tonumber(rawSource)
        local ped = playerSource and GetPlayerPed(playerSource) or 0
        if ped and ped > 0 then
            local coordsOk, playerCoords = pcall(GetEntityCoords, ped)
            local px = coordsOk and playerCoords and tonumber(playerCoords.x) or nil
            local py = coordsOk and playerCoords and tonumber(playerCoords.y) or nil
            local pz = coordsOk and playerCoords and tonumber(playerCoords.z) or nil
            if px and py and pz then
                local dx = px - center.x
                local dy = py - center.y
                local dz = pz - center.z
                if dx * dx + dy * dy + dz * dz <= radiusSquared then
                    nearbySources[#nearbySources + 1] = playerSource
                end
            end
        end

        checked = checked + 1
        if checked % Config.Persistence.resolveYieldEvery == 0 then Wait(0) end
    end

    local defaultCause = cause or 'explosion'
    local success, err, summary
    if escalate then
        success, err, summary = escalateBulkDamage(nearbySources, defaultCause)
    else
        success, err, summary = applyBulkDamage(nearbySources, level, defaultCause)
    end
    if summary then
        summary.playersChecked = checked
        summary.playersInArea = #nearbySources
        summary.radius = radius
    end
    return success, err, summary
end


local function escalatePhoneDamageInArea(coords, radius, cause)
    return applyPhoneDamageInArea(coords, radius, nil, cause or 'explosion')
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

local function hasDamagePermission(playerSource)
    if playerSource == 0 then return true end
    if not Config.Commands.restricted then return true end
    return IsPlayerAceAllowed(playerSource, ('command.%s'):format(Config.Commands.setDamage))
        or (Config.Commands.legacySetDamage and IsPlayerAceAllowed(playerSource, ('command.%s'):format(Config.Commands.legacySetDamage)))
end

local function hasRepairPermission(playerSource)
    if playerSource == 0 then return true end
    if not Config.Commands.restricted then return true end
    return IsPlayerAceAllowed(playerSource, ('command.%s'):format(Config.Commands.repair))
        or (Config.Commands.legacyRepair and IsPlayerAceAllowed(playerSource, ('command.%s'):format(Config.Commands.legacyRepair)))
end

local function hasEscalatePermission(playerSource)
    if playerSource == 0 then return true end
    if not Config.Commands.restricted then return true end
    return IsPlayerAceAllowed(playerSource, ('command.%s'):format(Config.Commands.escalateDamage))
end

local function hasDamageColorPermission(playerSource)
    if playerSource == 0 then return true end
    return IsPlayerAceAllowed(playerSource, ('command.%s'):format(Config.Commands.setDamageColor))
end

local function hasDamageAllPermission(playerSource)
    if playerSource == 0 then return true end
    return IsPlayerAceAllowed(playerSource, ('command.%s'):format(Config.Commands.setDamageAll))
end

local function hasDamageAreaPermission(playerSource)
    if playerSource == 0 then return false end
    return IsPlayerAceAllowed(playerSource, ('command.%s'):format(Config.Commands.setDamageArea))
end

local function hasRepairAllPermission(playerSource)
    if playerSource == 0 then return true end
    return IsPlayerAceAllowed(playerSource, ('command.%s'):format(Config.Commands.repairAll))
end

RegisterNetEvent('lb-phone-damage:server:syncPhone', function()
    local playerSource = source
    sendDamageColor(playerSource)
    local phoneNumber = resolveEquippedPhone(playerSource)
    setActivePhone(playerSource, phoneNumber)
    if phoneNumber then
        CreateThread(function()
            runManaged(function()
                return syncPhoneUnlocked(playerSource, phoneNumber)
            end)
        end)
    end
end)

AddEventHandler('lb-phone:numberChanged', function(playerSource)
    playerSource = tonumber(playerSource)
    if not playerSource then return end
    local phoneNumber = resolveEquippedPhone(playerSource)
    setActivePhone(playerSource, phoneNumber)
    if phoneNumber then
        CreateThread(function()
            runManaged(function()
                return syncPhoneUnlocked(playerSource, phoneNumber)
            end)
        end)
    end
end)

AddEventHandler('playerDropped', function()
    setActivePhone(source, nil)
end)

exports('ApplyPhoneDamage', function(playerSource, level, cause)
    local phoneNumber = resolveEquippedPhone(playerSource)
    if not phoneNumber then return false, 'no_equipped_phone' end
    setActivePhone(playerSource, phoneNumber)
    return applyByNumber(phoneNumber, level, cause)
end)

exports('ApplyPhoneDamageByNumber', applyByNumber)
exports('ApplyBulkPhoneDamage', applyBulkDamage)
exports('EscalateBulkPhoneDamage', escalateBulkDamage)
exports('ApplyPhoneDamageToAll', applyPhoneDamageToAll)
exports('EscalatePhoneDamageForAll', escalatePhoneDamageForAll)
exports('ApplyPhoneDamageInArea', applyPhoneDamageInArea)
exports('EscalatePhoneDamageInArea', escalatePhoneDamageInArea)

exports('EscalatePhoneDamage', function(playerSource, cause)
    local phoneNumber = resolveEquippedPhone(playerSource)
    if not phoneNumber then return false, 'no_equipped_phone' end
    setActivePhone(playerSource, phoneNumber)
    return escalateByNumber(phoneNumber, cause)
end)

exports('EscalatePhoneDamageByNumber', escalateByNumber)
exports('ApplyPhoneDamageDelta', applyPhoneDamageDelta)
exports('ApplyPhoneDamageDeltaByNumber', applyDamageDeltaByNumber)

LBPhoneDamageCore = LBPhoneDamageCore or {}
LBPhoneDamageCore.applyPhoneDamageDelta = applyPhoneDamageDelta

exports('GetPhoneDamage', function(phoneNumber)
    return runManaged(function()
        local result, err = getCachedDamageUnlocked(phoneNumber)
        if err then return nil, err end
        return copyDamageState(result)
    end)
end)

exports('RepairPhone', function(playerSource)
    local phoneNumber = resolveEquippedPhone(playerSource)
    if not phoneNumber then return false, 'no_equipped_phone' end
    setActivePhone(playerSource, phoneNumber)
    return repairByNumber(phoneNumber)
end)

exports('RepairPhoneByNumber', repairByNumber)
exports('RepairBulkPhoneDamage', repairBulkDamage)
exports('RepairAllPhones', repairAllPhones)

if Config.Commands.enabled then
    local function damageCommand(playerSource, args)
        if not hasDamagePermission(playerSource) then
            return commandReply(playerSource, 'You do not have permission to use this command.', false)
        end

        local level = normalizeLevel(args[1])
        if not level then
            commandReply(playerSource, ('Usage: /%s <1-3> [phoneNumber]'):format(Config.Commands.setDamage), false)
            return
        end

        local equippedPhone = resolveEquippedPhone(playerSource)
        local requestedPhone = normalizePhoneNumber(args[2])
        if playerSource > 0 and not Config.Commands.restricted and requestedPhone and requestedPhone ~= equippedPhone then
            return commandReply(playerSource, 'You can only test the phone you currently have equipped.', false)
        end
        local phoneNumber = requestedPhone or equippedPhone
        if not phoneNumber then
            commandReply(playerSource, 'No equipped phone; console usage requires a phone number.', false)
            return
        end

        if playerSource > 0 then setActivePhone(playerSource, equippedPhone) end
        local success, err, result = applyByNumber(phoneNumber, level, 'test_command')
        commandReply(playerSource, success
            and ('%s is damage level %d (seed %d).'):format(phoneNumber, result.damageLevel, result.damageSeed)
            or ('Damage failed: %s'):format(err or 'unknown_error'), success)
    end

    local function repairCommand(playerSource, args)
        if not hasRepairPermission(playerSource) then
            return commandReply(playerSource, 'You do not have permission to use this command.', false)
        end

        local equippedPhone = resolveEquippedPhone(playerSource)
        local requestedPhone = normalizePhoneNumber(args[1])
        if playerSource > 0 and not Config.Commands.restricted and requestedPhone and requestedPhone ~= equippedPhone then
            return commandReply(playerSource, 'You can only repair the phone you currently have equipped.', false)
        end
        local phoneNumber = requestedPhone or equippedPhone
        if not phoneNumber then
            commandReply(playerSource, ('Usage: /%s [phoneNumber]'):format(Config.Commands.repair), false)
            return
        end

        if playerSource > 0 then setActivePhone(playerSource, equippedPhone) end
        local success, err = repairByNumber(phoneNumber)
        commandReply(playerSource, success
            and ('Repaired %s.'):format(phoneNumber)
            or ('Repair failed: %s'):format(err or 'unknown_error'), success)
    end

    local function escalateCommand(playerSource, args)
        if not hasEscalatePermission(playerSource) then
            return commandReply(playerSource, 'You do not have permission to use this command.', false)
        end

        local equippedPhone = resolveEquippedPhone(playerSource)
        local requestedPhone = normalizePhoneNumber(args[1])
        if playerSource > 0 and not Config.Commands.restricted and requestedPhone and requestedPhone ~= equippedPhone then
            return commandReply(playerSource, 'You can only test the phone you currently have equipped.', false)
        end
        local phoneNumber = requestedPhone or equippedPhone
        if not phoneNumber then
            return commandReply(playerSource, ('Usage: /%s [phoneNumber]'):format(
                Config.Commands.escalateDamage
            ), false)
        end

        if playerSource > 0 then setActivePhone(playerSource, equippedPhone) end
        local success, err, result = escalateByNumber(phoneNumber, 'test_command_escalation')
        commandReply(playerSource, success
            and ('%s escalated to damage level %d (seed %d).'):format(
                phoneNumber, result.damageLevel, result.damageSeed
            )
            or ('Escalation failed: %s'):format(err or 'unknown_error'), success)
    end

    local function damageAllCommand(playerSource, args)
        if not hasDamageAllPermission(playerSource) then
            return commandReply(playerSource, 'You do not have permission to use this command.', false)
        end

        local level = normalizeLevel(args[1])
        if not level then
            return commandReply(playerSource, ('Usage: /%s <1-3>'):format(Config.Commands.setDamageAll), false)
        end

        local success, err, summary = applyPhoneDamageToAll(level, 'test_command_all')
        commandReply(playerSource, success
            and ('Applied damage level %d to %d unique equipped phone(s); %d player(s) had no phone.'):format(
                level, summary.uniquePhones, summary.noPhone
            )
            or ('Bulk damage failed after %d phone(s): %s'):format(
                summary and summary.changed or 0, err or 'unknown_error'
            ), success)
    end

    local function damageAreaCommand(playerSource, args)
        if not hasDamageAreaPermission(playerSource) then
            return commandReply(playerSource, playerSource == 0
                and 'This command requires an in-game player as its center.'
                or 'You do not have permission to use this command.', false)
        end

        local radius = normalizeAreaRadius(args[1])
        local level = args[2] and normalizeLevel(args[2]) or nil
        if not radius or (args[2] ~= nil and not level) then
            return commandReply(playerSource, ('Usage: /%s <radius> [1-3]; maximum radius: %d'):format(
                Config.Commands.setDamageArea, Config.MaxDamageAreaRadius
            ), false)
        end

        local ped = GetPlayerPed(playerSource)
        local coordsOk, coords = false, nil
        if ped and ped > 0 then coordsOk, coords = pcall(GetEntityCoords, ped) end
        if not coordsOk or not coords then
            return commandReply(playerSource, 'Your position could not be resolved.', false)
        end

        local success, err, summary = applyPhoneDamageInArea(coords, radius, level, 'explosion')
        commandReply(playerSource, success
            and (level
                and ('Applied damage level %d to %d unique equipped phone(s) within %.1f metres.'):format(
                    level, summary.uniquePhones, radius
                )
                or ('Escalated %d unique equipped phone(s) within %.1f metres.'):format(
                    summary.uniquePhones, radius
                ))
            or ('Area damage failed after %d phone(s): %s'):format(
                summary and summary.changed or 0, err or 'unknown_error'
            ), success)
    end

    local function repairAllCommand(playerSource)
        if not hasRepairAllPermission(playerSource) then
            return commandReply(playerSource, 'You do not have permission to use this command.', false)
        end

        local success, err, summary = repairAllPhones()
        commandReply(playerSource, success
            and ('Repaired %d unique equipped phone(s); %d player(s) had no phone.'):format(
                summary.repaired, summary.noPhone
            )
            or ('Bulk repair failed after %d phone(s): %s'):format(
                summary and summary.repaired or 0, err or 'unknown_error'
            ), success)
    end

    local function damageColorCommand(playerSource, args)
        if not hasDamageColorPermission(playerSource) then
            return commandReply(playerSource, 'You do not have permission to change the global crack color.', false)
        end

        local nextColor = normalizeDamageColor(args[1])
        if not nextColor then
            return commandReply(playerSource, ('Usage: /%s <black|white>'):format(Config.Commands.setDamageColor), false)
        end

        damageColor = nextColor
        TriggerClientEvent('lb-phone-damage:client:setDamageColor', -1, damageColor)
        commandReply(playerSource, ('Global crack color set to %s.'):format(damageColor), true)
    end

    RegisterCommand(Config.Commands.setDamage, damageCommand, false)
    RegisterCommand(Config.Commands.escalateDamage, escalateCommand, false)
    RegisterCommand(Config.Commands.setDamageAll, damageAllCommand, false)
    RegisterCommand(Config.Commands.setDamageArea, damageAreaCommand, false)
    RegisterCommand(Config.Commands.setDamageColor, damageColorCommand, false)
    RegisterCommand(Config.Commands.repair, repairCommand, false)
    RegisterCommand(Config.Commands.repairAll, repairAllCommand, false)

    if Config.Commands.legacySetDamage and Config.Commands.legacySetDamage ~= Config.Commands.setDamage then
        RegisterCommand(Config.Commands.legacySetDamage, damageCommand, false)
    end
    if Config.Commands.legacyRepair and Config.Commands.legacyRepair ~= Config.Commands.repair then
        RegisterCommand(Config.Commands.legacyRepair, repairCommand, false)
    end
end

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    math.randomseed(os.time())
    ensureDatabase(function() end)
end)
