--[[---------------------------------------------------------
	Money printer economy: unlocking, upgrades, collecting, and the
	per-player printer cap. The entity itself (entities/entities/
	ent_pdcity_printer.lua) only handles the physical shell, damage, and
	Use() -> PDCity.OpenPrinterMenuFor; all money/level state lives on the
	entity but every change is validated and applied here.

	Nothing here persists - printers are session-only (see the
	PlayerDisconnected cleanup below), matching the "if a player
	disconnects, its gone" requirement.
-----------------------------------------------------------]]

--[[---------------------------------------------------------
	Per-type tuning. "standard" is the only type - the original Money
	Printer (ent_pdcity_printer.lua) (see CanBuyPrinter
	in core/sh_f4_entities.lua).

	Looked up per-entity via ENT:GetPrinterProfile() (see
	ent_pdcity_printer.lua), keyed by self.pdcity_PrinterType.
-----------------------------------------------------------]]
PDCity.PRINTER_TYPES = {

	standard = {
		UnlockCost = 1000,
		BaseInterval = 300, -- 5 minutes
		BaseAmount = 500,
		SpeedStep = 30, -- seconds shaved off per speed level
		AmountStep = 750, -- dollars added per amount level
		MaxLevel = 5,
		UpgradeCosts = { 1000, 2500, 5000, 7500, 10000 }, -- cost of levels 1-5 (index = target level)
	},

}

-- Every class the rest of this file (and the lockpick) should treat
-- as "a printer" - one place to extend if a second type is ever added,
-- rather than hunting down every GetClass() == "ent_pdcity_printer"
-- comparison across this file, the entity files, and the lockpick.
PDCity.PRINTER_CLASSES = {
	ent_pdcity_printer = true,
}


-- $500 collected = 1 XP, scaled for any collection amount (a
-- non-round collect, e.g. from an upgraded print amount, still earns
-- proportionally rather than only counting whole $500 chunks).
PDCity.PRINTER_XP_PER_DOLLAR = 1 / 500

-- How long a successfully picked printer stays accessible to the
-- thief before the lock is treated as re-secured - forces them to
-- actually grab the cash promptly rather than picking it once and
-- having a standing invite back at their leisure.
PDCity.PRINTER_STEAL_WINDOW = 30

--[[---------------------------------------------------------
	Ownership cap: one each, never purchasable (the old paid "Additional
	Printers" upgrade is gone). Which jobs can buy a printer at all is
	the owner's choice, via the Catalogue's job role restrictions.
-----------------------------------------------------------]]

function PDCity.GetMaxPrinters(ply, class)
	return 1
end

-- True if ply's current job is allowed to buy a money printer from the
-- F4 shop (the Catalogue's job role restrictions on that entry).
local function CanJobRunPrinters(ply)
	for _, cfg in ipairs(PDCity.GetAllF4Entities()) do
		if cfg.Class == "ent_pdcity_printer" then
			return PDCity.HasF4JobAccess(ply, cfg)
		end
	end
	return false
end

-- Prunes any removed printers from the player's list (they don't persist,
-- and can be destroyed) and returns the live list. Shared by the cap
-- check and the tracker so a player who lost a printer can spawn another.
function PDCity.CleanPrinterList(ply)
	ply.pdcity_Printers = ply.pdcity_Printers or {}
	for i = #ply.pdcity_Printers, 1, -1 do
		if not IsValid(ply.pdcity_Printers[i]) then
			table.remove(ply.pdcity_Printers, i)
		end
	end
	return ply.pdcity_Printers
end

-- How many of one specific printer type the player currently owns.
function PDCity.CountPrinters(ply, class)
	local count = 0
	for _, ent in ipairs(PDCity.CleanPrinterList(ply)) do
		if ent:GetClass() == class then count = count + 1 end
	end
	return count
end

function PDCity.CanSpawnPrinter(ply, class)
	class = class or "ent_pdcity_printer"
	return PDCity.CountPrinters(ply, class) < PDCity.GetMaxPrinters(ply, class)
end

-- Records ownership + adds to the player's printer list. Called by BOTH
-- spawn paths (the Q-menu ENT:SpawnFunction and the F4 purchase Setup),
-- so the owner-only Use(), the cap, and the disconnect cleanup all work
-- no matter how the printer was acquired.
function PDCity.TrackPrinter(ent, ply)
	ent.pdcity_Owner = ply
	local list = PDCity.CleanPrinterList(ply)
	if not table.HasValue(list, ent) then
		table.insert(list, ent)
	end
end

util.AddNetworkString("PDCity_OpenPrinterMenu")
util.AddNetworkString("PDCity_PrinterUnlock")
util.AddNetworkString("PDCity_PrinterUpgrade")
util.AddNetworkString("PDCity_PrinterCollect")

local function IsValidPrinter(ent, ply)
	return IsValid(ent) and PDCity.PRINTER_CLASSES[ent:GetClass()] and ent.pdcity_Owner == ply
end

function PDCity.SendPrinterState(ply, ent)
	if not IsValid(ply) or not IsValid(ent) then return end

	net.Start("PDCity_OpenPrinterMenu")
	net.WriteEntity(ent)
	net.WriteBool(ent.pdcity_Unlocked)
	net.WriteUInt(math.floor(ent.pdcity_HeldMoney), 32)
	net.WriteUInt(ent.pdcity_SpeedLevel, 8)
	net.WriteUInt(ent.pdcity_AmountLevel, 8)
	net.WriteUInt(ent:GetPrintInterval(), 16)
	net.WriteUInt(ent:GetPrintAmount(), 32)
	net.WriteFloat(ent.pdcity_Unlocked and (timer.TimeLeft(ent:GetPrintTimerName()) or 0) or 0)
	net.WriteUInt(PDCity.CountPrinters(ply, ent:GetClass()), 8)
	net.WriteUInt(PDCity.GetMaxPrinters(ply, ent:GetClass()), 8)
	net.WriteUInt(ent:GetPrinterProfile().UnlockCost, 32)

	-- Next-level upgrade costs (0 = maxed), read from the entity's own
	-- profile rather than a client-side table, so a future second
	-- printer type wouldn't need this touched.
	local profile = ent:GetPrinterProfile()
	net.WriteUInt(profile.UpgradeCosts[ent.pdcity_SpeedLevel + 1] or 0, 32)
	net.WriteUInt(profile.UpgradeCosts[ent.pdcity_AmountLevel + 1] or 0, 32)

	net.Send(ply)
end

function PDCity.OpenPrinterMenuFor(ply, ent)
	PDCity.SendPrinterState(ply, ent)
end

net.Receive("PDCity_PrinterUnlock", function(len, ply)
	local ent = net.ReadEntity()
	if not IsValidPrinter(ent, ply) then return end
	if ent.pdcity_Unlocked then return end

	local unlockCost = ent:GetPrinterProfile().UnlockCost

	if not PDCity.AddMoney(ply, -unlockCost) then
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] You don't have $" .. unlockCost .. ".")
		return
	end

	ent.pdcity_Unlocked = true
	ent:StartPrinting()

	PDCity.GameLog("money", ply:Nick() .. " (" .. ply:SteamID() .. ") unlocked a "
		.. ent.PrintName .. " for $" .. unlockCost)

	ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] " .. ent.PrintName .. " unlocked - it's now printing $" .. ent:GetPrintAmount() .. " every " .. ent:GetPrintInterval() .. "s.")

	PDCity.SendPrinterState(ply, ent)
