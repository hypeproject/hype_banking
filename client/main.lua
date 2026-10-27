local STATES = {appReady = false, uiOpen = false}
local config = require 'shared.config'
require (('bridge.%s.client'):format(config.framework))
local utils = require 'client.utils'

local function setConfig()
    local locales = lib.getLocales()
    utils.sendMessage('setLocales', {translations = locales, currency = config.currency})
end

local function focusInterface(state)
    STATES.uiOpen = state
    SetNuiFocus(state, state)
end

local function openInterface(isAtm)
    if STATES.uiOpen then return end
    utils.sendMessage('setLoading', {status = true})
    local accounts = lib.callback.await('hype_banking:server:getBankData', false)
    if not accounts then
        utils.sendMessage('setLoading', {status = false})
        lib.notify({
            description = locale('loading_failed'),
            title = locale('bank_name'),
            type = 'error'
        })
        return
    end
    Wait(200)
    focusInterface(true)
    utils.sendMessage('setVisible', {
        status = STATES.uiOpen,
        accounts = accounts,
        loading = false,
        atm = isAtm,
        platinumThreshold = config.platinumThreshold
    })
    return true
end

utils.createPeds(openInterface)
utils.addModelInteraction(openInterface)

--[[ NUI Callbacks ]] --
RegisterNUICallback('appReady', function(_, cb)
    STATES.appReady = true
    setConfig()
    cb('ok')
end)

RegisterNUICallback('deposit', function(data, cb)
    local newTransaction = lib.callback.await('hype_banking:server:deposit', false, data)
    cb(newTransaction)
end)

RegisterNUICallback('withdraw', function(data, cb)
    local newTransaction = lib.callback.await('hype_banking:server:withdraw', false, data)
    cb(newTransaction)
end)

RegisterNUICallback('transfer', function(data, cb)
    local newTransaction = lib.callback.await('hype_banking:server:transfer', false, data)
    cb(newTransaction)
end)

RegisterNUICallback('closeInterface', function(_, cb)
    focusInterface(false)
    cb('ok')
end)

-- done
RegisterNUICallback('hype_banking:client:getPlayerAccounts', function(_, cb)
    local accounts = lib.callback.await('hype_banking:server:getPlayerAccounts', false)
    cb(accounts)
end)

-- done
RegisterNUICallback('hype_banking:client:createNewAccount', function (data, cb)
    local resp = lib.callback.await('hype_banking:server:createNewAccount', false, data)
    cb(resp)
end)

-- done
RegisterNUICallback('hype_banking:client:viewMemberManagement', function (data, cb)
    local resp = lib.callback.await('hype_banking:server:viewMemberManagement', false, data)
    cb(resp)
end)

-- done
RegisterNUICallback('hype_banking:client:addAccountMember', function (data, cb)
    local resp = lib.callback.await('hype_banking:server:addAccountMember', false, data)
    cb(resp)
end)

-- done
RegisterNUICallback('hype_banking:client:deleteAccount', function (data, cb)
    local resp = lib.callback.await('hype_banking:server:deleteAccount', false, data)
    cb(resp)
end)

-- done
RegisterNUICallback('hype_banking:client:removeAccountMember', function (data, cb)
    local resp = lib.callback.await('hype_banking:server:removeAccountMember', false, data)
    cb(resp)
end)

-- done
RegisterNUICallback('hype_banking:client:changeAccountName', function (data, cb)
    local resp = lib.callback.await('hype_banking:server:changeAccountName', false, data)
    cb(resp)
end)

-- done
RegisterNUICallback('hype_banking:client:getBankData', function(_, cb)
    local resp = lib.callback.await('hype_banking:server:getBankData', false)
    cb(resp)
end)

-- done
RegisterNUICallback('hype_banking:client:getPhoneData', function (_, cb)
    local resp = lib.callback.await('hype_banking:server:getPhoneData', false)
    cb(resp)
end)

-- done
RegisterNUICallback('hype_banking:client:sendMoney', function (data, cb)
    local resp = lib.callback.await('hype_banking:server:sendMoney', false, data)
    cb(resp)
end)
