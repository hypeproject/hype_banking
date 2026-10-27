local utils = {}
local config = require 'shared.config'

--- Create Transaction ID
function utils.createTransactionId()
    local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
    return string.gsub(template, '[xy]', function(c)
        local v = (c == 'x') and math.random(0, 0xf) or math.random(8, 0xb)
        return string.format('%x', v)
    end)
end

--- Sanitize Message (for display or logging safety)
---@param message string
---@return string
function utils.sanitizeMessage(message)
    if type(message) ~= "string" then
        message = tostring(message or '')
    end
    message = message:gsub("'", "''"):gsub("\\", "\\\\")
    return message
end

--- Get Management Access
---@param playerJob string
---@param playerGrade number
---@param access string | string[]
function utils.getManagementAccess(playerJob, playerGrade, access)
    if not playerJob or not playerGrade then
        return false
    end

    -- Check if job exists in management access config
    if not config.ManagementAccess or not config.ManagementAccess[playerJob] then
        return false
    end

    local numGrade = tonumber(playerGrade) or 0

    -- Handle both single string and array of access types
    local accessTypes = type(access) == 'table' and access or {access}
    
    -- Check each requested access type
    for _, accessType in ipairs(accessTypes) do
        local requiredGrade = config.ManagementAccess[playerJob][accessType]
        
        -- If access type doesn't exist or player grade is lower than required
        if not requiredGrade or numGrade < requiredGrade then
            return false
        end
    end
    
    return true
end

return utils