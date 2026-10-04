-- core/sv_restrictions.lua

--[[---------------------------------------------------------
	Falco's Prop Protection (FPP) hooks CanTool itself and denies any
	toolgun click on an entity it has no computed "touch rights" for -
	which includes every map-placed entity (doors included), since FPP
	only ever computes touch rights for player-spawned props. That
	denial happens in FPP's own hook.Add("CanTool", ...) callback, which
	runs (and can short-circuit) BEFORE the gamemode's own CanTool and
	before the toolgun ever calls TOOL:LeftClick - so without this, our
	owner-only admin tools (Door Faction, Prop Filter) silently never
	fire on any map-placed door, no matter what their own code does.

	These two tools manage server administration, not player builds -
	prop protection was never meant to gate them, so they're exempted
	outright rather than trying to grant them "ownership" of every map
	entity through FPP's own system. HOOK_HIGH makes sure this runs (and
	can return before) FPP's hook, which registers at normal priority.
-----------------------------------------------------------]]

local PDCITY_ADMIN_TOOL_MODES = {
	["pdcity_doorfaction"] = true,
	["pdcity_doorgroup"] = true,
	["pdcity_propfilter"] = true,
	["pdcity_jailspawn"] = true,
	["pdcity_npcspawner"] = true,
	["pdcity_propcopier"] = true,
	["pdcity_invwhitelist"] = true,
	["pdcity_spawnpoint"] = true,
	["pdcity_staffjailspot"] = true,
}

-- PDCity.CanSpawnFromMenu (owner or superadmin), not PDCity.IsOwner -
-- Prop Filter now allows superadmins too; the other tools here still
-- gate themselves to owner-only internally, so this is harmlessly wider
-- than what those actually let through.
hook.Add("CanTool", "pdcity_BypassProtectionForAdminTools", function(ply, trace, mode)
	if PDCITY_ADMIN_TOOL_MODES[mode] and PDCity.CanSpawnFromMenu(ply) then
		return true
	end
end, HOOK_HIGH)

--[[---------------------------------------------------------
	Only the server owner or superadmins may spawn entities from
	the Q menu (props, weapons, SENTs, NPCs, vehicles, effects,
	ragdolls).  Doesn't affect job loadouts (Player:Give() is a
	different code path), the garage system, the F4 shop, or the
	car dealer — all of those go through their own spawn paths.
-----------------------------------------------------------]]

hook.Add("PlayerSpawnSWEP", "pdcity_RestrictSWEPSpawning", function(ply, wname, wtable)
	if PDCity.CanSpawnFromMenu(ply) then return end
	ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Only the server owner or superadmins can spawn from the Q menu.")
	return false
end)

hook.Add("PlayerGiveSWEP", "pdcity_RestrictSWEPGiving", function(ply, wname, wtable)
	if PDCity.CanSpawnFromMenu(ply) then return end
	ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Only the server owner or superadmins can give themselves weapons.")
	return false
end)

--[[---------------------------------------------------------
	Prop model whitelist. Strict whitelist-only: nothing spawns unless
	its exact model path has been explicitly whitelisted (below) with
	the owner-only "Prop Filter" toolgun tool
	(entities/weapons/gmod_tool/stools/pdcity_propfilter.lua).

	Blacklist still exists as an explicit "never, no matter what" - not
	that it can currently conflict with anything (PDCity.SetPropOverride
	only ever has one of the two set for a given model), but it's a
	one-line safety net in case prop_overrides.json is ever hand-edited
	into an inconsistent state.

	Enforced on two hooks:
	  PlayerSpawnObject - the Q-menu spawn path (commands.lua)
	  PlayerSpawnProp   - fired per-prop by BOTH the Q-menu path and
	                      AdvDupe2's MakeProp (sv_clipboard.lua line
	                      ~896), so pasted dupes can't smuggle in
	                      off-whitelist props either
-----------------------------------------------------------]]

--[[---------------------------------------------------------
	Per-model overrides, managed in-game with the owner-only "Prop
	Filter" toolgun tool (entities/weapons/gmod_tool/stools/pdcity_propfilter.lua).

	Persisted to data/pdcity/prop_overrides.json across restarts.
-----------------------------------------------------------]]

local OVERRIDES_PATH = "pdcity/prop_overrides.json"

local PropOverrides = { Blacklist = {}, Whitelist = {} }

local function SaveOverrides()
	file.CreateDir("pdcity")
	file.Write(OVERRIDES_PATH, util.TableToJSON({
		Blacklist = PropOverrides.Blacklist,
		Whitelist = PropOverrides.Whitelist,
		Mode = PDCity.PROP_FILTER_MODE,
	}, true))
