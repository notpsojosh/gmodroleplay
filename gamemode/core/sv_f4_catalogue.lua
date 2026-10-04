--[[---------------------------------------------------------
	Server side of the F4 admin editor (cl_f4_admin.lua): persists the
	owner-editable sections/custom-entities catalogue (core/sh_f4_catalogue.lua)
	to data/pdcity/f4_catalogue.json, validates every change, and
	broadcasts the result to all clients so the F4 menu updates live.

	Every action re-checks PDCity.IsOwner(ply) here - the admin editor
	only shows for the owner client-side, but that's just UI; this is
	the actual enforcement.
-----------------------------------------------------------]]

util.AddNetworkString("pdcity_f4_sync")
util.AddNetworkString("pdcity_f4_admin")

local CATALOGUE_PATH = "pdcity/f4_catalogue.json"

-- Empty by default - the F4 Entities shop starts with nothing until the
-- owner adds their own via the admin editor (cl_f4_admin.lua). Seeded
-- (once, ever - see LoadCatalogue below) into the normal OWNER-EDITABLE
-- custom catalogue, same mechanism as any manually-added entry, so
-- anything you put here goes through real add/edit/remove_entity with
-- no code changes needed.
local DEFAULT_SEED_ENTITIES = {
}

-- True once DEFAULT_SEED_ENTITIES has ever been seeded in - persisted
-- (not just "file exists yet") since this file already existed on
-- servers that had Blue's Farm/Bitminers as hardcoded entries before
-- either of those moved into DEFAULT_SEED_ENTITIES: a plain "only seed
-- if the catalogue file is missing" check would never fire for them,
-- silently dropping every one of those items the moment this shipped.
local defaultsSeeded = false

local function SaveCatalogue()
	file.CreateDir("pdcity")
	file.Write(CATALOGUE_PATH, util.TableToJSON({
		Sections = PDCity.F4_SECTIONS,
		Entities = PDCity.F4_CUSTOM_ENTITIES,
		Overrides = PDCity.F4_ENTITY_OVERRIDES,
		DefaultsSeeded = defaultsSeeded,
	}, true))
end

local function LoadCatalogue()
	local raw = file.Read(CATALOGUE_PATH, "DATA")
	local data = raw and util.JSONToTable(raw)

	if raw and not data then
		ErrorNoHalt("[" .. PDCity.BRAND_TAG .. "] " .. CATALOGUE_PATH .. " was unreadable - keeping the built-in defaults.\n")
		return
	end

	if data then
		if istable(data.Sections) and #data.Sections > 0 then
			PDCity.F4_SECTIONS = data.Sections
		end

		if istable(data.Entities) then
			PDCity.F4_CUSTOM_ENTITIES = data.Entities
		end

		if istable(data.Overrides) then
			PDCity.F4_ENTITY_OVERRIDES = data.Overrides
		end

		defaultsSeeded = data.DefaultsSeeded == true
	end

	if not defaultsSeeded then
		-- Only ever runs once per server (the flag above, persisted
		-- immediately below, is what stops it running again) - after
		-- this, removing (or editing) any of these sticks permanently,
		-- same as anything else in the catalogue. Skips an ID already
		-- present so this can't ever double-insert if it somehow ran
		-- twice before the flag made it to disk (e.g. a crash between
		-- seeding and saving).
		for _, cfg in ipairs(DEFAULT_SEED_ENTITIES) do
			local already = false
			for _, existing in ipairs(PDCity.F4_CUSTOM_ENTITIES) do
				if existing.ID == cfg.ID then already = true break end
			end
			if not already then
				table.insert(PDCity.F4_CUSTOM_ENTITIES, table.Copy(cfg))
			end
		end

		defaultsSeeded = true
		SaveCatalogue()
	end
end

LoadCatalogue()

local function BroadcastCatalogue(ply)
	net.Start("pdcity_f4_sync")
		net.WriteString(util.TableToJSON({
			Sections = PDCity.F4_SECTIONS,
			Entities = PDCity.F4_CUSTOM_ENTITIES,
			Overrides = PDCity.F4_ENTITY_OVERRIDES,
		}))
	if IsValid(ply) then
		net.Send(ply)
	else
		net.Broadcast()
	end
