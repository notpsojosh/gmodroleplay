--[[---------------------------------------------------------
	DarkRP-style chat routing. All of it lives in one PlayerSay
	handler at priority -5: after the !motd/!welcome intercept (-10),
	before the default-priority command hooks - which is why anything
	starting with "!" is passed straight through untouched, so the
	existing !commands keep working exactly as before.

	  (normal)      local - only players within PDCITY_VOICE_HEAR_
	                DISTANCE see it, the same range they could hear
	                you speak (core/sh_voice.lua), so text and voice
	                agree about who's "in earshot"
	  (team)        untouched - default team-only behaviour
	  // or /ooc    global, out of character
	  /pm <name> <msg>   private message (partial name matching)
	  /r <msg>      reply to whoever last PM'd you
	  /advert <msg> global advert, yellow
	  /dwa <msg>    dark web advert - jobs with "Dark web access" only, plus
	                staff (moderation) and the sender

	Every route writes its own gamelog category (core/sv_gamelog.lua):
	chat, chat-ooc, pms, adverts, darkweb. The gamelog's own generic
	chat hook was removed in favour of this - it could miss consumed
	messages depending on hook order; this sees everything it routes.

	Rendering happens client-side in cl_chat.lua via one net message.
-----------------------------------------------------------]]

util.AddNetworkString("pdcity_chat")

-- Message kinds, shared with cl_chat.lua by number.
local CHAT_LOCAL = 1
local CHAT_OOC = 2
local CHAT_PM = 3
local CHAT_ADVERT = 4
local CHAT_DARKWEB = 5

local function Send(kind, sender, text, recipients, extra)
	net.Start("pdcity_chat")
		net.WriteUInt(kind, 4)
		net.WriteEntity(sender)
		net.WriteString(text)
		net.WriteString(extra or "")
	if recipients then net.Send(recipients) else net.Broadcast() end
end

local function D(ply)
	return ply:Nick() .. " (" .. ply:SteamID() .. ")"
end

-- Case-insensitive partial name match; nil plus a reason when it's
-- ambiguous or unknown, so /pm never silently picks the wrong person.
local function FindByName(name)
	name = string.lower(name)
	local found

	for _, p in ipairs(player.GetAll()) do
		if string.find(string.lower(PDCity.GetDisplayName(p)), name, 1, true) then
			if found then return nil, "More than one player matches \"" .. name .. "\" - be more specific." end
			found = p
		end
	end

	if not found then return nil, "No player matching \"" .. name .. "\"." end
	return found
end

local HEAR_SQR = PDCity.VOICE_HEAR_DISTANCE * PDCity.VOICE_HEAR_DISTANCE

hook.Add("PlayerSay", "pdcity_Chat", function(ply, text, teamChat)

	-- !commands belong to the hooks behind us (ULX, !hide, !content...).
	if string.sub(text, 1, 1) == "!" then return end

	-- Staff Menu mute (core/sv_staff_menu.lua) - checked here, first,
	-- rather than per-route below, so a muted player can't reach ANY of
	-- them (local, OOC, PM, adverts...) with a single check.
	if ply:GetNWBool("PDCity_Muted", false) then
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] You are muted and cannot chat.")
		return ""
	end

	-- Team chat: default behaviour, just logged.
	if teamChat then
		PDCity.GameLog("chat", "[TEAM] " .. D(ply) .. ": " .. text)
		return
	end

	local lower = string.lower(text)

	--[[-----------------------------------------------------
		OOC: // or /ooc
	-------------------------------------------------------]]
	local ooc = text:match("^//%s*(.+)") or lower:match("^/ooc%s+") and text:sub(6)
	if ooc and ooc ~= "" then
		Send(CHAT_OOC, ply, ooc)
		PDCity.GameLog("chat-ooc", D(ply) .. ": " .. ooc)
		return ""
	end

	--[[-----------------------------------------------------
		/pm and /r
	-------------------------------------------------------]]
	local pmName, pmMsg = text:match("^/[pP][mM]%s+(%S+)%s+(.+)")
	if pmName then
		local target, err = FindByName(pmName)
		if not target then
			ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] " .. err)
			return ""
		end
		if target == ply then
			ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] That's you.")
			return ""
		end

		target.pdcity_LastPMFrom = ply
		Send(CHAT_PM, ply, pmMsg, { ply, target }, PDCity.GetDisplayName(target))
		PDCity.GameLog("pms", D(ply) .. " -> " .. D(target) .. ": " .. pmMsg)
		return ""
	end

	local rMsg = text:match("^/[rR]%s+(.+)")
	if rMsg then
		local target = ply.pdcity_LastPMFrom
		if not IsValid(target) then
			ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Nobody has PM'd you (or they left).")
			return ""
		end

		target.pdcity_LastPMFrom = ply
		Send(CHAT_PM, ply, rMsg, { ply, target }, PDCity.GetDisplayName(target))
		PDCity.GameLog("pms", D(ply) .. " -> " .. D(target) .. " (reply): " .. rMsg)
		return ""
	end

	--[[-----------------------------------------------------
		/advert and /dwa
	-------------------------------------------------------]]
	local advert = text:match("^/[aA][dD][vV][eE][rR][tT]%s+(.+)")
	if advert then
		Send(CHAT_ADVERT, ply, advert)
		PDCity.GameLog("adverts", D(ply) .. ": " .. advert)
		return ""
	end

	local dwa = text:match("^/[dD][wW][aA]%s+(.+)")
	if dwa then
		-- Jobs with the "Dark web access" flag (F1 > Catalogue > Jobs),
		-- staff (moderation), and the sender.
		local recipients = {}
		for _, p in ipairs(player.GetAll()) do
			local job = PDCity.GetJob(p:Team())
			if p == ply or PDCity.IsStaff(p) or (job and job.DarkWeb) then
				recipients[#recipients + 1] = p
			end
		end

		Send(CHAT_DARKWEB, ply, dwa, recipients)
		PDCity.GameLog("darkweb", D(ply) .. ": " .. dwa)
		return ""
	end

	-- /name, /rpname, /n used to self-service a roleplay display name
	-- here - removed. Renaming a character is now ONLY done from the F1
	-- Character Selection screen's "Rename" option (cl_character_select.lua,
	-- core/sv_rpname.lua's PDCity.TryRenameCharacterSlot), or by an
	-- admin via !forcename (still chat-based, unchanged, below).

	-- Unknown /commands: swallowed silently rather than shouting the
	-- typo to everyone in range - no longer told to the sender either
	-- (used to ChatPrint "Unknown command..." here).
	if string.sub(text, 1, 1) == "/" then
		return ""
	end

	--[[-----------------------------------------------------
		Everything else: local chat, voice-hearing range
	-------------------------------------------------------]]
	local recipients = {}
	local pos = ply:GetPos()
	for _, p in ipairs(player.GetAll()) do
		if p == ply or p:GetPos():DistToSqr(pos) <= HEAR_SQR then
			recipients[#recipients + 1] = p
		end
	end

	Send(CHAT_LOCAL, ply, text, recipients)
	PDCity.GameLog("chat", D(ply) .. ": " .. text)
	return ""

-- Priority -1 (HOOK_HIGH), and the exact value matters: ULib replaces
-- the hook system and clamps priorities to [-2, 2], where -2 and 2 are
-- "monitor" levels whose RETURN VALUES ARE IGNORED. An earlier version
-- passed -5 assuming a wider scale; ULib clamped it to -2, every
-- `return ""` was discarded, and the default global chat broadcast
-- went out alongside ours - which showed up as every message doubled.
end, -1)
