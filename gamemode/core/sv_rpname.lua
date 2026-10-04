--[[---------------------------------------------------------
	Roleplay name - a display name separate from the player's fixed
	Steam nick (there's no way to actually change Player:Nick() itself).
	Self-service renaming is done from the F1 Character Selection
	screen's "Rename" option (cl_character_select.lua) via
	PDCity.TryRenameCharacterSlot below - NOT a chat command any more
	(used to be /name, /rpname, /n; removed from core/sv_chat.lua so
	renaming only ever happens through that one screen, or an admin's
	!forcename). Persisted on the profile like everything else
	(core/sv_profiles.lua), and synced to an NWString so it's visible to
	every client for free.

	Empty string means "no RP name set" throughout - an empty NWString is
	the wire-friendly way to represent "unset" without a separate bool.
	PDCity.GetDisplayName (core/sh_rpname.lua, both realms) is what
	actually resolves that down to "RP name if set, else Steam nick" -
	used by chat (cl_chat.lua) and the scoreboard (cl_scoreboard.lua) so
	both agree; anywhere else that shows a name (F1/F4 menus, world
	tips...) still shows the real Steam nick until/unless updated too.

	Self-service changes are rate-limited (10 minutes between changes,
	profile.RPNameCooldownUntil, os.time()-based so it survives a
	reconnect or restart mid-cooldown, unlike CurTime()) and blocked
	outright while an admin+ force-lock is active (profile.RPNameLockedUntil,
	24 hours from a !forcename, cleared early by !unforce) - both
	os.time() timestamps compared against the current wall-clock time,
	same convention already used for other real-world-duration state
	(core/sv_wanted.lua).

	No two players can be using the same effective display name at once
	(case-insensitive) - checked against every currently CONNECTED
	player's PDCity.GetDisplayName, not against every name anyone has
	ever used (that would mean scanning every saved profile on disk for
	every attempt, and a name freed up by someone disconnecting should
	immediately become available again anyway). Only applies to an
	actual RP name, never to clearing one back to a Steam nick - Steam
	nicks can already collide with each other and that's not something
	this system controls or should try to police.
-----------------------------------------------------------]]

local MAX_LENGTH = 18
local COOLDOWN_SECONDS = 10 * 60
local FORCE_LOCK_SECONDS = 24 * 60 * 60

util.AddNetworkString("pdcity_rename_character")

-- Trim, length, and character-set validation shared by every path - a
-- forced name still has to be a REAL name, "admin+" is a bypass on
-- cooldown/lock, not on format. Letters, digits, spaces, and hyphens
-- only; an empty/all-whitespace string is always allowed through here
-- (individual callers decide whether blank makes sense for THEM - it
-- did for the old "/name" clear-it path, it doesn't for renaming a
-- character, which always needs a real name).
local function ValidateRPName(name, excludePly)
	name = string.Trim(name or "")

	if name == "" then return true, name end

	if #name > MAX_LENGTH then
		return false, "Names can be at most " .. MAX_LENGTH .. " characters."
	end

	if not name:match("^[%a%d%- ]+$") then
		return false, "Names can only contain letters, numbers, spaces, and hyphens."
	end

	local lowered = string.lower(name)
	for _, other in ipairs(player.GetAll()) do
		if other ~= excludePly and string.lower(PDCity.GetDisplayName(other)) == lowered then
			return false, "That name is already in use by another player."
		end
	end

	return true, name
end

-- The actual write - shared by every path below. Operates on a
-- SPECIFIC slot's profile directly (composite key), not necessarily the
-- player's currently active one - renaming from the character select
-- screen targets a character that, by definition, isn't active yet
-- (nothing is, while that screen is up). Does NOT itself touch the
-- cooldown or lock timestamps; callers decide which (if either) apply
-- to how they got here.
local function ApplyRPNameToSlot(ply, slot, name)
	if not slot then return end

	local compositeKey = ply:SteamID64() .. ":" .. slot
	local profile = PDCity.LoadProfile(compositeKey)
	if profile then
		profile.RPName = name
		PDCity.MarkProfileDirtyByID(compositeKey)
	end

	-- The character's actual name (F1 Character Selection's flashcards,
	-- core/sv_accounts.lua's roster) changes right along with their RP
	-- name - to a player these are the same thing, "my character's
	-- name", not two separately-tracked labels.
	if name ~= "" then
		local account = PDCity.GetAccount(ply)
		if account and account.Characters[slot] then
			account.Characters[slot].Name = name
			PDCity.MarkAccountDirty(ply)
		end
	end

	if ply.pdcity_ActiveCharSlot == slot then
		ply:SetNWString("PDCity_RPName", name)
		if name ~= "" then ply:SetNWString("PDCity_CharacterName", name) end
	end
end

--[[---------------------------------------------------------
	Self-service: F1 Character Selection's "Rename" (cl_character_select.lua,
	net "pdcity_rename_character"). Always requires a real (non-blank)
	name - unlike the old chat command, there's no "clear it" case here,
	a character always has a name.
-----------------------------------------------------------]]

