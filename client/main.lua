local phoneOpen = false
local phoneTyping = false
local currentCallId = nil
local callActive = false
local testCall = nil

local phoneProp = nil
local phoneAnimState = nil

local function nui(action, data)
    SendNUIMessage({
        action = action,
        data = data or {}
    })
end

local function debugPrint(...)
    if Config.Debug then
        print('[blixt-mokia:client]', ...)
    end
end

local function loadModel(model)
    if type(model) == 'string' then
        model = joaat(model)
    end

    if not IsModelInCdimage(model) then
        debugPrint('Phone prop model not found:', model)
        return nil
    end

    RequestModel(model)
    local timeout = GetGameTimer() + 5000

    while not HasModelLoaded(model) do
        Wait(0)
        if GetGameTimer() > timeout then
            debugPrint('Timed out loading phone prop model:', model)
            return nil
        end
    end

    return model
end

local function loadAnimDict(dict)
    RequestAnimDict(dict)
    local timeout = GetGameTimer() + 5000

    while not HasAnimDictLoaded(dict) do
        Wait(0)
        if GetGameTimer() > timeout then
            debugPrint('Timed out loading anim dict:', dict)
            return false
        end
    end

    return true
end

local function deletePhoneProp()
    if phoneProp and DoesEntityExist(phoneProp) then
        DeleteEntity(phoneProp)
    end

    phoneProp = nil
end

local function ensurePhoneProp()
    if not Config.PhoneVisuals or not Config.PhoneVisuals.Enabled then return end
    if phoneProp and DoesEntityExist(phoneProp) then return end

    local ped = PlayerPedId()
    local model = loadModel(Config.PhoneVisuals.PropModel or 'prop_v_m_phone_o1s')
    if not model then return end

    phoneProp = CreateObject(model, 0.0, 0.0, 0.0, true, true, false)
    SetEntityCollision(phoneProp, false, false)
    SetModelAsNoLongerNeeded(model)

    local placement = Config.PhoneVisuals.PropPlacement or {}
    local bone = placement.bone or 28422
    local coords = placement.coords or vec3(0.0, 0.0, 0.0)
    local rot = placement.rot or vec3(0.0, 0.0, 0.0)

    AttachEntityToEntity(
        phoneProp,
        ped,
        GetPedBoneIndex(ped, bone),
        coords.x or 0.0,
        coords.y or 0.0,
        coords.z or 0.0,
        rot.x or 0.0,
        rot.y or 0.0,
        rot.z or 0.0,
        true,
        true,
        false,
        true,
        1,
        true
    )
end

local function clearPhoneAnim()
    local ped = PlayerPedId()
    local visuals = Config.PhoneVisuals or {}
    local anims = visuals.Animations or {}

    for _, anim in pairs(anims) do
        if anim.dict and anim.anim then
            StopAnimTask(ped, anim.dict, anim.anim, 1.0)
        end
    end

    phoneAnimState = nil
end

local function playPhoneAnim(state)
    local visuals = Config.PhoneVisuals or {}
    if not visuals.Enabled then return end

    local animConfig = visuals.Animations and visuals.Animations[state]
    if not animConfig or not animConfig.dict or not animConfig.anim then return end

    local ped = PlayerPedId()
    if IsEntityDead(ped) or IsPedRagdoll(ped) then return end

    ensurePhoneProp()

    if phoneAnimState ~= state then
        clearPhoneAnim()
        phoneAnimState = state
    end

    if not loadAnimDict(animConfig.dict) then return end

    if not IsEntityPlayingAnim(ped, animConfig.dict, animConfig.anim, 3) then
        TaskPlayAnim(
            ped,
            animConfig.dict,
            animConfig.anim,
            animConfig.blendIn or 3.0,
            animConfig.blendOut or -3.0,
            animConfig.duration or -1,
            animConfig.flag or 50,
            animConfig.playbackRate or 0.0,
            false,
            false,
            false
        )
    end
end

local function cleanupPhoneVisuals()
    clearPhoneAnim()
    deletePhoneProp()
end

local function refreshPhoneVisuals()
    if callActive then
        playPhoneAnim('call')
    elseif phoneOpen then
        playPhoneAnim('use')
    else
        cleanupPhoneVisuals()
    end
end

local function setPhoneVisible(visible)
    phoneOpen = visible
    SetNuiFocus(visible, visible)

    if not visible then
        phoneTyping = false
    end

    if SetNuiFocusKeepInput then
        SetNuiFocusKeepInput(visible and (Config.AllowMovementWhileOpen == true) and not phoneTyping)
    end

    nui(visible and 'open' or 'close')

    if visible then
        local phoneData = Bridge.CallbackAwait('blixt-mokia:server:getPhoneData')
        nui('phoneData', phoneData or {})
    end

    refreshPhoneVisuals()
