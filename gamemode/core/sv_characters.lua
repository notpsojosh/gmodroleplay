--[[---------------------------------------------------------
	Character selection - the session-level glue between an account
	(core/sv_accounts.lua, its Characters roster + slot limit) and a
	character profile (core/sv_profiles.lua, keyed by "<steamid64>:<slot>").

	Every connecting player is frozen and shown a mandatory selection
	screen (cl_character_select.lua) right after PlayerInitialSpawn -
	pick an existing character or create a new one (blocked at their
	account's own slot limit, core/sv_accounts.lua's PDCity.GetCharacterLimit).
	Nothing character-scoped (money, inventory, currencies, job XP, RP
	name) is available before that - every one of those systems' own
	PDCity.GetProfile(ply) calls already return nil until
	ply.pdcity_ActiveCharSlot is set, which only happens here.

	PDCity_CharacterSelected is fired once selection completes - anything
	that used to sync its own character-scoped data on PlayerInitialSpawn
	(inventory, currency balances, RP name) now does it on this hook
	instead, since there's no character to sync data FOR before this
	point.
-----------------------------------------------------------]]

util.AddNetworkString("pdcity_character_screen")
util.AddNetworkString("pdcity_character_select")
util.AddNetworkString("pdcity_request_character_screen")
util.AddNetworkString("pdcity_set_character_model")
util.AddNetworkString("pdcity_cancel_character_switch")

-- Real file AND on this player's allowed list (core/sv_character_models.lua's
-- default Models list + their own SteamID's whitelist entries) - guards
-- both the model chosen at character creation and a later "Change
-- Model" against a spoofed/garbage or simply not-permitted client value.
local function IsChoosableModel(ply, path)
	return PDCity.IsValidModelPath(path) and PDCity.IsCharacterModelAllowed(ply, path)
end

-- Frozen, invisible, and not solid while the selection screen is up - a
-- player hasn't "arrived" in the world as any specific character yet, so
-- they shouldn't be visible/collidable/movable as one either.
local function LockForSelection(ply)
	ply:Freeze(true)
	ply:SetNoDraw(true)
	ply:SetNotSolid(true)
	ply:SetMoveType(MOVETYPE_NONE)
end

local function UnlockAfterSelection(ply)
	ply:Freeze(false)
	ply:SetNoDraw(false)
	ply:SetNotSolid(false)
	ply:SetMoveType(MOVETYPE_WALK)
end

-- excludeSlot: drop this slot from what's sent - the screen is for
-- switching to a DIFFERENT character, not "switching" to the one
-- already active. NOT read off ply.pdcity_ActiveCharSlot here - by the
-- only call site that matters (SwitchToCharacterSelect below), that's
-- already been cleared to nil before this runs (has to be, so the
-- normal "pdcity_character_select" receiver will actually accept a
-- pick), so it has to be passed in explicitly instead.
-- Global (not local) - core/sv_rpname.lua's rename receiver needs to
-- refresh the client's list too, after a rename succeeds or fails.
function PDCity.SendCharacterScreen(ply, excludeSlot, mandatory)
	local account = PDCity.GetAccount(ply)
	if not account then return end

	local slots = PDCity.GetCharacterSlots(ply)
	if excludeSlot then
		for i = #slots, 1, -1 do
			if slots[i].Slot == excludeSlot then
				table.remove(slots, i)
			end
		end
	end

	net.Start("pdcity_character_screen")
		net.WriteString(util.TableToJSON(slots))
		net.WriteUInt(PDCity.GetCharacterLimit(ply), 8)
		net.WriteBool(mandatory or false)
	net.Send(ply)
end
local SendCharacterScreen = PDCity.SendCharacterScreen

hook.Add("PlayerInitialSpawn", "pdcity_ShowCharacterSelect", function(ply)
	if ply:IsBot() then return end
	ply.pdcity_ActiveCharSlot = nil

	timer.Simple(0.5, function()
		if not IsValid(ply) then return end
		LockForSelection(ply)
		SendCharacterScreen(ply, nil, true)
	end)
end)