end

hook.Add("PlayerInitialSpawn", "pdcity_SyncF4Catalogue", function(ply)
	BroadcastCatalogue(ply)
end)

--[[---------------------------------------------------------
	Validation helpers
-----------------------------------------------------------]]

local function IsValidClass(class)
	if not isstring(class) or class == "" then return false end
	return weapons.GetStored(class) ~= nil or scripted_ents.GetStored(class) ~= nil
end

local function IsValidJobList(jobs)
	if not istable(jobs) then return false end
	for _, id in ipairs(jobs) do
		if not PDCity.GetJob(id) then return false end
	end
	return true
end

local function IsValidRank(rank)
	if rank == nil or rank == "" then return true end
	return table.HasValue(PDCity.RANKS, rank)
end

local function IsValidPrice(price)
	return isnumber(price) and price >= 0 and price == math.floor(price)
end

-- Optional override shown on the shop card instead of whatever
-- PDCity.GetItemModel (core/sh_inventory.lua) can best-effort resolve from
-- the class alone - nil/empty is valid (falls back to that automatic
-- lookup), anything else has to actually be a model that exists.
local function IsValidModelOverride(model)
	if model == nil or model == "" then return true end
	return isstring(model) and util.IsValidModel(model)
end

--[[---------------------------------------------------------
	Action handlers. Each takes (ply, payload) where payload is the
	decoded table sent from cl_f4_admin.lua, and returns ok[, error].
-----------------------------------------------------------]]

local Actions = {}

function Actions.add_entity(ply, p)
	if not IsValidClass(p.Class) then return false, "Not a recognised entity/weapon class." end
	if not isstring(p.Name) or p.Name == "" then return false, "Name can't be empty." end
	if not isstring(p.Subsection) or not table.HasValue(PDCity.F4_SECTIONS, p.Subsection) then return false, "Pick a valid subsection." end
	if not IsValidPrice(p.Price) then return false, "Price must be a whole number, 0 or more." end
	if not IsValidRank(p.Rank) then return false, "Invalid rank." end
	if p.Jobs ~= nil and not IsValidJobList(p.Jobs) then return false, "Invalid job selection." end
	if not IsValidModelOverride(p.Model) then return false, "Not a recognised model." end

	local shipment = math.floor(tonumber(p.ShipmentCount) or 0)
	if shipment < 0 then return false, "Shipment count can't be negative." end
	if shipment > 100 then return false, "Shipment count is capped at 100." end

	table.insert(PDCity.F4_CUSTOM_ENTITIES, {
		ID = "custom_" .. os.time() .. "_" .. math.random(1000, 9999),
		Name = p.Name,
		Description = isstring(p.Description) and p.Description or "",
		Class = p.Class,
		Model = isstring(p.Model) and p.Model ~= "" and p.Model or nil,
		Icon = isstring(p.Icon) and p.Icon ~= "" and p.Icon or "icon16/box.png",
		Price = math.floor(p.Price),
		Subsection = p.Subsection,
		Jobs = p.Jobs,
		Rank = (p.Rank ~= "" and p.Rank) or nil,
		-- Only stored when it actually means something: 0 or 1 is just
		-- "sold singly", which is the absence of this field.
		ShipmentCount = (shipment > 1) and shipment or nil,
	})

	return true
end

function Actions.edit_entity(ply, p)
	local cfg
	for _, existing in ipairs(PDCity.F4_CUSTOM_ENTITIES) do
		if existing.ID == p.ID then cfg = existing break end
	end
	if not cfg then return false, "That entity no longer exists." end

	if not IsValidClass(p.Class) then return false, "Not a recognised entity/weapon class." end
	if not isstring(p.Name) or p.Name == "" then return false, "Name can't be empty." end
	if not isstring(p.Subsection) or not table.HasValue(PDCity.F4_SECTIONS, p.Subsection) then return false, "Pick a valid subsection." end
	if not IsValidPrice(p.Price) then return false, "Price must be a whole number, 0 or more." end
	if not IsValidRank(p.Rank) then return false, "Invalid rank." end
	if p.Jobs ~= nil and not IsValidJobList(p.Jobs) then return false, "Invalid job selection." end
	if not IsValidModelOverride(p.Model) then return false, "Not a recognised model." end

	local shipment = math.floor(tonumber(p.ShipmentCount) or 0)
	if shipment < 0 then return false, "Shipment count can't be negative." end
	if shipment > 100 then return false, "Shipment count is capped at 100." end

	cfg.Name = p.Name
	cfg.Description = isstring(p.Description) and p.Description or ""
	cfg.Class = p.Class
	cfg.Model = isstring(p.Model) and p.Model ~= "" and p.Model or nil
	cfg.Icon = isstring(p.Icon) and p.Icon ~= "" and p.Icon or "icon16/box.png"
	cfg.Price = math.floor(p.Price)
	cfg.Subsection = p.Subsection
	cfg.Jobs = p.Jobs
	cfg.Rank = (p.Rank ~= "" and p.Rank) or nil
	cfg.ShipmentCount = (shipment > 1) and shipment or nil

	return true