function PDCity.TryRenameCharacterSlot(ply, slot, newName)
	if slot == PDCity.STAFF_SLOT then
		return false, "Staff on Duty can't be renamed."
	end

	local account = PDCity.GetAccount(ply)
	if not account or not isstring(slot) or not account.Characters[slot] then
		return false, "That character doesn't exist."
	end

	local compositeKey = ply:SteamID64() .. ":" .. slot
	local profile = PDCity.LoadProfile(compositeKey)
	if not profile then return false, "Couldn't load that character." end

	local now = os.time()

	local lockedUntil = profile.RPNameLockedUntil or 0
	if lockedUntil > now then
		local mins = math.ceil((lockedUntil - now) / 60)
		return false, "This character's name was locked by an admin - " .. mins .. " more minute(s) (or !unforce)."
	end

	local cooldownUntil = profile.RPNameCooldownUntil or 0
	if cooldownUntil > now then
		local mins = math.ceil((cooldownUntil - now) / 60)
		return false, "You can rename this character again in " .. mins .. " more minute(s)."
	end

	local ok, nameOrErr = ValidateRPName(newName, ply)
	if not ok then return false, nameOrErr end
	if nameOrErr == "" then return false, "Enter a name for your character." end

	ApplyRPNameToSlot(ply, slot, nameOrErr)
	profile.RPNameCooldownUntil = now + COOLDOWN_SECONDS

	return true, nameOrErr
end

net.Receive("pdcity_rename_character", function(len, ply)
	if not IsValid(ply) then return end

	local data = util.JSONToTable(net.ReadString() or "")
	if not istable(data) or not isstring(data.Slot) then return end

	local ok, err = PDCity.TryRenameCharacterSlot(ply, data.Slot, isstring(data.Name) and data.Name or "")
	if not ok then
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] " .. err)
		-- Only re-sent on FAILURE, same as every other rejected
		-- character-select action - NOT on success, since a full resend
		-- rebuilds the client's whole lineup from scratch (cl_character_select.lua's
		-- PopulateList), which would reset which character is currently
		-- centred. The client already updates the name it's showing
		-- itself the moment it sends this, so success doesn't need it.
		PDCity.SendCharacterScreen(ply, ply.pdcity_PreviousCharSlot)
	end
end)

--[[---------------------------------------------------------
	Admin+: !forcename <user> <name>, !unforce <user>
-----------------------------------------------------------]]

hook.Add("PlayerSay", "pdcity_ForceNameChatCommands", function(ply, text)

	local args = string.Explode(" ", string.Trim(text))
	local cmd = string.lower(args[1] or "")

	if cmd ~= "!forcename" and cmd ~= "!unforce" then return end

	if not PDCity.IsAdminPlus(ply) then
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] You must be admin or above to use this.")
		return ""
	end

	table.remove(args, 1)
	local identifier = args[1]

	if not identifier then
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Usage: " .. cmd .. " <name or steamid>" .. (cmd == "!forcename" and " <new RP name>" or ""))
		return ""
	end

	local target = PDCity.FindPlayerByIdentifier(identifier)
	if not IsValid(target) then
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] No matching player found.")
		return ""
	end

	local profile = PDCity.GetProfile(target)
	if not profile then
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] That player's profile isn't loaded.")
		return ""
	end

	if cmd == "!unforce" then
		profile.RPNameLockedUntil = nil
		PDCity.MarkProfileDirty(target)

		PDCity.GameLog("names", ply:Nick() .. " (" .. ply:SteamID() .. ") lifted "
			.. target:Nick() .. " (" .. target:SteamID() .. ")'s RP name lock")

		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Cleared " .. PDCity.GetDisplayName(target) .. "'s RP name lock - they can change it again.")
		target:ChatPrint("[" .. PDCity.BRAND_TAG .. "] " .. PDCity.GetDisplayName(ply) .. " (admin) lifted your RP name lock.")

		return ""
	end

	-- !forcename
	table.remove(args, 1)
	local newName = table.concat(args, " ")

	local ok, nameOrErr = ValidateRPName(newName, target)
	if not ok then
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] " .. nameOrErr)
		return ""
	end

	ApplyRPNameToSlot(target, target.pdcity_ActiveCharSlot, nameOrErr)
	profile.RPNameLockedUntil = os.time() + FORCE_LOCK_SECONDS
	profile.RPNameCooldownUntil = nil -- the 24h lock supersedes the ordinary cooldown

	local shown = PDCity.GetDisplayName(target)

	PDCity.GameLog("names", ply:Nick() .. " (" .. ply:SteamID() .. ") force-set "
		.. target:Nick() .. " (" .. target:SteamID() .. ")'s RP name to \"" .. shown .. "\" (24h lock)")

	ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Set " .. PDCity.GetDisplayName(target) .. "'s RP name to \"" .. shown .. "\" - locked for 24 hours (!unforce to lift early).")
	target:ChatPrint("[" .. PDCity.BRAND_TAG .. "] " .. PDCity.GetDisplayName(ply) .. " (admin) set your RP name to \"" .. shown .. "\". It's locked for 24 hours.")

	return ""

end)

-- Restores whatever was saved for the ACTIVE character - RPName is
-- per-character (core/sv_profiles.lua), so this waits for character
-- selection (core/sv_characters.lua) instead of ordinary
-- PlayerInitialSpawn - there's no character's name to restore before
-- that point. Profile fields are plain Lua tables, never networked on
-- their own, so this NWString needs setting explicitly every time.
hook.Add("PDCity_CharacterSelected", "pdcity_SyncRPNameOnCharacterSelect", function(ply)
	local profile = PDCity.GetProfile(ply)
	if profile and isstring(profile.RPName) and profile.RPName ~= "" then
		ply:SetNWString("PDCity_RPName", profile.RPName)
	else
		ply:SetNWString("PDCity_RPName", "")
	end
end)