-- Re-locks and re-shows the screen on every respawn too, UNTIL a
-- selection has actually gone through this session - stops a player
-- falling through to a normal spawn (able to move, visible, solid)
-- before they've picked anyone, which PlayerInitialSpawn's own timer
-- delay alone can't fully guard against (a very fast respawn could race
-- it).
hook.Add("PlayerSpawn", "pdcity_HoldForCharacterSelect", function(ply)
	if ply:IsBot() or ply.pdcity_ActiveCharSlot then return end
	LockForSelection(ply)
end)

-- Held for this long before a character SWITCH's Spawn() actually
-- happens (they stay frozen/locked in the meantime, same as during the
-- initial pick) - mirrors the normal death respawn delay
-- (core/sv_respawn.lua) so switching characters isn't an instant
-- teleport. Doesn't apply to a player's very first pick after joining -
-- there's nothing to "switch" from yet.
local CHARACTER_SWITCH_DELAY = 5

local function FinishSelection(ply, slot, account)
	ply.pdcity_ActiveCharSlot = slot
	ply.pdcity_PreviousCharSlot = nil

	local isSwitch = ply.pdcity_HasSelectedCharacter
	ply.pdcity_HasSelectedCharacter = true

	local function ActuallySpawn()
		if not IsValid(ply) or ply.pdcity_ActiveCharSlot ~= slot then return end

		UnlockAfterSelection(ply)

		-- A switched-to character always starts back on Citizen rather
		-- than inheriting whatever team GMod still has cached from
		-- before the switch.
		if isSwitch then
			ply:SetTeam(PDCity.DEFAULT_JOB)
		end

		ply:Spawn()

		hook.Run("PDCity_CharacterSelected", ply, slot)
	end

	if isSwitch then
		-- Only actually freezes/hides them once a switch is CONFIRMED, not
		-- from the moment the character select screen is merely opened
		-- (SwitchToCharacterSelect below no longer locks either) - opening
		-- the screen to look, then closing without picking anything, used
		-- to leave a player permanently frozen/invisible/unable to move
		-- with nothing to undo it (LockForSelection ran on open, and
		-- nothing ever called UnlockAfterSelection unless a NEW selection
		-- went all the way through). See the "pdcity_cancel_character_switch"
		-- receiver below for the other half of that fix - restoring
		-- ActiveCharSlot if they close out having never reached this point.
		LockForSelection(ply)
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Switching character in " .. CHARACTER_SWITCH_DELAY .. " seconds...")
		timer.Simple(CHARACTER_SWITCH_DELAY, ActuallySpawn)
	else
		ActuallySpawn()
	end
end

