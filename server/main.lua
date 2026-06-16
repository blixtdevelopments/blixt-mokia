local PlayerNumbers = {}
local ActiveCalls = {}
local PendingByTarget = {}

local function debugPrint(...)
    if Config.Debug then
        print('[blixt-mokia:server]', ...)
    end
end


local function ensureDatabase()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `blixt_mokia_numbers` (
          `id` int(11) NOT NULL AUTO_INCREMENT,
          `citizenid` varchar(64) NOT NULL,
          `phone_number` varchar(20) NOT NULL,
          `display_name` varchar(64) DEFAULT NULL,
          `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
          PRIMARY KEY (`id`),
          UNIQUE KEY `citizenid` (`citizenid`),
          UNIQUE KEY `phone_number` (`phone_number`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `blixt_mokia_contacts` (
          `id` int(11) NOT NULL AUTO_INCREMENT,
          `owner_citizenid` varchar(64) NOT NULL,
          `name` varchar(32) NOT NULL,
          `phone_number` varchar(20) NOT NULL,
          `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
          PRIMARY KEY (`id`),
          KEY `owner_citizenid` (`owner_citizenid`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `blixt_mokia_messages` (
          `id` int(11) NOT NULL AUTO_INCREMENT,
          `sender_number` varchar(20) NOT NULL,
          `receiver_number` varchar(20) NOT NULL,
          `content` varchar(160) NOT NULL,
          `is_read` tinyint(1) NOT NULL DEFAULT 0,
          `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
          PRIMARY KEY (`id`),
          KEY `sender_receiver` (`sender_number`, `receiver_number`),
          KEY `receiver_sender` (`receiver_number`, `sender_number`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `blixt_mokia_call_history` (
          `id` int(11) NOT NULL AUTO_INCREMENT,
          `owner_number` varchar(20) NOT NULL,
          `other_number` varchar(20) NOT NULL,
          `direction` enum('incoming','outgoing') NOT NULL,
          `status` varchar(20) NOT NULL DEFAULT 'ended',
          `duration` int(11) NOT NULL DEFAULT 0,
          `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
          PRIMARY KEY (`id`),
          KEY `owner_number` (`owner_number`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `blixt_mokia_snake_scores` (
          `id` int(11) NOT NULL AUTO_INCREMENT,
          `citizenid` varchar(64) NOT NULL,
          `top_score` int(11) NOT NULL DEFAULT 0,
          `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
          PRIMARY KEY (`id`),
          UNIQUE KEY `citizenid` (`citizenid`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    debugPrint('Database tables checked/created.')
end

local function clampMessage(message)
    message = tostring(message or '')
    message = message:gsub('[\r\n]+', ' ')
    if #message > Config.MaxMessageLength then
        message = message:sub(1, Config.MaxMessageLength)
    end
    return message
end

local function normalizeNumber(number)
    number = tostring(number or '')
    number = number:gsub('%D', '')
    return number
end

local function generateNumber()
    if Config.NumberFormat == 'us_1999' then
        local areaCodes = Config.NumberAreaCodes or { '213', '310', '323', '415', '510', '702', '718', '917' }
        local areaCode = areaCodes[math.random(1, #areaCodes)]
        local exchange = tostring(Config.NumberExchange or '555')
        local lineNumber = tostring(math.random(0, 9999)):format('%04d')

        return ('%s%s%s'):format(areaCode, exchange, lineNumber)
    end

    local prefix = tostring(Config.NumberPrefix or '04')
    local digitsNeeded = (Config.NumberLength or 10) - #prefix
    local suffix = ''

    for _ = 1, digitsNeeded do
        suffix = suffix .. tostring(math.random(0, 9))
    end

    return prefix .. suffix
end

local function getSourceByCitizenId(citizenid)
    for _, playerId in ipairs(GetPlayers()) do
        local src = tonumber(playerId)
        if Bridge.GetCitizenId(src) == citizenid then
            return src
        end
    end
    return nil
end

local function getSourceByPhoneNumber(number)
    number = normalizeNumber(number)
    local row = MySQL.single.await('SELECT citizenid FROM blixt_mokia_numbers WHERE phone_number = ? LIMIT 1', { number })
    if not row then return nil end
    return getSourceByCitizenId(row.citizenid)
end

local function ensurePlayerNumber(source)
    local citizenid = Bridge.GetCitizenId(source)
    if not citizenid then return nil end

    if PlayerNumbers[source] then
        return PlayerNumbers[source]
    end

    local existing = MySQL.single.await('SELECT phone_number FROM blixt_mokia_numbers WHERE citizenid = ? LIMIT 1', { citizenid })
    if existing and existing.phone_number then
        PlayerNumbers[source] = existing.phone_number
        return existing.phone_number
    end

    local number
    repeat
        number = generateNumber()
        local taken = MySQL.scalar.await('SELECT 1 FROM blixt_mokia_numbers WHERE phone_number = ? LIMIT 1', { number })
    until not taken

    MySQL.insert.await('INSERT INTO blixt_mokia_numbers (citizenid, phone_number, display_name) VALUES (?, ?, ?)', {
        citizenid,
        number,
        Bridge.GetCharacterName(source)
    })

    PlayerNumbers[source] = number
    return number
end

local function getBasicData(source)
    local number = ensurePlayerNumber(source)

    return {
        number = number,
        name = Bridge.GetCharacterName(source)
    }
end

local function endCall(callId, endedBy)
    local call = ActiveCalls[callId]
    if not call then return end

    ActiveCalls[callId] = nil
    PendingByTarget[call.target] = nil

    if call.caller then
        Bridge.SetPlayerCall(call.caller, 0)
        TriggerClientEvent('blixt-mokia:client:callEnded', call.caller, { reason = endedBy == call.caller and 'You hung up' or 'Call ended' })
    end

    if call.target then
        Bridge.SetPlayerCall(call.target, 0)
        TriggerClientEvent('blixt-mokia:client:callEnded', call.target, { reason = endedBy == call.target and 'You hung up' or 'Call ended' })
    end

    local duration = 0
    if call.startedAt then
        duration = os.time() - call.startedAt
    end

    MySQL.insert('INSERT INTO blixt_mokia_call_history (owner_number, other_number, direction, status, duration) VALUES (?, ?, ?, ?, ?)', {
        call.callerNumber,
        call.targetNumber,
        'outgoing',
        call.startedAt and 'answered' or 'ended',
        duration
    })

    MySQL.insert('INSERT INTO blixt_mokia_call_history (owner_number, other_number, direction, status, duration) VALUES (?, ?, ?, ?, ?)', {
        call.targetNumber,
        call.callerNumber,
        'incoming',
        call.startedAt and 'answered' or 'ended',
        duration
    })
end

AddEventHandler('playerDropped', function()
    local src = source
    PlayerNumbers[src] = nil

    for callId, call in pairs(ActiveCalls) do
        if call.caller == src or call.target == src then
            endCall(callId, src)
        end
    end

    PendingByTarget[src] = nil
end)

CreateThread(function()
    Wait(1000)
    math.randomseed(os.time())

    local ok, err = pcall(ensureDatabase)
    if not ok then
        print(('[blixt-mokia] Failed to auto-create database tables: %s'):format(err))
        print('[blixt-mokia] Check oxmysql is started before blixt-mokia and your database connection is working.')
    end

    Bridge.RegisterPhoneItems()
end)

Bridge.RegisterCallback('blixt-mokia:server:getPhoneData', function(source)
    return getBasicData(source)
end)

Bridge.RegisterCallback('blixt-mokia:server:getContacts', function(source)
    local citizenid = Bridge.GetCitizenId(source)
    if not citizenid then return {} end

    return MySQL.query.await('SELECT id, name, phone_number FROM blixt_mokia_contacts WHERE owner_citizenid = ? ORDER BY name ASC', {
        citizenid
    }) or {}
end)

Bridge.RegisterCallback('blixt-mokia:server:addContact', function(source, data)
    local citizenid = Bridge.GetCitizenId(source)
    if not citizenid then return { success = false, message = 'No character loaded.' } end

    local name = tostring(data and data.name or ''):sub(1, 32)
    local number = normalizeNumber(data and data.number)

    if name == '' or number == '' then
        return { success = false, message = 'Name and number required.' }
    end

    local existing = MySQL.single.await([[
        SELECT id
        FROM blixt_mokia_contacts
        WHERE owner_citizenid = ? AND name = ? AND phone_number = ?
        LIMIT 1
    ]], { citizenid, name, number })

    if existing then
        return { success = true, duplicate = true }
    end

    MySQL.insert.await('INSERT INTO blixt_mokia_contacts (owner_citizenid, name, phone_number) VALUES (?, ?, ?)', {
        citizenid,
        name,
        number
    })

    return { success = true }
end)

Bridge.RegisterCallback('blixt-mokia:server:deleteContact', function(source, contactId)
    local citizenid = Bridge.GetCitizenId(source)
    if not citizenid then return { success = false } end

    MySQL.update.await('DELETE FROM blixt_mokia_contacts WHERE id = ? AND owner_citizenid = ?', {
        tonumber(contactId),
        citizenid
    })

    return { success = true }
end)

Bridge.RegisterCallback('blixt-mokia:server:getSnakeTopScore', function(source)
    local citizenid = Bridge.GetCitizenId(source)
    if not citizenid then return { topScore = 0 } end

    local topScore = MySQL.scalar.await('SELECT top_score FROM blixt_mokia_snake_scores WHERE citizenid = ? LIMIT 1', {
        citizenid
    })

    return {
        topScore = tonumber(topScore) or 0
    }
end)

Bridge.RegisterCallback('blixt-mokia:server:saveSnakeScore', function(source, score)
    local citizenid = Bridge.GetCitizenId(source)
    if not citizenid then return { success = false, topScore = 0, newHigh = false } end

    score = tonumber(score) or 0
    if score < 0 then score = 0 end

    local current = tonumber(MySQL.scalar.await('SELECT top_score FROM blixt_mokia_snake_scores WHERE citizenid = ? LIMIT 1', {
        citizenid
    })) or 0

    local newHigh = score > current

    if newHigh then
        MySQL.query.await([[
            INSERT INTO blixt_mokia_snake_scores (citizenid, top_score)
            VALUES (?, ?)
            ON DUPLICATE KEY UPDATE top_score = GREATEST(top_score, VALUES(top_score))
        ]], { citizenid, score })

        current = score
    end

    return {
        success = true,
        topScore = current,
        newHigh = newHigh
    }
end)

Bridge.RegisterCallback('blixt-mokia:server:getThreads', function(source)
    local myNumber = ensurePlayerNumber(source)
    if not myNumber then return {} end

    local rows = MySQL.query.await([[
        SELECT
            CASE
                WHEN sender_number = ? THEN receiver_number
                ELSE sender_number
            END AS other_number,
            MAX(created_at) AS last_time
        FROM blixt_mokia_messages
        WHERE sender_number = ? OR receiver_number = ?
        GROUP BY other_number
        ORDER BY last_time DESC
        LIMIT 50
    ]], { myNumber, myNumber, myNumber }) or {}

    for _, row in ipairs(rows) do
        local msg = MySQL.single.await([[
            SELECT content, sender_number, receiver_number, created_at
            FROM blixt_mokia_messages
            WHERE (sender_number = ? AND receiver_number = ?) OR (sender_number = ? AND receiver_number = ?)
            ORDER BY created_at DESC
            LIMIT 1
        ]], { myNumber, row.other_number, row.other_number, myNumber })

        row.last_message = msg and msg.content or ''
        row.direction = msg and msg.sender_number == myNumber and 'outgoing' or 'incoming'
    end

    return rows
end)

Bridge.RegisterCallback('blixt-mokia:server:getMessages', function(source, otherNumber)
    local myNumber = ensurePlayerNumber(source)
    otherNumber = normalizeNumber(otherNumber)

    if not myNumber or otherNumber == '' then return {} end

    MySQL.update.await('UPDATE blixt_mokia_messages SET is_read = 1 WHERE receiver_number = ? AND sender_number = ?', {
        myNumber,
        otherNumber
    })

    return MySQL.query.await([[
        SELECT id, sender_number, receiver_number, content, is_read, created_at
        FROM blixt_mokia_messages
        WHERE (sender_number = ? AND receiver_number = ?) OR (sender_number = ? AND receiver_number = ?)
        ORDER BY created_at ASC
        LIMIT 100
    ]], { myNumber, otherNumber, otherNumber, myNumber }) or {}
end)

Bridge.RegisterCallback('blixt-mokia:server:sendMessage', function(source, data)
    local myNumber = ensurePlayerNumber(source)
    local toNumber = normalizeNumber(data and data.number)
    local content = clampMessage(data and data.message)

    if not myNumber then return { success = false, message = 'No phone number.' } end
    if toNumber == '' or content == '' then return { success = false, message = 'Number and message required.' } end

    local delay = tonumber(Config.MessageDeliveryDelay) or 0

    SetTimeout(delay * 1000, function()
        MySQL.insert('INSERT INTO blixt_mokia_messages (sender_number, receiver_number, content) VALUES (?, ?, ?)', {
            myNumber,
            toNumber,
            content
        })

        local targetSource = getSourceByPhoneNumber(toNumber)
        if targetSource and GetPlayerPing(targetSource) > 0 then
            TriggerClientEvent('blixt-mokia:client:newMessage', targetSource, {
                from = myNumber,
                message = content
            })
        end
    end)

    return { success = true, delayed = delay > 0 }
end)

Bridge.RegisterCallback('blixt-mokia:server:startCall', function(source, rawNumber)
    local callerNumber = ensurePlayerNumber(source)
    local targetNumber = normalizeNumber(rawNumber)

    if not callerNumber then return { success = false, message = 'No phone number.' } end
    if targetNumber == '' then return { success = false, message = 'Enter a number.' } end
    if targetNumber == callerNumber then return { success = false, message = 'You cannot call yourself.' } end

    local targetSource = getSourceByPhoneNumber(targetNumber)
    if not targetSource then
        MySQL.insert('INSERT INTO blixt_mokia_call_history (owner_number, other_number, direction, status, duration) VALUES (?, ?, ?, ?, ?)', {
            callerNumber, targetNumber, 'outgoing', 'unavailable', 0
        })
        return { success = false, message = 'Number unavailable.' }
    end

    if PendingByTarget[targetSource] then
        return { success = false, message = 'Line busy.' }
    end

    for _, call in pairs(ActiveCalls) do
        if call.caller == source or call.target == source or call.caller == targetSource or call.target == targetSource then
            return { success = false, message = 'Line busy.' }
        end
    end

    local callId = ('%s:%s:%s'):format(source, targetSource, os.time())
    local channel = math.random(Config.CallChannelMin, Config.CallChannelMax)

    ActiveCalls[callId] = {
        id = callId,
        caller = source,
        target = targetSource,
        callerNumber = callerNumber,
        targetNumber = targetNumber,
        channel = channel,
        createdAt = os.time()
    }

    PendingByTarget[targetSource] = callId

    TriggerClientEvent('blixt-mokia:client:outgoingCall', source, {
        callId = callId,
        number = targetNumber
    })

    TriggerClientEvent('blixt-mokia:client:incomingCall', targetSource, {
        callId = callId,
        number = callerNumber,
        name = Bridge.GetCharacterName(source)
    })

    SetTimeout(Config.RingTimeout * 1000, function()
        local call = ActiveCalls[callId]
        if call and not call.startedAt then
            ActiveCalls[callId] = nil
            PendingByTarget[targetSource] = nil

            TriggerClientEvent('blixt-mokia:client:callEnded', source, { reason = 'No answer' })
            TriggerClientEvent('blixt-mokia:client:callEnded', targetSource, { reason = 'Missed call' })

            MySQL.insert('INSERT INTO blixt_mokia_call_history (owner_number, other_number, direction, status, duration) VALUES (?, ?, ?, ?, ?)', {
                callerNumber, targetNumber, 'outgoing', 'missed', 0
            })
            MySQL.insert('INSERT INTO blixt_mokia_call_history (owner_number, other_number, direction, status, duration) VALUES (?, ?, ?, ?, ?)', {
                targetNumber, callerNumber, 'incoming', 'missed', 0
            })
        end
    end)

    return { success = true }
end)

RegisterNetEvent('blixt-mokia:server:answerCall', function(callId)
    local src = source
    local call = ActiveCalls[callId]
    if not call or call.target ~= src then return end

    call.startedAt = os.time()
    PendingByTarget[src] = nil

    Bridge.SetPlayerCall(call.caller, call.channel)
    Bridge.SetPlayerCall(call.target, call.channel)

    TriggerClientEvent('blixt-mokia:client:callStarted', call.caller, {
        callId = callId,
        number = call.targetNumber
    })

    TriggerClientEvent('blixt-mokia:client:callStarted', call.target, {
        callId = callId,
        number = call.callerNumber
    })
end)

RegisterNetEvent('blixt-mokia:server:declineCall', function(callId)
    local src = source
    local call = ActiveCalls[callId]
    if not call or call.target ~= src then return end

    ActiveCalls[callId] = nil
    PendingByTarget[src] = nil

    TriggerClientEvent('blixt-mokia:client:callEnded', call.caller, { reason = 'Call rejected' })
    TriggerClientEvent('blixt-mokia:client:callEnded', call.target, { reason = 'Rejected' })

    MySQL.insert('INSERT INTO blixt_mokia_call_history (owner_number, other_number, direction, status, duration) VALUES (?, ?, ?, ?, ?)', {
        call.callerNumber, call.targetNumber, 'outgoing', 'rejected', 0
    })
    MySQL.insert('INSERT INTO blixt_mokia_call_history (owner_number, other_number, direction, status, duration) VALUES (?, ?, ?, ?, ?)', {
        call.targetNumber, call.callerNumber, 'incoming', 'rejected', 0
    })
end)

RegisterNetEvent('blixt-mokia:server:endCall', function(callId)
    endCall(callId, source)
end)
