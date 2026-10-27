fx_version 'cerulean'
game 'gta5'
lua54 'yes'
name 'hype_banking'
author 'Hype Project'
version '0.1.4'

shared_scripts {
    '@ox_lib/init.lua',
    'shared/*.lua',
}

client_scripts {
    'client/*.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/*.lua',
}

ui_page 'web/build/index.html'

files {
    'web/build/**',
    'locales/*.json',
    'bridge/**/client.lua',
}