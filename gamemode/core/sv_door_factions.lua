--[[---------------------------------------------------------
	Server side of door factions (core/sh_door_factions.lua): persists them
	to data/pdcity/door_factions.json, handles the F1 Site Admin panel's
	"Door Factions" tab (cl_site_admin.lua), and provides the setters the
	Door Faction tool uses (entities/weapons/gmod_tool/stools/
	pdcity_doorfaction.lua).

	Starts with zero factions - the owner creates every one in-game.
-----------------------------------------------------------]]

util.AddNetworkString("pdcity_door_factions_sync")
util.AddNetworkString("pdcity_door_factions_admin")

local SAVE_PATH = "pdcity/door_factions.json"
local NAME_MAX_LENGTH = 32

-- Never reused, even after a faction is deleted - a door saved under an
-- old ID must never silently start belonging to a different faction.
local nextFactionID = PDCity.DOOR_FACTION_ID_BASE + 1

-- False if the save file existed but couldn't be parsed. Orphan cleanup
-- (below) is skipped in that case, so a corrupt file can't wipe every
-- door assignment on the map.
local loadedCleanly = true

local function SaveFactions()
	file.CreateDir("pdcity")
	file.Write(SAVE_PATH, util.TableToJSON({
		NextID = nextFactionID,
		Factions = PDCity.EncodeDoorFactions(),
	}, true))
end

local function LoadFactions()
	local raw = file.Read(SAVE_PATH, "DATA")
	if not raw then return end

	local data = util.JSONToTable(raw)
	if not istable(data) then
		loadedCleanly = false
		ErrorNoHalt("[" .. PDCity.BRAND_TAG .. "] " .. SAVE_PATH .. " was unreadable - starting with no door factions.\n")
		return
	end

	PDCity.DOOR_FACTIONS = PDCity.DecodeDoorFactions(data.Factions)

	if isnumber(data.NextID) then
		nextFactionID = math.max(nextFactionID, data.NextID)
	end
	for id in pairs(PDCity.DOOR_FACTIONS) do
		nextFactionID = math.max(nextFactionID, id + 1)
	end
end

LoadFactions()
PDCity.RegisterDoorFactions()

local function BroadcastFactions(ply)
	net.Start("pdcity_door_factions_sync")
		net.WriteString(util.TableToJSON(PDCity.EncodeDoorFactions()))
	if IsValid(ply) then
		net.Send(ply)
	else
		net.Broadcast()
	end
end

hook.Add("PlayerInitialSpawn", "pdcity_SyncDoorFactions", function(ply)
	BroadcastFactions(ply)
end)

-- Every door MapCreationID currently assigned to `factionID`. DoorTable
-- also holds a "Lock" sub-table, hence the isnumber filter.
local function DoorsInFaction(factionID)
	local doors = {}
	for index, id in pairs(DoorTable or {}) do
		if isnumber(id) and id == factionID then
			table.insert(doors, index)
		end
	end
	return doors
end

