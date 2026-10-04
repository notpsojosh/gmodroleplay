--[[---------------------------------------------------------
	Which player models a character can choose (F1 Character Selection's
	"Change Model"/"Choose Model", cl_character_select.lua). Two layers,
	same additive-ish shape as core/sv_accounts.lua's character limit
	rules, but simpler - there's no stacking math, just set membership:

	  Models     the global default list every player can pick from
	  Whitelist  [steamID] = { model, model, ... } - EXTRA models only
	             that specific player may pick, on top of Models

	Owner-editable from Site Admin's "Character Models" tab
	(cl_character_models_admin.lua), persisted separately from any one
	account (it's server config, not player data):
	data/pdcity/character_models.json.
-----------------------------------------------------------]]

local CONFIG_PATH = "pdcity/character_models.json"

-- A real model path that actually exists on this server - the base
-- sanity check for anything model-related here, independent of whether
-- it's actually in anyone's allowed list. Global (not local) since both
-- this file and core/sv_characters.lua need it, and Lua resolves a
-- global function reference at CALL time, not load time, so it doesn't
-- matter which of these two files loads first.
function PDCity.IsValidModelPath(path)
	if not isstring(path) then return false end
	if not string.match(path, "^models/.+%.mdl$") then return false end
	if not file.Exists(path, "GAME") then return false end
	return true
end

-- Default selectable roster: the stock HL2 citizen models (female_01-12,
-- male_01-18 across the three player model groups). Computed from
-- player_manager.AllValidModels() - the same registry the admin's own
-- model picker (cl_character_models_admin.lua's OpenAdminModelPicker)
-- browses, populated by lua/autorun/citizen_addvalidmodel.lua on both
-- realms - rather than a hand-typed list of exact file paths, which
-- previously went stale/wrong (paths that don't actually exist show up
-- as GMod's generic error/checkerboard model, every one of them
-- rendering IDENTICALLY - easy to mistake for the same model "appearing
-- twice"). Every path here is guaranteed real since it comes straight
-- from GMod's own valid-model registry.
local function ComputeDefaultModels()
	local out = {}
	for _, path in pairs(player_manager.AllValidModels()) do
		if isstring(path) and string.match(string.lower(path), "^models/player/group%d+/") and PDCity.IsValidModelPath(path) then
			table.insert(out, path)
		end
	end
	table.sort(out)
	return out
end

-- Everything else (Kleiner, Alyx, riot/rebel skins, any addon
-- playermodel) has to be explicitly whitelisted to specific SteamIDs, or
-- added to this list from Site Admin.
local DEFAULT_MODELS = ComputeDefaultModels()

-- WhitelistNames: [steamID] = the player's name, recorded when they're
-- whitelisted or join - display only (Site Admin's whitelist list); every
-- permission check uses the SteamID alone.
PDCity.CHARACTER_MODEL_CONFIG = { Models = table.Copy(DEFAULT_MODELS), Whitelist = {}, WhitelistNames = {} }

-- Drops anything that isn't ACTUALLY a real model on this server -
-- shared by loading a saved config (self-heals a file that has stale/
-- bad entries from before this validation existed) and the owner's own
-- admin save action below.
local function SanitizeConfig(data)
	local cleanModels = {}
	for _, m in ipairs(data.Models or {}) do
		if PDCity.IsValidModelPath(m) and not table.HasValue(cleanModels, m) then
			table.insert(cleanModels, m)
		end
	end

	local cleanWhitelist = {}
	for steamID, models in pairs(data.Whitelist or {}) do
		if isstring(steamID) and steamID ~= "" and istable(models) then
			local list = {}
			for _, m in ipairs(models) do
				if PDCity.IsValidModelPath(m) and not table.HasValue(list, m) then
					table.insert(list, m)
				end
			end
			if #list > 0 then cleanWhitelist[steamID] = list end
		end
	end

	local cleanNames = {}
	for steamID in pairs(cleanWhitelist) do
		local name = istable(data.WhitelistNames) and data.WhitelistNames[steamID]
		if isstring(name) and name ~= "" then cleanNames[steamID] = name end
	end

	return { Models = cleanModels, Whitelist = cleanWhitelist, WhitelistNames = cleanNames }
end

local function SaveConfig()
	file.CreateDir("pdcity")
	file.Write(CONFIG_PATH, util.TableToJSON(PDCity.CHARACTER_MODEL_CONFIG, true))
end

local function LoadConfig()
	local raw = file.Read(CONFIG_PATH, "DATA")
	if not raw then return end

	local data = util.JSONToTable(raw)
	if istable(data) and istable(data.Models) and istable(data.Whitelist) then
		local sanitized = SanitizeConfig(data)

		-- If sanitizing wiped the default list out entirely (e.g. a file
		-- saved before this validation existed, full of paths that never
		-- actually existed), fall back to the freshly computed defaults
		-- rather than leaving everyone with nothing to choose from.
		if #sanitized.Models == 0 then
			sanitized.Models = table.Copy(DEFAULT_MODELS)
		end

		PDCity.CHARACTER_MODEL_CONFIG = sanitized
		SaveConfig() -- persist the cleaned-up version, not just in memory
	else
		ErrorNoHalt("[" .. PDCity.BRAND_TAG .. "] " .. CONFIG_PATH .. " was unreadable - keeping the default character model list.\n")
	end
end

LoadConfig()

-- Every model this specific player is allowed to choose right now: the
-- global default list plus whatever's been whitelisted to their SteamID.
function PDCity.GetAllowedCharacterModels(ply)
	if not IsValid(ply) or not ply:IsPlayer() then return table.Copy(PDCity.CHARACTER_MODEL_CONFIG.Models) end

	local out = table.Copy(PDCity.CHARACTER_MODEL_CONFIG.Models)
	local extra = PDCity.CHARACTER_MODEL_CONFIG.Whitelist[ply:SteamID()]
	if istable(extra) then
		for _, model in ipairs(extra) do
			if not table.HasValue(out, model) then table.insert(out, model) end
		end
	end

	return out
end

function PDCity.IsCharacterModelAllowed(ply, model)
	return table.HasValue(PDCity.GetAllowedCharacterModels(ply), model)
end

util.AddNetworkString("pdcity_character_models_admin")
util.AddNetworkString("pdcity_character_models_sync")

-- Broadcast on join same as every other owner-editable catalogue in this
-- gamemode (core/sv_accounts.lua's character limits, core/sv_job_catalogue.lua)
-- - every client gets the full config, not just the owner; only Site
-- Admin's UI for it is owner-gated, same trust level the character
-- limit rules' own SteamID-keyed entries already get.
local function BroadcastConfig(ply)
	net.Start("pdcity_character_models_sync")
		net.WriteString(util.TableToJSON(PDCity.CHARACTER_MODEL_CONFIG))
	if IsValid(ply) then net.Send(ply) else net.Broadcast() end
end

hook.Add("PlayerInitialSpawn", "pdcity_SyncCharacterModels", function(ply)
	-- Keeps a whitelisted player's recorded name current.
	local steamID = ply:SteamID()
	if PDCity.CHARACTER_MODEL_CONFIG.Whitelist[steamID] and PDCity.CHARACTER_MODEL_CONFIG.WhitelistNames[steamID] ~= ply:Nick() then
		PDCity.CHARACTER_MODEL_CONFIG.WhitelistNames[steamID] = ply:Nick()
		SaveConfig()
		BroadcastConfig()
		return
	end

	BroadcastConfig(ply)
end)

-- The default model list only - the whitelist has its own actions below,
-- so saving this from a stale form can never overwrite whitelist changes.
net.Receive("pdcity_character_models_admin", function(len, ply)
	if not PDCity.IsOwner(ply) then return end

	local data = util.JSONToTable(net.ReadString() or "")
	if not istable(data) or not istable(data.Models) then return end

	PDCity.CHARACTER_MODEL_CONFIG.Models = SanitizeConfig({ Models = data.Models }).Models
	SaveConfig()
	BroadcastConfig()

	PDCity.GameLog("staff", ply:Nick() .. " (" .. ply:SteamID() .. ") updated the default character model list")
end)

--[[---------------------------------------------------------
	Per-player whitelist actions - each applied and saved immediately.
	A SteamID can be typed as STEAM_0:X:XXXX or a 17-digit SteamID64.
-----------------------------------------------------------]]
util.AddNetworkString("pdcity_character_whitelist_admin")

local function NormalizeSteamID(raw)
	if not isstring(raw) then return nil end
	raw = string.upper(string.Trim(raw))

	if string.match(raw, "^%d+$") and #raw == 17 then
		raw = util.SteamIDFrom64(raw)
	end

	if string.match(raw, "^STEAM_[01]:[01]:%d+$") then
		return "STEAM_0" .. string.sub(raw, 8) -- STEAM_1 is the same account; ply:SteamID() always reports STEAM_0
	end
end

local WhitelistActions = {}

-- Merges into the player's existing entry if they already have one.
function WhitelistActions.add(ply, data)
	local steamID = NormalizeSteamID(data.SteamID)
	if not steamID then return false, "Enter a valid SteamID (STEAM_0:X:XXXXXXXX or a SteamID64)." end
	if not istable(data.Models) or #data.Models == 0 then return false, "Pick at least one model from the grid first." end

	local whitelist = PDCity.CHARACTER_MODEL_CONFIG.Whitelist
	local list = whitelist[steamID] or {}
	local added = 0

	for _, model in ipairs(data.Models) do
		if PDCity.IsValidModelPath(model) and not table.HasValue(list, model) then
			table.insert(list, model)
			added = added + 1
		end
	end

	if #list == 0 then return false, "None of those models exist on this server." end
	whitelist[steamID] = list

	local target = player.GetBySteamID(steamID)
	if IsValid(target) then
		PDCity.CHARACTER_MODEL_CONFIG.WhitelistNames[steamID] = target:Nick()
	end

	return true, "whitelisted " .. added .. " model(s) for " .. steamID
end

function WhitelistActions.remove_model(ply, data)
	local steamID = NormalizeSteamID(data.SteamID)
	local list = steamID and PDCity.CHARACTER_MODEL_CONFIG.Whitelist[steamID]
	if not list then return false, "That player isn't on the whitelist." end

	table.RemoveByValue(list, data.Model)

	-- An entry with no models left isn't an entry at all.
	if #list == 0 then
		PDCity.CHARACTER_MODEL_CONFIG.Whitelist[steamID] = nil
		PDCity.CHARACTER_MODEL_CONFIG.WhitelistNames[steamID] = nil
	end

	return true, "removed " .. tostring(data.Model) .. " from " .. steamID .. "'s whitelist"
end

function WhitelistActions.remove_entry(ply, data)
	local steamID = NormalizeSteamID(data.SteamID)
	if not steamID or not PDCity.CHARACTER_MODEL_CONFIG.Whitelist[steamID] then return false, "That player isn't on the whitelist." end

	PDCity.CHARACTER_MODEL_CONFIG.Whitelist[steamID] = nil
	PDCity.CHARACTER_MODEL_CONFIG.WhitelistNames[steamID] = nil

	return true, "removed " .. steamID .. " from the model whitelist"
end

net.Receive("pdcity_character_whitelist_admin", function(len, ply)
	if not PDCity.IsOwner(ply) then return end

	local data = util.JSONToTable(net.ReadString() or "")
	if not istable(data) or not isstring(data.Action) then return end

	local handler = WhitelistActions[data.Action]
	if not handler then return end

	local ok, result = handler(ply, data)
	if not ok then
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] " .. result)
		return
	end

	SaveConfig()
	BroadcastConfig()

	ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Whitelist updated.")
	PDCity.GameLog("staff", ply:Nick() .. " (" .. ply:SteamID() .. ") " .. result)
end)