end

-- Editing a BUILT-IN entity (core/sh_f4_entities.lua's PDCity.F4_ENTITIES,
-- e.g. Money Printer) - same fields as edit_entity above except Class,
-- which always comes from the hardcoded entry untouched (see
-- PDCity.F4_ENTITY_OVERRIDES's own header comment for why). Stored as an
-- override layered on top of the hardcoded entry rather than mutating a
-- table that doesn't survive a restart anyway. Removing one entirely
-- (rather than just editing its fields) is remove_builtin_entity, right
-- below - reversible via restore_builtin_entity.
function Actions.edit_builtin_entity(ply, p)
	local base
	for _, cfg in ipairs(PDCity.F4_ENTITIES) do
		if cfg.ID == p.ID then base = cfg break end
	end
	if not base then return false, "That entity doesn't exist." end

	if not isstring(p.Name) or p.Name == "" then return false, "Name can't be empty." end
	if not isstring(p.Subsection) or not table.HasValue(PDCity.F4_SECTIONS, p.Subsection) then return false, "Pick a valid subsection." end
	if not IsValidPrice(p.Price) then return false, "Price must be a whole number, 0 or more." end
	if not IsValidRank(p.Rank) then return false, "Invalid rank." end
	if p.Jobs ~= nil and not IsValidJobList(p.Jobs) then return false, "Invalid job selection." end
	if not IsValidModelOverride(p.Model) then return false, "Not a recognised model." end

	local shipment = math.floor(tonumber(p.ShipmentCount) or 0)
	if shipment < 0 then return false, "Shipment count can't be negative." end
	if shipment > 100 then return false, "Shipment count is capped at 100." end

	-- A fresh table, not a mutation of any existing override - see
	-- sh_f4_entities.lua's merge function for why that matters (cache
	-- invalidation keys off the override table's IDENTITY, not its
	-- contents).
	PDCity.F4_ENTITY_OVERRIDES[p.ID] = {
		Name = p.Name,
		Description = isstring(p.Description) and p.Description or "",
		Model = isstring(p.Model) and p.Model ~= "" and p.Model or nil,
		Icon = isstring(p.Icon) and p.Icon ~= "" and p.Icon or "icon16/box.png",
		Price = math.floor(p.Price),
		Subsection = p.Subsection,
		Jobs = p.Jobs,
		Rank = (p.Rank ~= "" and p.Rank) or nil,
		ShipmentCount = (shipment > 1) and shipment or nil,
	}
	PDCity.InvalidateF4EntityCache(p.ID)

	return true
end

-- Takes a hardcoded entity out of the shop entirely (owner asked for
-- "no hardcoded entities the catalogue can't remove" - this is how a
-- hardcoded one satisfies that: the Lua stays defined, but the entry
-- itself disappears from both the F4 shop and this admin list until
-- restore_builtin_entity below brings it back). Preserves any other
-- override fields already set (a fresh table copying them plus the flag,
-- not a mutation - same identity-based cache invalidation reasoning as
-- edit_builtin_entity above) rather than discarding an existing edit.
function Actions.remove_builtin_entity(ply, p)
	local exists = false
	for _, cfg in ipairs(PDCity.F4_ENTITIES) do
		if cfg.ID == p.ID then exists = true break end
	end
	if not exists then return false, "That entity doesn't exist." end

	local fresh = {}
	local old = PDCity.F4_ENTITY_OVERRIDES[p.ID]
	if old then for k, v in pairs(old) do fresh[k] = v end end
	fresh.Removed = true

	PDCity.F4_ENTITY_OVERRIDES[p.ID] = fresh
	PDCity.InvalidateF4EntityCache(p.ID)

	return true
