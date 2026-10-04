--[[---------------------------------------------------------
	Owner/superadmin tool for managing the prop model whitelist/blacklist
	(core/sv_restrictions.lua) - the owner and superadmins bypass the
	whole check regardless (PDCity.CanSpawnFromMenu, core/sh_permissions.lua)
	and can already spawn whatever they want without touching this tool
	at all; it's for managing what everyone ELSE can spawn. Aim at any
	prop:

	  Left click   - blacklist its model (always blocked, regardless of
	                 mode below)
	  Right click  - whitelist its model (always allowed, regardless of
	                 mode below)

	What a model with NEITHER override does depends on the owner-
	toggleable mode (core/sh_prop_filter.lua, F1 Site Admin's "Prop
	Filter" tab): "whitelist" mode blocks it, "blacklist" mode allows
	it. Same two clicks either way - only the untouched default flips.

	Overrides persist in data/pdcity/prop_overrides.json. Everyone else
	sees the tool in the menu but every click is rejected server-side.
-----------------------------------------------------------]]

TOOL.Category = "PD Roleplay"
TOOL.Name = "#tool.pdcity_propfilter.name"

TOOL.Information = {
	{ name = "left" },
	{ name = "right" },
}

if CLIENT then
	language.Add("tool.pdcity_propfilter.name", "Prop Filter (Owner/Superadmin)")
	language.Add("tool.pdcity_propfilter.desc", "Whitelist or blacklist specific prop models")
	language.Add("tool.pdcity_propfilter.left", "Blacklist this model")
	language.Add("tool.pdcity_propfilter.right", "Whitelist this model")
end

local function GetTargetModel(trace)
	local ent = trace.Entity
	if not IsValid(ent) or ent:IsPlayer() then return nil end
	local model = ent:GetModel()
	if not model or model == "" then return nil end
	return model
end

local function ApplyOverride(tool, trace, state)
	local ply = tool:GetOwner()
	if not PDCity.CanSpawnFromMenu(ply) then
		if SERVER then ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Only the server owner or superadmins can use the Prop Filter tool.") end
		return false
	end

	local model = GetTargetModel(trace)
	if not model then return false end

	if CLIENT then return true end

	PDCity.SetPropOverride(model, state)

	PDCity.GameLog("staff", ply:Nick() .. " (" .. ply:SteamID() .. ") set prop override for "
		.. model .. " to: " .. state)

	if state == "blacklist" then
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] BLACKLISTED: " .. model)
	else
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Whitelisted: " .. model)
	end

	return true
end

function TOOL:LeftClick(trace)
	return ApplyOverride(self, trace, "blacklist")
end

function TOOL:RightClick(trace)
	return ApplyOverride(self, trace, "whitelist")
end

function TOOL.BuildCPanel(panel)
	-- Reflects the CURRENT mode (core/sh_prop_filter.lua) at the moment
	-- the panel is built, rather than a static string that would go
	-- stale the moment an owner flips it via F1 Site Admin - this panel
	-- gets rebuilt fresh every time the Q menu's tool list is opened, so
	-- there's nothing to keep in sync after the fact.
	local modeText = (PDCity.PROP_FILTER_MODE == "blacklist")
		and "Right now, anything with NO override is spawnable by default - left click blacklists a model to block it."
		or "Right now, anything with NO override is blocked by default - right click whitelists a model to allow it."

	panel:AddControl("Header", {
		Description = "Owner/superadmin only. Left click a prop to blacklist its model (always blocked), right click to whitelist it (always allowed). " .. modeText .. " Changes save immediately and survive restarts.",
	})
end