end

exports('setPhoneVisible', setPhoneVisible)

exports('openPhone', function()
    setPhoneVisible(true)
end)

RegisterNetEvent('blixt-mokia:client:openPhone', function()
    if Config.Debug then
        print('[blixt-mokia:client] openPhone event received')
    end
    setPhoneVisible(true)
end)

if Config.EnableOpenCommand then
    RegisterCommand(Config.OpenCommand, function()
        setPhoneVisible(not phoneOpen)
    end, false)
end

if Config.Debug then
    RegisterCommand((Config.TestCall and Config.TestCall.Command) or 'testcall', function()
        if testCall or currentCallId or callActive then
            Bridge.Notify('A call is already active.', 'error')
            return
        end

        local callId = ('testcall:%s:%s'):format(GetPlayerServerId(PlayerId()), GetGameTimer())
        local number = (Config.TestCall and Config.TestCall.Number) or '0400002001'
        local name = (Config.TestCall and Config.TestCall.Name) or 'Test Caller'

        testCall = {
            callId = callId,
            number = number,
            name = name
        }

        currentCallId = callId
        callActive = false

        if not phoneOpen then
            setPhoneVisible(true)
        end

        nui('incomingCall', {
            callId = callId,
            number = number,
            name = name
        })

        refreshPhoneVisuals()

        SetTimeout(((Config.TestCall and Config.TestCall.RingSeconds) or 12) * 1000, function()
            if testCall and testCall.callId == callId and not callActive then
                currentCallId = nil
                callActive = false
                nui('callEnded', { reason = 'Missed test call' })
                testCall = nil
                refreshPhoneVisuals()
            end
        end)
    end, false)
end

RegisterNUICallback('close', function(_, cb)
    if testCall then
        testCall = nil
        currentCallId = nil
        callActive = false
    end

    phoneTyping = false
    setPhoneVisible(false)
    cb({ ok = true })
end)

RegisterNUICallback('setTypingState', function(data, cb)
    phoneTyping = data and data.typing == true

    if phoneOpen and SetNuiFocusKeepInput then
        SetNuiFocusKeepInput((Config.AllowMovementWhileOpen == true) and not phoneTyping)
    end

    cb({ ok = true })
end)

RegisterNUICallback('getContacts', function(_, cb)
    local contacts = Bridge.CallbackAwait('blixt-mokia:server:getContacts')
    cb(contacts or {})
end)

RegisterNUICallback('addContact', function(data, cb)
    local result = Bridge.CallbackAwait('blixt-mokia:server:addContact', data)
    cb(result or { success = false })
end)

RegisterNUICallback('deleteContact', function(data, cb)
    local result = Bridge.CallbackAwait('blixt-mokia:server:deleteContact', data and data.id)
    cb(result or { success = false })
end)

RegisterNUICallback('getThreads', function(_, cb)
    local threads = Bridge.CallbackAwait('blixt-mokia:server:getThreads')
    cb(threads or {})
end)

RegisterNUICallback('getMessages', function(data, cb)
    local messages = Bridge.CallbackAwait('blixt-mokia:server:getMessages', data and data.number)
    cb(messages or {})
end)

RegisterNUICallback('getSnakeTopScore', function(_, cb)
    local result = Bridge.CallbackAwait('blixt-mokia:server:getSnakeTopScore')
    cb(result or { topScore = 0 })
end)

RegisterNUICallback('saveSnakeScore', function(data, cb)
    local result = Bridge.CallbackAwait('blixt-mokia:server:saveSnakeScore', data and data.score)
    cb(result or { success = false, topScore = 0, newHigh = false })
end)

RegisterNUICallback('sendMessage', function(data, cb)
    local result = Bridge.CallbackAwait('blixt-mokia:server:sendMessage', data)
    cb(result or { success = false })
end)

RegisterNUICallback('startCall', function(data, cb)
    local result = Bridge.CallbackAwait('blixt-mokia:server:startCall', data and data.number)
    cb(result or { success = false })
end)

