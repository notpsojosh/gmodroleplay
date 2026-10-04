--[[---------------------------------------------------------
	Money system. The authoritative balance lives in the player's profile
	(core/sv_profiles.lua, "Money" field); this file keeps the networked
	copy in sync for HUD display and provides admin commands. All changes
	must go through PDCity.AddMoney so the NWInt never drifts from the
	profile.
-----------------------------------------------------------]]

-- Pushes the profile balance to the client-visible NWInt. Called on spawn
-- rather than PlayerInitialSpawn so it also re-syncs after respawns; the
-- profile itself is lazy-loaded so hook ordering doesn't matter.
hook.Add("PlayerSpawn", "pdcity_SyncMoney", function(ply)
	if ply:IsBot() then return end
	ply:SetNWInt("PDCity_Money", PDCity.GetMoney(ply))
end)

-- Belt-and-braces: PlayerSpawn above already re-syncs on every actual
-- spawn, but the FIRST spawn after picking/creating a character
-- (core/sv_characters.lua) can race it depending on engine timing - this
-- guarantees the HUD's money figure is never stale for that first moment.
hook.Add("PDCity_CharacterSelected", "pdcity_SyncMoneyOnCharacterSelect", function(ply)
	ply:SetNWInt("PDCity_Money", PDCity.GetMoney(ply))
end)

--[[---------------------------------------------------------
	Player-to-player transfers and money dropping.

	/dropmoney <amount>  - drops a cash briefcase (min $250, anti-spam)
	/give <amount>       - give to the player you're looking at (close range)
	/give <steamid|name> <amount>

	Both /give forms show a client-side confirmation dialog first
	(cl_give_confirm.lua); the transfer only happens when the client
	confirms, and the server re-validates everything at that point.
-----------------------------------------------------------]]

util.AddNetworkString("PDCity_ConfirmGive")
util.AddNetworkString("PDCity_GiveConfirmed")

local DROP_MINIMUM = 250
local GIVE_LOOK_RANGE = 200 -- max distance for the look-at /give form
local CONFIRM_TIMEOUT = 30

-- One pending give per giver; a new /give before confirming replaces it,
-- and the client's dialog is replaced along with it, so the open dialog
-- always matches the pending transfer.
local PendingGives = {}

local function ParseAmount(str)
	local amount = tonumber(str)
	if not amount then return nil end
	amount = math.floor(amount)
	if amount < 1 or amount > 2000000000 then return nil end
	return amount
end

-- Shared with core/sv_arrests.lua's !unarrest command.
function PDCity.FindPlayerByIdentifier(identifier)
	if string.match(identifier, "^STEAM_%d:%d:%d+$") then
		return player.GetBySteamID(string.upper(identifier))
	end

	if #identifier == 17 and string.match(identifier, "^%d+$") then
		return player.GetBySteamID64(identifier)
	end

	-- player.GetAll() (not GetHumans()) so this also matches bots - used
	-- by !unarrest (core/sv_arrests.lua) too, where a bot is a normal,
	-- validly-arrestable target, not just something to exclude the way
	-- it made sense to for /give.
	local search = string.lower(identifier)
	for _, other in ipairs(player.GetAll()) do
		if string.find(string.lower(PDCity.GetDisplayName(other)), search, 1, true) then
			return other
		end
	end
end

local function DropMoney(ply, args)

	local amount = ParseAmount(args[1])
	if not amount or amount < DROP_MINIMUM then
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Usage: /dropmoney <amount> (minimum $" .. DROP_MINIMUM .. ")")
		return
	end

	if not PDCity.AddMoney(ply, -amount) then
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] You don't have $" .. amount .. ".")
		return
	end

	local ent = ents.Create("ent_pdcity_money")
	if not IsValid(ent) then
		PDCity.AddMoney(ply, amount)
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Something went wrong - money refunded.")
		return
	end

	local tr = util.TraceLine({
		start = ply:EyePos(),
		endpos = ply:EyePos() + ply:GetAimVector() * 80,
		filter = ply,
	})

	ent:SetPos(tr.HitPos + tr.HitNormal * 8)
	ent:SetAmount(amount)
	ent:Spawn()
	ent:Activate()

	ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] You dropped $" .. amount .. ".")

end

local function RequestGiveConfirmation(ply, target, amount)

	PendingGives[ply] = {
		target = target,
		amount = amount,
		expires = CurTime() + CONFIRM_TIMEOUT,
	}

	net.Start("PDCity_ConfirmGive")
	-- PDCity.GetDisplayName (core/sh_rpname.lua): the RP name if one's
	-- set, else the real Steam nick - Player:Nick() itself can't be
	-- overridden, so this is the actual roleplay-facing name.
	net.WriteString(PDCity.GetDisplayName(target))
	net.WriteUInt(amount, 32)
	net.Send(ply)

