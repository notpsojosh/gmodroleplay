--[[---------------------------------------------------------
	Department whitelist/blacklist management panel - opened via
	"!whitelist" (core/sv_whitelist_chat.lua) or the F4 Jobs menu's
	"Manage Whitelist" button (cl_f4_menu.lua, superadmin/owner only).

	Left sidebar lists every whitelist-only job category (core/sh_jobs.lua's
	PDCity.IsSectionWhitelistOnly), greyed out if the local player can't
	manage that one (PDCity.CanIManageDepartment - their own level 6+ in
	it, or superadmin/owner). Selecting an accessible one requests that
	department's roster from the server (core/sv_whitelist.lua) and shows
	two tables: whitelisted players (with level + time since last
	promotion) and the blacklist, each with the controls to manage them.

	A target player is picked by typing either part of an ONLINE player's
	name, or a raw SteamID/SteamID64 directly - the latter is the only
	way to act on someone offline (there's no live index of every player
	who's ever connected to search by name against).
-----------------------------------------------------------]]

local function ResolveTargetSteamID64(input)
	input = string.Trim(input or "")
	if input == "" then return nil end

	if string.match(input, "^STEAM_%d:%d:%d+$") then
		return util.SteamIDTo64(input)
	end

	if string.match(input, "^%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d$") then
		return input
	end

	local lower = string.lower(input)
	for _, ply in ipairs(player.GetAll()) do
		if string.find(string.lower(ply:Nick()), lower, 1, true) then
			return ply:SteamID64(), ply:Nick()
		end
	end

	return nil
end

local function FormatTimeSince(unixTime)
	if not unixTime or unixTime <= 0 then return "never" end
	local seconds = os.time() - unixTime
	if seconds < 60 then return "just now" end
	if seconds < 3600 then return math.floor(seconds / 60) .. "m ago" end
	if seconds < 86400 then return math.floor(seconds / 3600) .. "h ago" end
	return math.floor(seconds / 86400) .. "d ago"
end

local function FormatExpiry(until_)
	if until_ == -1 then return "permanent" end
	local remaining = until_ - os.time()
	if remaining <= 0 then return "expired" end
	local days = math.ceil(remaining / 86400)
	return days .. "d left"
end

function PDCity.OpenWhitelistMenu()

	if IsValid(GAMEMODE.PDCityWhitelistFrame) then
		GAMEMODE.PDCityWhitelistFrame:Remove()
		return
	end

	-- Forward-declared - the onResize callback below needs it, but (like
	-- every other absolutely/explicitly-sized child on these frames)
	-- it's only actually created further down.
	local leftCol

	-- leftCol's width used to be computed ONCE from columns:GetWide() at
	-- creation time - before `columns` (Dock FILL) had actually been
	-- through a layout pass, so that read was 0/stale, and nothing ever
	-- recomputed it afterward either. Recalculating it here from the
	-- frame's own new width (always accurate, unlike a child's Dock-
	-- resolved size at the moment of a sibling's construction) fixes
	-- both the initial squish and the "doesn't resize" complaint in one
	-- go - content is newW-150 wide, minus its own 14px DockPadding on
	-- each side, minus the 12px gap between columns, split in half.
	local function ResizeColumns(newW)
		if IsValid(leftCol) then
			leftCol:SetWide((newW - 150 - 28 - 12) / 2)
		end
	end

	PDCity.PushMenuDim()
	local frameW, frameH = PDCity.ResponsiveFrameSize(1400, 900)
	local frame = PDCity.CreateModernFrame("Department Whitelist", frameW, frameH, function(newW, newH)
		if IsValid(GAMEMODE.PDCityWhitelistFrame) then
			local f = GAMEMODE.PDCityWhitelistFrame
			if IsValid(f.Sidebar) then f.Sidebar:SetSize(150, newH - 48) end
			if IsValid(f.Content) then f.Content:SetSize(newW - 150, newH - 48) end
		end
		ResizeColumns(newW)
	end)
	GAMEMODE.PDCityWhitelistFrame = frame
	frame.OnRemove = function() PDCity.PopMenuDim() end

	local sidebar = vgui.Create("DPanel", frame)
	sidebar:SetPos(0, 48)
	sidebar:SetSize(150, frame:GetTall() - 48)
	sidebar.Paint = function(self, w, h)
		draw.RoundedBoxEx(8, 0, 0, w, h, PDCity.THEME.TitleBar, false, false, false, true)
	end
	frame.Sidebar = sidebar

	local content = vgui.Create("DPanel", frame)
	content:SetPos(150, 48)
	content:SetSize(frame:GetWide() - 150, frame:GetTall() - 48)
	content:DockPadding(14, 14, 14, 14)
	content.Paint = function() end
	frame.Content = content

	local currentDepartment

	--[[-----------------------------------------------------
		Content: header + whitelisted players / blacklist tables
	-------------------------------------------------------]]
	local header = vgui.Create("DLabel", content)
	header:Dock(TOP)
	header:SetTall(26)
	header:SetFont("PDCity_Title")
	header:SetTextColor(PDCity.THEME.Text)
	header:SetText("Pick a department on the left")

	local columns = vgui.Create("DPanel", content)
	columns:Dock(FILL)
	columns:DockMargin(0, 12, 0, 0)
	columns.Paint = function() end

	leftCol = vgui.Create("DPanel", columns)
	leftCol:Dock(LEFT)
	leftCol.Paint = function() end
	ResizeColumns(frame:GetWide())

	local rightCol = vgui.Create("DPanel", columns)
	rightCol:Dock(FILL)
	rightCol:DockMargin(12, 0, 0, 0)
	rightCol.Paint = function() end

	--[[-----------------------------------------------------
		Left: Whitelisted Players
	-------------------------------------------------------]]
	local wlLabel = vgui.Create("DLabel", leftCol)
	wlLabel:Dock(TOP)
	wlLabel:SetTall(20)
	wlLabel:SetFont("PDCity_Heading")
	wlLabel:SetTextColor(PDCity.THEME.Text)
	wlLabel:SetText("Whitelisted Players")

	local wlList = vgui.Create("DListView", leftCol)
	wlList:Dock(TOP)
	wlList:SetTall(280)
	wlList:DockMargin(0, 6, 0, 0)
	wlList:SetMultiSelect(false)
	wlList:AddColumn("Name")
	wlList:AddColumn("Level")
	wlList:AddColumn("Last Promotion")

	local wlTargetEntry = vgui.Create("DTextEntry", leftCol)
	wlTargetEntry:Dock(TOP)
	wlTargetEntry:SetTall(26)
	wlTargetEntry:DockMargin(0, 8, 0, 0)
	wlTargetEntry:SetPlaceholderText("Player name (online) or SteamID")

	local wlLevelRow = vgui.Create("DPanel", leftCol)
	wlLevelRow:Dock(TOP)
	wlLevelRow:SetTall(26)
	wlLevelRow:DockMargin(0, 6, 0, 0)
	wlLevelRow.Paint = function() end

	local wlLevelEntry = vgui.Create("DTextEntry", wlLevelRow)
	wlLevelEntry:Dock(LEFT)
	wlLevelEntry:SetWide(80)
	wlLevelEntry:SetNumeric(true)
	wlLevelEntry:SetPlaceholderText("Level")

	local wlSetBtn = vgui.Create("DButton", wlLevelRow)
	wlSetBtn:Dock(FILL)
	wlSetBtn:DockMargin(6, 0, 0, 0)
	PDCity.StyleButton(wlSetBtn, "Set Level (0 = remove)")

	--[[-----------------------------------------------------
		Right: Blacklist
	-------------------------------------------------------]]
	local blLabel = vgui.Create("DLabel", rightCol)
	blLabel:Dock(TOP)
	blLabel:SetTall(20)
	blLabel:SetFont("PDCity_Heading")
	blLabel:SetTextColor(PDCity.THEME.Text)
	blLabel:SetText("Blacklist")

	local blList = vgui.Create("DListView", rightCol)
	blList:Dock(TOP)
	blList:SetTall(220)
	blList:DockMargin(0, 6, 0, 0)
	blList:SetMultiSelect(false)
	blList:AddColumn("Name")
	blList:AddColumn("Expires")
	blList:AddColumn("Reason")

	local unblacklistBtn = vgui.Create("DButton", rightCol)
	unblacklistBtn:Dock(TOP)
	unblacklistBtn:SetTall(24)
	unblacklistBtn:DockMargin(0, 4, 0, 0)
	PDCity.StyleButton(unblacklistBtn, "Remove Selected From Blacklist", { Accent = PDCity.THEME.Panel, AccentDim = PDCity.THEME.PanelHover, TextColor = PDCity.THEME.TextDim })

	local blTargetEntry = vgui.Create("DTextEntry", rightCol)
	blTargetEntry:Dock(TOP)
	blTargetEntry:SetTall(26)
	blTargetEntry:DockMargin(0, 10, 0, 0)
	blTargetEntry:SetPlaceholderText("Player name (online) or SteamID")

	local blDaysEntry = vgui.Create("DTextEntry", rightCol)
	blDaysEntry:Dock(TOP)
	blDaysEntry:SetTall(26)
	blDaysEntry:DockMargin(0, 6, 0, 0)
	blDaysEntry:SetPlaceholderText("Days (blank/-1 = permanent)")

	local blReasonEntry = vgui.Create("DTextEntry", rightCol)
	blReasonEntry:Dock(TOP)
	blReasonEntry:SetTall(26)
	blReasonEntry:DockMargin(0, 6, 0, 0)
	blReasonEntry:SetPlaceholderText("Reason (required)")

	local blacklistBtn = vgui.Create("DButton", rightCol)
	blacklistBtn:Dock(TOP)
	blacklistBtn:SetTall(26)
	blacklistBtn:DockMargin(0, 6, 0, 0)
	PDCity.StyleButton(blacklistBtn, "Blacklist", { Accent = Color(190, 70, 70), AccentDim = Color(140, 55, 55) })

	columns:SetVisible(false)

	--[[-----------------------------------------------------
		Sidebar: department list
	-------------------------------------------------------]]
	local function SelectDepartment(section)
		currentDepartment = section
		header:SetText(section .. " Whitelist Settings")
		columns:SetVisible(true)

		net.Start("pdcity_whitelist_roster_request")
			net.WriteString(section)
		net.SendToServer()
	end

	local y = 10
	for _, section in ipairs(PDCity.SECTIONS) do
		if PDCity.IsSectionWhitelistOnly(section) then
			local canAccess = PDCity.CanIManageDepartment(section)

			local btn = vgui.Create("PDCitySidebarTab", sidebar)
			btn:SetLabel(section)
			btn:SetPos(8, y)
			btn:SetSize(134, 34)
			btn:SetEnabled(canAccess)
			if not canAccess then btn:SetAlpha(120) end
			btn.DoClick = function()
				if not canAccess then return end
				for _, other in ipairs(sidebar:GetChildren()) do
					if other.SetActive then other:SetActive(other == btn) end
				end
				SelectDepartment(section)
			end

			y = y + 38
		end
	end

	if y == 10 then
		header:SetText("No whitelist-only departments exist yet")
	end

	--[[-----------------------------------------------------
		Actions
	-------------------------------------------------------]]
	wlSetBtn.DoClick = function()
		if not currentDepartment then return end
		local steamID64 = ResolveTargetSteamID64(wlTargetEntry:GetValue())
		if not steamID64 then
			LocalPlayer():ChatPrint("[" .. PDCity.BRAND_TAG .. "] Couldn't find that player - type part of an online player's name, or a SteamID.")
			return
		end

		local level = tonumber(wlLevelEntry:GetValue()) or 0

		net.Start("pdcity_whitelist_action")
			net.WriteString(util.TableToJSON({
				Action = "set_level",
				Department = currentDepartment,
				SteamID64 = steamID64,
				Level = level,
			}))
		net.SendToServer()
	end

	blacklistBtn.DoClick = function()
		if not currentDepartment then return end
		local steamID64 = ResolveTargetSteamID64(blTargetEntry:GetValue())
		if not steamID64 then
			LocalPlayer():ChatPrint("[" .. PDCity.BRAND_TAG .. "] Couldn't find that player - type part of an online player's name, or a SteamID.")
			return
		end

		if string.Trim(blReasonEntry:GetValue()) == "" then
			LocalPlayer():ChatPrint("[" .. PDCity.BRAND_TAG .. "] A reason is required.")
			return
		end

		net.Start("pdcity_whitelist_action")
			net.WriteString(util.TableToJSON({
				Action = "blacklist",
				Department = currentDepartment,
				SteamID64 = steamID64,
				Days = tonumber(blDaysEntry:GetValue()) or -1,
				Reason = blReasonEntry:GetValue(),
			}))
		net.SendToServer()
	end

	unblacklistBtn.DoClick = function()
		if not currentDepartment then return end
		local selected = blList:GetSelected()
		local row = selected and selected[1]
		if not row or not row.pdcitySteamID64 then return end

		net.Start("pdcity_whitelist_action")
			net.WriteString(util.TableToJSON({
				Action = "unblacklist",
				Department = currentDepartment,
				SteamID64 = row.pdcitySteamID64,
			}))
		net.SendToServer()
	end

	frame.RefreshRoster = function(self, department, data)
		if department ~= currentDepartment then return end

		wlList:Clear()
		for _, entry in ipairs(data.Whitelisted or {}) do
			local line = wlList:AddLine(entry.Name, entry.Level, FormatTimeSince(entry.PromotedAt))
			line.pdcitySteamID64 = entry.SteamID64
		end

		blList:Clear()
		for _, entry in ipairs(data.Blacklisted or {}) do
			local line = blList:AddLine(entry.Name, FormatExpiry(entry.Until), entry.Reason or "")
			line.pdcitySteamID64 = entry.SteamID64
		end
	end

end

net.Receive("pdcity_whitelist_roster", function()
	local department = net.ReadString()
	local data = util.JSONToTable(net.ReadString() or "")
	if not istable(data) then return end

	local frame = GAMEMODE.PDCityWhitelistFrame
	if IsValid(frame) and frame.RefreshRoster then
		frame:RefreshRoster(department, data)
	end
end)

net.Receive("pdcity_whitelist_open", function()
	PDCity.OpenWhitelistMenu()
end)
