Bridge = Bridge or {}

local function debugPrint(...)
    if Config and Config.Debug then
        print('[blixt-mokia:bridge]', ...)
    end
end

function Bridge.GetFramework()
    if Config and Config.Framework and Config.Framework ~= 'auto' then
        return Config.Framework
    end

    if GetResourceState('qb-core') == 'started' then return 'qb' end
    if GetResourceState('qbx_core') == 'started' then return 'qbx' end
    if GetResourceState('ox_lib') == 'started' then return 'ox' end
    return 'standalone'
end

if IsDuplicityVersion() then
    local QBCore

    local function getQBCore()
        if QBCore then return QBCore end
        if GetResourceState('qb-core') ~= 'started' then return nil end
        local ok, core = pcall(function()
            return exports['qb-core']:GetCoreObject()
        end)
        if ok then QBCore = core end
        return QBCore
    end

    function Bridge.GetPlayer(source)
        local framework = Bridge.GetFramework()

        if framework == 'qb' then
            local core = getQBCore()
            return core and core.Functions.GetPlayer(source) or nil
        end

        if framework == 'qbx' then
            local ok, player = pcall(function()
                return exports.qbx_core:GetPlayer(source)
            end)
            return ok and player or nil
        end

        local core = getQBCore()
        if core then return core.Functions.GetPlayer(source) end

        if GetResourceState('qbx_core') == 'started' then
            local ok, player = pcall(function()
                return exports.qbx_core:GetPlayer(source)
            end)
            if ok then return player end
        end

        return nil
    end

    function Bridge.GetCitizenId(source)
        local player = Bridge.GetPlayer(source)
        if not player then return nil end

        if player.PlayerData and player.PlayerData.citizenid then
            return player.PlayerData.citizenid
        end

        if player.citizenid then return player.citizenid end
        return nil
    end

    function Bridge.GetCharacterName(source)
        local player = Bridge.GetPlayer(source)
        if not player then return GetPlayerName(source) or 'Unknown' end

        local data = player.PlayerData or player
        local charinfo = data.charinfo or {}
        local first = charinfo.firstname or charinfo.firstName or ''
        local last = charinfo.lastname or charinfo.lastName or ''
        local name = (('%s %s'):format(first, last)):gsub('^%s+', ''):gsub('%s+$', '')

        if name == '' then name = GetPlayerName(source) or 'Unknown' end
        return name
    end

    function Bridge.Notify(source, message, notifyType)
        notifyType = notifyType or 'primary'
        if notifyType == 'inform' then notifyType = 'primary' end

        if GetResourceState('qb-core') == 'started' then
            TriggerClientEvent('QBCore:Notify', source, message, notifyType)
            return
        end

        if GetResourceState('ox_lib') == 'started' and lib and lib.notify then
            TriggerClientEvent('ox_lib:notify', source, {
                title = 'Mokia 3310',
                description = message,
                type = notifyType == 'primary' and 'inform' or notifyType
            })
            return
        end

        TriggerClientEvent('chat:addMessage', source, { args = { 'Mokia 3310', message } })
    end

    function Bridge.RegisterCallback(name, cb)
        if GetResourceState('qb-core') == 'started' then
            local core = getQBCore()
            if core and core.Functions and core.Functions.CreateCallback then
                core.Functions.CreateCallback(name, function(source, reply, ...)
                    local result = cb(source, ...)
                    reply(result)
                end)
                debugPrint('Registered QB callback:', name)
                return
            end
        end

        if GetResourceState('ox_lib') == 'started' and lib and lib.callback then
            lib.callback.register(name, cb)
            debugPrint('Registered ox callback:', name)
            return
        end

        error(('No supported callback system found for %s. Start qb-core or ox_lib before this resource.'):format(name))
    end

    function Bridge.OpenPhone(source)
        TriggerClientEvent('blixt-mokia:client:openPhone', source)
    end

    function Bridge.RegisterPhoneItems()
        local framework = Bridge.GetFramework()

        if framework == 'qb' or GetResourceState('qb-core') == 'started' then
            local core = getQBCore()
            if core and core.Functions and core.Functions.CreateUseableItem then
                for _, itemName in ipairs(Config.PhoneItems) do
                    core.Functions.CreateUseableItem(itemName, function(source)
                        debugPrint('QB usable item fired:', itemName, source)
                        Bridge.OpenPhone(source)
                    end)
                    debugPrint('Registered QB usable phone item:', itemName)
                end
            end
        elseif framework == 'qbx' and GetResourceState('qbx_core') == 'started' then
            for _, itemName in ipairs(Config.PhoneItems) do
                exports.qbx_core:CreateUseableItem(itemName, function(source)
                    debugPrint('QBX usable item fired:', itemName, source)
                    Bridge.OpenPhone(source)
                end)
                debugPrint('Registered QBX usable phone item:', itemName)
            end
        end

        if Config.UseOxInventoryHooks and GetResourceState('ox_inventory') == 'started' then
            local itemFilter = {}
            for _, itemName in ipairs(Config.PhoneItems) do
                itemFilter[itemName] = true
            end

            exports.ox_inventory:registerHook('useItem', function(payload)
                local source = payload and payload.source
                local itemName = payload and payload.itemName

                if not source or not itemName then return end
                if not itemFilter[itemName] then return end

                debugPrint('ox_inventory useItem hook fired:', itemName, source)
                Bridge.OpenPhone(source)
                return false
            end, {
                itemFilter = itemFilter
            })

            debugPrint('Registered ox_inventory useItem hook fallback.')
        end
    end

    function Bridge.SetPlayerCall(source, channel)
        exports['pma-voice']:setPlayerCall(source, channel)
    end
else
    local QBCore

    local function getQBCore()
        if QBCore then return QBCore end
        if GetResourceState('qb-core') ~= 'started' then return nil end
        local ok, core = pcall(function()
            return exports['qb-core']:GetCoreObject()
        end)
        if ok then QBCore = core end
        return QBCore
    end

    function Bridge.Notify(message, notifyType)
        notifyType = notifyType or 'primary'
        if notifyType == 'inform' then notifyType = 'primary' end

        local core = getQBCore()
        if core and core.Functions and core.Functions.Notify then
            core.Functions.Notify(message, notifyType)
            return
        end

        if GetResourceState('ox_lib') == 'started' and lib and lib.notify then
            lib.notify({
                title = 'Mokia 3310',
                description = message,
                type = notifyType == 'primary' and 'inform' or notifyType
            })
            return
        end

        TriggerEvent('chat:addMessage', { args = { 'Mokia 3310', message } })
    end

    function Bridge.CallbackAwait(name, ...)
        local args = { ... }
        local p = promise.new()
        local core = getQBCore()

        if core and core.Functions and core.Functions.TriggerCallback then
            core.Functions.TriggerCallback(name, function(result)
                p:resolve(result)
            end, table.unpack(args))
            return Citizen.Await(p)
        end

        if GetResourceState('ox_lib') == 'started' and lib and lib.callback then
            return lib.callback.await(name, false, table.unpack(args))
        end

        debugPrint('No callback system available for:', name)
        return nil
    end
end
