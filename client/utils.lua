local utils = {}
local config = require 'shared.config'
local points = {}
local interactionId = 'hype_banking:client:openBankUI'

--- Send NUI Message
---@param action string
---@param data any
function utils.sendMessage(action, data)
    return SendNUIMessage({
        action = action,
        data = data
    })
end

function utils.createBlip(data)
    local blip = AddBlipForCoord(data.coords.x, data.coords.y, data.coords.z)
    SetBlipSprite(blip, data.sprite)
    SetBlipDisplay(blip, data.display)
    SetBlipScale(blip, data.scale)
    SetBlipColour(blip, data.color)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(data.label)
    EndTextCommandSetBlipName(blip)
    return blip
end

--- Create Peds
---@param openBank function
function utils.createPeds(openBank)
    for k, v in pairs(config.peds) do
        local blipdata = table.clone(v.blip or config.blip)
        blipdata.coords = v.coords
        utils.createBlip(blipdata)
        local pts = lib.points.new({
            coords = vec4(v.coords.x, v.coords.y, v.coords.z, v.coords.w),
            heading = v.coords.w,
            distance = 60,
            model = v.model,
            manager = v.createAccounts
        })

        function pts:registerInteraction()
            pts:createPed()
            if config.interactionType == 'ox_target' then
                exports.ox_target:addLocalEntity(self.entity, {
                    {
                        label = locale('view_bank'),
                        icon = 'fas fa-university',
                        name = interactionId .. '_view',
                        onSelect = function()
                            openBank(false)
                        end
                    },
                    {
                        label = locale('manage_bank'),
                        icon = 'fas fa-briefcase',
                        name = interactionId .. '_manage',
                        onSelect = function()
                            if openBank(false) then
                                utils.sendMessage('setManagementConfig', true)
                            end
                        end,
                        canInteract = function()
                            return self.manager
                        end
                    }
                })
            elseif config.interactionType == 'interact' then
                exports.interact:AddLocalEntityInteraction({
                    entity = self.entity,
                    name = interactionId,
                    id = interactionId,
                    distance = 5.0,
                    interactDst = 3.0,
                    ignoreLos = true,
                    options = {
                        {
                            label = locale('view_bank'),
                            action = function()
                                openBank(false)
                            end
                        },
                        {
                            label = locale('manage_bank'),
                            name = interactionId .. '_manage',
                            id = interactionId .. '_manage',
                            action = function()
                                if openBank(false) then
                                    utils.sendMessage('setManagementConfig', true)
                                end
                            end,
                            canInteract = function()
                                return self.manager
                            end
                        }
                    }
                })
            end
        end

        function pts:removeInteraction()
            if config.interactionType == 'ox_target' then
                if DoesEntityExist(self.entity) then
                    exports.ox_target:removeLocalEntity(self.entity)
                end
            elseif config.interactionType == 'interact' then
                if DoesEntityExist(self.entity) then
                    exports.interact:RemoveLocalEntityInteraction(self.entity)
                end
            end
            pts:deletePed()
        end

        function pts:deletePed()
            if self.entity and DoesEntityExist(self.entity) then
                DeleteEntity(self.entity)
            end
            self.entity = nil
        end

        function pts:createPed()
            pts:deletePed()
            local model = lib.requestModel(self.model, 30000)
            if not model then return end
            self.entity = CreatePed(
                0,
                model,
                self.coords.x,
                self.coords.y,
                self.coords.z - 1.0,
                self.heading,
                false,
                false
            )
            SetEntityHeading(self.entity, self.heading)

            TaskStartScenarioInPlace(self.entity, 'PROP_HUMAN_STAND_IMPATIENT', 0, true)
            FreezeEntityPosition(self.entity, true)
            SetEntityInvincible(self.entity, true)
            SetBlockingOfNonTemporaryEvents(self.entity, true)
            SetModelAsNoLongerNeeded(model)
        end

        function pts:onEnter()
            pts:registerInteraction()
        end

        function pts:onExit()
            pts:removeInteraction()
        end
        points[#points + 1] = pts
    end
end

--- Register Prop Interaction
--- @param openBank function
function utils.addModelInteraction(openBank)
    if config.interactionType == 'ox_target' then
        exports.ox_target:addModel(config.atmProps, {
            {
                name = interactionId .. '_atm',
                label = locale('view_bank'),
                icon = 'fas fa-university',
                onSelect = function()
                    openBank(true)
                end
            }
        })
    else
        for _, v in pairs(config.atmProps) do
            exports.interact:AddModelInteraction({
                model = v,
                name = interactionId .. '_atm',
                id = interactionId .. '_atm',
                distance = 5.0,
                interactDst = 3.0,
                offset = vec3(0.0, 0.0, 0.8),
                options = {
                    {
                        label = locale('view_bank'),
                        action = function()
                            openBank(true)
                        end
                    }
                }
            })
        end
    end
end

function utils.removeModelInteraction()
    if config.interactionType == 'ox_target' then
        exports.ox_target:removeModel(config.atmProps, interactionId .. '_atm')
    else
        for _, v in pairs(config.atmProps) do
            exports.interact:RemoveModelInteraction(v, interactionId .. '_atm')
        end
    end
end

AddEventHandler('onResourceStop', function(res)
    if res ~= cache.resource then return end
    for _, v in pairs(points) do
        if v.removeInteraction then
            v:removeInteraction()
        end
        if v.remove then
            v:remove()
        end
    end

    utils.removeModelInteraction()
end)

return utils
