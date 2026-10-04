--[[---------------------------------------------------------
	Admin-editable half of the F4 Entities tab: subsections, and custom
	catalogue entries added in-game via the F4 admin editor
	(cl_f4_admin.lua). The hardcoded entries in core/sh_f4_entities.lua
	(ones needing custom Setup/CanBuy Lua, like the money printer) still
	live there - this file only holds what the owner adds/removes/
	reorders at runtime.

	Persisted server-side (core/sv_f4_catalogue.lua) as
	data/pdcity/f4_catalogue.json and synced to clients on join and
	whenever the owner changes it. Both tables below start with just a
	sensible default and get replaced wholesale by whichever realm loads
	(server, from disk) or receives (client, over the network) the real
	data - never partially mutated field-by-field, so a sync always
	fully matches what the server has.

	Custom entity fields (all optional except ID/Name/Class):
	  ID          unique string, generated when added
	  Name        display name
	  Description shown on the card
	  Class       entity/weapon class to spawn
	  Icon        icon16/ path for the card
	  Price       whole number, 0 = free
	  Subsection  which PDCity.F4_SECTIONS entry this groups under
	  Jobs        list of job IDs allowed to buy (nil/empty = everyone)
	  Rank        one of PDCity.RANKS required to buy (nil = "normal")
	  ShipmentCount
	              if set (>1), buying this spawns a shipment crate
	              (ent_pdcity_shipment) holding that many of Class
	              instead of the item itself. nil/0/1 = sold singly.
-----------------------------------------------------------]]

PDCity.RANKS = { "normal", "supporter", "goat" }

function PDCity.RankLevel(rank)
	for i, name in ipairs(PDCity.RANKS) do
		if name == rank then return i end
	end
	return 1
end

-- Server reads the authoritative account; client reads the networked
-- copy (see core/sv_accounts.lua's PDCity.SetRank/NWString sync). Rank is
-- account-scoped, not per-character.
function PDCity.GetRank(ply)
	if not IsValid(ply) then return "normal" end
	if SERVER then
		local account = PDCity.GetAccount(ply)
		return (account and account.Rank) or "normal"
	end
	return ply:GetNWString("PDCity_Rank", "normal")
end

function PDCity.RankMeets(ply, requiredRank)
	if not requiredRank or requiredRank == "" then return true end
	return PDCity.RankLevel(PDCity.GetRank(ply)) >= PDCity.RankLevel(requiredRank)
end

-- Turns a raw class name into a readable default display name, e.g.
-- "swep_lockpick" -> "Lockpick", "weapon_pdcity_taser" -> "Pdcity Taser".
-- Used by cl_f4_admin.lua to fill in the Name field when a class is
-- picked from the search list - the admin can still edit it afterwards.
local CLASS_NAME_PREFIXES = { "swep_", "weapon_", "entity_", "ent_", "npc_", "item_" }

function PDCity.PrettifyClassName(class)
	local name = class

	for _, prefix in ipairs(CLASS_NAME_PREFIXES) do
		if name:sub(1, #prefix) == prefix then
			name = name:sub(#prefix + 1)
			break
		end
	end

	name = name:gsub("_", " ")
	name = name:gsub("(%a)([%w']*)", function(first, rest) return first:upper() .. rest:lower() end)

	return name
end

-- Replaced wholesale by disk load (server) / network sync (client) -
-- see core/sv_f4_catalogue.lua and cl_f4_admin.lua.
PDCity.F4_SECTIONS = PDCity.F4_SECTIONS or { "General" }
PDCity.F4_CUSTOM_ENTITIES = PDCity.F4_CUSTOM_ENTITIES or {}

-- Every buyable entity: the hardcoded ones from sh_f4_entities.lua
-- (merged with any owner override - PDCity.GetMergedBuiltinF4Entities)
-- plus whatever's been added through the admin editor.
function PDCity.GetAllF4Entities()
	local all = {}
	for _, cfg in ipairs(PDCity.GetMergedBuiltinF4Entities()) do table.insert(all, cfg) end
	for _, cfg in ipairs(PDCity.F4_CUSTOM_ENTITIES) do table.insert(all, cfg) end
	return all
end

-- In PDCity.F4_SECTIONS order, sections with nothing in them are simply
-- skipped by whoever iterates PDCity.F4_SECTIONS and checks this.
function PDCity.GetF4EntitiesInSection(sectionName)
	local list = {}
	for _, cfg in ipairs(PDCity.GetAllF4Entities()) do
		if (cfg.Subsection or "General") == sectionName then
			table.insert(list, cfg)
		end
	end
	return list
end

-- Job restriction only. A player whose job isn't on the list shouldn't
-- know the entry exists at all, so cl_f4_menu.lua uses this to leave it
-- out of the list entirely rather than showing it locked.
--
-- cfg.VisibleCheck is the same idea but for entries whose eligibility
-- isn't a plain job-ID whitelist (e.g. "anyone except Police") - a
-- shared function(ply) -> bool, job-only logic (no server-only state
-- like printer caps, which still show normally and just refuse the
-- purchase with a message instead of hiding - see
-- core/sh_f4_entities.lua's CanBuyPrinter).
function PDCity.HasF4JobAccess(ply, cfg)
	if cfg.Jobs and #cfg.Jobs > 0 and not table.HasValue(cfg.Jobs, ply:Team()) then
		return false
	end
	if cfg.VisibleCheck and not cfg.VisibleCheck(ply) then
		return false
	end
	return true
end

-- Full access check (job + rank), ignoring price/cooldown (those are
-- only checked at purchase time, in core/sv_f4_entities.lua). Returns
-- false + a short reason string for the F4 card to display when locked -
-- used both for the purchase-time server check and for graying out a
-- rank-locked card the player can still see (unlike a job restriction,
-- which hides the card entirely - see PDCity.HasF4JobAccess above).
function PDCity.CanAccessF4Entity(ply, cfg)
	if not PDCity.HasF4JobAccess(ply, cfg) then
		return false, "JOB LOCKED"
	end

	if cfg.Rank and cfg.Rank ~= "" and not PDCity.RankMeets(ply, cfg.Rank) then
		return false, "RANK LOCKED"
	end

	return true
end