RegisterNUICallback('answerCall', function(data, cb)
    local callId = data and data.callId

    if testCall and callId == testCall.callId then
        callActive = true
        nui('callStarted', {
            callId = testCall.callId,
            number = testCall.number
        })
        refreshPhoneVisuals()

        SetTimeout((Config.TestCall.ConnectedSeconds or 4) * 1000, function()
            if testCall and testCall.callId == callId then
                currentCallId = nil
                callActive = false
                nui('callEnded', { reason = 'Test over' })
                testCall = nil
                refreshPhoneVisuals()
            end
        end)

        cb({ ok = true })
        return
    end

    if callId then
        TriggerServerEvent('blixt-mokia:server:answerCall', callId)
    end
    cb({ ok = true })
end)

RegisterNUICallback('declineCall', function(data, cb)
    local callId = data and data.callId

    if testCall and callId == testCall.callId then
        currentCallId = nil
        callActive = false
        nui('callEnded', { reason = 'Rejected' })
        testCall = nil
        refreshPhoneVisuals()
        cb({ ok = true })
        return
    end

    if callId then
        TriggerServerEvent('blixt-mokia:server:declineCall', callId)
    end
    cb({ ok = true })
end)

RegisterNUICallback('endCall', function(data, cb)
    local callId = data and data.callId or currentCallId

    if testCall and callId == testCall.callId then
        currentCallId = nil
        callActive = false
        nui('callEnded', { reason = 'Test over' })
        testCall = nil
        refreshPhoneVisuals()
        cb({ ok = true })
        return
    end

    if callId then
        TriggerServerEvent('blixt-mokia:server:endCall', callId)
    end
    cb({ ok = true })
end)

RegisterNetEvent('blixt-mokia:client:newMessage', function(data)
    nui('newMessage', data)
    Bridge.Notify(('New text from %s'):format(data.from or 'Unknown'), 'inform')
end)

RegisterNetEvent('blixt-mokia:client:incomingCall', function(data)
    currentCallId = data.callId
    callActive = false
    nui('incomingCall', data)
    if not phoneOpen then
        setPhoneVisible(true)
    else
        refreshPhoneVisuals()
    end
end)

RegisterNetEvent('blixt-mokia:client:outgoingCall', function(data)
    currentCallId = data.callId
    callActive = false
    nui('outgoingCall', data)
    refreshPhoneVisuals()
end)

RegisterNetEvent('blixt-mokia:client:callStarted', function(data)
    currentCallId = data.callId
    callActive = true
    nui('callStarted', data)
    refreshPhoneVisuals()
end)

RegisterNetEvent('blixt-mokia:client:callEnded', function(data)
    currentCallId = nil
    callActive = false
    nui('callEnded', data)
    refreshPhoneVisuals()
end)

CreateThread(function()
    while true do
        if phoneOpen and (Config.AllowMovementWhileOpen or phoneTyping) then
            Wait(0)

            if phoneTyping then
                -- Text-entry screens need exclusive keyboard focus so typed letters/numbers
                -- do not also move the player, open chat, equip weapons, or trigger shortcuts.
                DisableAllControlActions(0)

                -- Keep only camera/look available enough that the game does not feel hard-frozen.
                EnableControlAction(0, 1, true) -- look left/right
                EnableControlAction(0, 2, true) -- look up/down
                EnableControlAction(0, 249, true) -- push to talk
            else
                -- Keep normal movement/camera controls available, but stop combat/weapon actions
                -- from firing while the NUI has focus and the player is holding the phone.
                DisableControlAction(0, 24, true) -- attack
                DisableControlAction(0, 25, true) -- aim
                DisableControlAction(0, 37, true) -- weapon wheel
                DisableControlAction(0, 45, true) -- reload
                DisableControlAction(0, 68, true) -- vehicle aim
                DisableControlAction(0, 69, true) -- vehicle attack
                DisableControlAction(0, 70, true) -- vehicle attack 2
                DisableControlAction(0, 91, true) -- passenger aim
                DisableControlAction(0, 92, true) -- passenger attack
                DisableControlAction(0, 140, true) -- melee light
                DisableControlAction(0, 141, true) -- melee heavy
                DisableControlAction(0, 142, true) -- melee alternate
                DisableControlAction(0, 257, true) -- attack 2
                DisableControlAction(0, 263, true) -- melee attack 1
                DisableControlAction(0, 264, true) -- melee attack 2
            end
        else
            Wait(250)
        end
    end
end)

CreateThread(function()
    while true do
        Wait(1500)

        if phoneOpen or callActive then
            local ped = PlayerPedId()
            if IsEntityDead(ped) then
                cleanupPhoneVisuals()
            else
                refreshPhoneVisuals()
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end

    phoneTyping = false

    if phoneOpen then
        SetNuiFocus(false, false)
    end

    cleanupPhoneVisuals()
end)
