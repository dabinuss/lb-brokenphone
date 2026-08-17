fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'lb-brokenphone'
description 'Persistent, phone-number-based display damage for LB Phone.'
author 'Dabinuss'
version '1.0.1'

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

-- Keep config.lua and the integrations/ adapter layer readable/editable in
-- escrowed builds. config.lua needs tuning (commands, auto-damage chances,
-- hack text, etc.) without our help, and integrations/ hooks into
-- framework/weapon/vehicle specifics that vary per server -- owners need to
-- patch or extend detection themselves instead of forking from scratch.
escrow_ignore {
    'config.lua',
    'integrations/shared.lua',
    'integrations/damage-evidence.server.lua',
    'integrations/physical-damage.server.lua',
    'integrations/physical-damage.client.lua',
    'integrations/fire-damage.server.lua',
    'integrations/fire-damage.client.lua'
}

dependency 'lb-phone'