net.Receive("pdcity_character_select", function(len, ply)
	if not IsValid(ply) then return end
	if ply.pdcity_ActiveCharSlot then return end -- already picked this session

	local data = util.JSONToTable(net.ReadString() or "")
	if not istable(data) or not isstring(data.Action) then return end

	local account = PDCity.GetAccount(ply)
	if not account then return end

	if data.Action == "select" then
		local slot = isstring(data.Slot) and data.Slot

		-- "STAFF" isn't a real roster entry (core/sv_accounts.lua) - it's
		-- only ever offered to a currently staff-ranked player, and only
		-- checked against that, never against account.Characters.
		local isStaffSlot = slot == PDCity.STAFF_SLOT and PDCity.IsStaff(ply)

		if not slot or (not isStaffSlot and not account.Characters[slot]) then
			ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] That character doesn't exist.")
			SendCharacterScreen(ply, ply.pdcity_PreviousCharSlot)
			return
		end

		-- Real enforcement, not just hiding it from the list - a
		-- tampered client can't send this slot back and switch to
		-- themselves anyway.
		if slot == ply.pdcity_PreviousCharSlot then
			ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] You're already playing as that character.")
			SendCharacterScreen(ply, ply.pdcity_PreviousCharSlot)
			return
		end

		FinishSelection(ply, slot, account)

	elseif data.Action == "create" then
		local name = isstring(data.Name) and string.Trim(data.Name) or ""
		if name == "" then
			ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Enter a name for your new character.")
			SendCharacterScreen(ply, ply.pdcity_PreviousCharSlot)
			return
		end
		if #name > 32 then
			ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] That name's too long (32 characters max).")
			SendCharacterScreen(ply, ply.pdcity_PreviousCharSlot)
			return
		end

		local limit = PDCity.GetCharacterLimit(ply)
		local used = table.Count(account.Characters)
		if used >= limit then
			ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] You're at your character limit (" .. used .. "/" .. limit .. ").")
			SendCharacterScreen(ply, ply.pdcity_PreviousCharSlot)
			return
		end

		local slot = PDCity.NextFreeCharacterSlot(account)
		if not slot then
			ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] No free character slots left.")
			SendCharacterScreen(ply, ply.pdcity_PreviousCharSlot)
			return
		end

		local model = isstring(data.Model) and data.Model ~= "" and IsChoosableModel(ply, data.Model) and data.Model or nil

		account.Characters[slot] = { Name = name, CreatedAt = os.time(), Model = model }
		PDCity.MarkAccountDirty(ply)

		-- Seeds the new character's profile with the name they just chose
		-- (RPName) so it's not blank the first time they spawn in - the
		-- profile itself is lazy-created by PDCity.GetProfile below, so
		-- this has to happen AFTER FinishSelection sets the active slot.
		FinishSelection(ply, slot, account)
		local profile = PDCity.GetProfile(ply)
		if profile then
			profile.RPName = name
			ply:SetNWString("PDCity_RPName", name)
			PDCity.MarkProfileDirty(ply)
		end

		PDCity.GameLog("characters", ply:Nick() .. " (" .. ply:SteamID() .. ") created character " .. slot .. " (\"" .. name .. "\")")

	elseif data.Action == "delete" then
		local slot = isstring(data.Slot) and data.Slot

		if slot == PDCity.STAFF_SLOT then
			ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Staff on Duty can't be deleted.")
			SendCharacterScreen(ply, ply.pdcity_PreviousCharSlot)
			return
		end

		if not slot or not account.Characters[slot] then
			ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] That character doesn't exist.")
			SendCharacterScreen(ply, ply.pdcity_PreviousCharSlot)
			return
		end

		-- The client already made them type the character's name to
		-- confirm (cl_character_select.lua) - checked again here since
		-- that's just UI friction, not enforcement; a tampered client
		-- could otherwise send a bare delete with no confirmation at all.
		local confirmName = isstring(data.ConfirmName) and data.ConfirmName or ""
		if confirmName ~= account.Characters[slot].Name then
			ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Typed name didn't match - character not deleted.")
			SendCharacterScreen(ply, ply.pdcity_PreviousCharSlot)
			return
		end

		local deletedName = account.Characters[slot].Name

		-- Archives the character's profile file before removing it -
		-- core/sv_profiles.lua's PDCity.ArchiveAndDeleteProfile. Nothing
		-- tells the player this happens; it's a quiet safety net for
		-- support/recovery (e.g. a compromised account deleting
		-- characters that weren't really meant to go), not a feature to
		-- advertise.
		PDCity.ArchiveAndDeleteProfile(ply:SteamID64(), slot)

		account.Characters[slot] = nil
		PDCity.MarkAccountDirty(ply)

		PDCity.GameLog("characters", ply:Nick() .. " (" .. ply:SteamID() .. ") deleted character " .. slot .. " (\"" .. deletedName .. "\")")

		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Character \"" .. deletedName .. "\" deleted.")
		SendCharacterScreen(ply, ply.pdcity_PreviousCharSlot)

	else
		return
	end
end)

