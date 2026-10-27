local cachedAccounts = {}

local function normalizeAuth(auth)
    local map = {}
    if type(auth) == 'table' then
        for k, v in pairs(auth) do
            if type(k) == 'string' then
                map[k] = true
            elseif type(v) == 'string' then
                map[v] = true
            end
        end
    end
    return map
end

---@class AccountProps
---@field id string
---@field name string
---@field type string
---@field frozen boolean
---@field amount number
---@field transactions table
---@field auth table
---@field creator? string

---@class Account : OxClass
---@field data AccountProps
local account = lib.class('Account')

--- Constructor
---@param data AccountProps
function account:constructor(data)
    assert(type(data) == 'table', 'Invalid data type')
    self.amount = data.amount or 0
    self.frozen = data.frozen or false
    self.id = data.id
    self.name = data.name or data.id
    self.type = data.type or 'personal'
    self.transactions = data.transactions or {}
    self.auth = normalizeAuth(data.auth)
    self.creator = data.creator
    if self.creator then
        self.auth[self.creator] = true
    end
    return self
end

function account:addMoney(amount)
    assert(type(amount) == 'number', 'Invalid amount type')
    assert(amount > 0, 'Invalid amount')
    self.amount = self.amount + amount
    MySQL.update.await('UPDATE bank_accounts_new SET amount = ? WHERE id = ?', {
        self.amount,
        self.id
    })
    cachedAccounts[self.id].amount = self.amount
    return self.amount
end

function account:setAccountName(name)
    assert(type(name) == 'string', 'Invalid name type')
    if name == self.name then return self.name end
    self.name = name
    MySQL.update.await('UPDATE bank_accounts_new SET name = ? WHERE id = ?', {
        self.name,
        self.id
    })
    cachedAccounts[self.id].name = self.name
    return self.name
end

function account:removeMoney(amount)
    assert(type(amount) == 'number', 'Invalid amount type')
    assert(amount > 0, 'Invalid amount')
    if self.amount < amount then return false end
    self.amount = self.amount - amount
    MySQL.update.await('UPDATE bank_accounts_new SET amount = ? WHERE id = ?', {
        self.amount,
        self.id
    })
    cachedAccounts[self.id].amount = self.amount
    return self.amount
end

function account:setMoney(amount)
    assert(type(amount) == 'number', 'Invalid amount type')
    assert(amount >= 0, 'Invalid amount')
    self.amount = amount
    MySQL.update.await('UPDATE bank_accounts_new SET amount = ? WHERE id = ?', {
        self.amount,
        self.id
    })
    cachedAccounts[self.id].amount = self.amount
    return self.amount
end

local accounts = {}

--- Get All Accounts
---@return table<string, AccountProps>
function accounts.getAllAccounts()
    return cachedAccounts
end exports('GetAllAccounts', accounts.getAllAccounts)

--- Create Account
---@param data AccountProps
---@param insert? string
---@return Account | nil
function accounts.new(data, insert)
    if cachedAccounts[data.id] then
        return cachedAccounts[data.id]
    end

    local acc = account:new(data)
    cachedAccounts[acc.id] = acc

    if insert ~= 'default' then
        local authList = {}
        for k in pairs(acc.auth) do
            authList[#authList + 1] = k
        end

        MySQL.insert.await("INSERT INTO bank_accounts_new (id, name, amount, transactions, auth, isFrozen, creator) VALUES (?, ?, ?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE name = VALUES(name)", {
            data.id,
            data.name or data.id,
            data.amount or 0,
            json.encode(data.transactions or {}),
            json.encode(authList),
            data.frozen and 1 or 0,
            data.creator
        })
    end
    return acc
end exports('CreateAccount', accounts.new)

function accounts.delete(id, cachedPlayers)
    if not cachedAccounts[id] then
        return false
    end

    -- Remove from database
    local success = MySQL.update.await('DELETE FROM bank_accounts_new WHERE id = ?', {
        id
    })

    if success then
        -- Remove from cache
        cachedAccounts[id] = nil
        
        -- Remove from all cached players
        if cachedPlayers then
            for _, player in pairs(cachedPlayers) do
                if player.accounts then
                    for i = #player.accounts, 1, -1 do
                        if player.accounts[i] == id then
                            table.remove(player.accounts, i)
                            break
                        end
                    end
                end
            end
        end

        return true
    end

    return false
end

--- Get Account
---@param id string
---@return AccountProps
function accounts.getAccount(id)
    return cachedAccounts[id]
end exports('GetAccount', accounts.getAccount)

return accounts