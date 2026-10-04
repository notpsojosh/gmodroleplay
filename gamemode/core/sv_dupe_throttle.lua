--[[---------------------------------------------------------
	Throttles large duplicator pastes. duplicator.Paste
	(lua/includes/modules/duplicator.lua - stock GMod, not a workshop
	addon; every "advanced duplicator" tool including AdvDupe2 is built
	on top of it) creates EVERY entity in a paste synchronously, in a
	single for-loop, inside one function call. That's the actual
	mechanism behind "spawned 75 props and the server crashed": 75
	physics inits plus 75 full-entity network baselines sent to every
	connected client, all inside one ~15ms server frame.

	Rather than edit the stock module (fragile - could be reverted by
	a GMod update, and every dupe-capable tool on the server calls this
	same function), this wraps duplicator.Paste itself. Small pastes -
	the overwhelming majority of calls, a single prop or a welded
	chair+table - are completely unaffected: only pastes above
	BURST_SIZE get split into chunks and spread across several ticks,
	each chunk itself just a normal, safe-sized paste.

	Constraints need a subtlety: duplicator.Paste's own CreatedEntities
	table only ever contains entities from THAT ONE call, so a
	constraint spanning two different chunks would never find both its
	entities in any single chunk's table, however the chunks are
	split. So constraint creation is pulled out of RealPaste entirely
	for a throttled paste, and re-run ourselves via
	duplicator.CreateConstraintFromTable once every chunk has actually
	been created and merged into one combined entity table.
-----------------------------------------------------------]]

local BURST_SIZE = 15 -- entities created per chunk
local BURST_DELAY = 0.1 -- seconds between chunks

local RealPaste = duplicator.Paste

function duplicator.Paste(ply, entityList, constraintList)

	local count = table.Count(entityList)
	if count <= BURST_SIZE then
		return RealPaste(ply, entityList, constraintList)
	end

	-- Split into ordered chunks of BURST_SIZE entities each.
	local chunks = {}
	local current = {}
	local n = 0

	for k, v in pairs(entityList) do
		current[k] = v
		n = n + 1
		if n >= BURST_SIZE then
			table.insert(chunks, current)
			current = {}
			n = 0
		end
	end
	if next(current) then table.insert(chunks, current) end

	if IsValid(ply) then
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Large paste (" .. count .. " entities) - spawning it in over the next few seconds to avoid a lag spike.")
	end

	local allCreated = {}

	local function PasteChunk(i)

		-- Player disconnecting mid-paste shouldn't leave orphaned
		-- entities still trickling in with no owner to attribute them
		-- to; stop rather than continue creating on their behalf.
		if not IsValid(ply) then return end

		-- Empty constraint list per chunk, on purpose - see the
		-- header comment. Constraints are resolved once, below, after
		-- every chunk exists.
		local created = RealPaste(ply, chunks[i], {})
		for k, v in pairs(created) do
			allCreated[k] = v
		end

		if i < #chunks then
			timer.Simple(BURST_DELAY, function() PasteChunk(i + 1) end)
			return
		end

		for _, constraint in pairs(constraintList) do
			local ok, ent = pcall(duplicator.CreateConstraintFromTable, constraint, allCreated, ply)
			if not ok then
				ErrorNoHalt("[" .. PDCity.BRAND_TAG .. "] Throttled paste: a constraint failed to attach - " .. tostring(ent) .. "\n")
			end
		end

		if IsValid(ply) then
			ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Paste finished (" .. count .. " entities).")
		end

	end

	PasteChunk(1)

	-- A throttled paste can't return the real created-entity/
	-- constraint tables synchronously - most of them don't exist yet.
	-- Every normal-sized paste above (the vast majority of calls)
	-- still returns the real thing.
	return {}, {}

end

--[[---------------------------------------------------------
	AdvDupe2 specifically does NOT go through duplicator.Paste above -
	it has its own entirely separate per-tick creation queue
	(lua/advdupe2/sv_clipboard.lua, confirmed by extracting and reading
	the addon's actual GMA rather than assumed), so the throttle above
	never runs for it at all.

	That file's own queue already throttles entity CREATION across
	ticks - the real crash is a single, un-throttled step AFTER that:
	once every entity and constraint is done, if the player has
	"unfreeze all after paste" on, one loop calls EnableMotion(true)
	and Wake() on every physics object from the ENTIRE paste in one go.
	Waking dozens of physics objects simultaneously (especially ones
	touching or stacked) is a known way to crash Source's physics
	engine - the constraint solver has to resolve every one of those
	interactions in the same instant.

	AdvDupe2 already exposes hook.Call("AdvDupe_FinishPasting", ...)
	right after that unfreeze loop runs, with the full CreatedEntities
	list. We can't disable the checkbox itself - it's the client's own
	convar, reported to the addon's server-side code via GetInfo, not
	something server Lua can force - but we don't need to: this hook
	re-freezes everything the unfreeze loop just wound up, every time,
	regardless of paste size. The net effect is the same as the option
	not existing at all: a paste with "unfreeze all" checked now comes
	in exactly like a normal paste (frozen), full stop, rather than
	staggering the unfreeze back in - since the whole failure mode was
	"unfreeze," removing it entirely removes the risk entirely too,
	rather than just reducing it.
-----------------------------------------------------------]]

hook.Add("AdvDupe_FinishPasting", "pdcity_DisablePasteUnfreeze", function(pasteData)

	local info = pasteData and pasteData[1]
	if not info then return end

	local ply = info.Player
	if not IsValid(ply) then return end

	-- Only the specific option that causes the crash - a normal paste
	-- (frozen, or "preserve frozen state") is left completely
	-- untouched, since it was never involved in the crash to begin
	-- with.
	if not tobool(ply:GetInfo("advdupe2_paste_unfreeze")) then return end

	local created = info.CreatedEntities
	if not istable(created) then return end

	local refrozen = 0
	for _, ent in pairs(created) do
		if IsValid(ent) then
			local phys = ent:GetPhysicsObject()
			if IsValid(phys) and phys:IsMoveable() then
				phys:EnableMotion(false)
				phys:Sleep()
				refrozen = refrozen + 1
			end
		end
	end

	if refrozen > 0 then
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] \"Unfreeze all after paste\" is disabled on this server (it can crash the physics engine on large pastes) - your props came in frozen instead.")
	end

end)
