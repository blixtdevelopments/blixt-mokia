fx_version 'cerulean'
game 'gta5'

name 'blixt-mokia'
author 'Blixt Developments'
description 'Custom phone for qbox/qb-core nokia style'
version '1.0.0'

lua54 'yes'

ui_page 'html/index.html'

shared_scripts {
    'config.lua',
    'bridge/shared.lua'
}

client_scripts {
    'bridge/client.lua',
    'client/main.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'bridge/server.lua',
    'server/main.lua'
}

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
    'html/assets/phone.png',
    'html/assets/ringtone.mp3',
    'html/assets/nokiatext.mp3'
}

dependencies {
    'oxmysql',
    'pma-voice'
}


