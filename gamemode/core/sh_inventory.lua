--[[---------------------------------------------------------
	Shared inventory definitions - grid size, stack limits, and the
	helpers both realms need to describe an item (its model and display
	name) from nothing but its entity class.

	Storage/validation lives in core/sv_inventory.lua; the UI is
	cl_inventory.lua. Contents are stored per-player in the profile
	(core/sv_profiles.lua, "Inventory" field), so they survive death,
	disconnects and map changes - nothing clears them.
-----------------------------------------------------------]]

--[[---------------------------------------------------------
	Grid size - 6 wide, growing from 3 rows (18 slots) up to 6 rows (36
	slots) as a player earns job-class levels, rather than one fixed
	size. PDCity.INVENTORY_SLOTS/ROWS below describe the FULL grid at
	max capacity (used as the upper bound for slot-indexing loops and
	for how big the UI grid always is); PDCity.GetInventoryCapacity is
	what's actually USABLE right now - rows beyond that render locked
	(cl_inventory.lua) rather than the grid changing size as you level.

	+6 slots (one more full row) for every 10 total job-class levels -
	the sum of a player's level in every class they've earned XP in
	(core/sv_job_xp.lua's PDCity.GetTotalJobLevels), not every class
	that merely exists - capped at the max. Both thresholds land on a
	whole number of rows (18/24/30/36, all multiples of 6) by design.
-----------------------------------------------------------]]
PDCity.INVENTORY_COLS = 6
PDCity.INVENTORY_BASE_SLOTS = 18
PDCity.INVENTORY_MAX_SLOTS = 36
PDCity.INVENTORY_LEVELS_PER_TIER = 10
PDCity.INVENTORY_SLOTS_PER_TIER = 6

PDCity.INVENTORY_ROWS = PDCity.INVENTORY_MAX_SLOTS / PDCity.INVENTORY_COLS
PDCity.INVENTORY_SLOTS = PDCity.INVENTORY_MAX_SLOTS
PDCity.INVENTORY_MAX_STACK = 10

function PDCity.GetInventoryCapacity(totalLevels)
	totalLevels = math.max(0, tonumber(totalLevels) or 0)
	local bonus = math.floor(totalLevels / PDCity.INVENTORY_LEVELS_PER_TIER) * PDCity.INVENTORY_SLOTS_PER_TIER
	return math.min(PDCity.INVENTORY_MAX_SLOTS, PDCity.INVENTORY_BASE_SLOTS + bonus)
end

-- Never storable, whatever the circumstances - a hard floor underneath
-- the whitelist below, so a mis-click in the admin UI can't ever make
-- one of these storable. Money isn't listed here because it isn't
-- "refused": picking it up always credits the wallet instead (see
-- core/sv_inventory.lua), which is different from being rejected.
PDCity.INVENTORY_BLOCKED = {
	["ent_pdcity_printer"] = true,
	-- A crate is a container holding N of something else - putting the
	-- container itself into a slot would need nested inventories.
	["ent_pdcity_shipment"] = true,
}

PDCity.MONEY_CLASS = "ent_pdcity_money"

--[[---------------------------------------------------------
	Whitelist of storable classes. Nothing goes in the inventory unless
	its class is on this list - it starts empty, and the owner fills it
	in-game via the F4 admin editor's "Inventory Items" tab
	(cl_f4_admin.lua).

	Persisted and synced by core/sv_inventory.lua, and replaced wholesale
	on load/sync rather than mutated key-by-key, so a client's copy always
	matches the server's exactly. Same pattern as the F4 catalogue.

	Items already sitting in someone's inventory are deliberately NOT
	affected by removing a class from here: they stay put and can still
	be moved and dropped, you just can't pick up any more of them.
-----------------------------------------------------------]]
PDCity.INVENTORY_ALLOWED = PDCity.INVENTORY_ALLOWED or {}

--[[---------------------------------------------------------
	Class -> model / display name. Best-effort: an entity class with no
	single obvious model (point/logic entities) returns nil and the UI
	falls back to drawing the item's name only.

	SWEPs expose WorldModel; SENTs expose a Model field only if the file
	sets one as a *static* ENT.Model rather than just calling SetModel in
	Initialize (see the note in entities/entities/ent_pdcity_printer.lua).

	Tried adding a util.IsValidModel() check here for a specific case
	where a mounted weapon pack's ammo entity (M9K's m9k_ammo_357/
	m9k_ammo_pistol) registers a static ENT.Model that isn't a real
	model - that check turned out to reject plenty of otherwise-fine
	models too (client-side, IsValidModel appears to key off whether the
	engine has actually precached that model already, not just whether
	the file exists - most models here never have been), which made
	EVERY entity fall back to its icon16 instead of just the two broken
	ones. Reverted; a wrong auto-detected model like those two is a
	manual fix instead, via the F4 admin editor's own "Model shown on
	the shop card" override field (cl_f4_admin.lua) - built for exactly
	this case.
-----------------------------------------------------------]]

function PDCity.GetItemModel(class)
	local swep = weapons.GetStored(class)
	if swep and swep.WorldModel and swep.WorldModel ~= "" then
		return swep.WorldModel
	end

	local sent = scripted_ents.GetStored(class)
	if sent and sent.t and sent.t.Model and sent.t.Model ~= "" then
		return sent.t.Model
	end

	return nil
end

function PDCity.GetItemName(class)
	local swep = weapons.GetStored(class)
	if swep and swep.PrintName and swep.PrintName ~= "" then
		return swep.PrintName
	end

	local sent = scripted_ents.GetStored(class)
	if sent and sent.t and sent.t.PrintName and sent.t.PrintName ~= "" then
		return sent.t.PrintName
	end

	-- Same prefix-stripping/title-casing the F4 admin editor uses.
	return PDCity.PrettifyClassName(class)
end

-- Anything the inventory is willing to hold: whitelist-only, so a class
-- nobody has added is never storable. Money is deliberately excluded
-- here - it's intercepted before this is ever consulted.
function PDCity.CanStoreItem(class)
	if not isstring(class) or class == "" then return false end
	if PDCity.INVENTORY_BLOCKED[class] then return false end
	if class == PDCity.MONEY_CLASS then return false end

	return table.HasValue(PDCity.INVENTORY_ALLOWED, class)
end
