--[[---------------------------------------------------------
	Server side of the F1 Site Admin panel's "Warrant Approvers" tab:
	persists core/sh_warrant_perms.lua's PDCity.WARRANT_PERMS to
	data/pdcity/warrant_perms.json, validates every change, and
	broadcasts the result so core/sv_wanted.lua's IsWarrantApprover
	check (and every connected admin's panel) updates live.

	Gated at PDCity.IsOwner, same as the rest of the Site Admin panel -
	re-checked here regardless of what the client's UI already hides.
-----------------------------------------------------------]]

util.AddNetworkString("pdcity_warrant_perms_sync")
util.AddNetworkString("pdcity_warrant_perms_admin")

local SAVE_PATH = "pdcity/warrant_perms.json"
local defaultsSeeded = false

local function SavePerms()
	file.CreateDir("pdcity")
	file.Write(SAVE_PATH, util.TableToJSON({
		Perms = PDCity.WARRANT_PERMS,
		DefaultsSeeded = defaultsSeeded,
	}, true))
end

local function LoadPerms()
	local raw = file.Read(SAVE_PATH, "DATA")
	local data = raw and util.JSONToTable(raw)

	if raw and not data then
		ErrorNoHalt("[" .. PDCity.BRAND_TAG .. "] " .. SAVE_PATH .. " was unreadable - keeping the built-in defaults.\n")
		return
	end

	if data then
		if istable(data.Perms) then
			PDCity.WARRANT_PERMS.Groups = istable(data.Perms.Groups) and data.Perms.Groups or {}
			PDCity.WARRANT_PERMS.Jobs = istable(data.Perms.Jobs) and data.Perms.Jobs or {}
			PDCity.WARRANT_PERMS.ClassLevels = istable(data.Perms.ClassLevels) and data.Perms.ClassLevels or {}
		end
		defaultsSeeded = data.DefaultsSeeded == true
	end

	if not defaultsSeeded then
		defaultsSeeded = true
		SavePerms()
	end
end
LoadPerms()

local function BroadcastPerms(ply)
	net.Start("pdcity_warrant_perms_sync")
		net.WriteString(util.TableToJSON(PDCity.WARRANT_PERMS))
	if IsValid(ply) then
		net.Send(ply)
	else
		net.Broadcast()
	end
end

hook.Add("PlayerInitialSpawn", "pdcity_SyncWarrantPerms", function(ply)
	timer.Simple(1, function()
		if IsValid(ply) then BroadcastPerms(ply) end
	end)
end)

--[[---------------------------------------------------------
	The actual eligibility check - core/sv_wanted.lua uses this in place
	of its old hardcoded IsGovernmentApprover local.
-----------------------------------------------------------]]
function PDCity.IsWarrantApprover(ply)
	if not IsValid(ply) or not ply:IsPlayer() then return false end
	if PDCity.IsSuperAdminPlus(ply) then return true end

	if PDCity.WARRANT_PERMS.Groups[ply:GetUserGroup()] then return true end
	if PDCity.WARRANT_PERMS.Jobs[tostring(ply:Team())] then return true end

	local class = PDCity.GetJobClass(ply:Team())
	if class then
		local required = PDCity.WARRANT_PERMS.ClassLevels[class]
		if required and PDCity.GetPlayerClassLevel(ply) >= required then return true end
	end

	return false
end

--[[---------------------------------------------------------
	Admin actions
-----------------------------------------------------------]]

net.Receive("pdcity_warrant_perms_admin", function(len, ply)
	if not IsValid(ply) or not PDCity.IsOwner(ply) then return end
	if len > 65530 then return end

	local data = util.JSONToTable(net.ReadString() or "")
	if not istable(data) or not isstring(data.Action) then return end

	if data.Action == "set_group" then
		local group = isstring(data.Group) and data.Group or ""
		if group == "" then return end

		if data.Enabled then
			PDCity.WARRANT_PERMS.Groups[group] = true
		else
			PDCity.WARRANT_PERMS.Groups[group] = nil
		end

	elseif data.Action == "set_job" then
		local jobID = tonumber(data.JobID)
		if not jobID or not PDCity.GetJob(jobID) then return end

		if data.Enabled then
			PDCity.WARRANT_PERMS.Jobs[tostring(jobID)] = true
		else
			PDCity.WARRANT_PERMS.Jobs[tostring(jobID)] = nil
		end

	elseif data.Action == "set_class_level" then
		local class = isstring(data.Class) and data.Class or ""
		if class == "" or not table.HasValue(PDCity.SECTIONS, class) then return end

		local level = tonumber(data.Level)
		if not level or level < 1 or level ~= math.floor(level) then return end

		PDCity.WARRANT_PERMS.ClassLevels[class] = level

	elseif data.Action == "remove_class_level" then
		local class = isstring(data.Class) and data.Class or ""
		PDCity.WARRANT_PERMS.ClassLevels[class] = nil

	else
		return
	end

	PDCity.GameLog("staff", ply:Nick() .. " (" .. ply:SteamID() .. ") changed the warrant-approver rules")
	SavePerms()
	BroadcastPerms()
end)