end

do
	local raw = file.Read(OVERRIDES_PATH, "DATA")
	local stored = raw and util.JSONToTable(raw)
	if stored then
		PropOverrides.Blacklist = stored.Blacklist or {}
		PropOverrides.Whitelist = stored.Whitelist or {}
		if stored.Mode == "whitelist" or stored.Mode == "blacklist" then
			PDCity.PROP_FILTER_MODE = stored.Mode
		end
	end

	-- One-time cleanup for any model that ended up on both lists before
	-- PDCity.SetPropOverride below always kept them mutually exclusive
	-- (e.g. a hand-edit of prop_overrides.json). Blacklist wins ties -
	-- CheckPropModel already checks it first, so a duplicate was already
	-- being treated as blacklisted; this just makes the file match that.
	local dirty = false
	for model in pairs(PropOverrides.Blacklist) do
		if PropOverrides.Whitelist[model] then
			PropOverrides.Whitelist[model] = nil
			dirty = true
		end
	end

	if dirty then SaveOverrides() end
end

-- state: "blacklist", "whitelist", or nil to clear the model's override.
-- Always keeps the two lists mutually exclusive - setting a model to one
-- state removes it from the other outright, so the Prop Filter tool can
-- never leave a model on both (whitelisting something blacklisted un-
-- blacklists it, and vice versa).
-- Returns the state that now applies, for feedback.
function PDCity.SetPropOverride(model, state)
	model = string.lower(model or "")
	if model == "" then return end

	PropOverrides.Blacklist[model] = (state == "blacklist") or nil
	PropOverrides.Whitelist[model] = (state == "whitelist") or nil

	SaveOverrides()

	return state
end

function PDCity.GetPropOverride(model)
	model = string.lower(model or "")
	if PropOverrides.Blacklist[model] then return "blacklist" end
	if PropOverrides.Whitelist[model] then return "whitelist" end
end

--[[---------------------------------------------------------
	Owner-toggleable default direction (core/sh_prop_filter.lua) - F1
	Site Admin's "Prop Filter" tab.
-----------------------------------------------------------]]
util.AddNetworkString("pdcity_prop_filter_sync")
util.AddNetworkString("pdcity_prop_filter_mode_admin")

local function BroadcastPropFilterMode(ply)
	net.Start("pdcity_prop_filter_sync")
		net.WriteString(PDCity.PROP_FILTER_MODE)
	if IsValid(ply) then
		net.Send(ply)
	else
		net.Broadcast()
	end
end

hook.Add("PlayerInitialSpawn", "pdcity_SyncPropFilterMode", function(ply)
	timer.Simple(1, function()
		if IsValid(ply) then BroadcastPropFilterMode(ply) end
	end)
end)

net.Receive("pdcity_prop_filter_mode_admin", function(len, ply)
	if not IsValid(ply) or not PDCity.IsOwner(ply) then return end

	local mode = net.ReadString()
	if mode ~= "whitelist" and mode ~= "blacklist" then return end

	PDCity.PROP_FILTER_MODE = mode
	PDCity.GameLog("staff", ply:Nick() .. " (" .. ply:SteamID() .. ") set the prop filter mode to " .. mode)
	SaveOverrides()
	BroadcastPropFilterMode()
end)

local function CheckPropModel(ply, model)
	if PDCity.CanSpawnFromMenu(ply) then return end

	local override = PDCity.GetPropOverride(model)

	if override == "blacklist" then
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] That prop is blacklisted.")
		return false
	end

	if override == "whitelist" then return end

	-- No override either way - "whitelist" mode denies by default,
	-- "blacklist" mode allows by default (core/sh_prop_filter.lua).
	if PDCity.PROP_FILTER_MODE == "blacklist" then return end

	ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Only the server owner or superadmins can spawn props.")
	return false
end

hook.Add("PlayerSpawnObject", "pdcity_RestrictPropModels", CheckPropModel)
hook.Add("PlayerSpawnProp", "pdcity_RestrictPropModelsDupe", CheckPropModel)

