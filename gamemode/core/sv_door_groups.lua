--[[---------------------------------------------------------
	Persists door groups (owner-only "Door Group" toolgun tool,
	entities/weapons/gmod_tool/stools/pdcity_doorgroup.lua) and feeds them
	into the door system's OWN native group support - DoorGroups (gamemode/
	doors/sh_config.lua), normally only ever
	hand-edited in that file. Populating that same global from here means
	buying/selling a grouped door already propagates through the door system's
	own unmodified OwnDoor/UnownDoor logic (addons/the door system/lua/
	autorun/server/sv_doors.lua) - same "wrap the addon's own globals"
	approach core/sv_door_factions.lua already uses for DoorRestrictions/
	DoorTable.

	One thing the door system's own group support DOESN'T do: co-owners.
	CanUseDoor (gamemode/doors/sh_doors.lua) checks a
	door's OWN DoorCoOwners entry only - adding a co-owner to a group's
	parent door doesn't grant them the children too. Fixed below by
	replacing the "SyncCoOwner" net handler entirely (net.Receive only
	ever keeps the LAST registered handler for a given message name, and
	this file loads after the addon's own autorun) so a co-owner add/
	remove on ANY door in a group mirrors to every other door in it.

	Doesn't touch existing ownership when a group is disbanded - whoever
	already owns a door keeps it, they just stop sharing access going
	forward.
-----------------------------------------------------------]]

local STORE_DIR = "pdcity/door_groups"

local function StorePath()
	return STORE_DIR .. "/" .. game.GetMap() .. ".json"
end

-- [parentIndex] = { Name = "...", ChildDoors = { index, index, ... } } -
-- our own persisted copy; DoorGroups[game.GetMap()] is kept as a direct
-- reference to THIS table (not a copy) so any change here is instantly
-- visible to the door system's own buy/sell code too.
local PDCityDoorGroups = {}

local function LoadGroups()
	local raw = file.Read(StorePath(), "DATA")
	local stored = raw and util.JSONToTable(raw)
	if stored then
		local groups = {}
		for parentStr, group in pairs(stored) do
			groups[tonumber(parentStr)] = {
				Name = group.Name,
				ChildDoors = group.ChildDoors or {},
			}
		end
		PDCityDoorGroups = groups
	end

	DoorGroups[game.GetMap()] = PDCityDoorGroups
end
LoadGroups()

local function SaveGroups()
	file.CreateDir(STORE_DIR)
	file.Write(StorePath(), util.TableToJSON(PDCityDoorGroups, true))
end

-- childIndices: a plain array of MapCreationIDs. Overwrites any existing
-- group with the same parent outright (matching the tool's own "start a
-- fresh build" flow - there's no separate "edit" action).
function PDCity.AddDoorGroup(parentIndex, childIndices)
	PDCityDoorGroups[parentIndex] = {
		Name = "Door Group #" .. parentIndex,
		ChildDoors = childIndices,
	}
	SaveGroups()
end

-- anyMemberIndex can be the parent OR any child - either way the whole
-- group is removed. Returns false if that door isn't grouped at all.
function PDCity.RemoveDoorGroup(anyMemberIndex)
	local parentIndex = PDCityDoorGroups[anyMemberIndex] and anyMemberIndex or nil

	if not parentIndex then
		for pIndex, group in pairs(PDCityDoorGroups) do
			if table.HasValue(group.ChildDoors, anyMemberIndex) then
				parentIndex = pIndex
				break
			end
		end
	end

	if not parentIndex then return false end

	PDCityDoorGroups[parentIndex] = nil
	SaveGroups()
	return true
end

-- Every door MapCreationID sharing a group with `index` (parent AND every
-- child), or just `{ index }` on its own if it isn't grouped at all.
function PDCity.GetDoorGroupMembers(index)
	if PDCityDoorGroups[index] then
		local list = { index }
		for _, child in ipairs(PDCityDoorGroups[index].ChildDoors) do
			table.insert(list, child)
		end
		return list
	end

	for parentIndex, group in pairs(PDCityDoorGroups) do
		if table.HasValue(group.ChildDoors, index) then
			local list = { parentIndex }
			for _, child in ipairs(group.ChildDoors) do
				table.insert(list, child)
			end
			return list
		end
	end

	return { index }
end

net.Receive("SyncCoOwner", function(len, sender)
	local ply = net.ReadEntity()
	local index = net.ReadInt(32)
	local remove = net.ReadBool()

	-- Everything here arrives from the client: the door must be real, the
	-- co-owner a real player, and only the door's owner (or a door admin)
	-- may change who shares it.
	local door = ents.GetMapCreatedEntity(index)
	if not IsValidDoor(door) or not IsValid(ply) or not ply:IsPlayer() then return end
	if door:GetNWEntity("DoorOwner") ~= sender and not DS_IsDoorAdmin(sender) then return end

	if DoorTable[index] then
		DS_Notify(sender, "This door is managed by a group and cannot be owned.")
		return
	end

	local members = PDCity.GetDoorGroupMembers(index)

	for _, memberIndex in ipairs(members) do
		if remove then
			RemoveCoOwner(ply, memberIndex)
		else
			AddCoOwner(ply, memberIndex)
		end
	end

	net.Start("SyncCoOwnerClient")
		DS_WriteCoOwners(DoorCoOwners)
	net.Broadcast()

	local suffix = #members > 1 and " across the whole door group." or "."
	if remove then
		DS_Notify(sender, "Removed " .. ply:Nick() .. " from being a co-owner" .. suffix)
	else
		DS_Notify(sender, "Added " .. ply:Nick() .. " as a co-owner" .. suffix)
	end
end)
