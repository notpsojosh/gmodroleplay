--[[---------------------------------------------------------
	The "developer" list - owner-editable in-game (F1 Site Admin's
	"Developers" tab, cl_site_admin.lua), separate from
	PDCity.OWNER_STEAMIDS (core/sh_permissions.lua's hardcoded, hand-
	edited-in-the-file owner list). Lets the owner grant ONE specific,
	narrow power to someone with no file/console access at all: writing
	the Lua code behind a Job Activity's trigger
	(core/sv_activities.lua's "set_code"/"get_code" actions) - nothing
	else. A developer is NOT staff, NOT admin, and this list is checked
	nowhere else in the gamemode.

	Persisted to data/pdcity/developers.json, entirely server-side - the
	list itself is never networked to plain clients, only ever read/
	edited through the F1 Site Admin panel's own owner-only net messages.
-----------------------------------------------------------]]

local DEVELOPERS_PATH = "pdcity/developers.json"

-- [SteamID] = "display name recorded when added" - cosmetic only, shown
-- in the F1 Site Admin list; every permission check below uses the
-- SteamID key alone, never the name.
local Developers = {}

local function SaveDevelopers()
	file.CreateDir("pdcity")
	file.Write(DEVELOPERS_PATH, util.TableToJSON(Developers, true))
end

do
	local raw = file.Read(DEVELOPERS_PATH, "DATA")
	local stored = raw and util.JSONToTable(raw)
	if istable(stored) then Developers = stored end
end

-- Owner counts as a developer too (a strictly wider permission already
-- implies this narrower one) - callers never need to check both.
function PDCity.IsDeveloper(ply)
	if not IsValid(ply) or not ply:IsPlayer() then return false end
	if PDCity.IsOwner(ply) then return true end
	return Developers[ply:SteamID()] ~= nil
end

-- Networked so the client knows whether to show the F1 "Developer
-- Console" tile. UI only - every developer action is still checked
-- server-side with PDCity.IsDeveloper.
local function SyncDeveloperFlag(ply)
	if IsValid(ply) then ply:SetNWBool("PDCity_IsDeveloper", PDCity.IsDeveloper(ply)) end
end

hook.Add("PlayerInitialSpawn", "pdcity_SyncDeveloperFlag", SyncDeveloperFlag)

function PDCity.GetDeveloperList()
	local out = {}
	for steamID, name in pairs(Developers) do
		table.insert(out, { SteamID = steamID, Name = name })
	end
	table.sort(out, function(a, b) return a.Name < b.Name end)
	return out
end

util.AddNetworkString("pdcity_developers_admin")
util.AddNetworkString("pdcity_developers_list")

local function SendDeveloperList(ply)
	net.Start("pdcity_developers_list")
		net.WriteString(util.TableToJSON(PDCity.GetDeveloperList()))
	net.Send(ply)
end

-- Every action here is owner-only - unlike the narrow code-writing power
-- this list GRANTS, deciding WHO holds it is not itself delegable.
net.Receive("pdcity_developers_admin", function(len, ply)
	if not PDCity.IsOwner(ply) then return end

	local action = net.ReadString()

	if action == "list" then
		SendDeveloperList(ply)
		return
	end

	if action == "add" then
		local steamID = string.upper(string.Trim(net.ReadString() or ""))
		if not steamID:match("^STEAM_0:%d:%d+$") then
			ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Not a valid SteamID (expected STEAM_0:X:XXXXXXXX format).")
			return
		end

		local target = PDCity.FindPlayerByIdentifier(steamID)
		local name = IsValid(target) and PDCity.GetDisplayName(target) or steamID

		Developers[steamID] = name
		SaveDevelopers()
		SyncDeveloperFlag(target)
		PDCity.GameLog("staff", ply:Nick() .. " (" .. ply:SteamID() .. ") added " .. steamID .. " (" .. name .. ") as a developer")
		SendDeveloperList(ply)

	elseif action == "remove" then
		local steamID = net.ReadString()
		if Developers[steamID] then
			Developers[steamID] = nil
			SaveDevelopers()
			SyncDeveloperFlag(player.GetBySteamID(steamID))
			PDCity.GameLog("staff", ply:Nick() .. " (" .. ply:SteamID() .. ") removed " .. steamID .. " as a developer")
		end
		SendDeveloperList(ply)
	end
end)
