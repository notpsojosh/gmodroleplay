--[[---------------------------------------------------------
	Server log viewer - staff only (the server enforces that in
	core/sv_gamelog.lua; this file just draws whatever it's sent).

	Opened with the "Open server logs" keybind (F1 > Keybinds, staff
	only) or the "pdcity_logs" console command. Left rail: dates
	(newest first). Top: category chips. Middle: the log tail in a
	monospace view with a live filter box. Bottom: refresh + export.
-----------------------------------------------------------]]

surface.CreateFont("PDCity_Mono", {
	font = "Consolas",
	size = 14,
	weight = 400,
})

local frame
local curDate, curCat = "", ""
local rawContent = ""

-- "category" (normal per-category browsing) or "search" (results of a
-- player search, spanning every category for curDate) - the count
-- label and the stale-reply checks both depend on knowing which.
local curMode, curQuery = "category", ""

local function RequestListing(date)
	net.Start("pdcity_logs_list")
		net.WriteString(date or "")
	net.SendToServer()
end

local function RequestContent(date, category)
	net.Start("pdcity_logs_read")
		net.WriteString(date)
		net.WriteString(category)
	net.SendToServer()
end

local function RequestPlayerSearch(date, query)
	net.Start("pdcity_logs_searchplayer")
		net.WriteString(date)
		net.WriteString(query)
	net.SendToServer()
end

--[[---------------------------------------------------------
	Rendering
-----------------------------------------------------------]]

local function RenderContent()
	if not IsValid(frame) or not IsValid(frame.LogView) then return end

	local view = frame.LogView
	view:SetText("")

	local filter = ""
	if IsValid(frame.SearchBox) then
		filter = string.lower(frame.SearchBox:GetValue() or "")
	end

	local shown = 0
	for line in rawContent:gmatch("[^\n]+") do
		if filter == "" or string.find(string.lower(line), filter, 1, true) then
			-- Dim the timestamp, leave the event text bright.
			local ts, rest = line:match("^(%[[%d%- :]+%])%s?(.*)$")
			if ts then
				view:InsertColorChange(120, 126, 138, 255)
				view:AppendText(ts .. " ")
				view:InsertColorChange(225, 228, 235, 255)
				view:AppendText(rest .. "\n")
			else
				view:InsertColorChange(225, 228, 235, 255)
				view:AppendText(line .. "\n")
			end
			shown = shown + 1
		end
	end

	if shown == 0 then
		view:InsertColorChange(150, 155, 165, 255)
		view:AppendText(filter ~= "" and "No lines match that filter." or "No entries.")
	end

	if IsValid(frame.CountLabel) then
		if curMode == "search" then
			frame.CountLabel:SetText(shown .. " match(es) for \"" .. curQuery .. "\"")
		else
			frame.CountLabel:SetText(shown .. " lines" .. (filter ~= "" and " (filtered)" or ""))
		end
	end
end

--[[---------------------------------------------------------
	The window
-----------------------------------------------------------]]

local function BuildViewer(dates, cats, date)

	curDate = date

	if IsValid(frame) then frame:Remove() end

	local W, H = PDCity.ResponsiveFrameSize(1500, 1000)
	frame = PDCity.CreateModernFrame("Server Logs", W, H)

	-- Left rail: dates
	local dateRail = vgui.Create("DScrollPanel", frame)
	dateRail:SetPos(14, 52)
	dateRail:SetSize(120, H - 66)

	for _, d in ipairs(dates) do
		local b = vgui.Create("DButton", dateRail)
		b:Dock(TOP)
		b:SetTall(28)
		b:DockMargin(0, 0, 4, 6)
		b:SetText("")
		b.Paint = function(self, w, h)
			local active = (d == curDate)
			local col = active and PDCity.THEME.Accent
				or (self:IsHovered() and PDCity.THEME.PanelHover or PDCity.THEME.Panel)
			draw.RoundedBox(4, 0, 0, w, h, col)
			draw.SimpleText(d, "PDCity_Small", w / 2, h / 2,
				active and PDCity.THEME.Text or PDCity.THEME.TextDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
		b.DoClick = function() RequestListing(d) end
	end

	-- Category chips
	local chipBar = vgui.Create("DPanel", frame)
	chipBar:SetPos(144, 52)
	chipBar:SetSize(W - 158, 30)
	chipBar.Paint = function() end

	local x = 0
	for _, cat in ipairs(cats) do
		local chip = vgui.Create("DButton", chipBar)
		surface.SetFont("PDCity_Small")
		local tw = surface.GetTextSize(cat)
		chip:SetPos(x, 0)
		chip:SetSize(tw + 22, 26)
		x = x + tw + 28
		chip:SetText("")
		chip.Paint = function(self, w, h)
			local active = (cat == curCat)
			local col = active and PDCity.THEME.Accent
				or (self:IsHovered() and PDCity.THEME.PanelHover or PDCity.THEME.Panel)
			draw.RoundedBox(12, 0, 0, w, h, col)
			draw.SimpleText(cat, "PDCity_Small", w / 2, h / 2,
				active and PDCity.THEME.Text or PDCity.THEME.TextDim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
		chip.DoClick = function()
			curCat = cat
			curMode = "category"
			rawContent = "Loading..."
			RenderContent()
			RequestContent(curDate, cat)
		end
	end

	-- Player search: spans every category for curDate, not just
	-- whatever chip is selected - the whole point versus the line
	-- filter below, which only ever searches the one category already
	-- loaded.
	local playerBox = vgui.Create("DTextEntry", frame)
	playerBox:SetPos(144, 90)
	playerBox:SetSize(W - 158 - 220, 26)
	playerBox:SetPlaceholderText("Search by player (name or SteamID) across every category...")

	local function DoPlayerSearch()
		local q = playerBox:GetValue()
		if q == "" then return end
		curQuery = q
		curMode = "search"
		rawContent = "Searching..."
		RenderContent()
		RequestPlayerSearch(curDate, q)
	end
	playerBox.OnEnter = DoPlayerSearch

	local searchBtn = vgui.Create("DButton", frame)
	searchBtn:SetPos(W - 268, 90)
	searchBtn:SetSize(80, 26)
	searchBtn:SetText("")
	searchBtn.Paint = function(self, w, h)
		local col = self:IsHovered() and PDCity.THEME.Accent or PDCity.THEME.AccentDim
		draw.RoundedBox(4, 0, 0, w, h, col)
		draw.SimpleText("SEARCH", "PDCity_Small", w / 2, h / 2, PDCity.THEME.Text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
	searchBtn.DoClick = DoPlayerSearch

	local backBtn = vgui.Create("DButton", frame)
	backBtn:SetPos(W - 182, 90)
	backBtn:SetSize(38, 26)
	backBtn:SetText("")
	backBtn:SetTooltip("Back to category view")
	backBtn.Paint = function(self, w, h)
		draw.RoundedBox(4, 0, 0, w, h, self:IsHovered() and PDCity.THEME.PanelHover or PDCity.THEME.Border)
		draw.SimpleText("<-", "PDCity_Small", w / 2, h / 2, PDCity.THEME.Text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end
	backBtn.DoClick = function()
		curMode = "category"
		if curCat ~= "" then
			rawContent = "Loading..."
			RenderContent()
			RequestContent(curDate, curCat)
		end
	end

	-- Line filter, within whatever's currently shown (one category, or
	-- the current search results).
	local search = vgui.Create("DTextEntry", frame)
	frame.SearchBox = search
	search:SetPos(144, 124)
	search:SetSize(W - 158 - 110, 26)
	search:SetPlaceholderText("Filter shown lines...")
	search:SetUpdateOnType(true)
	search.OnValueChange = RenderContent

	local count = vgui.Create("DLabel", frame)
	frame.CountLabel = count
	count:SetPos(W - 118, 124)
	count:SetSize(104, 26)
	count:SetFont("PDCity_Small")
	count:SetContentAlignment(6)
	count:SetTextColor(PDCity.THEME.TextDim)
	count:SetText("")

	-- The log body
	local view = vgui.Create("RichText", frame)
	frame.LogView = view
	view:SetPos(144, 158)
	view:SetSize(W - 158, H - 220)
	view.Paint = function(self, w, h)
		draw.RoundedBox(6, 0, 0, w, h, Color(14, 16, 20, 255))
	end
	view.PerformLayout = function(self)
		self:SetFontInternal("PDCity_Mono")
	end

	-- Bottom bar
	local function BarButton(px, wide, label, onClick)
		local b = vgui.Create("DButton", frame)
		b:SetPos(px, H - 50)
		b:SetSize(wide, 32)
		b:SetText("")
		b.Paint = function(self, w, h)
			local col = self:IsHovered() and PDCity.THEME.Accent or PDCity.THEME.AccentDim
			draw.RoundedBox(5, 0, 0, w, h, col)
			draw.SimpleText(label, "PDCity_Small", w / 2, h / 2, PDCity.THEME.Text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		end
		b.DoClick = onClick
		return b
	end

	BarButton(144, 110, "REFRESH", function()
		if curCat ~= "" then RequestContent(curDate, curCat) else RequestListing(curDate) end
	end)

	BarButton(264, 190, "EXPORT THIS DAY", function()
		RunConsoleCommand("pdcity_exportlogs", curDate)
		PDCity.ShowToast("Export written server-side - see server console/notifications for the path.")
	end)

	local hint = vgui.Create("DLabel", frame)
	hint:SetPos(470, H - 50)
	hint:SetSize(W - 484, 32)
	hint:SetFont("PDCity_Small")
	hint:SetContentAlignment(6)
	hint:SetTextColor(PDCity.THEME.TextDim)
	hint:SetText("Full files: garrysmod/data/pdcity/gamelogs/" .. date .. "/")

	-- Auto-open the first category so the window never starts empty.
	if cats[1] then
		curCat = cats[1]
		RequestContent(curDate, curCat)
	end

end

--[[---------------------------------------------------------
	Net
-----------------------------------------------------------]]

net.Receive("pdcity_logs_listing", function()
	local dates = util.JSONToTable(net.ReadString() or "") or {}
	local cats = util.JSONToTable(net.ReadString() or "") or {}
	local date = net.ReadString()
	BuildViewer(dates, cats, date)
end)

net.Receive("pdcity_logs_content", function()
	local date = net.ReadString()
	local category = net.ReadString()
	local len = net.ReadUInt(32)
	local raw = util.Decompress(net.ReadData(len)) or "(failed to decompress)"

	if curMode ~= "category" or date ~= curDate or category ~= curCat then return end -- stale reply
	rawContent = raw
	RenderContent()

	-- Jump to the newest lines.
	if IsValid(frame) and IsValid(frame.LogView) then
		frame.LogView:GotoTextEnd()
	end
end)

net.Receive("pdcity_logs_searchresults", function()
	local date = net.ReadString()
	local query = net.ReadString()
	local len = net.ReadUInt(32)
	local raw = util.Decompress(net.ReadData(len)) or "(failed to decompress)"

	if curMode ~= "search" or date ~= curDate or query ~= curQuery then return end -- stale reply
	rawContent = raw
	RenderContent()

	if IsValid(frame) and IsValid(frame.LogView) then
		frame.LogView:GotoTextStart()
	end
end)

concommand.Add("pdcity_logs", function() RequestListing("") end)
