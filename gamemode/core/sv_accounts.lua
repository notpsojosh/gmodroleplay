--[[---------------------------------------------------------
	Account-level data - the SteamID-wide half of what a per-steamID
	profile (core/sv_profiles.lua) used to hold in one blob, before
	multiple characters per account existed. Whatever's true of the
	ACCOUNT regardless of which character is being played right now lives
	here: Rank/Staff (informational - real perms are ULX/UCL), Keybinds
	(a UI preference), department Whitelist levels/bans (job-access
	progress that follows the PERSON, not a single character), total
	playtime, and the character roster itself (which slots exist, and the
	character-slot limit rules).

	core/sv_profiles.lua is the other half now - per-CHARACTER data
	(Money, Inventory, Currencies, JobXP, RPName), keyed by
	"<steamid64>:<slot>" instead of a bare steamid64.

	Same file/folder as before on purpose: data/pdcity/players/<steamid64>/
	account.json, alongside that account's admin logs (core/sv_logs.lua)
	and its characters/ subfolder (core/sv_profiles.lua) - PDCity.PlayerDataDir
	is unchanged so nothing about the logs system needed touching for this.

	MIGRATION: the first time an account with no account.json yet is
	loaded, the OLD single profile.json (pre-multi-character) is split:
	account-scoped fields go into account.json, everything else becomes
	character slot "A" (core/sv_profiles.lua's own MigrateLegacyCharacterA).
	profile.json is renamed to profile.json.migrated afterwards - kept,
	not deleted, in case anything needs rolling back.
-----------------------------------------------------------]]

local DEFAULT_ACCOUNT = {
	Rank = "normal",        -- paid server rank: one of PDCity.RANKS (core/sh_f4_catalogue.lua)
	Staff = "none",         -- staff title, e.g. "none", "mod", "admin", "owner"
	WhitelistLevels = {},     -- [department] = access level (number)
	WhitelistPromotedAt = {}, -- [department] = os.time() of last level change
	DepartmentBans = {},      -- [department] = { Until = os.time()+N or -1 (permanent), Reason = "...", At = os.time() }
	LastKnownName = "",       -- kept current on every join - the only way to show a NAME for an offline player in the whitelist panel
	Keybinds = {},
	PlaytimeSeconds = 0,
	Characters = {},          -- [slot] = { Name = "...", CreatedAt = os.time() }

	-- Character-limit rules (owner-editable, Site Admin's "Character
	-- Limits" tab, cl_character_admin.lua) live on the OWNER's own
	-- account-independent config, not per-account - PDCity.CHARACTER_LIMIT_CONFIG
	-- below, not a per-player field. Kept out of DEFAULT_ACCOUNT.
}

local ACCOUNTS = {} -- [steamID64] = account table, in-memory cache
local Dirty = {}     -- SteamID64s with unsaved changes

-- Every account's own folder - account.json (this file), characters/*.json
-- (core/sv_profiles.lua), and admin logs (core/sv_logs.lua) all live
-- under here. Global (not local) - used well beyond this file, same as
-- it always was back when this lived in core/sv_profiles.lua before the
-- account/character split.
function PDCity.PlayerDataDir(steamID64)
	return "pdcity/players/" .. steamID64
end

local function AccountPath(steamID64)
	return PDCity.PlayerDataDir(steamID64) .. "/account.json"
end

local function ApplyDefaults(tbl, defaults)
	for key, defaultValue in pairs(defaults) do
		if tbl[key] == nil then
			tbl[key] = istable(defaultValue) and table.Copy(defaultValue) or defaultValue
		end
	end
end

--[[---------------------------------------------------------
	Legacy migration - reads the OLD single profile.json (pre-multi-
	character) and splits it. Only ever runs once per account (guarded by
	account.json not existing yet in PDCity.LoadAccount below), and never
	deletes the source file.
-----------------------------------------------------------]]
local function MigrateLegacyProfile(steamID64)
	local legacyPath = PDCity.PlayerDataDir(steamID64) .. "/profile.json"
	local raw = file.Read(legacyPath, "DATA")
	if not raw then return nil end

	local legacy = util.JSONToTable(raw)
	if not istable(legacy) then return nil end

	local account = {
		Rank = legacy.Rank,
		Staff = legacy.Staff,
		WhitelistLevels = legacy.WhitelistLevels,
		WhitelistPromotedAt = legacy.WhitelistPromotedAt,
		DepartmentBans = legacy.DepartmentBans,
		LastKnownName = legacy.LastKnownName,
		Keybinds = legacy.Keybinds,
		-- Their one pre-existing character becomes slot A - named after
		-- whatever RP name they'd already set, since that's the closest
		-- thing to a character name that existed before this system did.
		Characters = { A = { Name = (isstring(legacy.RPName) and legacy.RPName ~= "") and legacy.RPName or "Character A", CreatedAt = os.time() } },
	}

	-- Character slot "A" itself - everything that isn't one of the
	-- account fields above. PDCity.MigrateLegacyCharacterA
	-- (core/sv_profiles.lua) writes characters/A.json directly from this
	-- same legacy table, so both halves come from one read of the one
	-- old file.
	if isfunction(PDCity.MigrateLegacyCharacterA) then
		PDCity.MigrateLegacyCharacterA(steamID64, legacy)
	end

	-- GMod's file library has no rename - copy the bytes to the ".migrated"
	-- name, then delete the original, same effect.
	file.Write(legacyPath .. ".migrated", raw)
	file.Delete(legacyPath)
	print("[" .. PDCity.BRAND_TAG .. "] Migrated legacy profile for " .. steamID64 .. " - account data + character slot A.")

	return account
end

function PDCity.LoadAccount(steamID64)
	if ACCOUNTS[steamID64] then return ACCOUNTS[steamID64] end

	local account
	local raw = file.Read(AccountPath(steamID64), "DATA")

	if raw then
		account = util.JSONToTable(raw)
		if not account then
			file.CreateDir(PDCity.PlayerDataDir(steamID64))
			local backupPath = PDCity.PlayerDataDir(steamID64) .. "/corrupt_account_" .. os.time() .. ".json"
			file.Write(backupPath, raw)
			ErrorNoHalt("[" .. PDCity.BRAND_TAG .. "] Account for " .. steamID64 .. " was unreadable - backed up to " .. backupPath .. " and reset.\n")
		end
	else
		account = MigrateLegacyProfile(steamID64)
	end

	account = account or {}
	ApplyDefaults(account, DEFAULT_ACCOUNT)

	ACCOUNTS[steamID64] = account
	return account
end

function PDCity.SaveAccount(steamID64)
	local account = ACCOUNTS[steamID64]
	if not account then return end

	file.CreateDir(PDCity.PlayerDataDir(steamID64))
	file.Write(AccountPath(steamID64), util.TableToJSON(account, true))
	Dirty[steamID64] = nil
end

function PDCity.GetAccount(ply)
	if not IsValid(ply) or ply:IsBot() then return nil end
	return PDCity.LoadAccount(ply:SteamID64())
end

function PDCity.MarkAccountDirtyByID(steamID64)
	if not isstring(steamID64) or steamID64 == "" then return end
	Dirty[steamID64] = true

	if not timer.Exists("pdcity_AccountFlush") then
		timer.Create("pdcity_AccountFlush", 2, 1, function()
			for id in pairs(Dirty) do
				PDCity.SaveAccount(id)
			end
		end)
	end
end

function PDCity.MarkAccountDirty(ply)
	if not IsValid(ply) or ply:IsBot() then return end
	PDCity.MarkAccountDirtyByID(ply:SteamID64())
end

--[[---------------------------------------------------------
	Character roster - which slots exist on this account, and the
	limit-rules engine deciding how many they're allowed.

	Slots are single letters "A".."Z", assigned in order - matches the
	STEAMID:B convention from how this was originally described,  and 26
	is far beyond any limit a server would realistically configure.
-----------------------------------------------------------]]

-- Global - core/sv_characters.lua's character-creation flow needs this too.
function PDCity.NextFreeCharacterSlot(account)
	for i = 1, 26 do
		local slot = string.char(64 + i) -- "A".."Z"
		if not account.Characters[slot] then return slot end
	end
end

-- PDCity.STAFF_SLOT / _SLOT_NAME / _SLOT_MODEL are shared (core/sh_rpname.lua)
-- so the client can recognise this same slot key without needing this
-- server-only file. A fixed, non-persisted slot rather than one of the
-- ordinary "A".."Z" letters, so it can never collide with a real
-- character and never needs its own entry in account.Characters at all.
-- Every staff-ranked player gets the same slot key, with the same forced
-- name/model every time - not player-chosen, not renameable, not
-- restyleable (enforced server-side in core/sv_characters.lua's "select"/
-- "delete" and core/sv_rpname.lua's rename path, not just hidden
-- client-side). Its actual character-scoped data (money, inventory, job
-- XP...) still lives in a normal profile keyed "<steamid64>:STAFF"
-- (core/sv_profiles.lua) - only the roster-level identity (name/model) is
-- fixed.

function PDCity.GetCharacterSlots(ply)
	local account = PDCity.GetAccount(ply)
	if not account then return {} end

	local out = {}
	for slot, data in pairs(account.Characters) do
		table.insert(out, { Slot = slot, Name = data.Name, CreatedAt = data.CreatedAt, Model = data.Model })
	end
	table.sort(out, function(a, b) return a.Slot < b.Slot end)

	if PDCity.IsStaff(ply) then
		table.insert(out, {
			Slot = PDCity.STAFF_SLOT,
			Name = PDCity.STAFF_SLOT_NAME,
			CreatedAt = 0,
			Model = PDCity.STAFF_SLOT_MODEL,
		})
	end

	return out
end

-- Networked so every client (including this one, e.g. the HUD card,
-- cl_hud_card.lua) can show the ACTIVE character's actual name without a
-- round trip - deliberately separate from PDCity_RPName (core/sv_rpname.lua),
-- which falls back to the player's Steam nick when unset. A character
-- always has a real name from the moment it's created (required at
-- creation, core/sv_characters.lua), so nothing that shows this should
-- ever need a Steam-nick fallback the way chat/the scoreboard do.
hook.Add("PDCity_CharacterSelected", "pdcity_SyncCharacterNameOnSelect", function(ply, slot)
	if slot == PDCity.STAFF_SLOT then
		ply:SetNWString("PDCity_CharacterName", PDCity.STAFF_SLOT_NAME)
		return
	end

	local account = PDCity.GetAccount(ply)
	local data = account and account.Characters[slot]
	ply:SetNWString("PDCity_CharacterName", (data and data.Name) or "")
end)

-- Player-chosen appearance for a character (F1 Character Selection's
-- "Change Model") - a roster-level field like Name/CreatedAt above, not
-- character-profile data, since it needs to be known without loading
-- that character's profile file (the flashcard list, and a job with no
-- Models of its own at spawn time - see player_class/player_sandbox.lua's
-- PLAYER:SetModel). Empty string/nil means "hasn't picked one yet".
function PDCity.GetCharacterModel(ply)
	if not IsValid(ply) or ply:IsBot() then return nil end

	local slot = ply.pdcity_ActiveCharSlot
	if not slot then return nil end

	if slot == PDCity.STAFF_SLOT then return PDCity.STAFF_SLOT_MODEL end

	local account = PDCity.GetAccount(ply)
	if not account then return nil end

	local data = account.Characters[slot]
	return data and data.Model
