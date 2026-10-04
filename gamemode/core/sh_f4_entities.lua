--[[---------------------------------------------------------
	Entities purchasable from the F4 menu's Entities tab. Shared so the
	client can list them and the server can validate purchases
	(core/sv_f4_entities.lua).

	To add one here directly (for entries needing custom Setup/CanBuy
	Lua, which can't be expressed as data): append an entry to this
	file. For everything else, use the in-game F4 admin editor
	(cl_f4_admin.lua) instead - those entries live in
	core/sh_f4_catalogue.lua and support Subsection/Jobs/Rank without
	touching any files.

	Fields:
	  ID          unique string, what the client sends to the server
	  Name        display name
	  Description shown on the card
	  Price       deducted from the buyer's profile money (0 = free)
	  Class       entity class to spawn
	  Icon        icon16/ path for the card
	  Subsection  which core/sh_f4_catalogue.lua PDCity.F4_SECTIONS entry
	              this groups under (defaults to "General")
	  Jobs        list of job IDs allowed to buy (nil/empty = everyone)
	  Rank        one of PDCity.RANKS required to buy (nil = "normal")
	  Setup       optional function(ent, ply) run before ent:Spawn()
	  CanBuy      optional function(ply) -> bool[, reason], checked
	              server-side before any money changes hands

	CanBuy/Setup only ever run on the server (core/sv_f4_entities.lua);
	the client just reads Name/Description/Price/Icon to draw the card, so
	it's fine for those functions to call server-only globals here.
-----------------------------------------------------------]]

-- Caps are fixed per job and printer type (PDCity.GetMaxPrinters in
-- core/sv_printers.lua) - the paid "Additional Printers" upgrade no
-- longer exists.
local function CheckPrinterCap(ply, class)
	if PDCity.CanSpawnPrinter(ply, class) then return true end
	return false, "You already have the maximum of " .. PDCity.GetMaxPrinters(ply, class) .. " of these."
end

-- Which jobs may buy one is up to the owner (the Catalogue's job role
-- restrictions) - this only enforces the per-player printer cap.
local function CanBuyPrinter(ply)
	return CheckPrinterCap(ply, "ent_pdcity_printer")
end

local function SetupPrinter(ent, ply)
	ent:SetAngles(Angle(0, ply:EyeAngles().y, 0))
	PDCity.TrackPrinter(ent, ply)
end

-- Only this one is hardcoded now - everything else (Blue's Farm,
-- Bitminers 2, ...) is a one-time SEED into the owner-editable custom
-- catalogue instead (core/sv_f4_catalogue.lua's DEFAULT_SEED_ENTITIES),
-- which already supports real add/edit/remove with no code changes
-- needed. Money Printer can't move there too: CanBuy/Setup/
-- VisibleCheck below are real Lua (job checks, printer caps), not
-- expressible as the custom catalogue's plain data format - it stays
-- here, but is still removable from the shop via the override system
-- right below (Removed flag), same "hardcoded, but the owner can still
-- take it out via the catalogue" requirement Blue's Farm/Bitminers meet
-- a different way.
PDCity.F4_ENTITIES = {
	{
		ID = "money_printer",
		Name = "Money Printer",
		Description = "Prints money over time. Free to place - unlock it for $1000, then upgrade printing speed and payout. Only a police stunstick can destroy it.",
		Price = 0,
		Class = "ent_pdcity_printer",
		Icon = "icon16/printer.png",
		Subsection = "General",
		CanBuy = CanBuyPrinter,
		Setup = SetupPrinter,
	},
}

--[[---------------------------------------------------------
	Owner edits to a hardcoded entry here (F4 admin editor's Entities tab,
	same edit flow as a custom entity - core/sv_f4_catalogue.lua's
	edit_builtin_entity) layered on top, same reasoning and pattern as
	core/sh_jobs.lua's PDCity.JOB_OVERRIDES: this file reloads fresh from
	disk every restart and has nowhere else to remember an edit. Class is
	deliberately never overridable - CanBuy/Setup/VisibleCheck above are
	written for a SPECIFIC class (e.g. CanBuyPrinter assumes it's gating
	ent_pdcity_printer); swapping the class out from under them while
	keeping that logic would be nonsense.

	override.Removed = true takes an entry out of the shop AND the admin
	list entirely (core/sv_f4_catalogue.lua's remove_builtin_entity) -
	true removal, not a delete-then-can't-get-it-back: restore_builtin_entity
	clears the flag (PDCity.GetRemovedBuiltinF4Entities lists what's
	currently hidden so the admin editor can offer that). The underlying
	CanBuy/Setup Lua stays defined either way - harmless dead code while
	hidden, not something that needs deleting from this file to "remove"
	the item from the owner's point of view.

	Starts Removed = true - the F4 Entities shop ships with nothing
	visible by default, even though its code stays defined here. Restore
	it from the F4 admin editor's Entities tab ("Removed Built-in
	Items") if you want it.
-----------------------------------------------------------]]
PDCity.F4_ENTITY_OVERRIDES = PDCity.F4_ENTITY_OVERRIDES or {
	money_printer = { Removed = true },
}

local mergedF4EntityCache = {}

function PDCity.InvalidateF4EntityCache(id)
	mergedF4EntityCache[id] = nil
end

-- Merges a hardcoded entry with its override, if any - same shallow
-- key-by-key merge as PDCity.GetJob, and same cache-by-override-identity
-- invalidation scheme (see that function's own comment for why).
local function GetMergedBuiltinEntity(base)
	local override = PDCity.F4_ENTITY_OVERRIDES[base.ID]
	if not override then return base end

	local cached = mergedF4EntityCache[base.ID]
	if cached and cached.pdcity_OverrideRef == override then return cached end

	local merged = {}
	for k, v in pairs(base) do merged[k] = v end
	for k, v in pairs(override) do merged[k] = v end
	merged.Class = base.Class -- never overridable, see header comment
	merged.pdcity_OverrideRef = override

	mergedF4EntityCache[base.ID] = merged
	return merged
end

-- Searches both this file's hardcoded entries (merged with any owner
-- override) and the admin-added ones from core/sh_f4_catalogue.lua
-- (PDCity.GetAllF4Entities combines both) - a plain PDCity.F4_ENTITIES-only
-- search would silently fail to find anything added through the F4 admin
-- editor.
function PDCity.GetF4Entity(id)
	for _, cfg in ipairs(PDCity.GetAllF4Entities()) do
		if cfg.ID == id then return cfg end
	end
end

-- Excludes anything Removed - exposed separately from
-- PDCity.GetAllF4Entities (which already applies this) so cl_f4_admin.lua
-- can tell a builtin apart from a custom entry by ID without re-deriving
-- the merge itself.
function PDCity.GetMergedBuiltinF4Entities()
	local out = {}
	for _, base in ipairs(PDCity.F4_ENTITIES) do
		local merged = GetMergedBuiltinEntity(base)
		if not merged.Removed then
			table.insert(out, merged)
		end
	end
	return out
end

-- The mirror image: hardcoded entries currently hidden, for the admin
-- editor's "restore" list. Only Name/Class/ID matter while something's
-- hidden - other override fields are irrelevant until it's visible again.
function PDCity.GetRemovedBuiltinF4Entities()
	local out = {}
	for _, base in ipairs(PDCity.F4_ENTITIES) do
		local override = PDCity.F4_ENTITY_OVERRIDES[base.ID]
		if override and override.Removed then
			table.insert(out, base)
		end
	end
	return out
end
