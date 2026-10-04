--[[---------------------------------------------------------
	Server side of the inventory (core/sh_inventory.lua for the shared
	constants/helpers, cl_inventory.lua for the UI).

	Contents live in the player's profile (core/sv_profiles.lua), so
	they persist across death, disconnect and map change with no extra
	work - nothing in this file or anywhere else clears them on death.
	(A per-item "lost on death" tag was discussed but no item needs one
	yet, so it isn't implemented.)

	Storage shape, per player:
	  profile.Inventory = { [slot] = { Class = "...", Count = n } }
	slot is 1..PDCITY_INVENTORY_SLOTS. JSON turns integer keys into
	strings on save, so LoadInventory converts them back - same fix as
	core/sv_job_catalogue.lua.

	Everything the client asks for is re-validated here: slot indices,
	counts, and whether the class is storable at all. The UI is just a
	view.
-----------------------------------------------------------]]

util.AddNetworkString("pdcity_inv_sync")
util.AddNetworkString("pdcity_inv_action")
util.AddNetworkString("pdcity_inv_whitelist")
util.AddNetworkString("pdcity_inv_admin")

local PICKUP_RANGE = 90

-- C is stock sandbox's bind for the spawnmenu context menu
-- (gm_showspare1 -> GM:ShowSpare1) - repurposed as the inventory's
-- hold-to-peek key (cl_inventory.lua), so the stock context menu is
-- suppressed here rather than fighting it for the same key.
--
-- Hooked on "ShowSpare1" specifically, NOT the generic "PlayerBindPress"
-- (which an earlier version of this used) - PlayerBindPress fires for
-- EVERY bind, F1/F4/C included, and broke F1/F4 no longer closing on a
-- second press despite only ever matching "gm_showspare1" by name here;
-- something about a hook on that generic event interfered with the
-- engine's own special-bind dispatch for the OTHER special binds too.
-- "ShowSpare1" is the same dedicated per-bind hook name GM:ShowHelp/
-- GM:ShowSpare2 already use with no such conflict (init.lua) - hook.Run
-- stops at the first non-nil return, so returning true here reliably
-- blocks the stock context menu regardless of load order.
hook.Add("ShowSpare1", "pdcity_BlockContextMenuKey", function(ply)
	return true
end)

--[[---------------------------------------------------------
	Storable-class whitelist (PDCity.INVENTORY_ALLOWED in
	core/sh_inventory.lua). Owner-editable in-game via the F4 admin
	editor's "Inventory Items" tab; persisted here and broadcast to
	every client so their UI agrees with the server.
-----------------------------------------------------------]]

local WHITELIST_PATH = "pdcity/inventory_whitelist.json"

local function SaveWhitelist()
	file.CreateDir("pdcity")
	file.Write(WHITELIST_PATH, util.TableToJSON(PDCity.INVENTORY_ALLOWED, true))
end

local function LoadWhitelist()
	local raw = file.Read(WHITELIST_PATH, "DATA")
	if not raw then return end

	local stored = util.JSONToTable(raw)
	if istable(stored) then
		PDCity.INVENTORY_ALLOWED = stored
	else
		ErrorNoHalt("[" .. PDCity.BRAND_TAG .. "] " .. WHITELIST_PATH .. " was unreadable - starting with an empty inventory whitelist.\n")
	end
end

LoadWhitelist()

local function BroadcastWhitelist(ply)
	net.Start("pdcity_inv_whitelist")
		net.WriteString(util.TableToJSON(PDCity.INVENTORY_ALLOWED))
	if IsValid(ply) then net.Send(ply) else net.Broadcast() end
end

-- Returns ok[, error] rather than chat-printing/early-returning directly,
-- so the net.Receive below can report a failure back to the admin the
-- same way as every other admin action in this gamemode.
local function ApplyInventoryAction(action, class)
	if action == "add" then
		if PDCity.INVENTORY_BLOCKED[class] then
			return false, "That item can never be stored in an inventory."
		end
		if class == PDCity.MONEY_CLASS then
			return false, "Money always goes to the wallet - it can't be an inventory item."
		end
		if weapons.GetStored(class) == nil and scripted_ents.GetStored(class) == nil then
			return false, "Not a recognised entity/weapon class."
		end
		if table.HasValue(PDCity.INVENTORY_ALLOWED, class) then return true end

		table.insert(PDCity.INVENTORY_ALLOWED, class)

	elseif action == "remove" then
		if not table.HasValue(PDCity.INVENTORY_ALLOWED, class) then return true end
		table.RemoveByValue(PDCity.INVENTORY_ALLOWED, class)

	else
		return false, "Unknown action."
	end

	SaveWhitelist()
	BroadcastWhitelist()
	return true
end

-- Global - the Inventory Whitelist toolgun (entities/weapons/gmod_tool/
-- stools/pdcity_invwhitelist.lua) calls this directly rather than
-- round-tripping through "pdcity_inv_admin", since a tool's LeftClick/
-- RightClick already runs server-side with the owner and traced entity
-- both in hand - no client involvement needed for the mutation itself.
PDCity.SetInventoryWhitelist = ApplyInventoryAction

net.Receive("pdcity_inv_admin", function(len, ply)
	-- Owner only - re-checked here regardless of what the client's UI
	-- already hides (cl_f4_admin.lua).
	if not PDCity.IsOwner(ply) then return end

	local data = util.JSONToTable(net.ReadString() or "")
	if not istable(data) or not isstring(data.Action) or not isstring(data.Class) then return end

	local ok, err = ApplyInventoryAction(data.Action, data.Class)

	if not ok then
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] " .. (err or "That action failed."))
	end
end)

