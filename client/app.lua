local app = require 'shared.config'.App
local url = GetResourceMetadata(cache.resource, "ui_page", 0)

local function AddApp()
    if GetResourceState("lb-phone") ~= "started" then return end
    local added, errorMessage = exports["lb-phone"]:AddCustomApp({
        identifier = app.identifier,
        name = app.name,
        description = app.description,
        developer = app.developer,
        defaultApp = app.defaultApp,
        size = 59812,
        images = {
            "https://cfx-nui-" .. cache.resource .. "/web/build/image/screenshot-light.png",
            "https://cfx-nui-" .. cache.resource .. "/web/build/image/screenshot-dark.png"
        },
        ui = url:find("http") and url or cache.resource .. "/" .. url,
        icon = url:find("http") and url .. "/web/build/image/icon.svg" or "https://cfx-nui-" .. cache.resource .. "/web/build/image/icon.png",
        fixBlur = true,
        onUse = function()
        end,
        onClose = function()
            exports["lb-phone"]:DisableWalkableCam()
        end
    })

    if not added then
        print("^3[hype_banking]^0 Could not add lb-phone app: " .. tostring(errorMessage))
    end
end

CreateThread(function()
    if GetResourceState("lb-phone") == "started" then
        Wait(1000)
        AddApp()
    end
end)

AddEventHandler("onResourceStart", function(resource)
    if resource == "lb-phone" then
        Wait(1000)
        AddApp()
    end
end)