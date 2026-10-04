DoorTable = {
	Lock = {}
}
DoorCoOwners = {}

function IsValidDoor( ent )
	local doors = {
		["prop_door"] = true,
		["prop_door_rotating"] = true,
		["func_door"] = true,
		["func_door_rotating"] = true
	}
	return IsValid( ent ) and doors[ent:GetClass()]
end

local meta = FindMetaTable( "Player" )
function meta:CanUseDoor( door )
	local owner = door:GetNWEntity( "DoorOwner" )
	local index = door:MapCreationID()
	if owner == self or ( DoorCoOwners[index] and table.HasValue( DoorCoOwners[index], self ) ) then
		return true
	end
	local tbl = DoorTable[index]
	if !tbl then return false end
	local res = DoorRestrictions[tbl]
	if !res then return false end
	return res.CheckFunction( self )
end

--[[
	Network encoding for the two door tables, written field by field rather
	than with net.WriteTable (slow, and sends type tags for every value).

	DoorTable:    [mapCreationID] = restriction id (-1 = ownership disabled),
	              plus DoorTable.Lock = { [mapCreationID] = true }
	DoorCoOwners: [mapCreationID] = { player, player, ... }
]]
function DS_WriteDoorTable( tbl )
	local restrictions = {}
	for index, id in pairs( tbl or {} ) do
		if isnumber( index ) and isnumber( id ) then restrictions[#restrictions + 1] = index end
	end
	net.WriteUInt( #restrictions, 16 )
	for _, index in ipairs( restrictions ) do
		net.WriteInt( index, 32 )
		net.WriteInt( tbl[index], 32 )
	end

	local locked = {}
	for index in pairs( istable( tbl and tbl.Lock ) and tbl.Lock or {} ) do
		if isnumber( index ) then locked[#locked + 1] = index end
	end
	net.WriteUInt( #locked, 16 )
	for _, index in ipairs( locked ) do
		net.WriteInt( index, 32 )
	end
end

function DS_ReadDoorTable()
	local tbl = { Lock = {} }
	for i = 1, net.ReadUInt( 16 ) do
		local index = net.ReadInt( 32 )
		tbl[index] = net.ReadInt( 32 )
	end
	for i = 1, net.ReadUInt( 16 ) do
		tbl.Lock[net.ReadInt( 32 )] = true
	end
	return tbl
end

function DS_WriteCoOwners( tbl )
	local doors = {}
	for index, list in pairs( tbl or {} ) do
		if isnumber( index ) and istable( list ) then doors[#doors + 1] = index end
	end
	net.WriteUInt( #doors, 16 )
	for _, index in ipairs( doors ) do
		local players = {}
		for _, ply in ipairs( tbl[index] ) do
			if IsValid( ply ) then players[#players + 1] = ply end
		end
		net.WriteInt( index, 32 )
		net.WriteUInt( #players, 8 )
		for _, ply in ipairs( players ) do
			net.WriteEntity( ply )
		end
	end
end

function DS_ReadCoOwners()
	local tbl = {}
	for i = 1, net.ReadUInt( 16 ) do
		local index = net.ReadInt( 32 )
		local list = {}
		for j = 1, net.ReadUInt( 8 ) do
			local ply = net.ReadEntity()
			if IsValid( ply ) then list[#list + 1] = ply end
		end
		tbl[index] = list
	end
	return tbl
end

-- Who may use the admin door menu (force owner, restrictions, force lock).
-- Checked server-side on every admin action, not just used to decide
-- whether the client shows the menu. The gamemode's owner always counts.
function DS_IsDoorAdmin( ply )
	if not IsValid( ply ) or not ply:IsPlayer() then return false end
	if DOOR_CONFIG_ADMIN_RANKS[ply:GetUserGroup()] then return true end
	return PDCity ~= nil and PDCity.IsOwner ~= nil and PDCity.IsOwner( ply ) == true
end

-- True if ply is close enough to interact with door. Allows twice the
-- normal reach, so a player who drifted slightly with a menu open isn't
-- refused, while still stopping actions on doors across the map.
function DS_IsInDoorRange( ply, door )
	if not IsValid( ply ) or not IsValidDoor( door ) then return false end
	local reach = DOOR_CONFIG_DISTANCE * 2
	return ply:GetPos():DistToSqr( door:GetPos() ) < reach * reach
end

function meta:GetDoor()
	local distance = DOOR_CONFIG_DISTANCE * DOOR_CONFIG_DISTANCE
	local ent = self:GetEyeTrace().Entity
	if IsValidDoor( ent ) and self:GetPos():DistToSqr( ent:GetPos() ) < distance then
		return ent
	end
	return NULL
end

print( "Universal Door System v2.1.1 by OPGman successfully loaded." )