end

function Actions.restore_builtin_entity(ply, p)
	local old = PDCity.F4_ENTITY_OVERRIDES[p.ID]
	if not old or not old.Removed then return false, "That entity isn't removed." end

	local fresh = {}
	for k, v in pairs(old) do fresh[k] = v end
	fresh.Removed = nil

	-- Nothing else overridden - clear it out entirely rather than leaving
	-- an empty {} sitting around forever.
	PDCity.F4_ENTITY_OVERRIDES[p.ID] = next(fresh) and fresh or nil
	PDCity.InvalidateF4EntityCache(p.ID)

	return true
end

function Actions.remove_entity(ply, p)
	for i, cfg in ipairs(PDCity.F4_CUSTOM_ENTITIES) do
		if cfg.ID == p.ID then
			table.remove(PDCity.F4_CUSTOM_ENTITIES, i)
			return true
		end
	end
	return false, "That entity no longer exists."
end

function Actions.reorder_entities(ply, p)
	if not istable(p.Order) then return false, "Bad order list." end

	local byID = {}
	for _, cfg in ipairs(PDCity.F4_CUSTOM_ENTITIES) do byID[cfg.ID] = cfg end

	local reordered = {}
	for _, id in ipairs(p.Order) do
		if byID[id] then
			table.insert(reordered, byID[id])
			byID[id] = nil
		end
	end

	-- Anything not present in the submitted order (shouldn't happen from
	-- the real UI, but keep data rather than silently drop it) goes on
	-- the end in its previous relative order.
	for _, cfg in ipairs(PDCity.F4_CUSTOM_ENTITIES) do
		if byID[cfg.ID] then table.insert(reordered, cfg) end
	end

	PDCity.F4_CUSTOM_ENTITIES = reordered
	return true
end

function Actions.add_section(ply, p)
	if not isstring(p.Name) or p.Name == "" then return false, "Section name can't be empty." end
	if table.HasValue(PDCity.F4_SECTIONS, p.Name) then return false, "That section already exists." end

	table.insert(PDCity.F4_SECTIONS, p.Name)
	return true
end

function Actions.remove_section(ply, p)
	if not table.HasValue(PDCity.F4_SECTIONS, p.Name) then return false, "That section doesn't exist." end
	if #PDCity.F4_SECTIONS <= 1 then return false, "At least one section has to exist." end

	table.RemoveByValue(PDCity.F4_SECTIONS, p.Name)

	-- Reassign orphaned entries so nothing silently vanishes from the menu.
	for _, cfg in ipairs(PDCity.F4_CUSTOM_ENTITIES) do
		if cfg.Subsection == p.Name then
			cfg.Subsection = PDCity.F4_SECTIONS[1]
		end
	end

	return true
end

function Actions.reorder_sections(ply, p)
	if not istable(p.Order) then return false, "Bad order list." end
	if #p.Order ~= #PDCity.F4_SECTIONS then return false, "Section list doesn't match." end
	for _, name in ipairs(p.Order) do
		if not table.HasValue(PDCity.F4_SECTIONS, name) then return false, "Unknown section in order list." end
	end

	PDCity.F4_SECTIONS = p.Order
	return true
end

net.Receive("pdcity_f4_admin", function(len, ply)
	-- Owner only - re-checked here regardless of what the client's UI
	-- already hides (cl_f4_menu.lua/cl_f4_admin.lua).
	if not PDCity.IsOwner(ply) then return end

	local data = util.JSONToTable(net.ReadString() or "")
	if not istable(data) or not isstring(data.Action) then return end

	local handler = Actions[data.Action]
	if not handler then return end

	local payload = data.Payload or {}

	local ok, err = handler(ply, payload)
	if ok then
		SaveCatalogue()
		BroadcastCatalogue()
	end

	if not ok then
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] " .. (err or "That action failed."))
	end
end)
