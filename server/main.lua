local accounts = require 'server.account'
local utils = require 'shared.utils'
local config = require 'shared.config'
local invoices = {} --[[@as table<string, InvoiceProps>]]
local invoice = {}
local core = require (('bridge.%s.server'):format(config.framework))
local cachedPlayers = {}

local Jobs = core.GetJobs() or {}

local function onPlayerLoad(identifier)
    if not identifier then return end
    local account = MySQL.single.await('SELECT id, isFrozen, transactions FROM player_transactions WHERE id = ?', {identifier})
    
    if not account then
        MySQL.insert.await('INSERT INTO player_transactions (id, isFrozen, transactions) VALUES (?, ?, ?)', {identifier, 0, '[]'})
        account = {
            isFrozen = false,
            transactions = '[]'
        }
    end

    if not cachedPlayers[identifier] then
        cachedPlayers[identifier] = {
            isFrozen = (account.isFrozen == 1 or account.isFrozen == true),
            transactions = json.decode(account.transactions) or {},
            accounts = {}
        }
    end

    -- Match accounts where player is creator or in auth
    cachedPlayers[identifier].accounts = {}
    local allAccounts = accounts.getAllAccounts()
    for accId, acc in pairs(allAccounts) do
        if acc.creator == identifier or (acc.auth and acc.auth[identifier]) then
            cachedPlayers[identifier].accounts[#cachedPlayers[identifier].accounts + 1] = accId
        end
    end
end

--- Check if player has access to an account
---@param Player table
---@param account table
---@param permission "deposit" | "withdraw" | "transfer"
---@return boolean
local function hasAccountAccess(Player, account, permission)
    if not account then return false end
    -- Custom or Organization account created by a player
    if account.creator then
        return (account.creator == Player.identifier) or (account.auth and account.auth[Player.identifier] == true)
    end
    -- Job / Society account
    return utils.getManagementAccess(Player.job.name, Player.job.grade, permission)
end

---@class TransactionProps
---@field account string
---@field title string
---@field amount number
---@field message string
---@field issuer string
---@field receiver string
---@field trans_type "withdraw" | "deposit" | "transfer" | "receive"
---@field trans_id? string
---@field time? number

--- Create Transaction
---@param data TransactionProps
local function createTransaction(data)
    data.trans_id = data.trans_id or utils.createTransactionId()
    data.time = os.time()
    local account = accounts.getAccount(data.account)
    if account then
        table.insert(account.transactions, 1, data)
        local transactions = json.encode(account.transactions)
        MySQL.prepare.await("INSERT INTO bank_accounts_new (id, transactions) VALUES (?, ?) ON DUPLICATE KEY UPDATE transactions = ?", {
            data.account, transactions, transactions
        })
        return data
    end
    local playerAccount = cachedPlayers[data.account]
    if playerAccount then
        table.insert(playerAccount.transactions, 1, data)
        local transactions = json.encode(playerAccount.transactions)
        MySQL.prepare.await("INSERT INTO player_transactions (id, transactions) VALUES (?, ?) ON DUPLICATE KEY UPDATE transactions = ?", {
            data.account, transactions, transactions
        })
        return data
    end
    return false
end exports('CreateTransaction', createTransaction)

local function getBankData(source)
    local Player = core.GetPlayer(source)
    if not Player then return {} end

    local bankData = {}
    local identifier = Player.identifier
    if not cachedPlayers[identifier] then onPlayerLoad(identifier) end

    bankData[#bankData+1] = {
        id = identifier,
        type = locale('personal'),
        name = Player.name,
        frozen = cachedPlayers[identifier] and cachedPlayers[identifier].isFrozen or false,
        amount = Player.getMoney('bank'),
        cash = Player.getMoney('cash'),
        transactions = cachedPlayers[identifier] and cachedPlayers[identifier].transactions or {},
    }

    local account = accounts.getAccount(Player.job.name)
    if account and utils.getManagementAccess(Player.job.name, Player.job.grade, 'deposit') then
        bankData[#bankData+1] = account
    end

    -- Organization / Shared accounts
    local sharedAccounts = cachedPlayers[identifier] and cachedPlayers[identifier].accounts or {}
    for k = 1, #sharedAccounts do
        local sAccount = accounts.getAccount(sharedAccounts[k])
        if sAccount and sAccount.id ~= Player.job.name then
            bankData[#bankData+1] = sAccount
        end
    end

    return bankData
end

---@class InvoiceData
---@field player number
---@field target number
---@field item string
---@field amount number
---@field note string
---@field autoPay boolean

---@class InvoiceProps
---@field invoice_id string
---@field receiver_name string
---@field receiver_citizenid string
---@field receiver_job string
---@field author_name string
---@field author_citizenid string
---@field author_job string
---@field amount number
---@field total number
---@field vat number
---@field item string
---@field note string
---@field created_date number
---@field status "paid" | "pending" | "canceled"

--- Create Invoice
---@param data InvoiceData
function invoice.createInvoice(data)
    local player = core.GetPlayer(data.player)
    if not player then return end
    if not utils.getManagementAccess(player.job.name, player.job.grade, 'createInvoice') then return end

    local target = core.GetPlayer(data.target)
    if not target then return end

    local amount = tonumber(data.amount)
    if not amount or amount <= 0 then return end

    local jobLabel = player.job.label or (Jobs[player.job.name] and Jobs[player.job.name].label) or player.job.name
    local targetJobLabel = target.job.label or (Jobs[target.job.name] and Jobs[target.job.name].label) or target.job.name

    local newInvoice = {
        invoice_id = ('%s-%s-%s'):format(config.Invoices.prefix, jobLabel:gsub('%s+', ''), lib.string.random('........')),
        receiver_name = target.name,
        receiver_citizenid = target.identifier,
        receiver_job = target.job.name,
        author_name = player.name,
        author_citizenid = player.identifier,
        author_job = player.job.name,
        amount = amount,
        total = amount + (amount * (config.Invoices.vat or 0)),
        vat = config.Invoices.vat or 0,
        item = tostring(data.item or 'Service'),
        note = tostring(data.note or ''),
        created_date = os.time(),
        status = 'pending',
    } --[[@as InvoiceProps]]

    if data.autoPay then
        local money = target.getMoney('bank')
        if money >= newInvoice.total then
            target.removeMoney('bank', newInvoice.total, 'Invoice auto-payment: ' .. newInvoice.invoice_id)
            newInvoice.status = 'paid'

            -- Credit to issuer society or author
            local jobAccount = accounts.getAccount(player.job.name)
            if jobAccount then
                jobAccount:addMoney(newInvoice.total)
                createTransaction({
                    account = player.job.name,
                    title = ('%s / %s'):format(jobAccount.name, target.identifier),
                    amount = newInvoice.total,
                    message = ('Invoice %s paid by %s'):format(newInvoice.invoice_id, target.name),
                    issuer = target.name,
                    receiver = jobAccount.name,
                    trans_type = 'receive'
                })
            else
                player.addMoney('bank', newInvoice.total, 'Invoice payment: ' .. newInvoice.invoice_id)
            end

            createTransaction({
                account = target.identifier,
                title = ('%s / %s'):format(target.name, target.identifier),
                amount = newInvoice.total,
                message = ('Invoice %s paid to %s'):format(newInvoice.invoice_id, jobLabel),
                issuer = target.name,
                receiver = jobLabel,
                trans_type = 'transfer'
            })
        end
    end

    local resp = MySQL.insert.await([[
        INSERT INTO invoices (
            invoice_id, receiver_name, receiver_citizenid, receiver_job,
            author_name, author_citizenid, author_job,
            amount, total, vat, item, note, created_date, status
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        newInvoice.invoice_id,
        newInvoice.receiver_name,
        newInvoice.receiver_citizenid,
        newInvoice.receiver_job,
        newInvoice.author_name,
        newInvoice.author_citizenid,
        newInvoice.author_job,
        newInvoice.amount,
        newInvoice.total,
        newInvoice.vat,
        newInvoice.item,
        newInvoice.note,
        newInvoice.created_date,
        newInvoice.status
    })

    if resp then
        invoices[newInvoice.invoice_id] = newInvoice
        local description = newInvoice.status == 'paid' and ('Invoice paid to %s'):format(newInvoice.receiver_name) or ('Received new invoice from %s'):format(jobLabel)

        lib.notify(target.source, {
            title = 'Invoice',
            description = description,
            type = 'info',
            position = 'bottom',
        })

        lib.notify(player.source, {
            title = 'Invoice',
            description = ('Successfully created invoice with id %s'):format(newInvoice.invoice_id),
            type = 'success',
            position = 'bottom',
        })
    end

    return newInvoice
end exports('CreateInvoice', invoice.createInvoice)

function invoice.getPlayerInvoices(identifier)
    local tmp = {}
    for _, v in pairs(invoices) do
        if v.receiver_citizenid == identifier then
            table.insert(tmp, v)
        end
    end
    return tmp
end exports('GetPlayerInvoices', invoice.getPlayerInvoices)

function invoice.getPlayerPendingInvoices(identifier)
    local tmp = {}
    for _, v in pairs(invoices) do
        if v.receiver_citizenid == identifier and v.status == 'pending' then
            table.insert(tmp, v)
        end
    end
    return tmp
end exports('GetPlayerPendingInvoices', invoice.getPlayerPendingInvoices)

function invoice.getInvoiceByJob(job)
    local tmp = {}
    for _, v in pairs(invoices) do
        if v.author_job == job then
            table.insert(tmp, v)
        end
    end
    return tmp
end exports('GetInvoiceByJob', invoice.getInvoiceByJob)

function invoice.payInvoice(source, invoice_id)
    local player = core.GetPlayer(source)
    if not player then return end

    local inv = invoices[invoice_id]
    if not inv then return { status = 'error', message = 'Invoice not found' } end
    if inv.receiver_citizenid ~= player.identifier then return { status = 'error', message = 'Not your invoice' } end
    if inv.status ~= 'pending' then return { status = 'error', message = 'Invoice already paid or canceled' } end

    if inv.total > player.getMoney('bank') then
        return { status = 'nobalance' }
    end

    player.removeMoney('bank', inv.total, 'Invoice payment: ' .. invoice_id)
    inv.status = 'paid'
    invoices[invoice_id] = inv

    -- Credit to society or author
    local jobAccount = accounts.getAccount(inv.author_job)
    if jobAccount then
        jobAccount:addMoney(inv.total)
        createTransaction({
            account = inv.author_job,
            title = ('%s / %s'):format(jobAccount.name, player.identifier),
            amount = inv.total,
            message = ('Invoice %s paid by %s'):format(inv.invoice_id, player.name),
            issuer = player.name,
            receiver = jobAccount.name,
            trans_type = 'receive'
        })
    else
        local author = core.GetPlayerById(inv.author_citizenid)
        if author then
            author.addMoney('bank', inv.total, 'Received invoice payment: ' .. invoice_id)
        end
    end

    createTransaction({
        account = player.identifier,
        title = ('%s / %s'):format(player.name, player.identifier),
        amount = inv.total,
        message = ('Invoice %s paid'):format(inv.invoice_id),
        issuer = player.name,
        receiver = inv.author_job,
        trans_type = 'transfer'
    })

    MySQL.update.await('UPDATE invoices SET status = ? WHERE invoice_id = ?', {'paid', invoice_id})
    return {
        status = 'success',
        balance = player.getMoney('bank')
    }
end exports('PayInvoice', invoice.payInvoice)

local function getTotalAmount(invList)
    local total = 0
    for _, v in pairs(invList) do
        total = total + (v.total or 0)
    end
    return total
end

function invoice.payAllPendingInvoices(source)
    local player = core.GetPlayer(source)
    if not player then return end

    local playerInvoices = invoice.getPlayerPendingInvoices(player.identifier)
    local total = getTotalAmount(playerInvoices)
    local playerMoney = player.getMoney('bank')
    if total > playerMoney then
        return { status = 'nobalance' }
    end

    player.removeMoney('bank', total, 'Pay all pending invoices')

    local queries = {}
    for _, v in pairs(playerInvoices) do
        v.status = 'paid'
        invoices[v.invoice_id] = v
        queries[#queries + 1] = {
            query = 'UPDATE invoices SET status = ? WHERE invoice_id = ?',
            values = {'paid', v.invoice_id}
        }

        local jobAccount = accounts.getAccount(v.author_job)
        if jobAccount then
            jobAccount:addMoney(v.total)
            createTransaction({
                account = v.author_job,
                title = ('%s / %s'):format(jobAccount.name, player.identifier),
                amount = v.total,
                message = ('Invoice %s paid by %s'):format(v.invoice_id, player.name),
                issuer = player.name,
                receiver = jobAccount.name,
                trans_type = 'receive'
            })
        else
            local author = core.GetPlayerById(v.author_citizenid)
            if author then
                author.addMoney('bank', v.total, 'Received invoice payment: ' .. v.invoice_id)
            end
        end

        createTransaction({
            account = player.identifier,
            title = ('%s / %s'):format(player.name, player.identifier),
            amount = v.total,
            message = ('Invoice %s paid'):format(v.invoice_id),
            issuer = player.name,
            receiver = v.author_job,
            trans_type = 'transfer'
        })
    end

    if #queries > 0 then
        MySQL.transaction.await(queries)
    end

    return {
        status = 'success',
        balance = player.getMoney('bank')
    }
end exports('PayAllPendingInvoices', invoice.payAllPendingInvoices)

function invoice.cancelInvoice(source, invoice_id)
    local Player = core.GetPlayer(source)
    if not Player then return end

    local inv = invoices[invoice_id]
    if not inv then return { status = 'error', message = 'Invoice not found' } end
    if inv.author_job ~= Player.job.name then
        return { status = 'error', message = 'Not your invoice' }
    end
    if inv.status ~= 'pending' then
        return { status = 'error', message = 'Invoice not pending' }
    end

    inv.status = 'canceled'
    MySQL.update.await('UPDATE invoices SET status = ? WHERE invoice_id = ?', {'canceled', inv.invoice_id})
    invoices[inv.invoice_id] = inv
    return {
        status = 'success'
    }
end exports('CancelInvoice', invoice.cancelInvoice)

--[[ Callbacks ]]--

RegisterNetEvent('hype_banking:server:createInvoice', function (data)
    local src = source
    data.player = src
    return invoice.createInvoice(data)
end)

lib.callback.register('hype_banking:server:getPlayerAccounts', function(source)
    local Player = core.GetPlayer(source)
    if not Player then return {} end
    local identifier = Player.identifier
    local playerAccounts = cachedPlayers[identifier] and cachedPlayers[identifier].accounts or {}
    local data = {}
    for k = 1, #playerAccounts do
        local acc = accounts.getAccount(playerAccounts[k])
        if acc and acc.creator == identifier then
            data[#data+1] = {
                id = acc.id,
                name = acc.name,
                balance = acc.amount,
            }
        end
    end
    return data
end)

lib.callback.register('hype_banking:server:viewMemberManagement', function (source, data)
    local Player = core.GetPlayer(source)
    if not Player then return end
    local account = data.account
    local acc = accounts.getAccount(account)
    if not acc then return end
    local identifier = Player.identifier
    local resp = {
        account = account,
        members = {}
    }

    for memberId, _ in pairs(acc.auth) do
        if memberId ~= identifier then
            local Player2 = core.GetPlayerById(memberId)
            resp.members[memberId] = Player2 and Player2.name or memberId
        end
    end

    return resp
end)

lib.callback.register('hype_banking:server:createNewAccount', function(source, data)
    local Player = core.GetPlayer(source)
    if not Player then return { status = 'error' } end
    local accountId, accountLabel = data.accountId, data.label

    local account = accounts.getAccount(accountId)
    if account then
        return lib.notify(source, {title = locale("bank_name"), description = locale("account_taken"), type = "error"})
    end

    local identifier = Player.identifier
    local newAccount = {
        id = accountId,
        type = locale("org"),
        name = accountLabel or accountId,
        frozen = false,
        amount = 0,
        transactions = {},
        auth = { [identifier] = true },
        creator = identifier
    }
    local acc = accounts.new(newAccount)
    if not cachedPlayers[identifier] then
        onPlayerLoad(identifier)
    end
    cachedPlayers[identifier].accounts[#cachedPlayers[identifier].accounts+1] = accountId
    return {
        status = 'success',
    }
end)

lib.callback.register('hype_banking:server:changeAccountName', function (source, data)
    local Player = core.GetPlayer(source)
    if not Player then return false end
    local account, name = data.account, data.newName
    local acc = accounts.getAccount(account)
    if not acc then return false end
    if Player.identifier ~= acc.creator then return false end
    acc:setAccountName(name)
    return {
        status = 'success',
    }
end)

lib.callback.register('hype_banking:server:addAccountMember', function(source, data)
    local account, member = data.account, data.memberId
    if not account or not member then
        return { status = 'error', message = 'Invalid input parameters' }
    end

    local Player = core.GetPlayer(source)
    if not Player then
        return { status = 'error', message = locale("player_not_found") }
    end
    local acc = accounts.getAccount(account)
    if not acc then 
        return { status = 'error', message = locale("account_not_found") }
    end

    if Player.identifier ~= acc.creator then 
        return { status = 'error', message = locale("illegal_action", Player.name) }
    end

    local Player2 = core.GetPlayer(member) or core.GetPlayerById(member)
    if not Player2 then 
        return { status = 'error', message = locale("target_not_found") }
    end

    if Player2.identifier == Player.identifier then
        return { status = 'error', message = locale("cannot_add_self") }
    end

    local identifier = Player2.identifier
    
    if not cachedPlayers[identifier] then
        onPlayerLoad(identifier)
    end
    
    local alreadyInList = false
    for _, aId in ipairs(cachedPlayers[identifier].accounts) do
        if aId == account then
            alreadyInList = true
            break
        end
    end
    if not alreadyInList then
        cachedPlayers[identifier].accounts[#cachedPlayers[identifier].accounts + 1] = account
    end

    acc.auth[identifier] = true
    local authList = {}
    for k in pairs(acc.auth) do 
        authList[#authList + 1] = k 
    end

    MySQL.update.await('UPDATE bank_accounts_new SET auth = ? WHERE id = ?', {
        json.encode(authList),
        account
    })

    return {
        status = 'success',
        message = locale("member_added_success")
    }
end)

lib.callback.register('hype_banking:server:removeAccountMember', function(source, data)
    local Player = core.GetPlayer(source)
    if not Player then 
        return { status = 'error', message = locale("player_not_found") }
    end

    local account, member = data.account, data.memberId
    if not account or not member then
        return { status = 'error', message = locale("invalid_parameters") }
    end

    local acc = accounts.getAccount(account)
    if not acc then 
        return { status = 'error', message = locale("account_not_found") }
    end

    if Player.identifier ~= acc.creator then 
        return { status = 'error', message = locale("not_account_owner") }
    end

    local Player2 = core.GetPlayer(member) or core.GetPlayerById(member)
    local identifier = Player2 and Player2.identifier or member

    if identifier == Player.identifier then
        return { status = 'error', message = locale("cannot_remove_self") }
    end

    if acc.auth[identifier] then
        acc.auth[identifier] = nil
        
        if cachedPlayers[identifier] then
            for i = #cachedPlayers[identifier].accounts, 1, -1 do
                if cachedPlayers[identifier].accounts[i] == account then
                    table.remove(cachedPlayers[identifier].accounts, i)
                    break
                end
            end
        end

        local authList = {}
        for k in pairs(acc.auth) do
            authList[#authList + 1] = k
        end

        MySQL.update.await('UPDATE bank_accounts_new SET auth = ? WHERE id = ?', {
            json.encode(authList),
            account
        })

        return { 
            status = 'success', 
            message = locale("member_removed"),
            members = acc.auth,
        }
    end

    return {
        status = 'error',
        message = locale("member_not_in_account")
    }
end)

lib.callback.register('hype_banking:server:deleteAccount', function (src, data)
    local Player = core.GetPlayer(src)
    if not Player then return end
    local account = data.account
    local acc = accounts.getAccount(account)
    if not acc then return end
    if Player.identifier ~= acc.creator then return end
    accounts.delete(account, cachedPlayers)
    return {
        status = 'success',
    }
end)

lib.callback.register('hype_banking:server:payInvoice', function (src, data)
    return invoice.payInvoice(src, data.invoice_id)
end)

lib.callback.register('hype_banking:server:payAllPendingInvoices', function (src)
    return invoice.payAllPendingInvoices(src)
end)

lib.callback.register('hype_banking:server:getAllInvoices', function (src)
    local Player = core.GetPlayer(src)
    if not Player then return {} end
    local jobInvoices = invoice.getInvoiceByJob(Player.job.name)
    for _, v in pairs(jobInvoices) do
        v.author_job = Jobs[v.author_job] and Jobs[v.author_job].label or v.author_job
    end
    return jobInvoices
end)

lib.callback.register('hype_banking:server:getInvoices', function (src)
    local Player = core.GetPlayer(src)
    if not Player then return {} end
    local playerInvoices = invoice.getPlayerInvoices(Player.identifier)
    for _, v in pairs(playerInvoices) do
        v.author_job = Jobs[v.author_job] and Jobs[v.author_job].label or v.author_job
    end
    return playerInvoices
end)

lib.callback.register('hype_banking:server:cancelInvoice', function (src, data)
    local invoice_id = data.invoice_id
    local resp = invoice.cancelInvoice(src, invoice_id)
    return {
        status = (resp and resp.status == 'success') and 'success' or 'error'
    }
end)

lib.callback.register('hype_banking:server:sendMoney', function(src, data)
    if not data.target or not data.amount then
        return { status = 'error', message = 'invalid_input' }
    end

    local amount = tonumber(data.amount)
    if not amount or amount <= 0 then
        return { status = 'error', message = 'invalid_amount' }
    end

    local player = core.GetPlayer(src)
    if not player then
        return { status = 'error', message = 'player_not_found' }
    end

    local balance = player.getMoney('bank')
    if balance < amount then
        return { status = 'nobalance', message = 'insufficient_funds' }
    end

    local target = core.GetPlayer(data.target) or core.GetPlayerById(tostring(data.target))
    if not target then
        return { status = 'error', message = 'target_not_found' }
    end

    if not player.removeMoney('bank', amount, 'Phone transfer to ' .. target.name) then
        return { status = 'error', message = 'transfer_failed' }
    end

    target.addMoney('bank', amount, 'Phone transfer from ' .. player.name)

    createTransaction({
        account = player.identifier,
        title = ('%s / %s'):format(player.name, player.identifier),
        amount = amount,
        message = locale('phone_transfer_sent'),
        issuer = player.name,
        receiver = target.name,
        trans_type = 'transfer'
    })

    createTransaction({
        account = target.identifier,
        title = ('%s / %s'):format(target.name, target.identifier),
        amount = amount,
        message = locale('phone_transfer_received'),
        issuer = player.name,
        receiver = target.name,
        trans_type = 'receive'
    })

    return {
        status = 'success',
        balance = player.getMoney('bank')
    }
end)

lib.callback.register('hype_banking:server:deposit', function(source, data)
    local Player = core.GetPlayer(source)
    if not Player then return false end

    local amount = tonumber(data.amount)
    if not amount or amount < 1 then
        lib.notify(source, {
            description = locale("invalid_amount", "deposit"),
            title = locale("bank_name"),
            type = "error"
        })
        return false
    end

    local comment = (not data.comment or data.comment == "") and locale("comp_transaction", Player.name, "deposited", amount) or tostring(data.comment)
    
    if Player.getMoney('cash') < amount then
        lib.notify(source, {
            description = locale("not_enough_money"),
            title = locale("bank_name"),
            type = "error"
        })
        return false
    end

    local account = accounts.getAccount(data.fromAccount)
    if account then
        if not hasAccountAccess(Player, account, 'deposit') then
            lib.notify(source, {
                description = locale("no_access"),
                title = locale("bank_name"),
                type = "error"
            })
            return false
        end

        Player.removeMoney('cash', amount, 'Bank deposit: ' .. account.name)
        account:addMoney(amount)

        createTransaction({
            account = data.fromAccount,
            title = ('%s / %s'):format(account.name, Player.identifier),
            amount = amount,
            message = comment,
            issuer = Player.name,
            receiver = account.name,
            trans_type = "deposit"
        })
    else
        Player.removeMoney('cash', amount, 'Personal bank deposit')
        Player.addMoney('bank', amount, 'Personal bank deposit')

        createTransaction({
            account = Player.identifier,
            title = ('%s / %s'):format(Player.name, Player.identifier),
            amount = amount,
            message = comment,
            issuer = Player.name,
            receiver = Player.name,
            trans_type = "deposit"
        })
    end

    return getBankData(source)
end)

lib.callback.register('hype_banking:server:withdraw', function (src, data)
    local Player = core.GetPlayer(src)
    if not Player then return false end

    local amount, comment, fromAccount = tonumber(data.amount), data.comment, data.fromAccount
    if not amount or amount < 1 then
        lib.notify(src, {
            description = locale("invalid_amount", "withdraw"),
            title = locale("bank_name"),
            type = "error"
        })
        return false
    end

    comment = (not comment or comment == "") and locale("comp_transaction", Player.name, "withdrawed", amount) or tostring(comment)

    local account = accounts.getAccount(fromAccount)
    if account then
        if not hasAccountAccess(Player, account, 'withdraw') then
            lib.notify(src, {
                description = locale("no_access"),
                title = locale("bank_name"),
                type = "error"
            })
            return false
        end

        if account.amount < amount then
            lib.notify(src, {
                description = locale("not_enough_money"),
                title = locale("bank_name"),
                type = "error"
            })
            return false
        end

        account:removeMoney(amount)
        Player.addMoney('cash', amount, 'Bank withdraw: ' .. account.name)

        createTransaction({
            account = fromAccount,
            title = ('%s / %s'):format(account.name, Player.identifier),
            amount = amount,
            message = comment,
            issuer = Player.name,
            receiver = Player.name,
            trans_type = "withdraw"
        })

        return getBankData(src)
    else
        local playerMoney = Player.getMoney('bank')
        if playerMoney < amount then
            lib.notify(src, {
                description = locale("not_enough_money"),
                title = locale("bank_name"),
                type = "error"
            })
            return false
        end

        Player.removeMoney('bank', amount, 'Personal bank withdraw')
        Player.addMoney('cash', amount, 'Personal bank withdraw')

        createTransaction({
            account = Player.identifier,
            title = ('%s / %s'):format(Player.name, Player.identifier),
            amount = amount,
            message = comment,
            issuer = Player.name,
            receiver = Player.name,
            trans_type = "withdraw"
        })

        return getBankData(src)
    end
end)

lib.callback.register('hype_banking:server:transfer', function (src, data)
    local Player = core.GetPlayer(src)
    if not Player then return false end
    local amount, comment, fromAccount, toAccount = tonumber(data.amount), data.comment, data.fromAccount, data.stateid
    if not amount or amount < 1 then
        lib.notify(src, {
            description = locale("invalid_amount", "transfer"),
            title = locale("bank_name"),
            type = "error"
        })
        return false
    end

    comment = (not comment or comment == "") and locale("comp_transaction", Player.name, "transfered", amount) or tostring(comment)

    local account = accounts.getAccount(fromAccount)
    if account and not hasAccountAccess(Player, account, 'transfer') then
        lib.notify(src, {
            description = locale("no_access"),
            title = locale("bank_name"),
            type = "error"
        })
        return false
    end

    local targetAccount = accounts.getAccount(toAccount)
    if account and targetAccount then
        if account.amount < amount then
            lib.notify(src, {
                description = locale("not_enough_money"),
                title = locale("bank_name"),
                type = "error"
            })
            return false
        end
        account:removeMoney(amount)
        targetAccount:addMoney(amount)
        createTransaction({
            account = fromAccount,
            title = ('%s / %s'):format(account.name, Player.identifier),
            amount = amount,
            message = comment,
            issuer = Player.name,
            receiver = targetAccount.name,
            trans_type = "transfer",
        })
        createTransaction({
            account = toAccount,
            title = ('%s / %s'):format(targetAccount.name, toAccount),
            amount = amount,
            message = comment,
            issuer = account.name,
            receiver = targetAccount.name,
            trans_type = "receive",
        })
        return getBankData(src)
    elseif account and not targetAccount then
        local Target = core.GetPlayer(tonumber(toAccount)) or core.GetPlayerById(toAccount)
        if not Target then
            lib.notify(src, {
                description = locale("fail_transfer"),
                title = locale("bank_name"),
                type = "error"
            })
            return false
        end
        if account.amount < amount then
            lib.notify(src, {
                description = locale("not_enough_money"),
                title = locale("bank_name"),
                type = "error"
            })
            return false
        end
        account:removeMoney(amount)
        Target.addMoney('bank', amount, 'Transfer from ' .. account.name)
        createTransaction({
            account = fromAccount,
            title = ('%s / %s'):format(account.name, Player.identifier),
            amount = amount,
            message = comment,
            issuer = Player.name,
            receiver = Target.name,
            trans_type = "transfer",
        })
        createTransaction({
            account = Target.identifier,
            title = ('%s / %s'):format(Target.name, Target.identifier),
            amount = amount,
            message = comment,
            issuer = account.name,
            receiver = Target.name,
            trans_type = "receive",
        })
        return getBankData(src)
    else
        local accountMoney = Player.getMoney('bank')
        if accountMoney < amount then
            lib.notify(src, {
                description = locale("not_enough_money"),
                title = locale("bank_name"),
                type = "error"
            })
            return false
        end

        local Target = core.GetPlayer(tonumber(toAccount)) or core.GetPlayerById(toAccount)
        if not Target then
            lib.notify(src, {
                description = locale("fail_transfer"),
                title = locale("bank_name"),
                type = "error"
            })
            return false
        end
        Player.removeMoney('bank', amount, 'Transfer to ' .. Target.name)
        Target.addMoney('bank', amount, 'Transfer from ' .. Player.name)
        createTransaction({
            account = Player.identifier,
            title = ('%s / %s'):format(Player.name, Player.identifier),
            amount = amount,
            message = comment,
            issuer = Player.name,
            receiver = Target.name,
            trans_type = "transfer",
        })
        createTransaction({
            account = Target.identifier,
            title = ('%s / %s'):format(Target.name, Target.identifier),
            amount = amount,
            message = comment,
            issuer = Player.name,
            receiver = Target.name,
            trans_type = "receive",
        })
        return getBankData(src)
    end
end)

lib.callback.register('hype_banking:server:getBankData', function (src)
    return getBankData(src)
end)

lib.callback.register('hype_banking:server:getPhoneData', function (src)
    local Player = core.GetPlayer(src)
    if not Player then return end
    local playerInvoices = invoice.getPlayerPendingInvoices(Player.identifier)
    for _, v in pairs(playerInvoices) do
        v.author_job = Jobs[v.author_job] and Jobs[v.author_job].label or v.author_job
    end
    return {
        id = Player.identifier,
        balance = Player.getMoney('bank'),
        name = Player.name,
        invoices = playerInvoices
    }
end)

lib.addCommand('invoices', {
    help = 'View Invoices',
}, function (source, args, raw)
    local Player = core.GetPlayer(source)
    if not Player then return end
    if not utils.getManagementAccess(Player.job.name, Player.job.grade, 'viewInvoice') then
        lib.notify(source, {
            title = locale('bank_name'),
            description = locale('no_access'),
            type = 'error'
        })
        return
    end
    local jobInvoices = invoice.getInvoiceByJob(Player.job.name)
    for _, v in pairs(jobInvoices) do
        v.author_job = Jobs[v.author_job] and Jobs[v.author_job].label or v.author_job
    end
    TriggerClientEvent('hype_banking:client:openInvoiceMenu', source, jobInvoices)
end)

--[[ First Time Setup ]]--
core.onPlayerLoad(onPlayerLoad)
AddEventHandler('onResourceStart', function (res)
    if res ~= cache.resource then return end
    core.onResourceStart(onPlayerLoad)
end)

MySQL.ready(function ()
    local createTables = {
        { query = [[
            CREATE TABLE IF NOT EXISTS `bank_accounts_new` (
                `id` varchar(50) NOT NULL,
                `name` varchar(50) DEFAULT NULL,
                `amount` int(11) DEFAULT 0,
                `transactions` longtext DEFAULT '[]',
                `auth` longtext DEFAULT '[]',
                `isFrozen` int(11) DEFAULT 0,
                `creator` varchar(50) DEFAULT NULL,
                PRIMARY KEY (`id`)
            );
        ]], values = nil },
        { query = [[
            CREATE TABLE IF NOT EXISTS `player_transactions` (
                `id` varchar(50) NOT NULL,
                `isFrozen` int(11) DEFAULT 0,
                `transactions` longtext DEFAULT '[]',
                PRIMARY KEY (`id`)
            );
        ]], values = nil },
        { query = [[
            CREATE TABLE IF NOT EXISTS `invoices` (
                `id` int(11) NOT NULL AUTO_INCREMENT,
                `invoice_id` varchar(255) NOT NULL,
                `receiver_name` varchar(255) NOT NULL,
                `receiver_citizenid` varchar(255) NOT NULL,
                `receiver_job` varchar(255) NOT NULL,
                `author_name` varchar(255) NOT NULL,
                `author_citizenid` varchar(255) NOT NULL,
                `author_job` varchar(255) NOT NULL,
                `amount` int(11) NOT NULL,
                `total` int(11) NOT NULL,
                `vat` double NOT NULL DEFAULT 0,
                `item` varchar(255) NOT NULL,
                `note` varchar(255) NOT NULL,
                `created_date` int(11) NOT NULL,
                `status` varchar(255) NOT NULL,
                PRIMARY KEY (`id`),
                UNIQUE KEY `invoice_id` (`invoice_id`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
        ]], values = nil}
    }
    
    assert(MySQL.transaction.await(createTables), "Failed to create tables")

    -- Add name column if upgrading from older schema
    pcall(function()
        MySQL.query.await("ALTER TABLE `bank_accounts_new` ADD COLUMN IF NOT EXISTS `name` varchar(50) DEFAULT NULL AFTER `id`;")
    end)

    local registeredAccounts = MySQL.query.await('SELECT * FROM bank_accounts_new') or {}
    for _, v in pairs(registeredAccounts) do
        local rawAuth = json.decode(v.auth) or {}
        local authMap = {}
        for k, val in pairs(rawAuth) do
            if type(k) == 'string' then
                authMap[k] = true
            elseif type(val) == 'string' then
                authMap[val] = true
            end
        end

        accounts.new({
            id = v.id,
            name = v.name or (Jobs[v.id] and Jobs[v.id].label) or v.id,
            type = (Jobs[v.id] and locale("org")) or 'personal',
            frozen = (v.isFrozen == 1 or v.isFrozen == true),
            amount = v.amount or 0,
            transactions = json.decode(v.transactions) or {},
            auth = authMap,
            creator = v.creator
        }, 'default')
    end

    local query = {}
    for _, v in pairs(Jobs) do
        local acc = accounts.new({
            id = v.name,
            type = locale("org"),
            name = v.label,
            frozen = false,
            amount = 0,
            transactions = {},
            auth = {},
            creator = nil
        }, 'default')
        if acc then
            query[#query + 1] = {
                query = "INSERT INTO bank_accounts_new (id, name, amount, transactions, auth, isFrozen, creator) VALUES (?, ?, ?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE name = VALUES(name)",
                values = {
                    acc.id,
                    acc.name,
                    acc.amount,
                    json.encode(acc.transactions or {}),
                    json.encode({}),
                    acc.frozen and 1 or 0,
                    acc.creator
                }
            }
        end
    end

    if #query >= 1 then
        MySQL.transaction.await(query)
    end

    local data = MySQL.query.await('SELECT * FROM invoices WHERE status = ?', {'pending'}) or {}
    for _, v in pairs(data) do
        invoices[v.invoice_id] = v
    end
end)