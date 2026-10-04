--[[---------------------------------------------------------
	Inventory screen - a 6-wide grid, up to 6 rows (36 slots) deep, each
	slot holding a stack of up to PDCity.INVENTORY_MAX_STACK of one item,
	drawn as the item's own 3D model (SpawnIcon) with a stack count in
	the corner.

	  drag & drop  - move a stack between slots; dropping onto a
	                 matching stack merges, onto anything else swaps
	  right click  - Drop (one) / Drop X (choose how many)

	Everything here is a view: the server owns the contents and
	re-validates every request (core/sv_inventory.lua). This file never
	changes what it's showing directly - it asks, then redraws whatever
	the server sends back.

	Not every row is usable from the start - core/sh_inventory.lua's
	PDCity.GetInventoryCapacity grows it by a full row (+6 slots) for
	every 10 total job-class levels, capped at all 6 rows. Locked rows
	aren't shown at all - the grid only ever renders as many rows as the
	player currently has, growing (and the window resizing with it) the
	moment more unlock rather than sitting there as greyed-out padlocks.

	Opened by holding C (a quick peek - closes the moment you let go,
	unless it was already open some other way, see the Think hook below)
	or with F2 (see core/sv_door_claim.lua for how that key is shared
	with the door-claim action), or by an admin for someone else via
	"pdcity_viewinv <name>", which opens the same UI read-only.
-----------------------------------------------------------]]

local SLOT_SIZE = 72
-- 0, not a gap - "fully connected grid" (adjoining slots share a border
-- rather than floating as separate rounded boxes with daylight between
-- them). Each slot still draws its own 1px outline (below), which lines
-- up edge-to-edge with its neighbours' at this spacing and reads as one
-- continuous grid of grid lines rather than a stack of individual cards.
local SLOT_SPACING = 0

-- Last contents the server sent us, and whether they're ours to edit.
PDCity.INVENTORY = PDCity.INVENTORY or {}
-- How many of the (up to PDCity.INVENTORY_SLOTS) slots we can actually
-- use right now - synced alongside contents, defaults to the base size
-- until the first real sync lands.
PDCity.INVENTORY_CAPACITY = PDCity.INVENTORY_CAPACITY or PDCity.INVENTORY_BASE_SLOTS

local activeFrame
local activeIsReadOnly = false

local function SendAction(action, payload)
	payload = payload or {}
	payload.Action = action

	net.Start("pdcity_inv_action")
		net.WriteString(util.TableToJSON(payload))
	net.SendToServer()
end

--[[---------------------------------------------------------
	One slot. Always exists for every UNLOCKED index (empty slots are
	still drop targets) - BuildGrid below never even calls this for a
	locked one any more, so there's nothing here to guard against.
-----------------------------------------------------------]]
local function BuildSlot(parent, index, entry, readOnly)

	local slot = vgui.Create("DPanel", parent)
	slot:SetSize(SLOT_SIZE, SLOT_SIZE)
	slot.pdcitySlot = index
	slot.Paint = function(self, w, h)
		draw.RoundedBox(0, 0, 0, w, h, PDCity.THEME.Panel)
		surface.SetDrawColor(PDCity.THEME.Border)
		surface.DrawOutlinedRect(0, 0, w, h, 1)
	end

	if not readOnly then
		slot:Receiver("pdcity_inv", function(self, panels, dropped)
			if not dropped then return end

			local dragged = panels[1]
			if not IsValid(dragged) or not dragged.pdcitySlot then return end
			if dragged.pdcitySlot == self.pdcitySlot then return end

			SendAction("move", { From = dragged.pdcitySlot, To = self.pdcitySlot })
		end)
	end

	if not entry then return slot end

	local model = PDCity.GetItemModel(entry.Class)
	local name = PDCity.GetItemName(entry.Class)

	local icon
	if model then
		icon = vgui.Create("SpawnIcon", slot)
		icon:SetModel(model)
	else
		-- No resolvable model (point/logic entities) - show the name.
		icon = vgui.Create("DButton", slot)
		icon:SetText(name)
		icon:SetTextColor(PDCity.THEME.Text)
		icon.Paint = function() end
	end

	icon:SetPos(4, 4)
	icon:SetSize(SLOT_SIZE - 8, SLOT_SIZE - 8)
	icon:SetTooltip(name .. " x" .. entry.Count)
	icon.pdcitySlot = index

	-- Stack count, bottom-right, only once there's more than one.
	icon.PaintOver = function(self, w, h)
		if entry.Count <= 1 then return end
		draw.SimpleTextOutlined(entry.Count, "PDCity_Small", w - 3, h - 3,
			PDCity.THEME.Text, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM, 1, Color(0, 0, 0, 230))
	end

	if readOnly then
		-- Admin view: look, don't touch.
		icon:SetMouseInputEnabled(false)
		return slot
	end

	icon:Droppable("pdcity_inv")

	icon.DoRightClick = function()
		local menu = DermaMenu()

		menu:AddOption("Drop", function()
			SendAction("drop", { Slot = index, Count = 1 })
		end):SetIcon("icon16/arrow_down.png")

		if entry.Count > 1 then
			menu:AddOption("Drop X...", function()
				Derma_StringRequest(
					"Drop " .. name,
					"How many? (1 - " .. entry.Count .. ")",
					tostring(entry.Count),
					function(text)
						local count = math.floor(tonumber(text) or 0)
						if count < 1 then return end
						SendAction("drop", { Slot = index, Count = math.min(count, entry.Count) })
					end
				)
			end):SetIcon("icon16/arrow_down.png")

			menu:AddSpacer()

			-- Half, rounded down, so an odd stack leaves the larger
			-- part where it already was.
			menu:AddOption("Split Stack", function()
				SendAction("split", { Slot = index, Count = math.floor(entry.Count / 2) })
			end):SetIcon("icon16/arrow_divide.png")

			menu:AddOption("Split X...", function()
				Derma_StringRequest(
					"Split " .. name,
					"Move how many into a new slot? (1 - " .. (entry.Count - 1) .. ")",
					tostring(math.floor(entry.Count / 2)),
					function(text)
						local count = math.floor(tonumber(text) or 0)
						if count < 1 then return end
						SendAction("split", { Slot = index, Count = math.min(count, entry.Count - 1) })
					end
				)
			end):SetIcon("icon16/arrow_divide.png")
		end

		menu:Open()
	end

	return slot