end)

net.Receive("PDCity_PrinterUpgrade", function(len, ply)
	local ent = net.ReadEntity()
	local track = net.ReadString()

	if not IsValidPrinter(ent, ply) then return end
	if not ent.pdcity_Unlocked then return end

	local profile = ent:GetPrinterProfile()

	-- Only speed/amount remain: the old "printers" track (paying to
	-- raise the ownership cap) was removed - caps are now fixed per
	-- job/type, see PDCity.GetMaxPrinters above.
	if track ~= "speed" and track ~= "amount" then return end

	local levelField = (track == "speed") and "pdcity_SpeedLevel" or "pdcity_AmountLevel"
	local level = ent[levelField]

	if level >= profile.MaxLevel then
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] That upgrade is already maxed.")
		return
	end

	local cost = profile.UpgradeCosts[level + 1]

	if not PDCity.AddMoney(ply, -cost) then
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] You don't have $" .. cost .. ".")
		return
	end

	ent[levelField] = level + 1

	if track == "speed" then
		ent:StartPrinting() -- reapply the new (faster) interval
	end

	PDCity.GameLog("money", ply:Nick() .. " (" .. ply:SteamID() .. ") upgraded a "
		.. ent.PrintName .. " " .. track .. " to level " .. ent[levelField] .. " for $" .. cost)

	-- No ChatPrint here - the printer menu (cl_printer_menu.lua) rebuilds
	-- itself from PDCity.SendPrinterState right below and already shows
	-- the new level directly in the upgrade row, so a chat line added
	-- nothing but spam on repeated upgrades (buying several levels in a
	-- row, as players commonly do, filled the chatbox with identical
	-- "Upgraded to level X" lines).
	PDCity.SendPrinterState(ply, ent)
end)

--[[---------------------------------------------------------
	Lockpicking a printer (weapon_pdcity_lockpick.lua) - a one-time
	invitation to collect whatever's currently sitting in it, not a
	permanent takeover: the owner keeps their unlock/upgrades, this
	just lets someone else empty the till before it relocks.
-----------------------------------------------------------]]
function PDCity.GrantPrinterStealAccess(ply, ent)
	if not IsValid(ply) or not IsValid(ent) then return end

	local owner = ent.pdcity_Owner
	if ply == owner then return end -- can't "steal" your own printer

	ent.pdcity_StealAccess = ply

	timer.Create("pdcity_printer_steal_" .. ent:EntIndex(), PDCity.PRINTER_STEAL_WINDOW, 1, function()
		if IsValid(ent) and ent.pdcity_StealAccess == ply then
			ent.pdcity_StealAccess = nil
		end
	end)

	if IsValid(owner) then
		owner:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Someone just picked the lock on your " .. ent.PrintName .. "!")
	end

	PDCity.SendPrinterState(ply, ent)