end

--[[---------------------------------------------------------
	Limit rules - owner-editable (Site Admin's "Character Limits" tab).
	PDCity.CHARACTER_LIMIT_CONFIG = { Base = 2, Rules = { {Type=,Match=,Bonus=}, ... } }
	Every MATCHING rule's Bonus stacks additively onto Base - not
	"highest wins". Persisted separately from any one account (it's
	server config, not player data): data/pdcity/character_limits.json.
-----------------------------------------------------------]]

local LIMITS_PATH = "pdcity/character_limits.json"

PDCity.CHARACTER_LIMIT_CONFIG = { Base = 2, Rules = {
	-- Seeded default covering "staff get an extra slot dedicated to
	-- their on-duty character" - a normal, ownereditable/removable rule
	-- like any other, not special-cased in the engine itself.
	{ Type = "staff", Match = "", Bonus = 1 },
} }

local function SaveLimitConfig()
	file.CreateDir("pdcity")
	file.Write(LIMITS_PATH, util.TableToJSON(PDCity.CHARACTER_LIMIT_CONFIG, true))
end

local function LoadLimitConfig()
	local raw = file.Read(LIMITS_PATH, "DATA")
	if not raw then return end

	local data = util.JSONToTable(raw)
	if istable(data) and isnumber(data.Base) and istable(data.Rules) then
		PDCity.CHARACTER_LIMIT_CONFIG = data
	else
		ErrorNoHalt("[" .. PDCity.BRAND_TAG .. "] " .. LIMITS_PATH .. " was unreadable - keeping the default character limit config.\n")
	end
end

LoadLimitConfig()

-- One rule TYPE = one way of asking "does this player match?". Kept as a
-- small dispatch table so a new rule type is a one-entry addition, not a
-- growing if/elseif chain.
local RULE_MATCHERS = {
	steamid = function(ply, account, match) return ply:SteamID() == match or ply:SteamID64() == match end,
	staff = function(ply, account, match) return PDCity.IsStaff(ply) end,
	job_level = function(ply, account, match)
		local threshold = tonumber(match) or 0
		return PDCity.GetTotalJobLevels and PDCity.GetTotalJobLevels(ply) >= threshold
	end,
	playtime = function(ply, account, match)
		local thresholdHours = tonumber(match) or 0
		return (account.PlaytimeSeconds or 0) >= thresholdHours * 3600
	end,
	usergroup = function(ply, account, match) return ply:GetUserGroup() == match end,
}

function PDCity.GetCharacterLimit(ply)
	local account = PDCity.GetAccount(ply)
	if not account then return PDCity.CHARACTER_LIMIT_CONFIG.Base end

	local total = PDCity.CHARACTER_LIMIT_CONFIG.Base

	for _, rule in ipairs(PDCity.CHARACTER_LIMIT_CONFIG.Rules) do
		local matcher = RULE_MATCHERS[rule.Type]
		if matcher and matcher(ply, account, rule.Match) then
			total = total + (tonumber(rule.Bonus) or 0)
		end
	end

	return math.max(1, total)
end

util.AddNetworkString("pdcity_character_limits_admin")
util.AddNetworkString("pdcity_character_limits_sync")

-- Owner-only editor (cl_character_admin.lua) needs to know the CURRENT
-- config to load into its form - broadcast on join same as every other
-- owner-editable catalogue in this gamemode.
local function BroadcastLimitConfig(ply)
	net.Start("pdcity_character_limits_sync")
		net.WriteString(util.TableToJSON(PDCity.CHARACTER_LIMIT_CONFIG))
	if IsValid(ply) then net.Send(ply) else net.Broadcast() end
end

hook.Add("PlayerInitialSpawn", "pdcity_SyncCharacterLimits", function(ply)
	BroadcastLimitConfig(ply)
end)

net.Receive("pdcity_character_limits_admin", function(len, ply)
	if not PDCity.IsOwner(ply) then return end

	local data = util.JSONToTable(net.ReadString() or "")
	if not istable(data) or not isnumber(data.Base) or not istable(data.Rules) then return end

	local cleanRules = {}
	for _, rule in ipairs(data.Rules) do
		if istable(rule) and RULE_MATCHERS[rule.Type] and isnumber(rule.Bonus) then
			table.insert(cleanRules, { Type = rule.Type, Match = isstring(rule.Match) and rule.Match or "", Bonus = math.floor(rule.Bonus) })
		end
	end

	PDCity.CHARACTER_LIMIT_CONFIG = { Base = math.max(1, math.floor(data.Base)), Rules = cleanRules }
	SaveLimitConfig()
	BroadcastLimitConfig()

	PDCity.GameLog("staff", ply:Nick() .. " (" .. ply:SteamID() .. ") updated the character slot limit rules")
end)

--[[---------------------------------------------------------
	Playtime tracking - a simple cumulative counter, ticked while
	connected. Doesn't mark dirty every tick (that'd be a save every 60s
	for every connected player); rides along with whatever else already
	dirties the account, plus the normal disconnect/shutdown/autosave
	flush below picks up the accumulated seconds regardless.
-----------------------------------------------------------]]

