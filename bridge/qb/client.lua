if GetResourceState('qb-core') ~= 'started' then
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
        grade = job.grade and (job.grade.level or job.grade) or 0,
        label = job.label or job.name or 'Unemployed',
    }
end

local success, QB = pcall(function ()
    local obj = exports['qb-core']:GetCoreObject()
    local playerData = obj.Functions.GetPlayerData()
    if playerData and playerData.job then
        setPlayerJob(playerData.job)
    end
    return obj
end)

if not success then return end

RegisterNetEvent('QBCore:Client:OnJobUpdate', function (job)
    setPlayerJob(job)
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function ()
    local playerData = QB.Functions.GetPlayerData()
    if playerData and playerData.job then
        setPlayerJob(playerData.job)
    end
end)

local core = {}
function core.getPlayerData()
    return PlayerData
end

return core
