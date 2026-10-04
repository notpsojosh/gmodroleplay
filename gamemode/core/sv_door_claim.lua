--[[---------------------------------------------------------
	F2 (native bind -> gm_showteam -> GM:ShowTeam(ply), same mechanism as
	the F1/F4 menus - see core/sh_player_spawn.lua and init.lua) does one
	of two things, depending on what you're doing at the time:

	  holding weapon_keys, looking at a door  -> claim that door
	  holding weapon_keys, not at a door      -> open your inventory
	  not holding weapon_keys                 -> nothing

	Both are gated behind having your keys out: the keyring doubles as
	what you carry your pockets on, so F2 with anything else equipped
	deliberately does nothing rather than popping the inventory open
	mid-firefight.

	The claim itself mirrors the essential parts of the door system's own
	"OwnDoor" net.Receive handler (lua/autorun/server/sv_doors.lua)
	rather than opening its menu, skipping the admin-override and
	door-group paths since those don't apply to a normal quick claim.
-----------------------------------------------------------]]

function GM:ShowTeam(ply)

	if not IsValid(ply) then return end

	local wep = ply:GetActiveWeapon()
	if not IsValid(wep) or wep:GetClass() ~= "weapon_keys" then return end

	local door = ply:GetDoor()

	if not IsValid(door) then
		-- Keys out but not aimed at a door - this is the inventory key.
		-- ConCommand (not SendLua) for the same reason as the F1/F4
		-- menus: most clients have serverside Lua execution disabled.
		ply:ConCommand("pdcity_inventory")
		return
	end

	local entindex = door:MapCreationID()
	local doorowner = door:GetNWEntity("DoorOwner")

	if IsValid(doorowner) then return end -- already owned - nothing to claim
	if DoorTable[entindex] then return end -- restricted/group door, not a plain claim

	if PlayerDoors[ply] == nil then PlayerDoors[ply] = 0 end

	if DOOR_CONFIG_MAX_AMOUNT > 0 and PlayerDoors[ply] >= DOOR_CONFIG_MAX_AMOUNT then
		DS_Notify(ply, "You own the max amount of doors! Sell a door or sell all doors with the /sellalldoors chat command.")
		return
	end

	if hook.Run("DoorSystem_CanBuyDoor", ply, door, DOOR_CONFIG_PRICE) == false then return end

	PlayerDoors[ply] = PlayerDoors[ply] + 1
	door:SetNWEntity("DoorOwner", ply)
	DS_Notify(ply, "You now own this door.")
	hook.Run("DoorSystem_OnBuyDoor", ply, door, DOOR_CONFIG_PRICE)

	PDCity.GameLog("doors", ply:Nick() .. " (" .. ply:SteamID() .. ") claimed door #" .. entindex)

end
