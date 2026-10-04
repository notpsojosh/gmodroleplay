--[[---------------------------------------------------------
	Single choke point for freezing a player, used by every system that
	does it: cuffing/tasing (core/sv_arrests.lua, weapon_pdcity_taser.lua),
	physgun pickup/right-click-freeze/reload (shared.lua,
	core/sv_physgun_players.lua), and force-respawn cleanup
	(core/sv_staff_commands.lua).

	Player:Freeze() (blocks input only) and SetGravity(0) alone don't
	reliably stop a player from falling/sagging - player movement runs
	through its own engine pathway, separate from generic entity physics,
	so gravity tricks that work on props don't necessarily carry over.

	A MOVETYPE_NONE-based fix was tried here first (fully disabling the
	player's own movement simulation on any freeze) - reverted, because
	it broke the physgun's own release: dropping a physgunned player
	stopped calling PhysgunDrop at all, leaving them stuck frozen
	forever with no way to undo it short of a reconnect. Whatever the
	native weapon_physgun/player-carry code uses server-side to decide
	"is this player still being held" isn't independent of the player's
	normal movetype the way prop pickup is, so forcing it to NONE mid-hold
	looks to have desynced the engine's own hold-tracking. Not worth the
	risk a second time - what's below instead treats the CAUSE (velocity
	that gravity/movement keeps re-adding every tick, fighting whatever
	IS holding them in place) without touching movetype at all, so the
	engine's own physgun bookkeeping is left completely alone.

	There are two modes, both position-lock-free of movetype changes:

	  lockPosition = true  (default) - hard freeze: input blocked AND
	                 held at a fixed point every tick. Used for cuffing,
	                 tasing, explicit physgun right-click-freeze, and
	                 anything else where nothing else should be
	                 repositioning them.
	  lockPosition = false - soft freeze: input blocked, velocity zeroed
	                 every tick (so nothing accumulates and drags them
	                 downward), but position itself left completely free
	                 for whatever IS actively repositioning them (the
	                 physgun beam, while simply held) - this is what
	                 PDCity.SetPlayerFrozen(ent, true) is called with the
	                 instant the physgun PICKS UP a player (shared.lua).
-----------------------------------------------------------]]

local FrozenPositions = {} -- hard freeze: [ply] = the fixed point they're held at
local HeldPlayers = {}     -- soft freeze: [ply] = true, velocity-only correction

function PDCity.SetPlayerFrozen(ply, frozen, lockPosition)
	if not IsValid(ply) then return end
	if lockPosition == nil then lockPosition = true end

	ply:Freeze(frozen)
	ply:SetGravity(frozen and 0 or 1)

	if frozen and lockPosition then
		FrozenPositions[ply] = ply:GetPos()
		HeldPlayers[ply] = nil
	elseif frozen then
		HeldPlayers[ply] = true
		FrozenPositions[ply] = nil
	else
		FrozenPositions[ply] = nil
		HeldPlayers[ply] = nil
		ply:SetVelocity(-ply:GetVelocity()) -- no leftover drag velocity on release
	end
end

--[[---------------------------------------------------------
	Is this player frozen right now, by anything at all? Checks both of
	this file's own tables AND the engine's own FL_FROZEN flag, so a
	freeze applied by something outside this gamemode (ULX, another
	addon, or a leftover from before this system existed) still reports
	true - core/sv_physgun_players.lua's reload-to-unfreeze uses this to
	find stuck players it has no record of freezing itself.
-----------------------------------------------------------]]
function PDCity.IsPlayerFrozen(ply)
	if not IsValid(ply) then return false end
	if FrozenPositions[ply] or HeldPlayers[ply] then return true end
	return ply:IsFlagSet(FL_FROZEN)
end

hook.Add("Tick", "pdcity_HoldFrozenPlayers", function()
	for ply, pos in pairs(FrozenPositions) do
		if IsValid(ply) then
			ply:SetPos(pos)
			ply:SetVelocity(-ply:GetVelocity()) -- Entity:SetVelocity is additive, so this zeroes it out
		else
			FrozenPositions[ply] = nil
		end
	end

	for ply in pairs(HeldPlayers) do
		if IsValid(ply) then
			-- Doesn't touch position at all (the physgun beam needs full
			-- freedom to move them) - just zeroes whatever velocity
			-- gravity/movement simulation accumulated since the beam
			-- last repositioned them, which is what read as "always
			-- dragging them downward".
			ply:SetVelocity(-ply:GetVelocity())
		else
			HeldPlayers[ply] = nil
		end
	end
end)