end

--[[---------------------------------------------------------
	Frame
-----------------------------------------------------------]]

-- Grid pixel size for a given capacity - always the full 6 columns wide,
-- but only as many rows as are actually unlocked (rounded up, so a
-- capacity that isn't an exact multiple of a row still gets that
-- partial row's height - shouldn't happen given rows unlock as whole
-- +6 chunks, core/sh_inventory.lua, but safe regardless).
local function GridSize(capacity)
	local rows = math.max(1, math.ceil(capacity / PDCity.INVENTORY_COLS))
	local width = PDCity.INVENTORY_COLS * SLOT_SIZE + (PDCity.INVENTORY_COLS - 1) * SLOT_SPACING
	local height = rows * SLOT_SIZE + (rows - 1) * SLOT_SPACING
	return width, height
end

local function BuildGrid(parent, slots, readOnly, capacity)

	local grid = vgui.Create("DPanel", parent)
	grid:Dock(FILL)
	grid.Paint = function() end

	for index = 1, capacity do
		local col = (index - 1) % PDCity.INVENTORY_COLS
		local row = math.floor((index - 1) / PDCity.INVENTORY_COLS)

		local slot = BuildSlot(grid, index, slots[index], readOnly)
		slot:SetPos(col * (SLOT_SIZE + SLOT_SPACING), row * (SLOT_SIZE + SLOT_SPACING))
	end

	return grid

end

