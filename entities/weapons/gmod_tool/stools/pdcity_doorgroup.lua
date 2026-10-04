--[[---------------------------------------------------------
	Owner-only tool for tying doors together into a group (persisted,
	core/sv_door_groups.lua) so buying/co-owning ONE door in a building/
	apartment grants the same on every other door in it - built on top of
	the door system's OWN native door-group support (DoorGroups,
	normally only hand-edited in gamemode/doors/
	doors_config.lua) rather than a separate system: sv_door_groups.lua
	populates that same global from a persisted per-map file, so buying/
	selling a grouped door already propagates through the door system's own
	unmodified OwnDoor/UnownDoor logic. Co-owners don't natively cascade
	across a group (the door system tracks those per-door, group-unaware) -
	sv_door_groups.lua also replaces its SyncCoOwner net handler to fix
	that specifically.

	Building a group takes a few clicks, since it's more than one door:

	  Left click   - add the aimed door to the group you're building.
	                 The FIRST door clicked becomes the parent (the one
	                 that has to actually be bought); every door after
	                 that is added as a child.
	  Reload (R)   - finish and save the group you're building (need at
	                 least one child added first). Clears the in-progress
	                 state either way, ready to start a new group.
	  Right click  - disband whichever EXISTING saved group the aimed
	                 door belongs to (parent or any child) - not part of
	                 building a new one, this is independent/immediate.
	                 Doesn't touch who currently owns any of those doors,
	                 just un-links them going forward.
-----------------------------------------------------------]]

TOOL.Category = "PD Roleplay"
TOOL.Name = "#tool.pdcity_doorgroup.name"

TOOL.Information = {
	{ name = "left" },
	{ name = "right" },
	{ name = "reload" },
}

if CLIENT then
	language.Add("tool.pdcity_doorgroup.name", "Door Group (Owner/Superadmin)")
	language.Add("tool.pdcity_doorgroup.desc", "Tie doors together so buying/co-owning one grants all of them")
	language.Add("tool.pdcity_doorgroup.left", "Add this door to the group being built")
	language.Add("tool.pdcity_doorgroup.right", "Disband this door's existing group")
	language.Add("tool.pdcity_doorgroup.reload", "Finish and save the group being built")
end

-- the door system identifies doors by class rather than a dedicated flag -
-- same check its own weapon_keys/menu code uses (sh_doors.lua).
local DOOR_CLASSES = {
	["func_door"] = true,
	["func_door_rotating"] = true,
	["prop_door_rotating"] = true,
}

local function IsDoor(ent)
	return IsValid(ent) and DOOR_CLASSES[ent:GetClass()] == true
end

function TOOL:LeftClick(trace)
	local ply = self:GetOwner()
	if not PDCity.CanSpawnFromMenu(ply) then
		if SERVER then ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Only the server owner or superadmins can use the Door Group tool.") end
		return false
	end

	local door = trace.Entity
	if not IsDoor(door) then return false end

	if CLIENT then return true end

	local index = door:MapCreationID()
	if index < 0 then
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] That door isn't part of the map - can't group it.")
		return false
	end

	self.PDCityGroupParent = self.PDCityGroupParent or index
	self.PDCityGroupChildren = self.PDCityGroupChildren or {}

	if index == self.PDCityGroupParent then
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] That's already the parent door of the group you're building.")
		return true
	end

	if table.HasValue(self.PDCityGroupChildren, index) then
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Already added.")
		return true
	end

	table.insert(self.PDCityGroupChildren, index)
	ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Added - " .. #self.PDCityGroupChildren .. " door(s) linked to this group so far. Reload to save, or keep left-clicking to add more.")

	return true
end

function TOOL:RightClick(trace)
	local ply = self:GetOwner()
	if not PDCity.CanSpawnFromMenu(ply) then
		if SERVER then ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Only the server owner or superadmins can use the Door Group tool.") end
		return false
	end

	local door = trace.Entity
	if not IsDoor(door) then return false end

	if CLIENT then return true end

	local index = door:MapCreationID()
	if index < 0 or not PDCity.RemoveDoorGroup(index) then
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] That door isn't part of any saved group.")
		return false
	end

	ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Disbanded that door's group - existing owners are unaffected, they just no longer share access.")
	return true
end

function TOOL:Reload(trace)
	local ply = self:GetOwner()
	if not PDCity.CanSpawnFromMenu(ply) then
		if SERVER then ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Only the server owner or superadmins can use the Door Group tool.") end
		return false
	end

	if CLIENT then return true end

	local parent = self.PDCityGroupParent
	local children = self.PDCityGroupChildren

	self.PDCityGroupParent = nil
	self.PDCityGroupChildren = nil

	if not parent or not children or #children == 0 then
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Nothing to save - left-click a parent door and at least one other door first.")
		return false
	end

	PDCity.AddDoorGroup(parent, children)
	ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Saved: buying or co-owning the parent door now also grants " .. #children .. " other door(s).")

	return true
end

function TOOL.BuildCPanel(panel)
	panel:AddControl("Header", {
		Description = "Owner/superadmin only. Left click a door to start a group (first door = parent, the one that has to be bought), then left click every other door in the same building to link them. Reload to save. Right click any door in an existing group to disband it.",
	})
end
