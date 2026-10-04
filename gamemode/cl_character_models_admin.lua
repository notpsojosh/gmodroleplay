--[[---------------------------------------------------------
	Character Model list/whitelist editor - owner-only, Site Admin tab
	(cl_site_admin.lua). Two things live here (core/sv_character_models.lua):

	  Models     the global default list every character can pick from -
	             edited as a working copy, committed with "Save Default Models"
	  Whitelist  [steamID] = { model, ... } - EXTRA models only that player
	             may pick. Edited through the "Add to Whitelist" form and
	             the whitelisted-players list; each change saves immediately.

	The model grid on the right (cl_f4_admin.lua's
	PDCity.BuildPlayerModelPicker) adds to whichever list is its current
	target - shown in its heading.
-----------------------------------------------------------]]

net.Receive("pdcity_character_models_sync", function()
	PDCity.CHARACTER_MODEL_CONFIG = util.JSONToTable(net.ReadString() or "{}") or { Models = {}, Whitelist = {}, WhitelistNames = {} }
	hook.Run("PDCity_CharacterModelsUpdated")
end)

local function SendWhitelistAction(action, payload)
	payload = payload or {}
	payload.Action = action
	net.Start("pdcity_character_whitelist_admin")
		net.WriteString(util.TableToJSON(payload))
	net.SendToServer()
end

local function Config()
	local cfg = PDCity.CHARACTER_MODEL_CONFIG or {}
	return {
		Models = cfg.Models or {},
		Whitelist = cfg.Whitelist or {},
		WhitelistNames = cfg.WhitelistNames or {},
	}
end

-- Best name for a whitelisted SteamID: whoever's online with it now, then
-- the name recorded on the server, then a placeholder.
local function WhitelistName(steamID)
	local online = player.GetBySteamID(steamID)
	if IsValid(online) then return online:Nick() end
	return Config().WhitelistNames[steamID] or "Unknown player"
end

local function ShortModelName(model)
	return string.match(model, "([^/]+)%.mdl$") or model
end

-- A model chip: small thumbnail, name, and a ✕ - red on hover, since
-- clicking it calls onRemove. Sized from the measured text.
local CHIP_H, THUMB = 30, 26