--[[---------------------------------------------------------
	Storage
-----------------------------------------------------------]]

-- Normalises the profile's inventory table in place and returns it.
local function GetInventory(ply)
	local profile = PDCity.GetProfile(ply)
	if not profile then return nil end

	if not istable(profile.Inventory) then
		profile.Inventory = {}
	end

	-- JSON string keys -> numbers. Done lazily on first access rather
	-- than at load, so this file doesn't have to hook into the profile
	-- loader's own lifecycle.
	local needsFix = false
	for key in pairs(profile.Inventory) do
		if not isnumber(key) then needsFix = true break end
	end

	if needsFix then
		local fixed = {}
		for key, entry in pairs(profile.Inventory) do
			local slot = tonumber(key)
			if slot then fixed[slot] = entry end
		end
		profile.Inventory = fixed
	end

	return profile.Inventory
end

PDCity.GetInventory = GetInventory

-- How many of the (up to 36) slots this specific player can actually
-- use right now - core/sh_inventory.lua's level-based formula, applied
-- to their own total job-class levels (core/sv_job_xp.lua).
local function GetCapacity(ply)
	return PDCity.GetInventoryCapacity(PDCity.GetTotalJobLevels(ply))
end
PDCity.GetInventoryCapacityFor = GetCapacity

function PDCity.SyncInventory(ply)
	local inv = GetInventory(ply)
	if not inv then return end

	net.Start("pdcity_inv_sync")
		net.WriteString(util.TableToJSON({ Slots = inv }))
		net.WriteBool(false) -- not a read-only admin view
		net.WriteString("")
		net.WriteUInt(GetCapacity(ply), 8)
	net.Send(ply)
end

-- A level-up in ANY class can raise total levels past a tier threshold -
-- re-syncs immediately so the newly-unlocked row shows up live rather
-- than only after a reconnect.
hook.Add("PDCity_JobClassLevelUp", "pdcity_ResyncInventoryCapacity", function(ply)
	PDCity.SyncInventory(ply)
end)

--[[---------------------------------------------------------
	Adding / removing
-----------------------------------------------------------]]

