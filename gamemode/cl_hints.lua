

--[[---------------------------------------------------------
	The stock popup-hint system (tutorial-style toasts: "opening menu",
	physgun freeze/use tips, vehicle view, etc). Disabled outright - not
	just defaulted off, since a per-client archived convar wouldn't
	affect anyone who already has it saved from before, and the point
	was to remove the need for anyone to visit the context menu at all.

	GM:AddHint/SuppressHint are kept as no-ops (rather than deleted)
	since core/sv_thirdperson.lua-style SendHint calls elsewhere
	(PhysgunFreeze/PhysgunUse hints - see shared.lua and
	core/sv_spawn_defaults.lua) still net over PDCity_Hint expecting
	these functions to exist.
-----------------------------------------------------------]]

function GM:AddHint( name, delay )
end

function GM:SuppressHint( name )
end

--
-- Server-side hint/limit notifications arrive over this net message
-- (see player_extension.lua) instead of Player:SendLua, since most
-- clients have server-run Lua disabled and would never see them.
--
net.Receive( "PDCity_Hint", function()

	local action = net.ReadString()

	if ( action == "AddHint" ) then
		GAMEMODE:AddHint( net.ReadString(), net.ReadUInt( 8 ) )
	elseif ( action == "SuppressHint" ) then
		GAMEMODE:SuppressHint( net.ReadString() )
	elseif ( action == "LimitHit" ) then
		GAMEMODE:LimitHit( net.ReadString() )
	end

end )
