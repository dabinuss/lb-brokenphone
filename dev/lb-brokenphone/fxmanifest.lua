fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'lb-brokenphone'
description 'Persistent, phone-number-based display damage for LB Phone.'
author 'Dabinuss'
version '1.0.0'

shared_scripts {
    'config.lua',
    'integrations/shared.lua'
}
server_scripts {
    'server.lua',
    'integrations/damage-evidence.server.lua',
    'integrations/physical-damage.server.lua',
    'integrations/fire-damage.server.lua'
}
client_scripts {
    'client.lua',
    'integrations/physical-damage.client.lua',
    'integrations/fire-damage.client.lua'
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/lb-brokenphone.js',
    'html/cracks/**/*.webp',
    'html/fire/**/*.webp',
    'html/hack/*.gif',
    'html/hack/*.ogg',
}

dependency 'lb-phone'