end

local function GiveMoney(ply, args)

	local target, amount

	if args[2] then
		amount = ParseAmount(args[2])
		if not amount then
			ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Usage: /give <steamid or name> <amount>, or /give <amount> at someone nearby.")
			return
		end

		target = PDCity.FindPlayerByIdentifier(args[1])
		if not IsValid(target) then
			ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] No player found matching \"" .. args[1] .. "\".")
			return
		end
	else
		amount = ParseAmount(args[1])
		if not amount then
			ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Usage: /give <steamid or name> <amount>, or /give <amount> at someone nearby.")
			return
		end

		local tr = ply:GetEyeTrace()
		target = tr.Entity

		if not IsValid(target) or not target:IsPlayer()
			or ply:GetPos():DistToSqr(target:GetPos()) > GIVE_LOOK_RANGE * GIVE_LOOK_RANGE then
			ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Look at a player standing close to you, or use /give <steamid or name> <amount>.")
			return
		end
	end

	if target == ply then
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] You can't give money to yourself.")
		return
	end

	if PDCity.GetMoney(ply) < amount then
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] You don't have $" .. amount .. ".")
		return
	end

	RequestGiveConfirmation(ply, target, amount)

end

net.Receive("PDCity_GiveConfirmed", function(len, ply)

	local accepted = net.ReadBool()

	local pending = PendingGives[ply]
	PendingGives[ply] = nil
	if not pending or not accepted then return end

	if pending.expires < CurTime() then
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] That give request expired.")
		return
	end

	local target = pending.target
	if not IsValid(target) then
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] That player is no longer on the server.")
		return
	end

	-- Balance can have changed since the dialog opened - check again.
	if not PDCity.AddMoney(ply, -pending.amount) then
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] You no longer have $" .. pending.amount .. ".")
		return
	end

	PDCity.AddMoney(target, pending.amount)
	ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] You gave $" .. pending.amount .. " to " .. PDCity.GetDisplayName(target) .. ".")
	target:ChatPrint("[" .. PDCity.BRAND_TAG .. "] " .. PDCity.GetDisplayName(ply) .. " gave you $" .. pending.amount .. ".")

end)

hook.Add("PlayerSay", "pdcity_MoneyChatCommands", function(ply, text)

	local args = string.Explode(" ", string.Trim(text))
	local cmd = string.lower(args[1] or "")
	table.remove(args, 1)

	if cmd == "/dropmoney" then
		DropMoney(ply, args)
		return ""
	end

	if cmd == "/give" then
		GiveMoney(ply, args)
		return ""
	end

end)

--[[---------------------------------------------------------
	pdcity_givemoney <partial player name> <amount>
	Admin only (or server console). Negative amounts deduct; a deduction
	that would go below zero is rejected, same rule as everywhere else.
-----------------------------------------------------------]]

concommand.Add("pdcity_givemoney", function(ply, cmd, args)
	local isConsole = not IsValid(ply)
	if not isConsole and not ply:IsAdmin() then return end

	local function Reply(text)
		if isConsole then print(text) else ply:PrintMessage(HUD_PRINTCONSOLE, text) end
	end

	local search = args[1] and string.lower(args[1])
	local amount = tonumber(args[2])

	if not search or not amount then
		Reply("[" .. PDCity.BRAND_TAG .. "] Usage: pdcity_givemoney <partial player name> <amount>")
		return
	end

	local target
	for _, other in ipairs(player.GetHumans()) do
		if string.find(string.lower(other:Nick()), search, 1, true) then
			target = other
			break
		end
	end

	if not IsValid(target) then
		Reply("[" .. PDCity.BRAND_TAG .. "] No matching player found.")
		return
	end

	if not PDCity.AddMoney(target, amount) then
		Reply("[" .. PDCity.BRAND_TAG .. "] " .. target:Nick() .. " can't afford that deduction.")
		return
	end

	Reply("[" .. PDCity.BRAND_TAG .. "] " .. target:Nick() .. " now has $" .. PDCity.GetMoney(target) .. ".")
	target:ChatPrint(amount >= 0
		and ("[" .. PDCity.BRAND_TAG .. "] You received $" .. amount .. ".")
		or ("[" .. PDCity.BRAND_TAG .. "] $" .. math.abs(amount) .. " was deducted from you."))
end)
