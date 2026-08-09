fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'lb-phone-damage'
description 'Persistent, phone-number-based display damage for LB Phone.'
author 'Dabinuss'
version '1.0.0'

shared_script 'config.lua'
server_script 'server.lua'
client_script 'client.lua'

files {
    'html/cracks/**/*.png'
}

dependency 'lb-phone'
