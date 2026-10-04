--[[---------------------------------------------------------
	Server side of the F1 Site Admin panel's "XP System" toggle:
	persists core/sh_xp_settings.lua's PDCity.XP_ENABLED to
	data/pdcity/xp_settings.json and broadcasts changes to all clients.

	Gated at PDCity.IsOwner, same as the rest of the Site Admin panel.
-----------------------------------------------------------]]

util.AddNetworkString("pdcity_xp_settings_sync")
util.AddNetworkString("pdcity_xp_settings_admin")

local SAVE_PATH = "pdcity/xp_settings.json"

local function SaveXPSettings()
	file.CreateDir("pdcity")
	file.Write(SAVE_PATH, util.TableToJSON({ Enabled = PDCity.XP_ENABLED }, true))
end

local function LoadXPSettings()
	local raw = file.Read(SAVE_PATH, "DATA")
	local data = raw and util.JSONToTable(raw)

	if raw and not data then
		ErrorNoHalt("[" .. PDCity.BRAND_TAG .. "] " .. SAVE_PATH .. " was unreadable - keeping the built-in default (enabled).\n")
		return
	end

	if data and data.Enabled ~= nil then
		PDCity.XP_ENABLED = data.Enabled == true
	end
end
LoadXPSettings()

local function BroadcastXPSettings(ply)
	net.Start("pdcity_xp_settings_sync")
		net.WriteBool(PDCity.XP_ENABLED)
	if IsValid(ply) then
		net.Send(ply)
	else
		net.Broadcast()
	end
end

hook.Add("PlayerInitialSpawn", "pdcity_SyncXPSettings", function(ply)
	timer.Simple(1, function()
		if IsValid(ply) then BroadcastXPSettings(ply) end
	end)
end)

net.Receive("pdcity_xp_settings_admin", function(len, ply)
	if not IsValid(ply) or not PDCity.IsOwner(ply) then return end

	PDCity.XP_ENABLED = net.ReadBool()

	PDCity.GameLog("staff", ply:Nick() .. " (" .. ply:SteamID() .. ") turned the XP system " .. (PDCity.XP_ENABLED and "ON" or "OFF"))
	SaveXPSettings()
	BroadcastXPSettings()
end)
