local PlayerNumbers = {}
local ActiveCalls = {}
local PendingByTarget = {}
local AnnouncementSender = 'ANNOUNCEMENT'
local AnnouncementSession
local AnnouncementsReady = false

local function isDefaultAnnouncementHidden()
    local setting = tostring(GetConvar('txAdmin-hideDefaultAnnouncement', 'false')):lower()
    return setting == 'true' or setting == '1'
end

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
          `caller_id_private` tinyint(1) NOT NULL DEFAULT 0,
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

    if Config.TxAdminAnnouncements then
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS `blixt_mokia_announcements` (
              `id` int(11) NOT NULL AUTO_INCREMENT,
              `session_id` varchar(64) NOT NULL,
              `citizenid` varchar(64) NOT NULL,
              `content` text NOT NULL,
              `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
              PRIMARY KEY (`id`),
              KEY `session_recipient` (`session_id`, `citizenid`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        ]])

        -- Earlier versions created this table without per-character recipients.
        local recipientColumn = MySQL.single.await([[
            SELECT COLUMN_NAME
            FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME = 'blixt_mokia_announcements'
              AND COLUMN_NAME = 'citizenid'
            LIMIT 1
        ]])

        if not recipientColumn then
            MySQL.query.await([[
                ALTER TABLE `blixt_mokia_announcements`
                ADD COLUMN `citizenid` varchar(64) NOT NULL DEFAULT '' AFTER `session_id`
            ]])
            print('[blixt-mokia] Updated announcement database schema.')
        end

        local recipientIndex = MySQL.single.await([[
            SELECT INDEX_NAME
            FROM INFORMATION_SCHEMA.STATISTICS
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME = 'blixt_mokia_announcements'
              AND INDEX_NAME = 'session_recipient'
            LIMIT 1
        ]])

        if not recipientIndex then
            MySQL.query.await([[
                ALTER TABLE `blixt_mokia_announcements`
                ADD INDEX `session_recipient` (`session_id`, `citizenid`)
            ]])
        end
    end

    local callerIdColumn = MySQL.single.await([[
        SELECT COLUMN_NAME
        FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME = 'blixt_mokia_numbers'
          AND COLUMN_NAME = 'caller_id_private'
        LIMIT 1
    ]])

    if not callerIdColumn then
        MySQL.query.await('ALTER TABLE `blixt_mokia_numbers` ADD COLUMN `caller_id_private` tinyint(1) NOT NULL DEFAULT 0 AFTER `display_name`')
    end

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
    local numberFormat = tostring(Config.NumberFormat or '')

    -- Keep both names for backwards compatibility. Older configs used us_213 even
    -- though the generator originally only checked for us_1999.
    if numberFormat == 'us_1999' or numberFormat == 'us_213' or numberFormat:sub(1, 3) == 'us_' then
        local areaCodes = Config.NumberAreaCodes or { '213', '310', '323', '415', '510', '702', '718', '917' }
        local areaCode = tostring(areaCodes[math.random(1, #areaCodes)])
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

local function generateUniqueNumber()
    local number

    repeat
        number = generateNumber()
        local taken = MySQL.scalar.await('SELECT 1 FROM blixt_mokia_numbers WHERE phone_number = ? LIMIT 1', { number })
    until not taken

    return number
end

local function isLegacyAustralianNumber(number)
    number = normalizeNumber(number)
    return #number == 10 and number:sub(1, 2) == tostring(Config.LegacyNumberPrefix or '04')
end

local function migrateLegacyNumbers()
    if Config.AutoMigrateLegacyNumbers == false then return end

    local rows = MySQL.query.await('SELECT citizenid, phone_number FROM blixt_mokia_numbers') or {}
    local migrated = 0

    for _, row in ipairs(rows) do
        local oldNumber = normalizeNumber(row.phone_number)

        if isLegacyAustralianNumber(oldNumber) then
            local newNumber = generateUniqueNumber()

            -- Update every stored reference so contacts, texts and call records continue
            -- to point at the same character after their number is converted.
            MySQL.update.await('UPDATE blixt_mokia_contacts SET phone_number = ? WHERE phone_number = ?', { newNumber, oldNumber })
            MySQL.update.await('UPDATE blixt_mokia_messages SET sender_number = ? WHERE sender_number = ?', { newNumber, oldNumber })
            MySQL.update.await('UPDATE blixt_mokia_messages SET receiver_number = ? WHERE receiver_number = ?', { newNumber, oldNumber })
            MySQL.update.await('UPDATE blixt_mokia_call_history SET owner_number = ? WHERE owner_number = ?', { newNumber, oldNumber })
            MySQL.update.await('UPDATE blixt_mokia_call_history SET other_number = ? WHERE other_number = ?', { newNumber, oldNumber })
            MySQL.update.await('UPDATE blixt_mokia_numbers SET phone_number = ? WHERE citizenid = ?', { newNumber, row.citizenid })

            migrated = migrated + 1
            print(('[blixt-mokia] Migrated legacy number %s -> %s (%s)'):format(oldNumber, newNumber, row.citizenid))
        end
    end

    if migrated > 0 then
        print(('[blixt-mokia] Automatically migrated %s legacy Australian phone number(s) to US format.'):format(migrated))
    else
        debugPrint('No legacy Australian phone numbers needed migration.')
    end
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

    local number = generateUniqueNumber()

    MySQL.insert.await('INSERT INTO blixt_mokia_numbers (citizenid, phone_number, display_name, caller_id_private) VALUES (?, ?, ?, 0)', {
        citizenid,
        number,
        Bridge.GetCharacterName(source)
    })

    PlayerNumbers[source] = number
    return number
end

local function getBasicData(source)
    local number = ensurePlayerNumber(source)
    local citizenid = Bridge.GetCitizenId(source)
    local callerIdPrivate = false

    if citizenid then
        callerIdPrivate = (tonumber(MySQL.scalar.await('SELECT caller_id_private FROM blixt_mokia_numbers WHERE citizenid = ? LIMIT 1', { citizenid })) or 0) == 1
    end

    return {
        number = number,
        name = Bridge.GetCharacterName(source),
        callerIdPrivate = callerIdPrivate
    }
end

local function getCallerIdPrivate(source)
    local citizenid = Bridge.GetCitizenId(source)
    if not citizenid then return false end

    return (tonumber(MySQL.scalar.await('SELECT caller_id_private FROM blixt_mokia_numbers WHERE citizenid = ? LIMIT 1', { citizenid })) or 0) == 1
end

local function historyCallerNumber(call)
    if call.callerIdPrivate then
        return 'PRIVATE'
    end

    return call.callerNumber
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
        historyCallerNumber(call),
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

    if Config.TxAdminAnnouncements then
        -- GlobalState survives a resource restart, but resets when FXServer restarts.
        local session = GlobalState.blixtMokiaAnnouncementSession
        if not session then
            session = ('%d_%d_%d'):format(os.time(), GetGameTimer(), math.random(10000, 99999))
            GlobalState.blixtMokiaAnnouncementSession = session
        end
        AnnouncementSession = session
    end

    local ok, err = pcall(ensureDatabase)
    if not ok then
        print(('[blixt-mokia] Failed to auto-create database tables: %s'):format(err))
        print('[blixt-mokia] Check oxmysql is started before blixt-mokia and your database connection is working.')
    else
        local migratedOk, migratedErr = pcall(migrateLegacyNumbers)
        if not migratedOk then
            print(('[blixt-mokia] Legacy phone-number migration failed: %s'):format(migratedErr))
        end
    end

    if Config.TxAdminAnnouncements and ok then
        local cleared, cleanupErr = pcall(function()
            MySQL.update.await('DELETE FROM blixt_mokia_announcements WHERE session_id <> ?', { AnnouncementSession })
        end)
        AnnouncementsReady = cleared
        if not cleared then
            print(('[blixt-mokia] txAdmin announcement storage unavailable: %s'):format(cleanupErr))
        end
    end

    if Config.TxAdminAnnouncements then
        print('[blixt-mokia] txAdmin SMS announcements enabled.')
        if not isDefaultAnnouncementHidden() then
            print('[blixt-mokia] IMPORTANT: Enable "Hide Default Announcement" in txAdmin > Settings > Game > Notifications. SMS routing is inactive until then.')
        end
    end

    Bridge.RegisterPhoneItems()
end)

-- Only manual txAdmin announcements are routed. Scheduled restarts use a different event.
if Config.TxAdminAnnouncements then
    AddEventHandler('txAdmin:events:announcement', function(eventData)
        -- Leave txAdmin in full control if the server owner hasn't hidden its default popup.
        if not isDefaultAnnouncementHidden() then return end
        local message = type(eventData) == 'table' and eventData.message or nil
        if type(message) ~= 'string' or message == '' then return end

        local hideAuthor = tostring(GetConvar('txAdmin-hideAdminInMessages', 'false')):lower()
        local author = (hideAuthor == 'true' or hideAuthor == '1')
            and GetConvar('txAdmin-serverName', 'txAdmin')
            or (eventData.author or 'anonym')

        for _, playerId in ipairs(GetPlayers()) do
            local target = tonumber(playerId)
            if target then
                local citizenid = Bridge.GetCitizenId(target)
                if AnnouncementsReady and citizenid and Bridge.HasPhoneItem(target) then
                    local saved, id = pcall(function()
                        return MySQL.insert.await([[
                            INSERT INTO blixt_mokia_announcements (session_id, citizenid, content)
                            VALUES (?, ?, ?)
                        ]], { AnnouncementSession, citizenid, message })
                    end)
                    if saved and tonumber(id) and tonumber(id) > 0 then
                        TriggerClientEvent('blixt-mokia:client:newMessage', target, {
                            from = AnnouncementSender,
                            message = message
                        })
                    else
                        -- Never lose a broadcast if storage is unavailable.
                        TriggerClientEvent('txcl:showAnnouncement', target, message, author)
                    end
                else
                    TriggerClientEvent('txcl:showAnnouncement', target, message, author)
                end
            end
        end
    end)
end

Bridge.RegisterCallback('blixt-mokia:server:getPhoneData', function(source)
    return getBasicData(source)
end)

Bridge.RegisterCallback('blixt-mokia:server:setCallerIdPrivate', function(source, enabled)
    local citizenid = Bridge.GetCitizenId(source)
    if not citizenid then return { success = false, message = 'No character loaded.' } end

    ensurePlayerNumber(source)
    local private = enabled == true

    MySQL.update.await('UPDATE blixt_mokia_numbers SET caller_id_private = ? WHERE citizenid = ?', {
        private and 1 or 0,
        citizenid
    })

    return { success = true, callerIdPrivate = private }
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
            UNIX_TIMESTAMP(MAX(created_at)) AS last_time
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

    if Config.TxAdminAnnouncements and AnnouncementsReady then
        local citizenid = Bridge.GetCitizenId(source)
        if citizenid then
            local latest = MySQL.single.await([[
                SELECT content, UNIX_TIMESTAMP(created_at) AS last_time
                FROM blixt_mokia_announcements
                WHERE session_id = ? AND citizenid = ?
                ORDER BY id DESC LIMIT 1
            ]], { AnnouncementSession, citizenid })
            if latest then
                rows[#rows + 1] = {
                    other_number = AnnouncementSender,
                    last_message = latest.content,
                    last_time = latest.last_time,
                    direction = 'incoming'
                }
                table.sort(rows, function(a, b)
                    return (tonumber(a.last_time) or 0) > (tonumber(b.last_time) or 0)
                end)
            end
        end
    end

    return rows
end)

Bridge.RegisterCallback('blixt-mokia:server:getMessages', function(source, otherNumber)
    local myNumber = ensurePlayerNumber(source)
    if otherNumber == AnnouncementSender then
        if not Config.TxAdminAnnouncements or not AnnouncementsReady or not myNumber then return {} end
        local citizenid = Bridge.GetCitizenId(source)
        if not citizenid then return {} end

        local items = MySQL.query.await([[
            SELECT id, content, created_at, UNIX_TIMESTAMP(created_at) AS sent_at
            FROM blixt_mokia_announcements
            WHERE session_id = ? AND citizenid = ?
            ORDER BY id DESC LIMIT 100
        ]], { AnnouncementSession, citizenid }) or {}

        local results = {}
        for i = #items, 1, -1 do
            local item = items[i]
            results[#results + 1] = {
                id = item.id,
                sender_number = AnnouncementSender,
                receiver_number = myNumber,
                content = item.content,
                is_read = 1,
                created_at = item.created_at,
                sent_at = item.sent_at
            }
        end
        return results
    end
    otherNumber = normalizeNumber(otherNumber)

    if not myNumber or otherNumber == '' then return {} end

    MySQL.update.await('UPDATE blixt_mokia_messages SET is_read = 1 WHERE receiver_number = ? AND sender_number = ?', {
        myNumber,
        otherNumber
    })

    return MySQL.query.await([[
        SELECT id, sender_number, receiver_number, content, is_read,
               created_at, UNIX_TIMESTAMP(created_at) AS sent_at
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

    local callerIdPrivate = getCallerIdPrivate(source)

    ActiveCalls[callId] = {
        id = callId,
        caller = source,
        target = targetSource,
        callerNumber = callerNumber,
        targetNumber = targetNumber,
        callerIdPrivate = callerIdPrivate,
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
        number = callerIdPrivate and nil or callerNumber,
        private = callerIdPrivate
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
                targetNumber, callerIdPrivate and 'PRIVATE' or callerNumber, 'incoming', 'missed', 0
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
        number = call.callerIdPrivate and nil or call.callerNumber,
        private = call.callerIdPrivate
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
        call.targetNumber, historyCallerNumber(call), 'incoming', 'rejected', 0
    })
end)

RegisterNetEvent('blixt-mokia:server:endCall', function(callId)
    endCall(callId, source)
end)