end

net.Receive("PDCity_PrinterCollect", function(len, ply)
	local ent = net.ReadEntity()
	if not IsValid(ent) or not PDCity.PRINTER_CLASSES[ent:GetClass()] then return end

	local isOwner = ent.pdcity_Owner == ply
	local isThief = ent.pdcity_StealAccess == ply
	if not isOwner and not isThief then return end

	local amount = math.floor(ent.pdcity_HeldMoney)
	if amount <= 0 then
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Nothing to collect yet.")
		return
	end

	ent.pdcity_HeldMoney = 0
	PDCity.AddMoney(ply, amount)

	if isThief then
		ent.pdcity_StealAccess = nil -- single use per successful pick

		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] You stole $" .. amount .. " from the " .. ent.PrintName .. "!")

		local owner = ent.pdcity_Owner
		if IsValid(owner) then
			owner:ChatPrint("[" .. PDCity.BRAND_TAG .. "] " .. PDCity.GetDisplayName(ply) .. " stole $" .. amount .. " from your " .. ent.PrintName .. "!")
		end
	else
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Collected $" .. amount .. " from your " .. ent.PrintName .. ".")

		-- Any class: rewards whatever job the collector currently
		-- holds, not just specific ones (core/sv_job_xp.lua). Only the
		-- legitimate owner earns this - stealing already pays out in
		-- cash, which is reward enough for that action.
		PDCity.AddXPForCurrentJob(ply, amount * PDCity.PRINTER_XP_PER_DOLLAR)
	end

	PDCity.SendPrinterState(ply, ent)
end)

--[[---------------------------------------------------------
	XP for destroying someone else's printer, for jobs that can't run one -
	ent_pdcity_printer.lua's OnTakeDamage calls this the moment a
	printer is actually destroyed, not on every hit.

	Rate limit is a streak, not a fixed-size sliding window: the first
	3 destructions grant full XP; the 4th and every one after it while
	the streak continues only grants half, and the only way back to
	full rate is to go a full 5 minutes without destroying another one
	(at which point the streak - and the count - resets to zero).
	That's different from "3 per rolling 5 minutes" (which would let a
	4th back in as soon as the 1st ages out) - this is deliberately
	stickier, so grinding printers doesn't creep back to full rate
	just by spacing hits out slightly.
-----------------------------------------------------------]]

local PRINTER_DESTROY_XP_FULL = 20
local PRINTER_DESTROY_XP_REDUCED = 10
local PRINTER_DESTROY_RATE_LIMIT = 3
local PRINTER_DESTROY_RATE_WINDOW = 300 -- 5 minutes

function PDCity.GrantPrinterDestroyXP(attacker, owner, ent)
	if not IsValid(attacker) then return end

	-- Rewarded only for jobs that can't run printers themselves (e.g. law
	-- enforcement, once the owner restricts printers to other jobs) - so
	-- printer owners can't farm XP by destroying each other's.
	if attacker == owner or CanJobRunPrinters(attacker) then return end

	local now = CurTime()
	local lastTime = attacker.pdcity_PrinterDestroyLastTime or 0

	-- A full window of inactivity since the last qualifying kill resets
	-- the streak entirely, rather than just letting the oldest one age
	-- out of a rolling count.
	if now - lastTime > PRINTER_DESTROY_RATE_WINDOW then
		attacker.pdcity_PrinterDestroyCount = 0
	end

	attacker.pdcity_PrinterDestroyCount = (attacker.pdcity_PrinterDestroyCount or 0) + 1
	attacker.pdcity_PrinterDestroyLastTime = now

	local reduced = attacker.pdcity_PrinterDestroyCount > PRINTER_DESTROY_RATE_LIMIT
	local xp = reduced and PRINTER_DESTROY_XP_REDUCED or PRINTER_DESTROY_XP_FULL

	PDCity.AddXPForCurrentJob(attacker, xp)

	local name = IsValid(ent) and ent.PrintName or "printer"

	if reduced then
		attacker:ChatPrint("[" .. PDCity.BRAND_TAG .. "] " .. name .. " destroyed (+" .. xp .. " xp - reduced rate, ease off for 5 minutes to reset).")
	else
		attacker:ChatPrint("[" .. PDCity.BRAND_TAG .. "] " .. name .. " destroyed (+" .. xp .. " xp).")
	end
end

-- Printers never persist - a disconnecting player's printers are simply
-- removed, per the "if a player disconnects, its gone" requirement.
hook.Add("PlayerDisconnected", "pdcity_PrinterDisconnectCleanup", function(ply)
	if not ply.pdcity_Printers then return end

	for _, ent in ipairs(ply.pdcity_Printers) do
		if IsValid(ent) then ent:Remove() end
	end

	ply.pdcity_Printers = nil
end)
