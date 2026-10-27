if GetResourceState('hype_core') ~= 'started' then
    return
end

PlayerData = PlayerData or {}
PlayerData.job = PlayerData.job or {
    name = 'unemployed',
    grade = 0,
    label = 'Unemployed'
}

local function setPlayerJob(job)
    if not job then return end
    PlayerData.job = {
        name = job.name or 'unemployed',
        grade = job.grade or 0,
        label = job.label or job.name or 'Unemployed',
    }
end

local success, hype = pcall(function ()
    local obj = exports.hype_core:getSharedObject()
    local pData = obj.GetPlayerData and obj.GetPlayerData() or obj.PlayerData
    if pData and pData.job then
        setPlayerJob(pData.job)
    end
    return obj
end)

if not success then return end

RegisterNetEvent('esx:setJob', function (job)
    setPlayerJob(job)
end)

RegisterNetEvent('esx:playerLoaded', function (xPlayer, isNew, skin)
    if xPlayer and xPlayer.job then
        setPlayerJob(xPlayer.job)
    end
end)

local core = {}
function core.getPlayerData()
    return PlayerData
end

return core