-- Fills existing partial stacks of the same class first, then empty
-- slots. Returns how many were actually stored (0 if full).
function PDCity.InventoryAdd(ply, class, count)
	local inv = GetInventory(ply)
	if not inv then return 0 end
	if not PDCity.CanStoreItem(class) then return 0 end

	count = math.max(1, math.floor(tonumber(count) or 1))
	local stored = 0
	local capacity = GetCapacity(ply)

	for slot = 1, capacity do
		if count <= 0 then break end
		local entry = inv[slot]
		if entry and entry.Class == class and entry.Count < PDCity.INVENTORY_MAX_STACK then
			local room = PDCity.INVENTORY_MAX_STACK - entry.Count
			local moved = math.min(room, count)
			entry.Count = entry.Count + moved
			count = count - moved
			stored = stored + moved
		end
	end

	for slot = 1, capacity do
		if count <= 0 then break end
		if not inv[slot] then
			local moved = math.min(PDCity.INVENTORY_MAX_STACK, count)
			inv[slot] = { Class = class, Count = moved }
			count = count - moved
			stored = stored + moved
		end
	end

	if stored > 0 then
		PDCity.MarkProfileDirty(ply)
		PDCity.SyncInventory(ply)
	end

	return stored
end

-- Removes up to count from a slot. Returns how many were removed.
local function RemoveFromSlot(ply, slot, count)
	local inv = GetInventory(ply)
	if not inv then return 0 end

	local entry = inv[slot]
	if not entry then return 0 end

	local removed = math.min(entry.Count, count)
	entry.Count = entry.Count - removed

	if entry.Count <= 0 then inv[slot] = nil end

	if removed > 0 then
		PDCity.MarkProfileDirty(ply)
		PDCity.SyncInventory(ply)
	end

	return removed
end

-- Removes up to `count` of `class`, searching every slot (not just one) -
-- PDCity.InventoryAdd's missing counterpart, added when a Developer
-- Console NPC-seller script needed to take an item back rather than
-- just ever handing them out. Returns how many were actually removed
-- (0 if the player doesn't have any) - callers should check this before
-- paying out, the same way PDCity.AddMoney's own return value is
-- checked before treating a charge as having gone through.
function PDCity.InventoryRemove(ply, class, count)
	local inv = GetInventory(ply)
	if not inv then return 0 end

	count = math.max(1, math.floor(tonumber(count) or 1))
	local removed = 0
	local capacity = GetCapacity(ply)

	for slot = 1, capacity do
		if count <= 0 then break end
		local entry = inv[slot]
		if entry and entry.Class == class then
			local took = RemoveFromSlot(ply, slot, count)
			removed = removed + took
			count = count - took
		end
	end

	return removed
end

-- How many of `class` the player currently holds, summed across every
-- slot - lets a seller script check "can they even afford to sell this"
-- before attempting PDCity.InventoryRemove.
function PDCity.InventoryCount(ply, class)
	local inv = GetInventory(ply)
	if not inv then return 0 end

	local total = 0
	for _, entry in pairs(inv) do
		if entry and entry.Class == class then total = total + entry.Count end
	end

	return total
end

--[[---------------------------------------------------------
	Dropping back into the world
-----------------------------------------------------------]]

local function SpawnItemInWorld(ply, class)
	local tr = util.TraceLine({
		start = ply:GetShootPos(),
		endpos = ply:GetShootPos() + ply:GetAimVector() * 64,
		filter = ply,
	})

	local ent = ents.Create(class)
	if not IsValid(ent) then return nil end

	ent:SetPos(tr.HitPos + tr.HitNormal * 8)
	ent:SetAngles(Angle(0, ply:EyeAngles().y, 0))
	ent:Spawn()
	ent:Activate()

	-- Same treatment /drop gives a dropped weapon: no walk-over
	-- auto-pickup, +USE only (see core/sv_drop.lua).
	if ent:IsWeapon() then
		ent.pdcity_DroppedWeapon = true
	end

	local phys = ent:GetPhysicsObject()
	if IsValid(phys) then phys:Wake() end

	return ent
end

local function DropFromSlot(ply, slot, count)
	local inv = GetInventory(ply)
	if not inv then return end

	local entry = inv[slot]
	if not entry then return end

	count = math.Clamp(math.floor(tonumber(count) or 1), 1, entry.Count)

	local class = entry.Class
	local dropped = 0

	for _ = 1, count do
		if not IsValid(SpawnItemInWorld(ply, class)) then break end
		dropped = dropped + 1
	end

	if dropped > 0 then
		RemoveFromSlot(ply, slot, dropped)
		PDCity.GameLog("inventory", ply:Nick() .. " (" .. ply:SteamID() .. ") dropped "
			.. dropped .. "x " .. PDCity.GetItemName(class))
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Dropped " .. dropped .. "x " .. PDCity.GetItemName(class) .. ".")
	end
end

--[[---------------------------------------------------------
	Moving between slots (drag & drop in the UI)
-----------------------------------------------------------]]

local function MoveSlot(ply, from, to)
	local inv = GetInventory(ply)
	if not inv then return end
	if from == to then return end

	local source = inv[from]
	if not source then return end

	local dest = inv[to]

	if dest and dest.Class == source.Class then
		-- Merge stacks, leaving any overflow behind in the source slot.
		local room = PDCity.INVENTORY_MAX_STACK - dest.Count
		local moved = math.min(room, source.Count)

		dest.Count = dest.Count + moved
		source.Count = source.Count - moved
		if source.Count <= 0 then inv[from] = nil end
	else
		-- Plain swap (dest may be nil, which is just a move).
		inv[to] = source
		inv[from] = dest
	end

	PDCity.MarkProfileDirty(ply)
	PDCity.SyncInventory(ply)
end

-- Moves part of a stack into the first free slot, leaving the rest
-- behind. count is how many to split OFF, so it has to leave at least
-- one behind (splitting the whole stack is just a move).
local function SplitSlot(ply, slot, count)
	local inv = GetInventory(ply)
	if not inv then return end

	local entry = inv[slot]
	if not entry or entry.Count < 2 then return end

	count = math.Clamp(math.floor(tonumber(count) or 0), 1, entry.Count - 1)

	local free
	for i = 1, GetCapacity(ply) do
		if not inv[i] then free = i break end
	end

	if not free then
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] No free slot to split into.")
		return
	end

	entry.Count = entry.Count - count
	inv[free] = { Class = entry.Class, Count = count }

	PDCity.MarkProfileDirty(ply)
	PDCity.SyncInventory(ply)