timer.Create("pdcity_AccountPlaytimeTick", 60, 0, function()
	for _, ply in ipairs(player.GetHumans()) do
		local account = PDCity.GetAccount(ply)
		if account then
			account.PlaytimeSeconds = (account.PlaytimeSeconds or 0) + 60
			PDCity.MarkAccountDirty(ply)
		end
	end
end)

--[[---------------------------------------------------------
	Lifecycle
-----------------------------------------------------------]]

hook.Add("PlayerInitialSpawn", "pdcity_LoadAccount", function(ply)
	if ply:IsBot() then return end
	local account = PDCity.LoadAccount(ply:SteamID64())
	ply:SetNWString("PDCity_Rank", account.Rank)

	if account.LastKnownName ~= ply:Nick() then
		account.LastKnownName = ply:Nick()
		PDCity.MarkAccountDirty(ply)
	end
end)

hook.Add("PlayerDisconnected", "pdcity_SaveAccount", function(ply)
	if ply:IsBot() then return end
	local steamID64 = ply:SteamID64()
	PDCity.SaveAccount(steamID64)
	ACCOUNTS[steamID64] = nil
end)

hook.Add("ShutDown", "pdcity_SaveAllAccounts", function()
	for steamID64 in pairs(ACCOUNTS) do
		PDCity.SaveAccount(steamID64)
	end
end)

