--[[---------------------------------------------------------
	Server side of Custom Currencies (core/sh_currencies.lua): definition
	persistence, the F4 admin editor's Currencies-tab actions, and the
	per-player balance storage/API.
-----------------------------------------------------------]]

util.AddNetworkString("pdcity_currency_sync")
util.AddNetworkString("pdcity_currency_admin")
util.AddNetworkString("pdcity_currency_balance_sync")

local CURRENCIES_PATH = "pdcity/currencies.json"
local nextCurrencyID = 1

local function SaveCurrencies()
	file.CreateDir("pdcity")
	file.Write(CURRENCIES_PATH, util.TableToJSON({
		Currencies = PDCity.CURRENCIES,
		NextID = nextCurrencyID,
	}, true))
end

local function LoadCurrencies()
	local raw = file.Read(CURRENCIES_PATH, "DATA")
	if not raw then return end

	local data = util.JSONToTable(raw)
	if not data then
		ErrorNoHalt("[" .. PDCity.BRAND_TAG .. "] " .. CURRENCIES_PATH .. " was unreadable - starting with no custom currencies.\n")
		return
	end

	if istable(data.Currencies) then PDCity.CURRENCIES = data.Currencies end
	if isnumber(data.NextID) then nextCurrencyID = math.max(nextCurrencyID, data.NextID) end
end

LoadCurrencies()

local function BroadcastCurrencies(ply)
	net.Start("pdcity_currency_sync")
		net.WriteString(util.TableToJSON(PDCity.CURRENCIES))
	if IsValid(ply) then net.Send(ply) else net.Broadcast() end
end

--[[---------------------------------------------------------
	Admin actions - owner only, same shape as every other catalogue in
	this gamemode (Activities, Custom NPCs, ...).
-----------------------------------------------------------]]
local Actions = {}

local function BuildCurrencyFields(p, existingID)
	if not isstring(p.Name) or p.Name == "" then return false, "Name can't be empty." end

	local symbol = isstring(p.Symbol) and string.Trim(p.Symbol) or ""
	if symbol == "" then return false, "Symbol can't be empty." end

	for _, c in ipairs(PDCity.CURRENCIES) do
		if c.ID ~= existingID and c.Symbol == symbol then
			return false, "Another currency already uses that symbol."
		end
	end

	return {
		Name = p.Name,
		Symbol = symbol,
		Icon = isstring(p.Icon) and p.Icon or "",
	}
end

function Actions.add(ply, p)
	local fields, err = BuildCurrencyFields(p, nil)
	if not fields then return false, err end

	fields.ID = nextCurrencyID
	nextCurrencyID = nextCurrencyID + 1

	table.insert(PDCity.CURRENCIES, fields)
	return true
end

function Actions.edit(ply, p)
	local id = tonumber(p.ID)
	local currency
	for _, c in ipairs(PDCity.CURRENCIES) do
		if c.ID == id then currency = c break end
	end
	if not currency then return false, "That currency no longer exists." end

	local fields, err = BuildCurrencyFields(p, id)
	if not fields then return false, err end

	fields.ID = id
	for k in pairs(currency) do currency[k] = nil end
	for k, v in pairs(fields) do currency[k] = v end

	return true
end

function Actions.remove(ply, p)
	local id = tonumber(p.ID)
	for i, c in ipairs(PDCity.CURRENCIES) do
		if c.ID == id then
			table.remove(PDCity.CURRENCIES, i)
			return true
		end
	end
	return false, "That currency no longer exists."
end

net.Receive("pdcity_currency_admin", function(len, ply)
	if not PDCity.IsOwner(ply) then return end

	local data = util.JSONToTable(net.ReadString() or "")
	if not istable(data) or not isstring(data.Action) then return end

	local handler = Actions[data.Action]
	if not handler then return end

	local ok, err = handler(ply, data.Payload or {})

	if ok then
		SaveCurrencies()
		BroadcastCurrencies()
		hook.Run("PDCity_CurrencyCatalogueUpdated")
	else
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] " .. (err or "That action failed."))
	end
end)

hook.Add("PlayerInitialSpawn", "pdcity_SyncCurrencies", function(ply)
	BroadcastCurrencies(ply)
end)

--[[---------------------------------------------------------
	Per-player balances - stored in the player's own profile
	(core/sv_profiles.lua), same "lives with the rest of their save data,
	nothing extra to load/save" treatment core/sv_inventory.lua's own
	Inventory field already gets. Shape: profile.Currencies = { [currencyID] = amount }.
-----------------------------------------------------------]]

local function GetBalances(ply)
	local profile = PDCity.GetProfile(ply)
	if not profile then return nil end

	if not istable(profile.Currencies) then
		profile.Currencies = {}
	end

	-- JSON string keys -> numbers, same fix core/sv_inventory.lua's own
	-- GetInventory needs for the exact same reason (util.TableToJSON turns
	-- integer keys into strings on save).
	local needsFix = false
	for key in pairs(profile.Currencies) do
		if not isnumber(key) then needsFix = true break end
	end

	if needsFix then
		local fixed = {}
		for key, amount in pairs(profile.Currencies) do
			local id = tonumber(key)
			if id then fixed[id] = amount end
		end
		profile.Currencies = fixed
	end

	return profile.Currencies
end

local function SyncCurrencyBalances(ply)
	local balances = GetBalances(ply)
	if not balances then return end

	net.Start("pdcity_currency_balance_sync")
		net.WriteString(util.TableToJSON(balances))
	net.Send(ply)
end

-- Balances are per-character (core/sv_profiles.lua) - pushed once a
-- character's actually been selected (core/sv_characters.lua), not on
-- ordinary PlayerInitialSpawn, since there's nothing to sync before that.
hook.Add("PDCity_CharacterSelected", "pdcity_SyncCurrencyBalancesOnCharacterSelect", function(ply)
	SyncCurrencyBalances(ply)
end)

function PDCity.GetCurrencyBalance(ply, currencyID)
	local balances = GetBalances(ply)
	if not balances then return 0 end
	return balances[currencyID] or 0
end

-- Returns true/false (whether it actually applied) - false for a
-- currencyID that doesn't exist (typo'd from devcode/Flow) rather than
-- silently creating a balance entry for a currency nobody defined.
function PDCity.AddCurrency(ply, currencyID, amount)
	if not PDCity.GetCurrencyByID(currencyID) then return false end

	local balances = GetBalances(ply)
	if not balances then return false end

	amount = math.floor(tonumber(amount) or 0)
	if amount == 0 then return true end

	balances[currencyID] = math.max(0, (balances[currencyID] or 0) + amount)
	PDCity.MarkProfileDirty(ply)
	SyncCurrencyBalances(ply)
	return true
end

-- False (no-op) if they don't have enough - same "check the return value
-- before treating a charge as having gone through" contract as
-- PDCity.AddMoney/PDCity.InventoryRemove.
function PDCity.RemoveCurrency(ply, currencyID, amount)
	if not PDCity.GetCurrencyByID(currencyID) then return false end

	local balances = GetBalances(ply)
	if not balances then return false end

	amount = math.floor(tonumber(amount) or 0)
	local have = balances[currencyID] or 0
	if have < amount then return false end

	balances[currencyID] = have - amount
	PDCity.MarkProfileDirty(ply)
	SyncCurrencyBalances(ply)
	return true
end