local function OpenInventoryFrame(slots, readOnly, ownerName, capacity)

	if IsValid(activeFrame) then activeFrame:Remove() end

	capacity = capacity or PDCity.INVENTORY_CAPACITY

	local width, height = GridSize(capacity)

	local title = readOnly and (ownerName .. "'s Inventory (read-only)") or "Inventory"

	local frame = PDCity.CreateModernFrame(title, width + 40, height + 88)

	-- PDCity.CreateModernFrame enforces a 560x360 floor (sized for its
	-- usual bigger menus), which left dead space along the right/bottom
	-- edges any time the grid itself - especially at base capacity,
	-- before levelling unlocks extra rows - came out smaller than that.
	-- That floor only applies to the SIZE PASSED INTO the constructor;
	-- calling :SetSize directly afterwards (same as PDCityRebuild's own
	-- resize below already does) isn't clamped, so this forces the frame
	-- down to the grid's own true size instead.
	frame:SetSize(width + 40, height + 88)
	frame:Center()

	activeFrame = frame
	activeIsReadOnly = readOnly

	local content = vgui.Create("DPanel", frame)
	content:SetPos(20, 68)
	content:SetSize(width, height)
	content.Paint = function() end

	local grid = BuildGrid(content, slots, readOnly, capacity)

	-- Swaps the slot grid for a freshly-built one WITHOUT touching the
	-- frame's fade-in. Recreating the whole FRAME on every server sync
	-- (which is what dragging a stack triggers) replayed
	-- PDCity.CreateModernFrame's fade-in from alpha 0, which read as the
	-- window blinking off and back on mid-drag - only the frame/content
	-- SIZE changes here, and only when capacity itself actually grew
	-- (a level-up while the window's already open), not on every
	-- ordinary contents sync.
	frame.PDCityRebuild = function(newSlots, newCapacity)
		newCapacity = newCapacity or capacity
		if newCapacity ~= capacity then
			capacity = newCapacity
			local newWidth, newHeight = GridSize(capacity)
			frame:SetSize(newWidth + 40, newHeight + 88)
			frame:Center()
			content:SetSize(newWidth, newHeight)
		end

		if IsValid(grid) then grid:Remove() end
		grid = BuildGrid(content, newSlots, readOnly, capacity)
	end

	frame.OnClose = function()
		activeFrame = nil
	end

	return frame

end

--[[---------------------------------------------------------
	Server pushes contents here on every change; if the matching window
	is open, rebuild its grid in place so it always shows the truth.
-----------------------------------------------------------]]

net.Receive("pdcity_inv_sync", function()
	local data = util.JSONToTable(net.ReadString() or "")
	local readOnly = net.ReadBool()
	local ownerName = net.ReadString()
	local capacity = net.ReadUInt(8)

	if not istable(data) then return end

	-- JSON turns the numeric slot keys into strings on the way over.
	local slots = {}
	for key, entry in pairs(data.Slots or {}) do
		local index = tonumber(key)
		if index then slots[index] = entry end
	end

	if readOnly then
		-- An admin's snapshot of somebody else - always opens a window,
		-- never overwrites the player's own cached contents.
		OpenInventoryFrame(slots, true, ownerName, capacity)
		return
	end

	PDCity.INVENTORY = slots
	PDCity.INVENTORY_CAPACITY = capacity

	-- Only refresh a window that's showing OUR inventory; an open admin
	-- view of someone else shouldn't be replaced by our own contents.
	if IsValid(activeFrame) and not activeIsReadOnly then
		activeFrame.PDCityRebuild(slots, capacity)
	end
end)

net.Receive("pdcity_inv_whitelist", function()
	local stored = util.JSONToTable(net.ReadString() or "")
	if istable(stored) then
		PDCity.INVENTORY_ALLOWED = stored
		hook.Run("PDCity_InventoryWhitelistUpdated")
	end
end)

function PDCity.OpenInventory()
	if IsValid(activeFrame) then
		activeFrame:Remove()
		activeFrame = nil
		return
	end

	OpenInventoryFrame(PDCity.INVENTORY, false, nil, PDCity.INVENTORY_CAPACITY)
end

concommand.Add("pdcity_inventory", PDCity.OpenInventory)

--[[---------------------------------------------------------
	Hold C - a quick peek, closes the instant you let go. Polled client-
	side every frame rather than through core/sh_keybinds.lua's server-
	listened system: that system only ever sees a discrete press/release
	as a game BUTTON, which the engine stops sending to the server at
	all while a VGUI panel has keyboard focus (this frame's own focus,
	the moment it opens) - the exact bug already hit once with the Staff
	Menu's own hotkey. input.IsKeyDown reads the raw physical key state
	instead, unaffected by that.

	Only auto-closes what THIS opened - if the inventory is already open
	some other way (F2, or an admin's read-only view), holding/releasing
	C afterwards leaves it alone rather than yanking it shut under them.
-----------------------------------------------------------]]
local heldOpenedIt = false

hook.Add("Think", "pdcity_InventoryHoldC", function()
	local ply = LocalPlayer()
	if not IsValid(ply) then return end

	local down = ply:Alive() and not ply:IsTyping() and input.IsKeyDown(KEY_C)

	if down then
		if not IsValid(activeFrame) then
			OpenInventoryFrame(PDCity.INVENTORY, false, nil, PDCity.INVENTORY_CAPACITY)
			heldOpenedIt = true
		end
	elseif heldOpenedIt then
		heldOpenedIt = false
		if IsValid(activeFrame) and not activeIsReadOnly then
			activeFrame:Remove()
			activeFrame = nil
		end
	end
end)
