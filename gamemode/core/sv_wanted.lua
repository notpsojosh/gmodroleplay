--[[---------------------------------------------------------
	Wanted status: a NWBool ("PDCity_Wanted") + NWString reason
	("PDCity_WantedReason") that lasts 10 minutes. The wanted player is
	told by a notification; nothing else in the gamemode draws it yet.

	PDCity.SetWanted is the one entry point everything goes through.
	Right now the only caller is an approved warrant (below), but it's
	deliberately generic so any future "this action makes you wanted
	automatically" activity can just call it directly.

	Warrant requests: anyone carrying the Warrant Request tool submits a
	target + reason via weapon_pdcity_warrantrequest / cl_warrant_request.lua.
	Who carries it is the owner's choice (job weapon loadouts).
	That goes into a pending queue, NOT straight to wanted - only someone
	PDCity.IsWarrantApprover (core/sv_warrant_perms.lua) allows can
	approve it (or deny it), via cl_warrant_approval.lua. Who that is is
	fully configurable (usergroups, specific jobs, or class+level rules)
	via the F1 Site Admin panel's "Warrant Approvers" tab - it used to be
	hardcoded to "Government, class level 5+" here.
-----------------------------------------------------------]]

local WANTED_DURATION = 600 -- 10 minutes

util.AddNetworkString("pdcity_warrant_submit")
util.AddNetworkString("pdcity_warrant_list_request")
util.AddNetworkString("pdcity_warrant_pending_sync")
util.AddNetworkString("pdcity_warrant_decide")

--[[---------------------------------------------------------
	Wanted status
-----------------------------------------------------------]]

function PDCity.SetWanted(ply, reason, sourceName)
	if not IsValid(ply) then return end

	reason = isstring(reason) and reason or ""

	ply:SetNWBool("PDCity_Wanted", true)
	ply:SetNWString("PDCity_WantedReason", reason)

	local timerName = "pdcity_wanted_" .. ply:SteamID64()
	timer.Create(timerName, WANTED_DURATION, 1, function()
		if not IsValid(ply) then return end
		ply:SetNWBool("PDCity_Wanted", false)
		ply:SetNWString("PDCity_WantedReason", "")
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Your wanted status has expired.")
	end)

	ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] You are now WANTED: " .. reason)
	PDCity.GameLog("wanted", ply:Nick() .. " (" .. ply:SteamID() .. ") marked WANTED by " ..
		(sourceName or "unknown") .. " - reason: " .. reason)
end

function PDCity.ClearWanted(ply)
	if not IsValid(ply) then return end

	timer.Remove("pdcity_wanted_" .. ply:SteamID64())
	ply:SetNWBool("PDCity_Wanted", false)
	ply:SetNWString("PDCity_WantedReason", "")
end

hook.Add("PlayerDisconnected", "pdcity_wanted_timer_cleanup", function(ply)
	timer.Remove("pdcity_wanted_" .. ply:SteamID64())
end)

--[[---------------------------------------------------------
	Permissions
-----------------------------------------------------------]]

-- Holding the Warrant Request tool is the permission: the owner decides
-- which jobs get it through their weapon loadouts.
local function CanRequestWarrant(ply)
	return ply:HasWeapon("weapon_pdcity_warrantrequest")
end

-- core/sv_warrant_perms.lua's PDCity.IsWarrantApprover - kept as a local
-- alias here since it's what this file used to define itself, and every
-- call site below already refers to it by this name.
local function IsApprover(ply)
	return PDCity.IsWarrantApprover(ply)
end

--[[---------------------------------------------------------
	Pending warrant requests
-----------------------------------------------------------]]

local PendingWarrants = {}
local NextWarrantID = 1

local function BuildPendingPayload()
	local list = {}

	for id, req in pairs(PendingWarrants) do
		if IsValid(req.Requester) and IsValid(req.Target) then
			table.insert(list, {
				ID = id,
				Requester = PDCity.GetDisplayName(req.Requester),
				Target = PDCity.GetDisplayName(req.Target),
				Reason = req.Reason,
				Time = req.Time,
			})
		end
	end

	table.sort(list, function(a, b) return a.Time < b.Time end)
	return list
end

local function SyncPendingToApprovers()
	local payload = util.TableToJSON(BuildPendingPayload())

	for _, gov in ipairs(player.GetAll()) do
		if IsApprover(gov) then
			net.Start("pdcity_warrant_pending_sync")
				net.WriteString(payload)
			net.Send(gov)
		end
	end