end

--[[---------------------------------------------------------
	Client requests
-----------------------------------------------------------]]

net.Receive("pdcity_inv_action", function(len, ply)
	if not IsValid(ply) then return end

	local data = util.JSONToTable(net.ReadString() or "")
	if not istable(data) or not isstring(data.Action) then return end

	-- Capped at THIS player's current capacity, not the flat max (36) -
	-- otherwise a modified client could address/move into a row they
	-- haven't unlocked yet by level.
	local capacity = GetCapacity(ply)
	local function ValidSlot(n)
		n = tonumber(n)
		return n and n >= 1 and n <= capacity and math.floor(n) == n and n
	end

	if data.Action == "move" then
		local from, to = ValidSlot(data.From), ValidSlot(data.To)
		if from and to then MoveSlot(ply, from, to) end

	elseif data.Action == "drop" then
		local slot = ValidSlot(data.Slot)
		if slot and ply:Alive() then DropFromSlot(ply, slot, data.Count or 1) end

	elseif data.Action == "split" then
		local slot = ValidSlot(data.Slot)
		if slot then SplitSlot(ply, slot, data.Count) end
	end
end)

--[[---------------------------------------------------------
	Picking things up: CTRL+E stores, plain E is left to whatever the
	entity itself does on Use (money crediting the wallet, a printer
	opening its menu, ...).

	CTRL is IN_DUCK, so "crouch held while USE is pressed" is the test.
-----------------------------------------------------------]]

