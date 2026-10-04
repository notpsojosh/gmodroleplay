--[[---------------------------------------------------------
	Per-class XP storage and granting.

	Printer collection (core/sv_printers.lua) is the first activity
	wired up; more will call PDCity.AddXPForCurrentJob as they're
	added, same as perks are still undecided (core/sh_job_perks.lua).
	This file is the plumbing everything else attaches to: an activity
	handler somewhere just calls PDCity.AddXPForCurrentJob(ply, amount)
	and the class, level-up detection, chat message, persistence and
	client sync are all already handled here.

	Levels are never stored directly - they're always derived from the
	stored XP total via core/sh_xp.lua, so there's exactly one source
	of truth and no way for a saved level to disagree with its XP.
-----------------------------------------------------------]]

util.AddNetworkString("pdcity_jobxp_sync")

local function GetJobXPTable(ply)
	local profile = PDCity.GetProfile(ply)
	if not profile then return nil end

	if not istable(profile.JobXP) then profile.JobXP = {} end
	return profile.JobXP
end

function PDCity.GetJobClassXP(ply, class)
	local xpTable = GetJobXPTable(ply)
	if not xpTable or not isstring(class) then return 0 end
	return xpTable[class] or 0
end

-- A player's level in whatever class their CURRENT job belongs to - the
-- same "class level" gate PDCity.ApplyJob below already uses for
-- RequiredLevel rank-ups, pulled out into its own function since
-- permission checks elsewhere (e.g. core/sv_wanted.lua's warrant system)
-- need the same "is this player Police/Government level N+" check
-- without duplicating the XP-to-level lookup themselves. Server-only,
-- like everything else in this file - the client computes its own
-- level from its synced PDCity.MY_JOB_XP cache instead (cl_f4_menu.lua).
function PDCity.GetPlayerClassLevel(ply)
	if not IsValid(ply) then return 0 end

	local class = PDCity.GetJobClass(ply:Team())
	if not class then return 0 end

	return PDCity.LevelForXP(PDCity.GetJobClassXP(ply, class))
end

-- Sum of the player's level in every class they've earned XP in - the
-- inventory's level-based capacity (core/sh_inventory.lua's
-- PDCity.GetInventoryCapacity) is based on this. A class never touched
-- doesn't count - otherwise every player would start with bonus slots
-- equal to however many job categories happen to exist, growing every
-- time an admin adds a new one, rather than reflecting anything the
-- player actually did.
function PDCity.GetTotalJobLevels(ply)
	local xpTable = GetJobXPTable(ply)
	if not xpTable then return 0 end

	local total = 0
	for _, xp in pairs(xpTable) do
		total = total + PDCity.LevelForXP(xp)
	end
	return total
end

local function SyncJobXP(ply)
	local xpTable = GetJobXPTable(ply)
	if not xpTable then return end

	net.Start("pdcity_jobxp_sync")
		net.WriteString(util.TableToJSON(xpTable))
	net.Send(ply)
end

