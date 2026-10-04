--[[---------------------------------------------------------
	Owner-editable HUD card settings (cl_hud_card.lua's colours, size,
	icons, and which custom currencies show) - a single global config, not
	per-player. Edited in-game via the HUD Editor (cl_hud_editor.lua,
	opened from Site Admin), persisted here, broadcast to every client the
	same way Activities/Custom NPCs are so everyone's card matches
	whatever the owner picked.

	Deliberately ONE "set" action replacing the whole settings table,
	rather than per-field admin actions like Activities/Currencies use -
	this is a single global blob edited from one form, not a list of many
	independent records to add/edit/remove.
-----------------------------------------------------------]]

util.AddNetworkString("pdcity_hud_settings_sync")
util.AddNetworkString("pdcity_hud_settings_admin")

local SETTINGS_PATH = "pdcity/hud_settings.json"

-- Defaults live in core/sh_hud_settings.lua. Every field is optional on
-- the wire - an old/partial saved file just keeps the defaults for
-- whatever it's missing.
local DefaultSettings = PDCity.DefaultHUDSettings

PDCity.HUD_SETTINGS = DefaultSettings()

local function SaveSettings()
	file.CreateDir("pdcity")
	file.Write(SETTINGS_PATH, util.TableToJSON(PDCity.HUD_SETTINGS, true))
end

local function LoadSettings()
	local raw = file.Read(SETTINGS_PATH, "DATA")
	if not raw then return end

	local data = util.JSONToTable(raw)
	if not istable(data) then
		ErrorNoHalt("[" .. PDCity.BRAND_TAG .. "] " .. SETTINGS_PATH .. " was unreadable - keeping the default HUD settings.\n")
		return
	end

	local defaults = DefaultSettings()
	for k, v in pairs(data) do defaults[k] = v end
	PDCity.HUD_SETTINGS = defaults
end

LoadSettings()

local function BroadcastSettings(ply)
	net.Start("pdcity_hud_settings_sync")
		net.WriteString(util.TableToJSON(PDCity.HUD_SETTINGS))
	if IsValid(ply) then net.Send(ply) else net.Broadcast() end
end

hook.Add("PlayerInitialSpawn", "pdcity_SyncHUDSettings", function(ply)
	BroadcastSettings(ply)
end)

local function IsValidColor(c)
	return istable(c) and isnumber(c.r) and isnumber(c.g) and isnumber(c.b)
end

net.Receive("pdcity_hud_settings_admin", function(len, ply)
	if not PDCity.IsOwner(ply) then return end

	local data = util.JSONToTable(net.ReadString() or "")
	if not istable(data) then return end

	local newSettings = DefaultSettings()

	newSettings.Scale = math.Clamp(tonumber(data.Scale) or 1.0, 0.6, 1.8)
	newSettings.Width = math.Clamp(math.Round(tonumber(data.Width) or 100), PDCity.HUD_WIDTH_MIN, PDCity.HUD_WIDTH_MAX)
	newSettings.Height = math.Clamp(math.Round(tonumber(data.Height) or 100), PDCity.HUD_HEIGHT_MIN, PDCity.HUD_HEIGHT_MAX)

	for _, key in ipairs({ "HealthLow", "HealthHigh", "ArmorLow", "ArmorHigh" }) do
		if IsValidColor(data[key]) then
			newSettings[key] = { r = math.Clamp(data[key].r, 0, 255), g = math.Clamp(data[key].g, 0, 255), b = math.Clamp(data[key].b, 0, 255) }
		end
	end

	newSettings.HealthIcon = isstring(data.HealthIcon) and data.HealthIcon or ""
	newSettings.ArmorIcon = isstring(data.ArmorIcon) and data.ArmorIcon or ""

	newSettings.DisplayedCurrencies = {}
	if istable(data.DisplayedCurrencies) then
		for _, id in ipairs(data.DisplayedCurrencies) do
			if isnumber(id) and PDCity.GetCurrencyByID(id) then
				table.insert(newSettings.DisplayedCurrencies, id)
			end
		end
	end

	newSettings.CardOpacity = math.Clamp(math.Round(tonumber(data.CardOpacity) or 100), 0, 100)
	newSettings.ChipOpacity = math.Clamp(math.Round(tonumber(data.ChipOpacity) or 100), 0, 100)

	if isstring(data.Font) and table.HasValue(PDCity.FONT_CHOICES, data.Font) then
		newSettings.Font = data.Font
	end

	if isstring(data.Title) then
		newSettings.Title = string.sub(string.Trim(data.Title), 1, PDCity.HUD_TITLE_MAX_LENGTH)
	end

	for _, element in ipairs(PDCity.HUD_TEXT_ELEMENTS) do
		newSettings.TextSizes[element.Key] = PDCity.GetHUDTextSize(data, element)
	end

	PDCity.HUD_SETTINGS = newSettings
	SaveSettings()
	BroadcastSettings()

	PDCity.GameLog("staff", ply:Nick() .. " (" .. ply:SteamID() .. ") updated the HUD card settings")
end)
