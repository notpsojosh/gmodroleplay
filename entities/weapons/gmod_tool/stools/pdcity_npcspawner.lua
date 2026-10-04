--[[---------------------------------------------------------
	Owner-only tool for permanently placing PD City's own custom NPCs
	(core/sh_npc_classes.lua) - never stock HL2/CSS NPCs, only entities
	built for this gamemode. Placements persist across restarts (see
	core/sv_npc_spawns.lua).

	  Left click   - place the selected NPC type here
	  Right click  - remove the NPC you're looking at (if it's one of ours)

	"Remove ALL" used to be Reload (R) - moved to the console command
	"pdcity_clearnpcs confirm" (core/sv_npc_spawns.lua) since R is
	GMod's default reload bind and far too easy to hit by accident.
-----------------------------------------------------------]]

TOOL.Category = "PD Roleplay"
TOOL.Name = "#tool.pdcity_npcspawner.name"

TOOL.ClientConVar = {
	["class"] = PDCity.NPC_CLASSES and PDCity.NPC_CLASSES[1] and PDCity.NPC_CLASSES[1].Class or "",
}

TOOL.Information = {
	{ name = "left" },
	{ name = "right" },
}

if CLIENT then
	language.Add("tool.pdcity_npcspawner.name", "NPC Spawner (Owner)")
	language.Add("tool.pdcity_npcspawner.desc", "Permanently place or remove PD City's own custom NPCs")
	language.Add("tool.pdcity_npcspawner.left", "Place the selected NPC here (persists across restarts)")
	language.Add("tool.pdcity_npcspawner.right", "Remove the NPC you're looking at")
end

local function CheckOwner(tool)
	local ply = tool:GetOwner()
	if PDCity.IsOwner(ply) then return true end
	if SERVER then ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Only the server owner can use the NPC Spawner tool.") end
	return false
end

local function IsKnownClass(class)
	for _, entry in ipairs(PDCity.GetAllNPCClasses()) do
		if entry.Class == class then return true end
	end
	return false
end

function TOOL:LeftClick(trace)
	if not CheckOwner(self) then return false end
	if not trace.Hit then return false end
	if CLIENT then return true end

	local ply = self:GetOwner()
	local class = self:GetClientInfo("class")

	if not IsKnownClass(class) then
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Unknown NPC type selected.")
		return false
	end

	local pos = trace.HitPos + trace.HitNormal * 2
	local ang = Angle(0, ply:EyeAngles().y + 180, 0)

	local ent = PDCity.SpawnManagedNPC(class, pos, ang)
	if not IsValid(ent) then
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Failed to spawn that NPC.")
		return false
	end

	ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Placed permanently (" .. PDCity.CountNPCSpawns() .. " total on this map).")
	return true
end

function TOOL:RightClick(trace)
	if not CheckOwner(self) then return false end
	if CLIENT then return true end

	local ply = self:GetOwner()
	local target = trace.Entity

	if not IsValid(target) then return false end

	-- Managed NPC placed by this tool - remove and clean up persistence
	if target.pdcity_NPCSpawnID then
		PDCity.RemoveManagedNPC(target.pdcity_NPCSpawnID)
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Removed (" .. PDCity.CountNPCSpawns() .. " left on this map).")
		return true
	end

	-- Not managed but still one of our own entity classes (e.g. spawned
	-- from the Q menu Entities tab) - remove it directly
	if IsKnownClass(target:GetClass()) then
		target:Remove()
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Removed entity.")
		return true
	end

	ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] That's not one of " .. PDCity.BRAND_NAME .. "'s managed NPCs.")
	return true
end

function TOOL.BuildCPanel(panel)

	panel:AddControl("Header", {
		Description = "Owner-only. Left click to permanently place the selected NPC (survives server restarts). Right click a placed NPC to remove it. Only " .. PDCity.BRAND_NAME .. "'s own custom NPCs can be placed this way. To remove ALL of them, run \"pdcity_clearnpcs confirm\" in console.",
	})

	local combo = panel:ComboBox("NPC Type", "pdcity_npcspawner_class")
	for _, entry in ipairs(PDCity.GetAllNPCClasses()) do
		combo:AddChoice(entry.Name, entry.Class)
	end

end