end

-- Shared by the keybind (core/sv_keybinds.lua) and the client's own
-- pdcity_warrants concommand (cl_warrant_approval.lua) - a non-eligible
-- player just gets the same chat denial either way.
function PDCity.SendWarrantList(ply)
	if not IsValid(ply) then return end

	if not IsApprover(ply) then
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] You're not allowed to review warrant requests.")
		return
	end

	net.Start("pdcity_warrant_pending_sync")
		net.WriteString(util.TableToJSON(BuildPendingPayload()))
	net.Send(ply)
end

net.Receive("pdcity_warrant_list_request", function(len, ply)
	PDCity.SendWarrantList(ply)
end)

net.Receive("pdcity_warrant_submit", function(len, ply)
	if not IsValid(ply) then return end

	if not CanRequestWarrant(ply) then
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] You need the Warrant Request tool to request a warrant.")
		return
	end

	local target = net.ReadEntity()
	local reason = string.Trim(net.ReadString() or "")

	if not IsValid(target) or not target:IsPlayer() then
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Invalid target.")
		return
	end

	if target == ply then
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] You can't request a warrant on yourself.")
		return
	end

	if reason == "" then
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] You need to give a reason.")
		return
	end

	if #reason > 200 then reason = string.sub(reason, 1, 200) end

	for _, req in pairs(PendingWarrants) do
		if req.Requester == ply and req.Target == target then
			ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] You already have a pending warrant request on " .. PDCity.GetDisplayName(target) .. ".")
			return
		end
	end

	local id = NextWarrantID
	NextWarrantID = NextWarrantID + 1

	PendingWarrants[id] = {
		Requester = ply,
		Target = target,
		Reason = reason,
		Time = os.time(),
	}

	ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Warrant request submitted for " .. PDCity.GetDisplayName(target) .. ".")
	PDCity.GameLog("warrants", ply:Nick() .. " (" .. ply:SteamID() .. ") requested a warrant on " ..
		target:Nick() .. " (" .. target:SteamID() .. ") - reason: " .. reason)

	for _, gov in ipairs(player.GetAll()) do
		if IsApprover(gov) then
			gov:ChatPrint("[" .. PDCity.BRAND_TAG .. "] New warrant request from " .. PDCity.GetDisplayName(ply) .. " on " .. PDCity.GetDisplayName(target) ..
				" - press your warrant requests key to review.")
		end
	end

	SyncPendingToApprovers()
end)

net.Receive("pdcity_warrant_decide", function(len, ply)
	if not IsValid(ply) or not IsApprover(ply) then return end

	local id = net.ReadUInt(32)
	local approve = net.ReadBool()

	local req = PendingWarrants[id]
	if not req then return end

	PendingWarrants[id] = nil

	local requester = req.Requester
	local target = req.Target

	if approve then
		if IsValid(target) then
			PDCity.SetWanted(target, req.Reason, ply:Nick())
			if IsValid(requester) then
				requester:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Your warrant request on " .. PDCity.GetDisplayName(target) .. " was approved by " .. PDCity.GetDisplayName(ply) .. ".")
			end
		end
	else
		PDCity.GameLog("wanted", ply:Nick() .. " (" .. ply:SteamID() .. ") DENIED a warrant"
			.. (IsValid(target) and (" on " .. target:Nick() .. " (" .. target:SteamID() .. ")") or "")
			.. " requested by " .. (IsValid(requester) and requester:Nick() or "unknown")
			.. " - reason: " .. tostring(req.Reason))

		if IsValid(requester) then
			requester:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Your warrant request" .. (IsValid(target) and (" on " .. PDCity.GetDisplayName(target)) or "") ..
				" was denied by " .. PDCity.GetDisplayName(ply) .. ".")
		end
	end

	SyncPendingToApprovers()
end)

-- A requester or target disconnecting mid-review invalidates that
-- request outright rather than leaving a stale entry an approver could
-- still act on.
hook.Add("PlayerDisconnected", "pdcity_warrant_cleanup", function(ply)
	local changed = false

	for id, req in pairs(PendingWarrants) do
		if req.Requester == ply or req.Target == ply then
			PendingWarrants[id] = nil
			changed = true
		end
	end

	if changed then SyncPendingToApprovers() end
end)
