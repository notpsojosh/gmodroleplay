--[[---------------------------------------------------------
	Owner-only tool: point at any entity in the world and left-click to
	whitelist its class for inventory pickup (core/sh_inventory.lua's
	PDCity.INVENTORY_ALLOWED, the same list the F4 admin editor's
	"Inventory Items" tab manages) - right-click removes it again. Both
	call PDCity.SetInventoryWhitelist (core/sv_inventory.lua) directly -
	a tool's LeftClick/RightClick already runs server-side with the owner
	and traced entity both in hand, no networking needed for the mutation
	itself. Purely a faster, aim-at-it alternative to hunting the class
	down in that tab's list - not a second, separate whitelist.
-----------------------------------------------------------]]

TOOL.Category = "PD Roleplay"
TOOL.Name = "#tool.pdcity_invwhitelist.name"

TOOL.Information = {
	{ name = "left" },
	{ name = "right" },
}

if CLIENT then
	language.Add("tool.pdcity_invwhitelist.name", "Inventory Whitelist (Owner)")
	language.Add("tool.pdcity_invwhitelist.desc", "Whitelist or remove an entity's class for inventory pickup")
	language.Add("tool.pdcity_invwhitelist.left", "Whitelist the entity you're looking at for inventory pickup")
	language.Add("tool.pdcity_invwhitelist.right", "Remove the entity you're looking at from inventory pickup")
end

local function CheckOwner(tool)
	local ply = tool:GetOwner()
	if PDCity.IsOwner(ply) then return true end
	if SERVER then ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Only the server owner can use the Inventory Whitelist tool.") end
	return false
end

local function ApplyToTraced(tool, trace, action)
	if not CheckOwner(tool) then return false end

	local ent = trace.Entity
	if not IsValid(ent) or ent:IsWorld() or ent:IsPlayer() then
		if SERVER then tool:GetOwner():ChatPrint("[" .. PDCity.BRAND_TAG .. "] Aim at an entity first.") end
		return false
	end

	if SERVER then
		local class = ent:GetClass()
		local ok, err = PDCity.SetInventoryWhitelist(action, class)
		local ply = tool:GetOwner()

		if ok then
			ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] "
				.. (action == "add" and "Whitelisted " or "Removed ") .. class
				.. (action == "add" and " for inventory pickup." or " from inventory pickup."))
		else
			ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] " .. (err or "That action failed."))
		end
	end

	return true
end

function TOOL:LeftClick(trace)
	return ApplyToTraced(self, trace, "add")
end

function TOOL:RightClick(trace)
	return ApplyToTraced(self, trace, "remove")
end

function TOOL.BuildCPanel(panel)
	panel:AddControl("Header", {
		Description = "Owner-only. Left click any entity to whitelist its class for inventory pickup (CTRL+E). Right click to remove it again. Same whitelist as the F4 admin editor's \"Inventory Items\" tab - this is just a faster way to add/remove it while looking straight at it.",
	})
end
