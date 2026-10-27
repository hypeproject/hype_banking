if GetResourceState('qb-core') ~= 'started' then
    return
end
local core = {}
local success, QB = pcall(function ()
    local obj = exports['qb-core']:GetCoreObject()
    return obj
end)

if not success then return end

local function createPlayerObject(player)
    local playerData = player.PlayerData
    local jobLabel = playerData.job.label
    if not jobLabel and QB.Shared and QB.Shared.Jobs and QB.Shared.Jobs[playerData.job.name] then
        jobLabel = QB.Shared.Jobs[playerData.job.name].label
    end

    return {
        identifier = playerData.citizenid,
        source = playerData.source,
        name = ('%s %s'):format(playerData.charinfo.firstname, playerData.charinfo.lastname),
        job = {
            name = playerData.job.name,
            grade = playerData.job.grade.level or 0,
            label = jobLabel or playerData.job.name
        },
        removeMoney = function (type, amount, reason)
            return player.Functions.RemoveMoney(type, amount, reason)
        end,
        addMoney = function (type, amount, reason)
            return player.Functions.AddMoney(type, amount, reason)
        end,
        getMoney = function (type)
            return player.Functions.GetMoney(type)
        end,
    }
end

--- Get Framework Player Data By Source
---@param source number | string | integer
function core.GetPlayer(source)
    if not source or source == '' then return end
    local player = QB.Functions.GetPlayer(tonumber(source) or source)
    if not player then return end
    return createPlayerObject(player)
end

--- Get Framework Player Data By Identifier
---@param identifier string
function core.GetPlayerById(identifier)
    if not identifier or identifier == '' then return end
    local player = QB.Functions.GetPlayerByCitizenId(identifier)
    if not player then return end
    return createPlayerObject(player)
end

function core.GetJobs()
    local jobs = {}
    if QB.Shared and QB.Shared.Jobs then
        for jobName, job in pairs(QB.Shared.Jobs) do
            jobs[jobName] = {
                label = job.label,
                name = jobName
            }
        end
    end
    return jobs
end

function core.GetGangs()
    local gangs = {}
    if QB.Shared and QB.Shared.Gangs then
        for gangName, gang in pairs(QB.Shared.Gangs) do
            gangs[gangName] = {
                label = gang.label,
                name = gangName
            }
        end
    end
    return gangs
end

--- On Framework Player Loaded
---@param cb function
function core.onPlayerLoad(cb)
    AddEventHandler('QBCore:Server:PlayerLoaded', function (Player)
        cb(Player?.PlayerData?.citizenid)
    end)
end

--- On Resource Start To Load Player Data
---@param cb function
function core.onResourceStart(cb)
    local players = QB.Functions.GetQBPlayers()
    for _, Player in pairs(players) do
        if Player then
            cb(Player?.PlayerData?.citizenid)
        end
    end
end

return core