timer.Create("pdcity_AccountAutosave", 60, 0, function()
	for _, ply in ipairs(player.GetHumans()) do
		PDCity.SaveAccount(ply:SteamID64())
	end
end)

--[[---------------------------------------------------------
	Admin: pdcity_setrank <name> <normal|supporter|goat> - moved here from
	core/sv_profiles.lua now that Rank is account-scoped, not per-character.
-----------------------------------------------------------]]

function PDCity.SetRank(ply, rank)
	local account = PDCity.GetAccount(ply)
	if not account then return false end
	if not table.HasValue(PDCity.RANKS, rank) then return false end

	account.Rank = rank
	ply:SetNWString("PDCity_Rank", rank)
	PDCity.MarkAccountDirty(ply)
	return true
end

concommand.Add("pdcity_setrank", function(ply, cmd, args)
	if IsValid(ply) and not PDCity.IsOwner(ply) then return end

	local search = args[1] and string.lower(args[1])
	local rank = args[2] and string.lower(args[2])

	if not search or not rank then
		local msg = "[" .. PDCity.BRAND_TAG .. "] Usage: pdcity_setrank <name> <" .. table.concat(PDCity.RANKS, "|") .. ">"
		if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, msg) else print(msg) end
		return
	end

	if not table.HasValue(PDCity.RANKS, rank) then
		local msg = "[" .. PDCity.BRAND_TAG .. "] Invalid rank. Choose one of: " .. table.concat(PDCity.RANKS, ", ")
		if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, msg) else print(msg) end
		return
	end

	local target
	for _, other in ipairs(player.GetHumans()) do
		if string.find(string.lower(other:Nick()), search, 1, true) then
			target = other
			break
		end
	end

	if not IsValid(target) then
		local msg = "[" .. PDCity.BRAND_TAG .. "] No matching player found."
		if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, msg) else print(msg) end
		return
	end

	PDCity.SetRank(target, rank)

	PDCity.GameLog("staff", (IsValid(ply) and (ply:Nick() .. " (" .. ply:SteamID() .. ")") or "CONSOLE")
		.. " set " .. target:Nick() .. " (" .. target:SteamID() .. ")'s rank to " .. rank)

	target:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Your rank was set to " .. rank .. ".")
	if IsValid(ply) then ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Set " .. target:Nick() .. "'s rank to " .. rank .. ".") end
end)
