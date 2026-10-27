if GetResourceState('qbx_core') ~= 'started' then
    return
end

local core = {}

local function createPlayerObject(player)
    local playerData = player.PlayerData
    local jobLabel = playerData.job.label
    if not jobLabel then
        local jobs = exports.qbx_core:GetJobs()
        if jobs and jobs[playerData.job.name] then
            jobLabel = jobs[playerData.job.name].label
        end
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
    local player = exports.qbx_core:GetPlayer(tonumber(source) or source)
    if not player then return end
    return createPlayerObject(player)
end

--- Get Framework Player Data By Identifier
---@param identifier string
function core.GetPlayerById(identifier)
    if not identifier or identifier == '' then return end
    local player = exports.qbx_core:GetPlayerByCitizenId(identifier)
    if not player then return end
    return createPlayerObject(player)
end

function core.GetJobs()
    local jobs = {}
    local frameworkJobs = exports.qbx_core:GetJobs() or {}
    for jobName, job in pairs(frameworkJobs) do
        jobs[jobName] = {
            label = job.label,
            name = jobName
        }
    end
    return jobs
end

function core.GetGangs()
    local gangs = {}
    local frameworkGangs = exports.qbx_core:GetGangs() or {}
    for gangName, gang in pairs(frameworkGangs) do
        gangs[gangName] = {
            label = gang.label,
            name = gangName
        }
    end
    return gangs
end

--- On Framework Player Loaded
---@param cb function
function core.onPlayerLoad(cb)
    AddEventHandler('qbx_core:server:playerLoaded', function (playerData)
        cb(playerData?.citizenid)
    end)
    AddEventHandler('QBCore:Server:PlayerLoaded', function (Player)
        cb(Player?.PlayerData?.citizenid)
    end)
end

--- On Resource Start To Load Player Data
---@param cb function
function core.onResourceStart(cb)
    local players = exports.qbx_core:GetQBPlayers() or {}
    for _, Player in pairs(players) do
        if Player then
            cb(Player?.PlayerData?.citizenid)
        end
    end
end

return core
