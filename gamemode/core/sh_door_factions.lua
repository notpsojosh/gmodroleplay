--[[---------------------------------------------------------
	Job-faction door ownership - built on the door system's OWN
	"managed by a group" mechanism (DoorRestrictions + DoorTable, see
	gamemode/doors/sh_config.lua and sv_doors.lua). A
	door with a DoorTable entry can only be locked/unlocked by players
	passing DoorRestrictions[id].CheckFunction, and can't be bought/sold/
	F2-claimed by an individual player.

	Factions are created in-game only (F1 > Site Admin > Door Factions,
	core/sv_door_factions.lua) - none ship by default. Membership is:
	  - every job whose category (Section) is ticked on the faction, plus
	  - every job that ticks the faction itself (F4 > Jobs, job.DoorFactions)

	Each faction's ID is what's saved per door in data/doorsystem/<map>.json,
	so IDs are handed out once and never reused (see sv_door_factions.lua).
	IDs start above PDCity.DOOR_FACTION_ID_BASE so they never collide with
	the door system's own built-in restrictions (1 = Admin Only, 2 = Superadmin).

	Must be SHARED: the door system's client HUD (cl_doors.lua) reads
	DoorRestrictions[id].Name every frame.
-----------------------------------------------------------]]

DoorRestrictions = DoorRestrictions or {}

PDCity.DOOR_FACTION_ID_BASE = 100

-- [id] = { ID = id, Name = "...", Sections = { [sectionName] = true } }
PDCity.DOOR_FACTIONS = PDCity.DOOR_FACTIONS or {}

function PDCity.GetDoorFactionByID(id)
	return PDCity.DOOR_FACTIONS[id]
end

function PDCity.GetSortedDoorFactions()
	local list = {}
	for _, faction in pairs(PDCity.DOOR_FACTIONS) do
		table.insert(list, faction)
	end
	table.sort(list, function(a, b) return a.ID < b.ID end)
	return list
end

function PDCity.JobInDoorFaction(job, factionID)
	if not job then return false end

	local faction = PDCity.DOOR_FACTIONS[factionID]
	if not faction then return false end

	if job.Section and faction.Sections[job.Section] then return true end

	for _, id in ipairs(job.DoorFactions or {}) do
		if id == factionID then return true end
	end

	return false
end

-- Keeps DoorRestrictions in step with PDCity.DOOR_FACTIONS: drops entries
-- for deleted factions, (re)creates one per existing faction. The
-- CheckFunction looks the faction up by ID at call time, so renames and
-- membership changes take effect without re-registering.
function PDCity.RegisterDoorFactions()
	for id in pairs(DoorRestrictions) do
		if id > PDCity.DOOR_FACTION_ID_BASE and not PDCity.DOOR_FACTIONS[id] then
			DoorRestrictions[id] = nil
		end
	end

	for id, faction in pairs(PDCity.DOOR_FACTIONS) do
		DoorRestrictions[id] = {
			Name = faction.Name,
			CheckFunction = function(ply)
				return PDCity.JobInDoorFaction(PDCity.GetJob(ply:Team()), id)
			end,
		}
	end
end

-- JSON shape (saved file + network sync) is a plain array of factions,
-- since JSON object keys would turn the numeric IDs into strings.
function PDCity.EncodeDoorFactions()
	local list = {}
	for _, faction in ipairs(PDCity.GetSortedDoorFactions()) do
		table.insert(list, { ID = faction.ID, Name = faction.Name, Sections = faction.Sections })
	end
	return list
end

function PDCity.DecodeDoorFactions(list)
	local out = {}
	if not istable(list) then return out end

	for _, entry in ipairs(list) do
		local id = istable(entry) and tonumber(entry.ID)
		if id and id > PDCity.DOOR_FACTION_ID_BASE and isstring(entry.Name) then
			out[id] = {
				ID = id,
				Name = entry.Name,
				Sections = istable(entry.Sections) and entry.Sections or {},
			}
		end
	end

	return out
end

if CLIENT then

	net.Receive("pdcity_door_factions_sync", function()
		local data = util.JSONToTable(net.ReadString() or "")
		if not istable(data) then return end

		PDCity.DOOR_FACTIONS = PDCity.DecodeDoorFactions(data)
		PDCity.RegisterDoorFactions()

		hook.Run("PDCity_DoorFactionsUpdated")
		hook.Run("PDCity_SiteContentUpdated")
	end)

end
