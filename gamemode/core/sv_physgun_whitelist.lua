--[[---------------------------------------------------------
	Server side of the physgun whitelist (PDCity.PHYSGUN_WHITELIST in
	core/sh_physgun_whitelist.lua). Owner-editable in-game via the F4 admin
	editor's "Physgun Whitelist" tab, or the Physgun Whitelist tool
	(entities/weapons/gmod_tool/stools/pdcity_physgunwhitelist.lua);
	persisted here and broadcast to every client so their prediction
	agrees with the server. Same shape as core/sv_inventory.lua's own
	storable-class whitelist - deliberately copied rather than shared,
	since the two lists mean different things and shouldn't move together.
-----------------------------------------------------------]]

util.AddNetworkString("pdcity_physgun_whitelist")
util.AddNetworkString("pdcity_physgun_admin")

local WHITELIST_PATH = "pdcity/physgun_whitelist.json"

local function SaveWhitelist()
	file.CreateDir("pdcity")
	file.Write(WHITELIST_PATH, util.TableToJSON(PDCity.PHYSGUN_WHITELIST, true))
end

local function LoadWhitelist()
	local raw = file.Read(WHITELIST_PATH, "DATA")
	if not raw then return end

	local stored = util.JSONToTable(raw)
	if istable(stored) then
		PDCity.PHYSGUN_WHITELIST = stored
	else
		ErrorNoHalt("[" .. PDCity.BRAND_TAG .. "] " .. WHITELIST_PATH .. " was unreadable - starting with an empty physgun whitelist.\n")
	end
end
LoadWhitelist()

local function BroadcastWhitelist(ply)
	net.Start("pdcity_physgun_whitelist")
		net.WriteString(util.TableToJSON(PDCity.PHYSGUN_WHITELIST))
	if IsValid(ply) then net.Send(ply) else net.Broadcast() end
end

hook.Add("PlayerInitialSpawn", "pdcity_SyncPhysgunWhitelist", function(ply)
	BroadcastWhitelist(ply)
end)

-- Returns ok[, error], same convention as PDCity.SetInventoryWhitelist.
--
-- Deliberately NOT restricted to weapons.GetStored/scripted_ents.GetStored
-- the way core/sv_inventory.lua's own whitelist is - an inventory item can
-- only ever be a weapon or a SENT, but a legitimate physgun target can be
-- ANY entity class in the game (native NPCs, vehicles, brush entities like
-- func_physbox, map props), most of which are never registered in either
-- of those two Lua registries at all. The F4 admin panel's search list can
-- still only offer weapon/SENT classes (same GetAllClasses() the Inventory
-- Items tab uses), but the Physgun Whitelist TOOL - aim at a live entity
-- and left-click - reaches everything else; this function has to accept
-- whatever class it's handed either way.
local function ApplyPhysgunAction(action, class)
	if not isstring(class) or class == "" then return false, "No class given." end

	if action == "add" then
		if PDCity.PHYSGUN_ALWAYS_ALLOWED[class] then
			return false, "That class is already always allowed - it doesn't need whitelisting."
		end
		if table.HasValue(PDCity.PHYSGUN_WHITELIST, class) then return true end

		table.insert(PDCity.PHYSGUN_WHITELIST, class)

	elseif action == "remove" then
		if not table.HasValue(PDCity.PHYSGUN_WHITELIST, class) then return true end
		table.RemoveByValue(PDCity.PHYSGUN_WHITELIST, class)

	else
		return false, "Unknown action."
	end

	SaveWhitelist()
	BroadcastWhitelist()
	return true
end

-- Global - the Physgun Whitelist toolgun calls this directly (its
-- LeftClick/RightClick already run server-side with the owner and traced
-- entity both in hand, no networking needed for the mutation itself), same
-- pattern as PDCity.SetInventoryWhitelist.
PDCity.SetPhysgunWhitelist = ApplyPhysgunAction

net.Receive("pdcity_physgun_admin", function(len, ply)
	-- Owner only - re-checked here regardless of what the client's UI
	-- already hides (cl_f4_admin.lua).
	if not PDCity.IsOwner(ply) then return end

	local data = util.JSONToTable(net.ReadString() or "")
	if not istable(data) or not isstring(data.Action) or not isstring(data.Class) then return end

	local ok, err = ApplyPhysgunAction(data.Action, data.Class)

	if not ok then
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] " .. (err or "That action failed."))
	end
end)