-- Doors pointing at a faction ID that no longer exists (e.g. saved under
-- an older version that had hardcoded factions) would be locked to
-- nobody. Cleared once the map's DoorTable has loaded. Deferred a tick so
-- the door system's own InitPostEntity loader has run first.
hook.Add("InitPostEntity", "pdcity_ReconcileDoorFactions", function()
	timer.Simple(0, function()
		if not istable(DoorTable) then return end

		local orphaned = {}
		for index, id in pairs(DoorTable) do
			if isnumber(id) and id > PDCity.DOOR_FACTION_ID_BASE and not PDCity.DOOR_FACTIONS[id] then
				if loadedCleanly then
					table.insert(orphaned, index)
				else
					nextFactionID = math.max(nextFactionID, id + 1)
				end
			end
		end

		if #orphaned == 0 then return end

		for _, index in ipairs(orphaned) do
			RemoveDoorRestriction(index)
		end
		LoadDoorTable(true)

		print("[" .. PDCity.BRAND_TAG .. "] Cleared " .. #orphaned .. " door(s) assigned to factions that no longer exist.")
	end)
end)

--[[---------------------------------------------------------
	Door assignment - used by the Door Faction tool
-----------------------------------------------------------]]

-- Wipes any personal owner/co-owners so the faction check is the only
-- thing that decides access. AddDoorRestriction doesn't sync clients
-- itself, so co-owners and DoorTable are re-broadcast here.
function PDCity.SetDoorFaction(door, factionID)
	if not PDCity.DOOR_FACTIONS[factionID] then return false end

	local index = door:MapCreationID()

	AddDoorRestriction(index, factionID)
	door:SetNWEntity("DoorOwner", NULL)
	door:SetNWString("DoorName", "")
	DoorCoOwners[index] = nil

	net.Start("SyncCoOwnerClient")
	DS_WriteCoOwners(DoorCoOwners)
	net.Broadcast()

	LoadDoorTable(true)

	return true
end

function PDCity.ClearDoorFaction(door)
	RemoveDoorRestriction(door:MapCreationID())
	LoadDoorTable(true)
end

-- Name of whatever restriction the door has (faction or the door system's own
-- Admin Only etc.), or nil if unassigned.
function PDCity.GetDoorFaction(door)
	local restrictionID = DoorTable[door:MapCreationID()]
	local restriction = restrictionID and DoorRestrictions[restrictionID]
	return restriction and restriction.Name
end

--[[---------------------------------------------------------
	Site Admin actions
-----------------------------------------------------------]]

-- Returns the cleaned name, or nil + an error message.
local function ValidateName(name, ignoreID)
	if not isstring(name) then return nil, "Faction name can't be empty." end

	name = string.Trim(name)
	if name == "" then return nil, "Faction name can't be empty." end
	if #name > NAME_MAX_LENGTH then return nil, "Faction names can be at most " .. NAME_MAX_LENGTH .. " characters." end

	local lower = string.lower(name)
	for id, faction in pairs(PDCity.DOOR_FACTIONS) do
		if id ~= ignoreID and string.lower(faction.Name) == lower then
			return nil, "A faction called \"" .. faction.Name .. "\" already exists."
		end
	end

	return name
end

local Actions = {}

function Actions.create(ply, p)
	local name, err = ValidateName(p.Name)
	if not name then return false, err end

	local id = nextFactionID
	nextFactionID = nextFactionID + 1

	PDCity.DOOR_FACTIONS[id] = { ID = id, Name = name, Sections = {} }
	return true, "created door faction \"" .. name .. "\""
end

function Actions.rename(ply, p)
	local id = tonumber(p.ID)
	local faction = id and PDCity.DOOR_FACTIONS[id]
	if not faction then return false, "That faction no longer exists." end

	local name, err = ValidateName(p.Name, id)
	if not name then return false, err end

	local oldName = faction.Name
	faction.Name = name
	return true, "renamed door faction \"" .. oldName .. "\" to \"" .. name .. "\""
end

function Actions.delete(ply, p)
	local id = tonumber(p.ID)
	local faction = id and PDCity.DOOR_FACTIONS[id]
	if not faction then return false, "That faction no longer exists." end

	-- Doors must be cleared too, or every client would be holding a
	-- DoorTable entry pointing at a restriction that no longer exists.
	local doors = DoorsInFaction(id)
	for _, index in ipairs(doors) do
		RemoveDoorRestriction(index)
	end
	if #doors > 0 then LoadDoorTable(true) end

	PDCity.DOOR_FACTIONS[id] = nil
	return true, "deleted door faction \"" .. faction.Name .. "\" (cleared from " .. #doors .. " door(s))"
end

function Actions.set_section(ply, p)
	local id = tonumber(p.ID)
	local faction = id and PDCity.DOOR_FACTIONS[id]
	if not faction then return false, "That faction no longer exists." end
	if not isstring(p.Section) or p.Section == "" then return false, "Pick a category." end

	if p.Enabled then
		if not table.HasValue(PDCity.SECTIONS, p.Section) then return false, "That category doesn't exist." end
		faction.Sections[p.Section] = true
	else
		faction.Sections[p.Section] = nil
	end

	return true, (p.Enabled and "added" or "removed") .. " category \"" .. p.Section .. "\" "
		.. (p.Enabled and "to" or "from") .. " door faction \"" .. faction.Name .. "\""
end

net.Receive("pdcity_door_factions_admin", function(len, ply)
	if not IsValid(ply) or not PDCity.IsOwner(ply) then return end
	if len > 65530 then return end

	local data = util.JSONToTable(net.ReadString() or "")
	if not istable(data) or not isstring(data.Action) then return end

	local handler = Actions[data.Action]
	if not handler then return end

	local ok, result = handler(ply, data)
	if not ok then
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] " .. (result or "That action failed."))
		return
	end

	PDCity.RegisterDoorFactions()
	SaveFactions()
	BroadcastFactions()

	PDCity.GameLog("doors", ply:Nick() .. " (" .. ply:SteamID() .. ") " .. result)
end)