--[[---------------------------------------------------------
	Fail-safe: clamps every class in this player's stored XP back down
	to the level cap (core/sh_xp.lua's PDCity.XP_MAX_LEVEL) if any of
	them are over it, and re-syncs if anything actually changed.

	PDCity.AddJobXP below already clamps every NEW grant to the cap on
	its own (via math.min), so this should never find anything to fix
	in the normal course of play - it exists for data left over from
	BEFORE the cap was lowered (it used to be 99), and as a backstop
	against any other path that ever sets JobXP directly without going
	through that clamp. Run automatically on every join (below), and
	callable directly for an already-connected player.
-----------------------------------------------------------]]
function PDCity.ClampJobXP(ply)
	local xpTable = GetJobXPTable(ply)
	if not xpTable then return end

	local cap = PDCity.XPForLevel(PDCity.XP_MAX_LEVEL)
	local changed = false

	for class, xp in pairs(xpTable) do
		if xp > cap then
			xpTable[class] = cap
			changed = true
		end
	end

	if changed then
		PDCity.MarkProfileDirty(ply)
		SyncJobXP(ply)
	end
end

-- The general entry point: grants XP toward a specific class,
-- wherever the caller already knows which one (e.g. something that
-- always rewards Police regardless of the player's exact rank).
function PDCity.AddJobXP(ply, class, amount)

	if not PDCity.XP_ENABLED then return end -- core/sh_xp_settings.lua - owner-toggleable via F1 Site Admin
	if not IsValid(ply) or not isstring(class) or not isnumber(amount) or amount <= 0 then return end

	local xpTable = GetJobXPTable(ply)
	if not xpTable then return end

	local cap = PDCity.XPForLevel(PDCity.XP_MAX_LEVEL)

	local oldXP = math.min(xpTable[class] or 0, cap) -- fail-safe: never grant on top of an already-over-cap value
	local oldLevel = PDCity.LevelForXP(oldXP)

	local newXP = math.min(oldXP + amount, cap)
	xpTable[class] = newXP

	local newLevel = PDCity.LevelForXP(newXP)

	PDCity.MarkProfileDirty(ply)
	SyncJobXP(ply)

	if newLevel > oldLevel then
		ply:ChatPrint(("[" .. PDCity.BRAND_TAG .. "] %s level up! You are now level %d."):format(class, newLevel))

		local perk = PDCity.GetPerkForLevel(class, newLevel)
		if perk then
			ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Unlocked: " .. perk)
		end

		-- So a future perk system (or anything else) can react to a
		-- level-up without this file needing to know what perks are.
		hook.Run("PDCity_JobClassLevelUp", ply, class, newLevel, oldLevel)
	end

end

-- The entry point activities should actually call: rewards whatever
-- class the player is CURRENTLY working as, so a single "you did the
-- thing" call anywhere in the gamemode always credits the right
-- class without that code needing to know which job the player holds.
function PDCity.AddXPForCurrentJob(ply, amount)
	if not IsValid(ply) then return end

	local class = PDCity.GetJobClass(ply:Team())
	if not class then return end

	PDCity.AddJobXP(ply, class, amount)
end

-- Job XP is per-character (core/sv_profiles.lua) - waits for character
-- selection (core/sv_characters.lua), not ordinary PlayerInitialSpawn,
-- same reasoning as inventory/currency balances/RP name.
hook.Add("PDCity_CharacterSelected", "pdcity_SyncJobXPOnCharacterSelect", function(ply)
	PDCity.ClampJobXP(ply) -- fail-safe first, so a stale over-cap profile is fixed before syncing it out
	SyncJobXP(ply)
end)

--[[---------------------------------------------------------
	Testing hook, until real activities exist to grant XP.

	Owner-only console command: pdcity_grantxp <class> <amount>
	[target SteamID] - grants XP to yourself, or another connected
	player if a SteamID is given, so leveling can be tested (including
	with a bot standing in for a second player where that's useful)
	without needing any activity wired up yet.
-----------------------------------------------------------]]
concommand.Add("pdcity_grantxp", function(ply, cmd, args)

	if IsValid(ply) and not PDCity.IsOwner(ply) then
		if IsValid(ply) then ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Owner only.") end
		return
	end

	local class = args[1]
	local amount = tonumber(args[2])
	local targetID = args[3]

	if not isstring(class) or not amount or amount <= 0 then
		local msg = "Usage: pdcity_grantxp <class> <amount> [SteamID]"
		if IsValid(ply) then ply:ChatPrint(msg) else print(msg) end
		return
	end

	local target = ply
	if targetID then
		target = nil
		for _, candidate in ipairs(player.GetAll()) do
			if candidate:SteamID() == targetID then
				target = candidate
				break
			end
		end
	end

	if not IsValid(target) then
		local msg = "[" .. PDCity.BRAND_TAG .. "] Couldn't find that player."
		if IsValid(ply) then ply:ChatPrint(msg) else print(msg) end
		return
	end

	PDCity.AddJobXP(target, class, math.floor(amount))

end)
