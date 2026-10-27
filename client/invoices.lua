local utils = require 'shared.utils'
local config = require 'shared.config'
require (('bridge.%s.client'):format(config.framework))

local function invoiceMenu(playerId)
    local input = lib.inputDialog('Create Invoice', {
        { type = 'input', label = 'Item', required = true, placeholder = 'cth: Jasa Perbaikan Kendaraan' },
        { type = 'number', label = 'Amount', required = true, min = 1 },
        { type = 'textarea', label = 'Note (Optional)'},
        { type = 'checkbox', label = 'Auto Pay', default = false},
    })
    
    if not input or not input[2] or tonumber(input[2]) <= 0 then return end
    TriggerServerEvent('hype_banking:server:createInvoice', {
        target = playerId,
        item = input[1],
        amount = tonumber(input[2]),
        note = input[3],
        autoPay = input[4] or false,
    })
end

local function canCreateInvoice()
    if not PlayerData or not PlayerData.job or not PlayerData.job.name then
        return false
    end
    return utils.getManagementAccess(PlayerData.job.name, PlayerData.job.grade or 0, 'createInvoice')
end

if config.interactionType == 'ox_target' then
    exports.ox_target:addGlobalPlayer({
        {
            name = "createInvoice",
            label = "Send Invoice",
            icon = "fa-money-bill-wave",
            onSelect = function (data)
                local entity = data.entity
                local playerIndex = NetworkGetPlayerIndexFromPed(entity)
                if playerIndex and playerIndex ~= -1 then
                    local serverId = GetPlayerServerId(playerIndex)
                    invoiceMenu(serverId)
                end
            end,
            canInteract = function ()
                return canCreateInvoice()
            end
        },
    })
elseif config.interactionType == 'interact' then
    exports.interact:addGlobalPlayerInteraction({
        distance = 5.0,
        interactDst = 1.5,
        offset = vec3(0.0, 0.0, 0.0),
        id = 'createInvoice',
        options = {
            name = 'createInvoice',
            label = 'Send Invoice',
            action = function(entity, _, _, serverId)
                invoiceMenu(serverId)
            end,
            canInteract = function ()
                return canCreateInvoice()
            end
        }
    })
end

RegisterNetEvent('hype_banking:client:openInvoiceMenu', function (invoiceList)
    SendNUIMessage({action = 'setLoading', data = {status = true}})
    SetTimeout(500, function()
        SetNuiFocus(true, true)
        SendNUIMessage({
            action = 'setVisible',
            data = {
                status = true,
                page = 'invoices',
                loading = false,
            }
        })
        SendNUIMessage({
            action = 'setInvoices',
            data = invoiceList or {}
        })
    end)
end)

RegisterNUICallback('hype_banking:client:getInvoices', function (_, cb)
    local resp = lib.callback.await('hype_banking:server:getInvoices', false)
    cb(resp)
end)

RegisterNUICallback('hype_banking:client:getAllInvoices', function (_, cb)
    local resp = lib.callback.await('hype_banking:server:getAllInvoices', false)
    cb(resp)
end)

RegisterNUICallback('hype_banking:client:payInvoice', function (inv, cb)
    local resp = lib.callback.await('hype_banking:server:payInvoice', false, inv)
    cb(resp)
end)

RegisterNUICallback('hype_banking:client:cancelInvoice', function (inv, cb)
    local resp = lib.callback.await('hype_banking:server:cancelInvoice', false, inv)
    cb(resp)
end)

RegisterNUICallback('hype_banking:client:payAllPendingInvoices', function (_, cb)
    local resp = lib.callback.await('hype_banking:server:payAllPendingInvoices', false)
    cb(resp)
end)