local function TryInventoryPickup(ply)
	local tr = util.TraceLine({
		start = ply:GetShootPos(),
		endpos = ply:GetShootPos() + ply:GetAimVector() * PICKUP_RANGE,
		filter = ply,
	})

	local ent = tr.Entity
	if not IsValid(ent) then return end

	local class = ent:GetClass()

	-- Money never goes in the inventory - CTRL+E on it behaves exactly
	-- like plain E, crediting the wallet. Nothing to do here to make
	-- that happen: the same keypress already runs the engine's own
	-- +USE, which calls the entity's Use and banks the cash. Calling
	-- Use here as well would just try to bank it twice.
	if class == PDCity.MONEY_CLASS then return end

	if PDCity.INVENTORY_BLOCKED[class] then
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] You can't put that in your inventory.")
		return
	end

	if not PDCity.CanStoreItem(class) then
		-- Only worth saying anything for things that could plausibly be
		-- items - staying quiet for map geometry and ordinary props, or
		-- every mistimed crouch-and-use would spam chat.
		if weapons.GetStored(class) or scripted_ents.GetStored(class) then
			ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] That isn't an inventory item.")
		end
		return
	end

	-- A weapon someone is holding isn't lying around to be taken.
	if ent:IsWeapon() and IsValid(ent:GetOwner()) then return end

	if PDCity.InventoryAdd(ply, class, 1) < 1 then
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Your inventory is full.")
		return
	end

	ply:EmitSound("items/ammo_pickup.wav", 60, 110)
	ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Picked up " .. PDCity.GetItemName(class) .. ".")
	ent:Remove()
end

hook.Add("KeyPress", "pdcity_InventoryPickup", function(ply, key)
	if key ~= IN_USE then return end
	if not IsValid(ply) or not ply:Alive() then return end
	if not ply:KeyDown(IN_DUCK) then return end

	TryInventoryPickup(ply)
end)

-- The storable-CLASS whitelist (which item classes exist at all) is a
-- global catalogue, not per-character - safe on ordinary PlayerInitialSpawn.
-- The actual CONTENTS (PDCity.SyncInventory) are per-character
-- (core/sv_profiles.lua), so that one waits for character selection
-- instead (core/sv_characters.lua) - there's no inventory to sync before
-- a character's actually been picked.
hook.Add("PlayerInitialSpawn", "pdcity_SyncInventoryWhitelist", function(ply)
	if ply:IsBot() then return end
	timer.Simple(1, function()
		if not IsValid(ply) then return end
		BroadcastWhitelist(ply)
	end)
end)

hook.Add("PDCity_CharacterSelected", "pdcity_SyncInventoryOnCharacterSelect", function(ply)
	PDCity.SyncInventory(ply)
end)

--[[---------------------------------------------------------
	Admin: pdcity_viewinv <partial name>
	Opens a read-only copy of someone's inventory. Deliberately silent -
	the target is never told, and nothing is sent to them.
-----------------------------------------------------------]]

concommand.Add("pdcity_viewinv", function(ply, cmd, args)
	if not IsValid(ply) or not ply:IsAdmin() then return end

	local search = args[1] and string.lower(args[1])
	if not search then
		ply:PrintMessage(HUD_PRINTCONSOLE, "[" .. PDCity.BRAND_TAG .. "] Usage: pdcity_viewinv <partial player name>")
		return
	end

	local target
	for _, other in ipairs(player.GetHumans()) do
		if string.find(string.lower(other:Nick()), search, 1, true) then
			target = other
			break
		end
	end

	if not IsValid(target) then
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] No matching player found.")
		return
	end

	local inv = GetInventory(target)
	if not inv then
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] That player has no profile.")
		return
	end

	PDCity.GameLog("staff", ply:Nick() .. " (" .. ply:SteamID() .. ") viewed "
		.. target:Nick() .. " (" .. target:SteamID() .. ")'s inventory")

	net.Start("pdcity_inv_sync")
		net.WriteString(util.TableToJSON({ Slots = inv }))
		net.WriteBool(true) -- read-only
		net.WriteString(target:Nick())
		net.WriteUInt(GetCapacity(target), 8) -- the TARGET's capacity, so the reviewer sees their real lock state
	net.Send(ply)
end)
