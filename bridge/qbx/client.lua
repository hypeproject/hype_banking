if GetResourceState('qbx_core') ~= 'started' then
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

local function initPlayerData()
    local success, playerData = pcall(function()
        return exports.qbx_core:GetPlayerData()
    end)
    if success and playerData and playerData.job then
        setPlayerJob(playerData.job)
    end
end

if LocalPlayer and LocalPlayer.state and LocalPlayer.state.isLoggedIn then
    initPlayerData()
end

RegisterNetEvent('qbx_core:client:onJobUpdate', function(job)
    setPlayerJob(job)
end)

RegisterNetEvent('QBCore:Client:OnJobUpdate', function(job)
    setPlayerJob(job)
end)

RegisterNetEvent('qbx_core:client:playerLoaded', function()
    initPlayerData()
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    initPlayerData()
end)

local core = {}
function core.getPlayerData()
    return PlayerData
end

return core
