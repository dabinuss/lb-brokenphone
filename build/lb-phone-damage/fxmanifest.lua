fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'lb-phone-damage'
description 'Persistent, phone-number-based display damage for LB Phone.'
author 'Dabinuss'
version '1.0.0'

shared_script 'config.lua'
server_scripts {
    'server.lua',
    'integrations/damage-events.server.lua'
}
client_scripts {
    'client.lua',
    'integrations/damage-events.client.lua'
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/lb-phone-damage.js',
    'html/cracks/**/*.webp',
}

dependency 'lb-phone'
