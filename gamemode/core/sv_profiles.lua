--[[---------------------------------------------------------
	Per-CHARACTER profiles. core/sv_accounts.lua is the account-wide half
	(Rank, Staff, Keybinds, department Whitelist, playtime, the character
	roster itself) - this file is everything that's different per
	character: Money, Inventory, Custom Currencies, Job XP, RP name.

	One JSON file per CHARACTER: data/pdcity/players/<steamid64>/characters/<slot>.json
	(slot = "A", "B", "C"... core/sv_accounts.lua's character roster).
	Keyed everywhere below by a composite "<steamid64>:<slot>" string, not
	a bare steamid64 - PDCity.LoadProfile takes that composite key
	directly; PDCity.GetProfile(ply) builds it from whichever character
	the player has actually selected (ply.pdcity_ActiveCharSlot,
	core/sv_characters.lua) and returns nil if they haven't picked one
	yet - every existing caller already nil-guards this (money/inventory/
	currencies/job-XP just don't apply before that point, same as they
	don't for a bot).

	Files are pretty-printed so they can be read and hand-edited with any
	text editor while the server is down (edits while a player is online
	will be overwritten by the in-memory copy on next save).

	New fields: add them to DEFAULT_PROFILE below. Existing character
	files automatically pick up new defaults the next time they load -
	missing keys are filled in, unknown keys in the file are preserved.
-----------------------------------------------------------]]

local DEFAULT_PROFILE = {
	Money = 5000,
	ShopPurchases = {},     -- list of purchased item identifiers
	ShopCredits = 0,
	Inventory = {},         -- [slot] = { Class = "...", Count = n }, see core/sv_inventory.lua
	JobXP = {},             -- [section name] = total xp, see core/sv_job_xp.lua
	Currencies = {},        -- [currencyID] = amount, see core/sv_currencies.lua
	RPName = "",
	RPNameCooldownUntil = nil,
	RPNameLockedUntil = nil,
}

-- In-memory cache of loaded character profiles, keyed by "steamid64:slot".
local Profiles = {}

-- Composite keys with unsaved changes, flushed by the debounced save timer.
local Dirty = {}

local function SplitCompositeKey(key)
	local steamID64, slot = key:match("^(.+):([A-Z])$")
	return steamID64, slot
end

local function CharacterPath(compositeKey)
	local steamID64, slot = SplitCompositeKey(compositeKey)
	if not steamID64 then return nil end
	return PDCity.PlayerDataDir(steamID64) .. "/characters/" .. slot .. ".json"
end

-- Fills in any keys missing from tbl with (deep) copies of the defaults.
-- Keys the file has that we don't know about are left alone, so nothing
-- hand-added or from a newer version gets destroyed by an older server.
local function ApplyDefaults(tbl, defaults)
	for key, defaultValue in pairs(defaults) do
		if tbl[key] == nil then
			if istable(defaultValue) then
				tbl[key] = table.Copy(defaultValue)
			else
				tbl[key] = defaultValue
			end
		end
	end
end

-- Called once by core/sv_accounts.lua's own migration, from the OLD
-- (pre-multi-character) profile.json, to seed the account's first
-- character (slot A) directly - writes characters/A.json straight to
-- disk rather than going through the normal cache/dirty path, since
-- nothing has actually loaded this character yet at that point.
function PDCity.MigrateLegacyCharacterA(steamID64, legacy)
	local character = {
		Money = legacy.Money,
		ShopPurchases = legacy.ShopPurchases,
		ShopCredits = legacy.ShopCredits,
		Inventory = legacy.Inventory,
		JobXP = legacy.JobXP,
		Currencies = legacy.Currencies,
		RPName = legacy.RPName,
		RPNameCooldownUntil = legacy.RPNameCooldownUntil,
		RPNameLockedUntil = legacy.RPNameLockedUntil,
	}
	ApplyDefaults(character, DEFAULT_PROFILE)

	local dir = PDCity.PlayerDataDir(steamID64) .. "/characters"
	file.CreateDir(dir)
	file.Write(dir .. "/A.json", util.TableToJSON(character, true))
end

function PDCity.LoadProfile(compositeKey)
	if Profiles[compositeKey] then return Profiles[compositeKey] end

	local path = CharacterPath(compositeKey)
	if not path then return nil end

	local profile
	local raw = file.Read(path, "DATA")

	if raw then
		profile = util.JSONToTable(raw)
		if not profile then
			local steamID64 = SplitCompositeKey(compositeKey)
			file.CreateDir(PDCity.PlayerDataDir(steamID64))
			local backupPath = PDCity.PlayerDataDir(steamID64) .. "/corrupt_character_" .. os.time() .. ".json"
			file.Write(backupPath, raw)
			ErrorNoHalt("[" .. PDCity.BRAND_TAG .. "] Character " .. compositeKey .. " was unreadable - backed up to " .. backupPath .. " and reset.\n")
		end
	end

	profile = profile or {}
	ApplyDefaults(profile, DEFAULT_PROFILE)

	Profiles[compositeKey] = profile
	return profile
end

function PDCity.SaveProfile(compositeKey)
	local profile = Profiles[compositeKey]
	if not profile then return end

	local path = CharacterPath(compositeKey)
	if not path then return end

	local steamID64 = SplitCompositeKey(compositeKey)
	file.CreateDir(PDCity.PlayerDataDir(steamID64) .. "/characters")
	file.Write(path, util.TableToJSON(profile, true))
	Dirty[compositeKey] = nil
end

-- Character deletion (F1 Character Selection's "Delete Character",
-- core/sv_characters.lua). Copies the profile file into a
-- deleted_characters/ backup first, THEN removes the live one - a quiet
-- safety net for support/recovery (e.g. a compromised account deleting
-- characters that weren't really meant to go), never surfaced to the
-- player. Also drops the in-memory cache/dirty flag, or the periodic
-- autosave/debounced-flush timers would just write the live file back
-- into existence after this runs.
function PDCity.ArchiveAndDeleteProfile(steamID64, slot)
	local compositeKey = steamID64 .. ":" .. slot

	-- Flush any pending changes first so the backup reflects the most
	-- current state, not a stale on-disk copy from before the last
	-- debounced save.
	if Profiles[compositeKey] then
		PDCity.SaveProfile(compositeKey)
	end

	local path = CharacterPath(compositeKey)
	local raw = path and file.Read(path, "DATA")
	if raw then
		local backupDir = PDCity.PlayerDataDir(steamID64) .. "/deleted_characters"
		file.CreateDir(backupDir)
		file.Write(backupDir .. "/" .. slot .. "_" .. os.time() .. ".json", raw)
	end

	if path then file.Delete(path) end
	Profiles[compositeKey] = nil
	Dirty[compositeKey] = nil
end

-- The main accessor. Everything that reads or writes CHARACTER data
-- should go through this: local profile = PDCity.GetProfile(ply)
-- Returns nil until the player has actually selected/created a character
-- (core/sv_characters.lua) - same as it already does for a bot or an
-- invalid player, so every existing nil-guarded caller needs no changes.
function PDCity.GetProfile(ply)
	if not IsValid(ply) or ply:IsBot() then return nil end
	if not ply.pdcity_ActiveCharSlot then return nil end
	return PDCity.LoadProfile(ply:SteamID64() .. ":" .. ply.pdcity_ActiveCharSlot)
end

-- Mark a profile as changed by its composite key directly - the actual
-- primitive both dirty-markers below share.
function PDCity.MarkProfileDirtyByID(compositeKey)
	if not isstring(compositeKey) or compositeKey == "" then return end
	Dirty[compositeKey] = true

	if not timer.Exists("pdcity_ProfileFlush") then
		timer.Create("pdcity_ProfileFlush", 2, 1, function()
			for id in pairs(Dirty) do
				PDCity.SaveProfile(id)
			end
		end)
	end
end

-- Mark a player's ACTIVE character's profile as changed. Writes are
-- debounced (2s) so a burst of changes becomes one disk write.
function PDCity.MarkProfileDirty(ply)
	if not IsValid(ply) or ply:IsBot() then return end
	if not ply.pdcity_ActiveCharSlot then return end
	PDCity.MarkProfileDirtyByID(ply:SteamID64() .. ":" .. ply.pdcity_ActiveCharSlot)
end

--[[---------------------------------------------------------
	Convenience helpers for the common fields.
-----------------------------------------------------------]]

function PDCity.GetMoney(ply)
	local profile = PDCity.GetProfile(ply)
	return profile and profile.Money or 0
end

-- Positive or negative amounts. Returns false if the player can't afford
-- a deduction; money never goes below zero.
function PDCity.AddMoney(ply, amount)
	local profile = PDCity.GetProfile(ply)
	if not profile then return false end
	if amount < 0 and profile.Money + amount < 0 then return false end

	profile.Money = profile.Money + amount
	ply:SetNWInt("PDCity_Money", profile.Money)
	PDCity.MarkProfileDirty(ply)
	return true
end

function PDCity.GetCredits(ply)
	local profile = PDCity.GetProfile(ply)
	return profile and profile.ShopCredits or 0
end

function PDCity.AddCredits(ply, amount)
	local profile = PDCity.GetProfile(ply)
	if not profile then return false end
	if amount < 0 and profile.ShopCredits + amount < 0 then return false end

	profile.ShopCredits = profile.ShopCredits + amount
	PDCity.MarkProfileDirty(ply)
	return true
end

--[[---------------------------------------------------------
	Lifecycle: characters load lazily (there's no "the" character to load
	on spawn any more - core/sv_characters.lua's selection screen decides
	which one, then PDCity.GetProfile lazy-loads it same as always).
	Saving on disconnect/shutdown/autosave only makes sense for a player
	who actually selected one this session.
-----------------------------------------------------------]]

hook.Add("PlayerDisconnected", "pdcity_SaveActiveCharacter", function(ply)
	if ply:IsBot() or not ply.pdcity_ActiveCharSlot then return end
	local compositeKey = ply:SteamID64() .. ":" .. ply.pdcity_ActiveCharSlot
	PDCity.SaveProfile(compositeKey)
	Profiles[compositeKey] = nil
end)

hook.Add("ShutDown", "pdcity_SaveAllProfiles", function()
	for compositeKey in pairs(Profiles) do
		PDCity.SaveProfile(compositeKey)
	end
end)

-- Periodic autosave: writes every online player's ACTIVE character once a
-- minute, dirty or not - belt-and-braces alongside the ~2s dirty debounce.
timer.Create("pdcity_ProfileAutosave", 60, 0, function()
	for _, ply in ipairs(player.GetHumans()) do
		if ply.pdcity_ActiveCharSlot then
			PDCity.SaveProfile(ply:SteamID64() .. ":" .. ply.pdcity_ActiveCharSlot)
		end
	end
end)

--[[---------------------------------------------------------
	Admin inspection: pdcity_profile [partial player name]
	Prints your own ACTIVE character's profile with no argument, or
	another player's. Server console can pass a name too.
-----------------------------------------------------------]]

concommand.Add("pdcity_profile", function(ply, cmd, args)
	local isConsole = not IsValid(ply)
	if not isConsole and not ply:IsAdmin() then return end

	local target
	local search = args[1] and string.lower(args[1])

	if search then
		for _, other in ipairs(player.GetHumans()) do
			if string.find(string.lower(other:Nick()), search, 1, true) then
				target = other
				break
			end
		end
	elseif not isConsole then
		target = ply
	end

	local function Reply(text)
		if isConsole then print(text) else ply:PrintMessage(HUD_PRINTCONSOLE, text) end
	end

	if not IsValid(target) then
		Reply("[" .. PDCity.BRAND_TAG .. "] No matching player found.")
		return
	end

	local profile = PDCity.GetProfile(target)
	if not profile then
		Reply("[" .. PDCity.BRAND_TAG .. "] No active character selected yet.")
		return
	end

	if isConsole or target ~= ply then
		PDCity.GameLog("staff", (isConsole and "CONSOLE" or (ply:Nick() .. " (" .. ply:SteamID() .. ")"))
			.. " viewed " .. target:Nick() .. " (" .. target:SteamID() .. ")'s character " .. target.pdcity_ActiveCharSlot .. " profile")
	end

	Reply("[" .. PDCity.BRAND_TAG .. "] Character " .. target.pdcity_ActiveCharSlot .. " for " .. target:Nick() .. " (" .. target:SteamID64() .. "):")
	Reply(util.TableToJSON(profile, true))
end)
