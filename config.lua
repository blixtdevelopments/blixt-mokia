Config = {}

Config.Debug = false

-- Framework support: 'auto', 'qb', 'qbx', or 'standalone'.
Config.Framework = 'qbx'

-- Item(s) that open the phone. Keep this as 'phone' if replacing qbx_npwd/npwd.
Config.PhoneItems = {
    'phone'
}

-- Optional dev command. Disabled by default so players only open via item.
-- Turn on temporarily if you need to confirm the NUI opens at all.
Config.EnableOpenCommand = false
Config.OpenCommand = 'mokia'

-- Some Qbox/ox_inventory setups do not fire qbx_core usable item callbacks the same way.
-- This enables an ox_inventory item hook fallback so using the item opens the phone.
Config.UseOxInventoryHooks = false

-- Optional txAdmin SMS announcements.
-- To enable:
-- 1. Set this to true.
-- 2. In txAdmin > Settings > Game > Notifications, enable "Hide Default Announcement".
-- 3. Restart the server.
-- Players with a phone item get an SMS from Announcement; players without one
-- still see the original txAdmin popup. Restart warnings are never sent as SMS.
-- If you turn this off later, disable "Hide Default Announcement" in txAdmin too.
Config.TxAdminAnnouncements = true


-- Script will randomly generate area codes so every number is different
Config.NumberFormat = 'us_1999'
Config.NumberAreaCodes = {
    '213', -- Los Angeles
    '310', -- West Los Angeles / coastal LA
    '323', -- Los Angeles
    '415', -- San Francisco
    '510', -- East Bay
    '702', -- Las Vegas
    '718', -- New York City
    '917', -- New York mobile/pager-era overlay
}
Config.NumberExchange = '555'
Config.NumberLength = 10

-- Automatically convert old 04xxxxxxxx numbers from earlier builds to US numbers.
-- Existing contacts, messages and call history are updated at the same time.
Config.AutoMigrateLegacyNumbers = true
Config.LegacyNumberPrefix = '04'

-- Call channel range used for pma-voice.
Config.CallChannelMin = 700000
Config.CallChannelMax = 799999

-- Ring timeout in seconds.
Config.RingTimeout = 30

-- Message length limit.
Config.MaxMessageLength = 160

-- 10 sec delay when message is sent just like back in the day
Config.MessageDeliveryDelay = 10

-- Simple html sounds
Config.EnableUiBeeps = true

-- Turn this on if you want the NUI to show slightly larger while tuning.
Config.LargeUi = false

-- Lets the player walk/drive while the phone NUI is open.
-- Combat/weapon inputs are still blocked client-side while the phone is open.
Config.AllowMovementWhileOpen = true

-- Debug-only test call command. Only registered when Config.Debug = true.
Config.TestCall = {
    Command = 'testcall',
    Number = '2135552001',
    Name = 'Test Caller',
    RingSeconds = 12,
    ConnectedSeconds = 4
}

-- Visual phone prop/animation handling. replaced with older phone prop
Config.PhoneVisuals = {
    Enabled = true,
    PropModel = 'prop_v_m_phone_o1s',

    -- Close to the standard GTA/FiveM cellphone hand placement.
    -- If the Mokia prop sits slightly wrong in-game, tweak these only.
    PropPlacement = {
        bone = 28422,
        coords = vec3(0.0, 0.0, 0.0),
        rot = vec3(0.0, 0.0, 0.0)
    },

    Animations = {
        -- Phone open / texting / looking at screen.
        use = {
            dict = 'cellphone@',
            anim = 'cellphone_text_read_base',
            flag = 50,
            blendIn = 3.0,
            blendOut = -3.0,
            duration = -1
        },

        -- Active answered call / phone to ear.
        call = {
            dict = 'cellphone@',
            anim = 'cellphone_call_listen_base',
            flag = 50,
            blendIn = 3.0,
            blendOut = -3.0,
            duration = -1
        }
    }
}
