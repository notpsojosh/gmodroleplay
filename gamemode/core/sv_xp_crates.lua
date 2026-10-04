--[[---------------------------------------------------------
	XP crates: pick one up (E) and choose which job class to put its
	XP into. Unlike money, picking one up doesn't immediately consume
	it - the player has to actually choose a class first, so walking
	away from the menu (or closing it) leaves the crate exactly where
	it was for later.

	The class list/current levels shown in the menu are exactly what
	the F1 "Job Levels" tab already displays (PDCity.GetAllJobClasses,
	PDCity.MY_JOB_XP synced by core/sv_job_xp.lua) - this menu doesn't
	send any extra state of its own beyond which entity and how much
	XP is on offer.
-----------------------------------------------------------]]

util.AddNetworkString("pdcity_xpcrate_open")
util.AddNetworkString("pdcity_xpcrate_choose")

-- Claiming (hiding the crate so nobody else can grab it) already
-- happened in ENT:Use before this is ever called - no need to check
-- pdcity_Claimed here too, since by definition it's already true by
-- the time we reach this point for the one legitimate call.
function PDCity.OpenXPCrateMenuFor(ply, ent)
	if not IsValid(ply) or not IsValid(ent) then return end

	net.Start("pdcity_xpcrate_open")
		net.WriteEntity(ent)
		net.WriteUInt(ent:GetAmount(), 16)
	net.Send(ply)
end

net.Receive("pdcity_xpcrate_choose", function(len, ply)
	if not IsValid(ply) then return end

	local ent = net.ReadEntity()
	local class = net.ReadString()

	if not IsValid(ent) or ent:GetClass() ~= "ent_pdcity_xpcrate" then return end

	-- pdcity_Resolved (not pdcity_Claimed) - Claimed just means "the
	-- menu was opened", which is already true for the one legitimate
	-- player by this point. Resolved specifically guards against a
	-- double-choose (e.g. a duplicate/delayed net message) actually
	-- granting XP twice. Also only the player who opened the menu may
	-- complete it - cheap extra safety against a forged choose for a
	-- crate someone never actually claimed.
	if ent.pdcity_Resolved then return end
	if ent.pdcity_ClaimedBy ~= ply then return end

	-- Real class, not just any string the client feels like sending -
	-- checked against the same authoritative list the menu was built
	-- from (core/sh_jobs.lua's PDCity.SECTIONS).
	if not table.HasValue(PDCity.GetAllJobClasses(), class) then return end

	-- Set before AddJobXP (which nets state back to the player) rather
	-- than after, so a second choose sent in the same instant can't
	-- slip through before this flag lands.
	ent.pdcity_Resolved = true

	PDCity.AddJobXP(ply, class, ent:GetAmount())
	ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] +" .. ent:GetAmount() .. " " .. class .. " XP.")
	ply:EmitSound("items/ammo_pickup.wav", 60, 110)

	ent:Remove()
end)