--[[---------------------------------------------------------
	Same problem as the CanTool bypass above, on different hooks.
	Falco's Prop Protection has its own model blacklist too (its default
	list blocks several explosive props to stop grief) and hooks these
	same events at normal priority. Since the first hook to return a
	value wins, FPP's block could fire and stop the spawn before our own
	CheckPropModel/permission checks - which already let the owner/any
	superadmin through - ever got a say. HOOK_HIGH makes this run first,
	so that exemption actually takes effect regardless of what FPP (or
	any other addon hooking these) decides.

	PlayerSpawnVehicle is included here too, not just the two prop
	hooks - FPP (and similar prop-protection addons) commonly restrict
	vehicle spawns the same way, and this hook was missing the same
	bypass the prop hooks already had, which is why vehicles kept
	silently failing to spawn for an owner/superadmin even after every
	other cause (trace distance, Spawn_Vehicle scope) was ruled out.
-----------------------------------------------------------]]
local function BypassOtherAddonSpawnBlocks(ply)
	if PDCity.CanSpawnFromMenu(ply) then return true end
end
hook.Add("PlayerSpawnObject", "pdcity_BypassOtherAddonBlacklists", BypassOtherAddonSpawnBlocks, HOOK_HIGH)
hook.Add("PlayerSpawnProp", "pdcity_BypassOtherAddonBlacklistsDupe", BypassOtherAddonSpawnBlocks, HOOK_HIGH)
hook.Add("PlayerSpawnVehicle", "pdcity_BypassOtherAddonBlacklistsVehicle", BypassOtherAddonSpawnBlocks, HOOK_HIGH)

--[[---------------------------------------------------------
	Owner/superadmin-only spawn menu. All Q-menu spawn tabs
	(Entities, NPCs, Vehicles, Effects, Ragdolls) are gated by
	CanSpawnFromMenu above.

	Doesn't touch job loadouts (Player:Give()), the garage system,
	the F4 shop, or the car dealer — all of those go through their
	own spawn paths and enforce their own access control.

	The Dupes tab isn't a spawn hook at all - AdvDupe2 pastes entities by
	calling ents.Create directly, bypassing every hook above entirely.
	What actually gates it is CanTool below, denying the stock
	"duplicator" tool and AdvDupe2's own "advdupe2" tool mode
	to non-superadmins outright.
-----------------------------------------------------------]]

hook.Add("PlayerSpawnSENT", "pdcity_RestrictSENTs", function(ply, class)
	if PDCity.CanSpawnFromMenu(ply) then return end
	ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Only the server owner or superadmins can spawn entities.")
	return false
end)

hook.Add("PlayerSpawnNPC", "pdcity_RestrictNPCs", function(ply, npc_type, weapon)
	if PDCity.CanSpawnFromMenu(ply) then return end
	ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Only the server owner or superadmins can spawn NPCs.")
	return false
end)

hook.Add("PlayerSpawnEffect", "pdcity_RestrictEffects", function(ply, model)
	if PDCity.CanSpawnFromMenu(ply) then return end
	ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Only the server owner or superadmins can spawn effects.")
	return false
end)

hook.Add("PlayerSpawnRagdoll", "pdcity_RestrictRagdolls", function(ply, model)
	if PDCity.CanSpawnFromMenu(ply) then return end
	ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Only the server owner or superadmins can spawn ragdolls.")
	return false
end)

hook.Add("PlayerSpawnVehicle", "pdcity_RestrictVehicles", function(ply, model, name, vtable)
	if PDCity.CanSpawnFromMenu(ply) then return end
	ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Only the server owner or superadmins can spawn vehicles.")
	return false
end)

local RESTRICTED_TOOLS = {
	["remover"] = true,
	["duplicator"] = true, -- stock GMod duplicator
	["advdupe2"] = true, -- Advanced Duplicator 2 (workshop 773402917)
}

hook.Add("CanTool", "pdcity_ToolRestrict", function(ply, trace, tool)
	if RESTRICTED_TOOLS[tool] and not PDCity.CanSpawnFromMenu(ply) then
		return false
	end
end)

-- Every owner-only PD City tool (Door Faction, Garage Door, NPC Spawner,
-- ...) already gates itself with PDCity.IsOwner in its own LeftClick/
-- RightClick, so there's nothing left for Falco's Prop Protection to
-- usefully protect here - but FPP still intercepts CanTool first and
-- blocks by default on anything without a CPPI owner, which is exactly
-- what a native, non-scripted entity (a map door, func_door/
-- prop_door_rotating - no ENT table of its own, so there's no per-entity
-- ENT:CanTool override to add the way ent_pdcity_garage.lua already
-- needed) always is. hook.Add's 4th
-- argument runs this BEFORE FPP's own hook (registered at normal
-- priority) - hook.Run stops at the first non-nil return, so returning
-- true here for the owner short-circuits FPP entirely rather than
-- racing it.
hook.Add("CanTool", "pdcity_OwnerToolsBypassFPP", function(ply, trace, tool)
	if tool and tool:find("^pdcity_") and PDCity.IsOwner(ply) then
		return true
	end
end, HOOK_HIGH)