-- Shared by "!characters"/"/switchcharacter" AND the F1 menu's
-- "Character Selection" tab (cl_f1_menu.lua, via the
-- "pdcity_request_character_screen" net message below) - lets a player
-- go back to the selection screen mid-session (e.g. wanting to play a
-- different character without reconnecting). Re-locks them exactly like
-- a fresh join would.
local function SwitchToCharacterSelect(ply)
	-- Captured before clearing ActiveCharSlot (has to be cleared for the
	-- "pdcity_character_select" receiver to accept a pick at all) so
	-- both the list they're shown AND the server-side check above still
	-- know which character they're switching AWAY from.
	ply.pdcity_PreviousCharSlot = ply.pdcity_ActiveCharSlot
	ply.pdcity_ActiveCharSlot = nil

	-- Deliberately NOT LockForSelection here (unlike the very first,
	-- mandatory join) - this can be closed again without picking
	-- anything (F1's X/Escape, not shown on the mandatory screen at
	-- all), and freezing/hiding/notsolid-ing them the instant the tab
	-- opens had nothing to ever undo that if they backed out. Freezing
	-- now only happens once FinishSelection's "isSwitch" branch
	-- confirms an actual pick; closing without picking is handled by
	-- "pdcity_cancel_character_switch" below, restoring ActiveCharSlot
	-- so they're just... still playing, same as before they opened it.
	SendCharacterScreen(ply, ply.pdcity_PreviousCharSlot)
end

hook.Add("PlayerSay", "pdcity_SwitchCharacterCommand", function(ply, text)
	local cmd = string.lower(string.Trim(text))
	if cmd ~= "!characters" and cmd ~= "/switchcharacter" then return end

	SwitchToCharacterSelect(ply)

	return ""
end)

-- Sent when the F1 menu's "Character Selection" tab is opened normally
-- (not via the mandatory join screen, which already has this data pushed
-- to it unprompted) - same effect as "!characters", just triggered by a
-- tab click instead of typing in chat.
net.Receive("pdcity_request_character_screen", function(len, ply)
	if not IsValid(ply) then return end
	SwitchToCharacterSelect(ply)
end)

-- Sent by cl_f1_menu.lua whenever the F1 dashboard closes (X, Escape, or
-- the F1 toggle), regardless of which tab was open - a no-op unless a
-- mid-session character switch was actually left mid-air (ActiveCharSlot
-- still nil from SwitchToCharacterSelect above, never completed by an
-- actual "select"/"create" pick). Restores whichever character they were
-- already playing as, so backing out of "Switch Character" without
-- picking anything just... does nothing, instead of leaving them stuck
-- with no active character at all.
net.Receive("pdcity_cancel_character_switch", function(len, ply)
	if not IsValid(ply) then return end
	if ply.pdcity_ActiveCharSlot then return end -- either never switching, or already confirmed a pick

	local previous = ply.pdcity_PreviousCharSlot
	if not previous then return end -- mandatory first-join screen has no character to go back to

	ply.pdcity_ActiveCharSlot = previous
	ply.pdcity_PreviousCharSlot = nil
	UnlockAfterSelection(ply) -- harmless if they were never actually locked
end)

--[[---------------------------------------------------------
	"Change Model" (F1 Character Selection, either the active card or an
	alt one) - works on ANY of the player's own characters, not just the
	active one, so switching to a character you haven't played yet
	already has your chosen look. core/sv_accounts.lua's
	PDCity.GetCharacterModel is what player_class/player_sandbox.lua's
	PLAYER:SetModel reads at spawn time for a job with no Models of its
	own; if this IS the active character right now, also apply it live
	instead of waiting for their next spawn.
-----------------------------------------------------------]]
net.Receive("pdcity_set_character_model", function(len, ply)
	if not IsValid(ply) then return end

	local data = util.JSONToTable(net.ReadString() or "")
	if not istable(data) or not isstring(data.Slot) then return end

	if data.Slot == PDCity.STAFF_SLOT then
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Staff on Duty's model is fixed and can't be changed.")
		return
	end

	local account = PDCity.GetAccount(ply)
	if not account or not account.Characters[data.Slot] then return end

	local model = isstring(data.Model) and data.Model or ""
	if model ~= "" and not IsChoosableModel(ply, model) then
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] That's not one of your available player models.")
		return
	end

	account.Characters[data.Slot].Model = model ~= "" and model or nil
	PDCity.MarkAccountDirty(ply)

	if ply.pdcity_ActiveCharSlot == data.Slot and model ~= "" and ply:Alive() then
		local job = PDCity.GetJob(ply:Team())
		if not (job and job.Models and #job.Models > 0) then
			util.PrecacheModel(model)
			ply:SetModel(model)
			ply:SetSkin(0)
		end
	end
end)
