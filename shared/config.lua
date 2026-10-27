local config = {}
config.locale = 'en' -- en, id
config.progressType = 'circle' -- circle or bar
config.currency = 'USD'
config.platinumThreshold = 75000 -- Amount required for an account to be considered platinum
config.interactionType = 'ox_target' -- ox_target or interact https://github.com/darktrovx/interact

config.framework = 'auto' -- esx / qb / qbx / hype / auto

-- Normalize and auto-detect framework if needed
local configuredFramework = config.framework
if configuredFramework == 'qbox' then
    configuredFramework = 'qbx'
end

if not configuredFramework or configuredFramework == 'auto' then
    if GetResourceState('qbx_core') == 'started' then
        configuredFramework = 'qbx'
    elseif GetResourceState('qb-core') == 'started' then
        configuredFramework = 'qb'
    elseif GetResourceState('es_extended') == 'started' then
        configuredFramework = 'esx'
    elseif GetResourceState('hype_core') == 'started' then
        configuredFramework = 'hype'
    else
        configuredFramework = 'esx'
    end
end
config.framework = configuredFramework

config.App = {
    name = 'Hype Banking',
    description = 'Banking App',
    developer = 'Hype',
    identifier = 'hype-banking',
    defaultApp = true
}

config.Invoices = {
    vat = 0,
    prefix = 'INV',
}

config.ManagementAccess = {
    ['police'] = {
        createInvoice = 2,
        cancelInvoice = 2,
        viewInvoice = 2,
        withdraw = 2,
        deposit = 2,
        transfer = 2,
    },
    ['ambulance'] = {
        createInvoice = 2,
        cancelInvoice = 2,
        viewInvoice = 2,
        withdraw = 2,
        deposit = 2,
        transfer = 2,
    },
}

config.atmProps = {
    `prop_atm_01`,
    `prop_atm_02`,
    `prop_atm_03`,
    `prop_fleeca_atm`
}

config.blip = {
    sprite = 108,
    display = 4,
    scale = 0.8,
    color = 2,
    label = 'Bank',
}

--[[ Peds And Bank Locations]]
--
config.peds = {
    [1] = {
        -- Pacific Standard
        model = 'u_m_m_bankman',
        coords = vector4(241.44, 227.19, 106.29, 170.43),
        blip = {
            sprite = 108,
            display = 4,
            scale = 0.8,
            color = 5,
            label = 'Pacific Bank',
        },
        createAccounts = true
    },
    [2] = {
        model = 'ig_barry',
        coords = vector4(313.84, -280.58, 54.16, 338.31)
    },
    [3] = {
        model = 'ig_barry',
        coords = vector4(149.46, -1042.09, 29.37, 335.43)
    },
    [4] = {
        model = 'ig_barry',
        coords = vector4(-351.23, -51.28, 49.04, 341.73)
    },
    [5] = {
        model = 'ig_barry',
        coords = vector4(-1211.9, -331.9, 37.78, 20.07)
    },
    [6] = {
        model = 'ig_barry',
        coords = vector4(-2961.14, 483.09, 15.7, 83.84)
    },
    [7] = {
        model = 'ig_barry',
        coords = vector4(1174.8, 2708.2, 38.09, 178.52)
    },
    [8] = {
        -- paleto
        model = 'u_m_m_bankman',
        coords = vector4(-112.22, 6471.01, 31.63, 134.18),
        createAccounts = true
    }
}

return config
