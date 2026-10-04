--[[---------------------------------------------------------
	Owner-only tool for permanently assigning a door to a job faction
	(core/sv_door_factions.lua). Pick a faction in the tool's Q-menu
	panel, then aim at any door:

	  Left click        - assign the door to the selected faction
	  Right click       - report the door's current assignment (no change)
	  Shift+right click - clear the door's faction assignment

	Clearing used to be Reload (R) - moved to shift+right-click since R
	is GMod's default reload bind and far too easy to hit by accident;
	shift+right-click needs a deliberate two-part gesture instead.

	Once assigned, only players on a job in that faction can lock/unlock
	the door (via weapon_keys), and it can no longer be bought, sold, or
	F2-claimed by an individual player. Non-owners see the tool in the
	menu but every click is rejected server-side.
-----------------------------------------------------------]]

TOOL.Category = "PD Roleplay"
TOOL.Name = "#tool.pdcity_doorfaction.name"

-- Faction ID (core/sh_door_factions.lua), not name - "0" means none picked.
TOOL.ClientConVar = {
	["faction"] = "0",
}

TOOL.Information = {
	{ name = "left" },
	{ name = "right" },
}

if CLIENT then
	language.Add("tool.pdcity_doorfaction.name", "Door Faction (Owner)")
	language.Add("tool.pdcity_doorfaction.desc", "Permanently assign a door to a job faction")
	language.Add("tool.pdcity_doorfaction.left", "Assign door to the selected faction")
	language.Add("tool.pdcity_doorfaction.right", "Check the door's current assignment (shift+right click clears it)")
end

local function GetTargetDoor(trace, tool)
	local ent = trace.Entity

	if not IsValid(ent) then
		if SERVER then tool:GetOwner():ChatPrint("[" .. PDCity.BRAND_TAG .. "] Not looking at anything (trace hit nothing).") end
		return nil
	end

	if not IsValidDoor(ent) then
		if SERVER then
			tool:GetOwner():ChatPrint("[" .. PDCity.BRAND_TAG .. "] Not a recognized door - hit entity class: " .. ent:GetClass())
		end
		return nil
	end

	return ent
end

local function CheckOwner(tool)
	local ply = tool:GetOwner()
	if PDCity.IsOwner(ply) then return true end
	if SERVER then ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Only the server owner can use the Door Faction tool.") end
	return false
end

function TOOL:LeftClick(trace)
	if not CheckOwner(self) then return false end

	local door = GetTargetDoor(trace, self)
	if not door then return false end

	if CLIENT then return true end

	local ply = self:GetOwner()
	local ok, err = pcall(function()
		local factionID = tonumber(self:GetClientInfo("faction"))
		local faction = factionID and PDCity.GetDoorFactionByID(factionID)

		if not faction then
			ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] No faction selected. Create one in F1 > Site Admin > Door Factions, then pick it in this tool's Q-menu panel.")
			return
		end

		PDCity.SetDoorFaction(door, factionID)

		PDCity.GameLog("doors", ply:Nick() .. " (" .. ply:SteamID() .. ") assigned door #"
			.. door:MapCreationID() .. " to faction: " .. faction.Name)

		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] This door is now permanently owned by: " .. faction.Name)
	end)

	if not ok then
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] ERROR: " .. tostring(err))
		print("[" .. PDCity.BRAND_TAG .. "] Door Faction tool LeftClick error: " .. tostring(err))
	end

	return true
end

function TOOL:RightClick(trace)
	if not CheckOwner(self) then return false end

	local door = GetTargetDoor(trace, self)
	if not door then return false end

	if CLIENT then return true end

	local ply = self:GetOwner()

	-- Shift+right-click clears the assignment - a deliberate two-part
	-- gesture. This used to be Reload (R), but that's GMod's default
	-- reload bind and far too easy to hit by muscle memory, instantly
	-- wiping an assignment with a single accidental keypress.
	if ply:KeyDown(IN_SPEED) then
		local ok, err = pcall(function()
			PDCity.ClearDoorFaction(door)
			ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Cleared this door's faction assignment.")
		end)

		if not ok then
			ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] ERROR: " .. tostring(err))
			print("[" .. PDCity.BRAND_TAG .. "] Door Faction tool clear error: " .. tostring(err))
		end

		return true
	end

	local ok, err = pcall(function()
		local faction = PDCity.GetDoorFaction(door)

		if faction then
			ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] This door belongs to faction: " .. faction)
		else
			local owner = door:GetNWEntity("DoorOwner")
			if IsValid(owner) then
				ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] This door is personally owned by " .. owner:Nick() .. ".")
			else
				ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] This door has no faction or personal owner.")
			end
		end
	end)

	if not ok then
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] ERROR: " .. tostring(err))
		print("[" .. PDCity.BRAND_TAG .. "] Door Faction tool RightClick error: " .. tostring(err))
	end

	return true
end

function TOOL.BuildCPanel(panel)

	panel:AddControl("Header", {
		Description = "Owner-only. Pick a faction, then left click a door to permanently assign it - only players on a job in that faction can lock/unlock it, and it can no longer be bought or claimed by an individual player. Right click checks a door's current assignment; shift+right click clears it.",
	})

	-- A plain DComboBox rather than panel:ComboBox - that one binds the
	-- convar to the box's display text, which would show the raw faction
	-- ID instead of its name.
	local combo = vgui.Create("DComboBox", panel)
	combo:SetTall(22)
	panel:AddItem(combo)

	combo.OnSelect = function(self, index, value, data)
		RunConsoleCommand("pdcity_doorfaction_faction", tostring(data))
	end

	local function Fill()
		combo:Clear()

		local convar = GetConVar("pdcity_doorfaction_faction")
		local current = convar and convar:GetInt() or 0
		local factions = PDCity.GetSortedDoorFactions()
		local found = false

		for _, faction in ipairs(factions) do
			local isCurrent = faction.ID == current
			combo:AddChoice(faction.Name, faction.ID, isCurrent)
			found = found or isCurrent
		end

		if #factions == 0 then
			combo:SetValue("No factions yet - create one in F1 > Site Admin")
		elseif not found then
			combo:SetValue("Select a faction")
		end
	end
	Fill()

	hook.Add("PDCity_DoorFactionsUpdated", combo, function() Fill() end)

end