local function AddModelChip(parent, model, onRemove)
	local shortName = ShortModelName(model)

	surface.SetFont("PDCity_Small")
	local textW = surface.GetTextSize(shortName)

	local chip = vgui.Create("DButton", parent)
	chip:SetSize(2 + THUMB + 8 + textW + 10 + 12 + 8, CHIP_H)
	chip:SetText("")
	chip:SetTooltip(model .. "\nClick to remove")
	chip.Paint = function(self, w, h)
		local hovered = self:IsHovered()
		draw.RoundedBox(6, 0, 0, w, h, hovered and Color(190, 70, 70) or ColorAlpha(PDCity.THEME.Accent, 70))
		draw.SimpleText(shortName, "PDCity_Small", 2 + THUMB + 8, h / 2, PDCity.THEME.Text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		draw.SimpleText("\226\156\149", "PDCity_Small", w - 12, h / 2, hovered and PDCity.THEME.Text or PDCity.THEME.TextDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
	chip.DoClick = onRemove

	local thumb = vgui.Create("SpawnIcon", chip)
	thumb:SetPos(2, (CHIP_H - THUMB) / 2)
	thumb:SetSize(THUMB, THUMB)
	thumb:SetModel(model)
	thumb:SetMouseInputEnabled(false)

	return chip
end

local function ChipLayout(parent)
	local layout = vgui.Create("DIconLayout", parent)
	layout:Dock(TOP)
	layout:DockMargin(0, 6, 0, 0)
	layout:SetSpaceX(6)
	layout:SetSpaceY(6)
	-- Chips wrapping onto another line changes this height; the box
	-- around it has to re-fit.
	layout.OnSizeChanged = function() parent:InvalidateLayout() end
	return layout
end

function PDCity.BuildCharacterModelsTab(parent)

	local root = vgui.Create("DPanel", parent)
	root:Dock(FILL)
	root.Paint = function() end

	--[[-----------------------------------------------------
		Grid target: "default" (the default list), "form" (the Add to
		Whitelist form's pending models), or "player" (the player selected
		in the whitelisted list - adds save immediately).
	-------------------------------------------------------]]
	local pickTarget = "default"
	local selectedSteamID -- the player shown in the detail view
	local OnModelPicked -- set once the lists below exist

	-- Before the form: a RIGHT dock must come before the FILL one.
	local picker = PDCity.BuildPlayerModelPicker(root, function(model) OnModelPicked(model) end, { Header = "" })
	picker:Dock(RIGHT)
	picker:SetWide(420)
	picker:DockMargin(12, 0, 0, 0)

	local function SetPickTarget(target)
		pickTarget = target

		local label = "Default Models"
		if target == "form" then
			label = "the Add to Whitelist form"
		elseif target == "player" and selectedSteamID then
			label = WhitelistName(selectedSteamID)
		end
		picker:SetHeader("Click to add to: " .. label)
	end

	local formHolder = vgui.Create("DPanel", root)
	formHolder:Dock(FILL)
	formHolder.Paint = function(self, w, h) draw.RoundedBox(6, 0, 0, w, h, PDCity.THEME.Panel) end

	local form = vgui.Create("DScrollPanel", formHolder)
	form:Dock(FILL)
	form:DockMargin(14, 14, 14, 14)
	PDCity.ApplyFastScroll(form)

	local function Heading(text, topMargin)
		local label = vgui.Create("DLabel", form)
		label:Dock(TOP)
		label:SetTall(22)
		label:DockMargin(0, topMargin or 0, 0, 0)
		label:SetFont("PDCity_Heading")
		label:SetText(text)
		label:SetTextColor(PDCity.THEME.Text)
		return label
	end

	local function Hint(text, tall)
		local label = vgui.Create("DLabel", form)
		label:Dock(TOP)
		label:SetTall(tall or 18)
		label:DockMargin(0, 2, 0, 0)
		label:SetFont("PDCity_Small")
		label:SetWrap(true)
		label:SetText(text)
		label:SetTextColor(PDCity.THEME.TextDim)
		return label
	end

	-- A section box that gets an accent outline while it's the grid's target.
	local function Section(target)
		local box = vgui.Create("DPanel", form)
		box:Dock(TOP)
		box:DockMargin(0, 8, 0, 0)
		box:DockPadding(12, 10, 12, 12)
		box.Paint = function(self, w, h)
			if pickTarget == target then
				draw.RoundedBox(6, 0, 0, w, h, PDCity.THEME.Accent)
				draw.RoundedBox(6, 1, 1, w - 2, h - 2, PDCity.THEME.Background)
			else
				draw.RoundedBox(6, 0, 0, w, h, PDCity.THEME.Background)
			end
		end
		-- Fits its contents plus the bottom padding, and re-flows the scroll
		-- area whenever that changes its height. Only resizes when the
		-- height actually differs, so it can't keep re-triggering itself.
		box.PerformLayout = function(self)
			local bottom = 0
			for _, child in ipairs(self:GetChildren()) do
				if child:IsVisible() then
					local _, y = child:GetPos()
					bottom = math.max(bottom, y + child:GetTall())
				end
			end
			local wanted = bottom + 12
			if self:GetTall() ~= wanted then self:SetTall(wanted) end
		end
		box.OnSizeChanged = function() form:InvalidateLayout() end
		return box
	end

	local GHOST_BUTTON = { Accent = PDCity.THEME.Panel, AccentDim = PDCity.THEME.PanelHover, TextColor = PDCity.THEME.TextDim }
	local DANGER_BUTTON = { Accent = Color(190, 70, 70), AccentDim = Color(140, 55, 55) }

	--[[-----------------------------------------------------
		Default models (working copy, "Save Default Models" commits)
	-------------------------------------------------------]]
	Hint("Which player models a character can choose. Default Models is what every player can pick from; the whitelist below grants specific players EXTRA models on top.", 34)

	Heading("Default Models", 10)

	local defaultBox = Section("default")
	local models = {}

	local modelListView = vgui.Create("DListView", defaultBox)
	modelListView:Dock(TOP)
	modelListView:SetMultiSelect(false)
	modelListView:AddColumn("Model path")
	modelListView:SetTall(64)

	local function RefreshModelList()
		modelListView:Clear()
		for _, path in ipairs(models) do
			local line = modelListView:AddLine(path)
			line.pdcityModelPath = path
		end
		modelListView:SetTall(math.Clamp(16 + #models * 18 + 4, 64, 200))
		defaultBox:InvalidateLayout()
	end

	local defaultBtnRow = vgui.Create("DPanel", defaultBox)
	defaultBtnRow:Dock(TOP)
	defaultBtnRow:SetTall(28)
	defaultBtnRow:DockMargin(0, 8, 0, 0)
	defaultBtnRow.Paint = function() end

	local addDefaultBtn = vgui.Create("DButton", defaultBtnRow)
	addDefaultBtn:Dock(LEFT)
	addDefaultBtn:SetWide(190)
	PDCity.StyleButton(addDefaultBtn, "+ Add Models (from the grid)", GHOST_BUTTON)
	addDefaultBtn.DoClick = function() SetPickTarget("default") end

	local removeDefaultBtn = vgui.Create("DButton", defaultBtnRow)
	removeDefaultBtn:Dock(LEFT)
	removeDefaultBtn:SetWide(140)
	removeDefaultBtn:DockMargin(8, 0, 0, 0)
	PDCity.StyleButton(removeDefaultBtn, "Remove Selected", DANGER_BUTTON)
	removeDefaultBtn.DoClick = function()
		local selected = modelListView:GetSelected()
		local row = selected and selected[1]
		if not row then return end
		table.RemoveByValue(models, row.pdcityModelPath)
		RefreshModelList()
	end

	local saveDefaultBtn = vgui.Create("DButton", defaultBtnRow)
	saveDefaultBtn:Dock(RIGHT)
	saveDefaultBtn:SetWide(170)
	PDCity.StyleButton(saveDefaultBtn, "Save Default Models")
	saveDefaultBtn.DoClick = function()
		net.Start("pdcity_character_models_admin")
			net.WriteString(util.TableToJSON({ Models = models }))
		net.SendToServer()
	end

	--[[-----------------------------------------------------
		Add to Whitelist form - submitting merges into the player's
		existing entry if they already have one.
	-------------------------------------------------------]]
	Heading("Add to Whitelist", 18)
	Hint("Give one player extra models. If they're already whitelisted, these are added to what they have.")

	local formBox = Section("form")
	local pendingModels = {}

	local steamRow = vgui.Create("DPanel", formBox)
	steamRow:Dock(TOP)
	steamRow:SetTall(26)
	steamRow.Paint = function() end

	local steamEntry = vgui.Create("DTextEntry", steamRow)
	steamEntry:Dock(FILL)
	steamEntry:SetPlaceholderText("SteamID - STEAM_0:X:XXXXXXXX or SteamID64")
	steamEntry.OnGetFocus = function() SetPickTarget("form") end

	-- Fills the SteamID box from someone who's online right now.
	local onlineCombo = vgui.Create("DComboBox", steamRow)
	onlineCombo:Dock(RIGHT)
	onlineCombo:SetWide(220)
	onlineCombo:DockMargin(8, 0, 0, 0)
	onlineCombo:SetSortItems(false)
	onlineCombo:SetValue("...or pick an online player")

	local baseOpenMenu = onlineCombo.OpenMenu
	onlineCombo.OpenMenu = function(self, ...)
		self:Clear()
		for _, ply in ipairs(player.GetHumans()) do
			self:AddChoice(ply:Nick() .. "  (" .. ply:SteamID() .. ")", ply:SteamID())
		end
		self:SetValue("...or pick an online player")
		baseOpenMenu(self, ...)
	end
	onlineCombo.OnSelect = function(self, index, value, steamID)
		steamEntry:SetValue(steamID)
		SetPickTarget("form")
	end

	local pendingHint = vgui.Create("DLabel", formBox)
	pendingHint:Dock(TOP)
	pendingHint:SetTall(18)
	pendingHint:DockMargin(0, 10, 0, 0)
	pendingHint:SetFont("PDCity_Small")
	pendingHint:SetTextColor(PDCity.THEME.TextDim)

	local pendingChips = ChipLayout(formBox)

	local function RefreshPending()
		pendingChips:Clear()
		for i, model in ipairs(pendingModels) do
			AddModelChip(pendingChips, model, function()
				table.remove(pendingModels, i)
				RefreshPending()
			end)
		end

		local useGridBtn = vgui.Create("DButton", pendingChips)
		useGridBtn:SetSize(170, CHIP_H)
		PDCity.StyleButton(useGridBtn, "+ Add Models (from the grid)", GHOST_BUTTON)
		useGridBtn.DoClick = function() SetPickTarget("form") end

		pendingHint:SetText(#pendingModels == 0
			and "Models to whitelist: none yet - click models in the grid."
			or "Models to whitelist (" .. #pendingModels .. "):")
		formBox:InvalidateLayout()
	end

	local submitBtn = vgui.Create("DButton", formBox)
	submitBtn:Dock(TOP)
	submitBtn:SetTall(28)
	submitBtn:DockMargin(0, 10, 0, 0)
	PDCity.StyleButton(submitBtn, "Whitelist These Models")
	submitBtn.DoClick = function()
		local steamID = string.Trim(steamEntry:GetValue())
		if steamID == "" then
			LocalPlayer():ChatPrint("[" .. PDCity.BRAND_TAG .. "] Enter a SteamID first.")
			return
		end
		if #pendingModels == 0 then
			LocalPlayer():ChatPrint("[" .. PDCity.BRAND_TAG .. "] Pick at least one model from the grid first.")
			return
		end

		SendWhitelistAction("add", { SteamID = steamID, Models = pendingModels })

		pendingModels = {}
		steamEntry:SetValue("")
		RefreshPending()
	end

	--[[-----------------------------------------------------
		Whitelisted players - searchable list; picking one shows their
		models below, each change saving immediately.
	-------------------------------------------------------]]
	Heading("Whitelisted Players", 18)

	local searchEntry = vgui.Create("DTextEntry", form)
	searchEntry:Dock(TOP)
	searchEntry:SetTall(26)
	searchEntry:DockMargin(0, 6, 0, 0)
	searchEntry:SetPlaceholderText("Search by name, SteamID or model...")
	searchEntry:SetUpdateOnType(true)

	local playerList = vgui.Create("DListView", form)
	playerList:Dock(TOP)
	playerList:SetTall(170)
	playerList:DockMargin(0, 6, 0, 0)
	playerList:SetMultiSelect(false)
	playerList:AddColumn("Player")
	playerList:AddColumn("SteamID")
	playerList:AddColumn("Models"):SetFixedWidth(60)

	local detailBox = Section("player")

	local detailTitle = vgui.Create("DLabel", detailBox)
	detailTitle:Dock(TOP)
	detailTitle:SetTall(22)
	detailTitle:SetFont("PDCity_Heading")
	detailTitle:SetTextColor(PDCity.THEME.Text)

	local detailChips = ChipLayout(detailBox)

	local detailBtnRow = vgui.Create("DPanel", detailBox)
	detailBtnRow:Dock(TOP)
	detailBtnRow:SetTall(28)
	detailBtnRow:DockMargin(0, 10, 0, 0)
	detailBtnRow.Paint = function() end

	local detailAddBtn = vgui.Create("DButton", detailBtnRow)
	detailAddBtn:Dock(LEFT)
	detailAddBtn:SetWide(190)
	PDCity.StyleButton(detailAddBtn, "+ Add Models (from the grid)", GHOST_BUTTON)
	detailAddBtn.DoClick = function() SetPickTarget("player") end

	-- Two clicks, since it removes everything this player was granted.
	local removePlayerBtn = vgui.Create("DButton", detailBtnRow)
	removePlayerBtn:Dock(RIGHT)
	removePlayerBtn:SetWide(230)

	local removeArmed = false
	local function DisarmRemove()
		removeArmed = false
		PDCity.StyleButton(removePlayerBtn, "Remove Player From Whitelist", DANGER_BUTTON)
	end
	DisarmRemove()

	removePlayerBtn.DoClick = function(self)
		if not selectedSteamID then return end
		if removeArmed then
			SendWhitelistAction("remove_entry", { SteamID = selectedSteamID })
			DisarmRemove()
			return
		end
		removeArmed = true
		PDCity.StyleButton(self, "Click again to confirm", DANGER_BUTTON)
		timer.Simple(4, function()
			if IsValid(self) and removeArmed then DisarmRemove() end
		end)
	end

	local function RefreshDetail()
		local list = selectedSteamID and Config().Whitelist[selectedSteamID]
		detailBox:SetVisible(list ~= nil)

		if not list then
			if pickTarget == "player" then SetPickTarget("default") end
			form:InvalidateLayout()
			return
		end

		detailTitle:SetText(WhitelistName(selectedSteamID) .. "  -  " .. selectedSteamID)

		detailChips:Clear()
		for _, model in ipairs(list) do
			AddModelChip(detailChips, model, function()
				SendWhitelistAction("remove_model", { SteamID = selectedSteamID, Model = model })
			end)
		end

		DisarmRemove()
		detailBox:InvalidateLayout()
		form:InvalidateLayout()
	end

	local function RefreshPlayerList()
		local filter = string.lower(string.Trim(searchEntry:GetValue()))
		local whitelist = Config().Whitelist

		local steamIDs = {}
		for steamID in pairs(whitelist) do table.insert(steamIDs, steamID) end
		table.sort(steamIDs, function(a, b) return string.lower(WhitelistName(a)) < string.lower(WhitelistName(b)) end)

		playerList:Clear()
		for _, steamID in ipairs(steamIDs) do
			local list = whitelist[steamID]
			local name = WhitelistName(steamID)

			local matches = filter == "" or string.find(string.lower(name), filter, 1, true) or string.find(string.lower(steamID), filter, 1, true)
			if not matches then
				for _, model in ipairs(list) do
					if string.find(string.lower(model), filter, 1, true) then matches = true break end
				end
			end

			if matches then
				local line = playerList:AddLine(name, steamID, #list)
				line.pdcitySteamID = steamID
				if steamID == selectedSteamID then playerList:SelectItem(line) end
			end
		end

		RefreshDetail()
	end

	playerList.OnRowSelected = function(self, index, row)
		selectedSteamID = row.pdcitySteamID
		RefreshDetail()
		if pickTarget == "player" then SetPickTarget("player") end -- refresh the grid heading's name
	end

	searchEntry.OnValueChange = function() RefreshPlayerList() end

	--[[-----------------------------------------------------
		Grid clicks + refreshing
	-------------------------------------------------------]]
	OnModelPicked = function(model)
		if pickTarget == "form" then
			if not table.HasValue(pendingModels, model) then
				table.insert(pendingModels, model)
				RefreshPending()
			end
		elseif pickTarget == "player" and selectedSteamID then
			SendWhitelistAction("add", { SteamID = selectedSteamID, Models = { model } })
		elseif not table.HasValue(models, model) then
			table.insert(models, model)
			RefreshModelList()
		end
	end

	local function LoadIntoForm()
		models = table.Copy(Config().Models)
		RefreshModelList()
		RefreshPending()
		RefreshPlayerList()
		SetPickTarget(pickTarget)
	end
	LoadIntoForm()

	-- Whitelist changes save instantly, so only that part reloads on a
	-- sync - an unsaved edit to the default list isn't thrown away.
	hook.Add("PDCity_CharacterModelsUpdated", root, function() RefreshPlayerList() end)

	root.PDCityRefresh = LoadIntoForm

	return root

end
