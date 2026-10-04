--[[---------------------------------------------------------
	Scoreboard (TAB).

	pdcity never inherited one: it doesn't include base's
	cl_scoreboard.lua, and nothing else defined GM:ScoreboardShow, so
	until now TAB did nothing at all. This is a fresh one styled to
	match the rest of the gamemode's menus (cl_theme.lua).

	Right-clicking any row gives everyone - not just staff - the option
	to copy a player's SteamID or SteamID64, or open their Steam
	profile. That's all public information any player can already read
	off the Steam overlay; it's here purely so it's quick to grab.
-----------------------------------------------------------]]

local ROW_HEIGHT = 40
local BOARD_WIDTH = 720

--[[---------------------------------------------------------
	One player row
-----------------------------------------------------------]]

local PLAYER_ROW = {}

function PLAYER_ROW:Init()

	self:Dock(TOP)
	self:DockMargin(0, 0, 0, 4)
	self:SetTall(ROW_HEIGHT)
	self:DockPadding(4, 4, 4, 4)

	-- Explicit, because OnMousePressed below is the whole point of this
	-- row and a panel that isn't taking mouse input never receives it.
	self:SetMouseInputEnabled(true)

	self.AvatarButton = self:Add("DButton")
	self.AvatarButton:Dock(LEFT)
	self.AvatarButton:SetWide(32)
	self.AvatarButton:SetText("")
	self.AvatarButton.Paint = function() end
	self.AvatarButton.DoClick = function()
		if IsValid(self.Player) then self.Player:ShowProfile() end
	end
	-- Right-clicking the avatar should behave like right-clicking the
	-- row, rather than being a dead zone.
	self.AvatarButton.DoRightClick = function() self:OpenPlayerMenu() end

	self.Avatar = vgui.Create("AvatarImage", self.AvatarButton)
	self.Avatar:SetSize(32, 32)
	self.Avatar:SetMouseInputEnabled(false)

	self.Ping = self:Add("DLabel")
	self.Ping:Dock(RIGHT)
	self.Ping:SetWide(60)
	self.Ping:SetFont("PDCity_Small")
	self.Ping:SetTextColor(PDCity.THEME.TextDim)
	self.Ping:SetContentAlignment(6)

	self.Job = self:Add("DLabel")
	self.Job:Dock(RIGHT)
	self.Job:SetWide(220)
	self.Job:SetFont("PDCity_Small")
	self.Job:SetContentAlignment(6)

	-- Staff rank (usergroup/owner) and donator rank (PDCity.GetRank,
	-- core/sh_f4_catalogue.lua's "normal"/"supporter"/"goat") - both
	-- read off values already networked to every client (usergroups are
	-- synced by the engine itself; PDCity_Rank is a plain NWString), so
	-- no extra round trip needed. Added here, BEFORE Name, since Name is
	-- Dock(FILL) and would otherwise claim this space first - GMod's
	-- docking processes children in the order they were added, not by
	-- direction, so FILL only leaves room for a RIGHT dock added earlier.
	self.Badge = self:Add("DLabel")
	self.Badge:Dock(RIGHT)
	self.Badge:SetWide(140)
	self.Badge:SetFont("PDCity_Small")
	self.Badge:SetContentAlignment(6)
	self.Badge:SetTextColor(Color(230, 190, 90))

	self.Name = self:Add("DLabel")
	self.Name:Dock(FILL)
	self.Name:DockMargin(10, 0, 0, 0)
	self.Name:SetFont("PDCity_Body")
	self.Name:SetTextColor(PDCity.THEME.Text)

end

function PLAYER_ROW:Setup(ply)
	self.Player = ply
	self.Avatar:SetPlayer(ply, 32)
	self:Think()
end

--[[---------------------------------------------------------
	Right-click menu - the point of this file.
-----------------------------------------------------------]]
function PLAYER_ROW:OpenPlayerMenu()

	local ply = self.Player
	if not IsValid(ply) then return end

	local menu = DermaMenu()
	menu:AddOption(PDCity.GetDisplayName(ply)):SetIcon("icon16/user.png")
	menu:AddSpacer()

	-- Bots have no real Steam identity, so offer nothing that would
	-- copy a meaningless "BOT" string or open a dead profile page.
	if ply:IsBot() then
		menu:AddOption("(bot - no Steam profile)"):SetIcon("icon16/exclamation.png")
		menu:Open()
		return
	end

	local steamID = ply:SteamID()
	local steamID64 = ply:SteamID64()

	menu:AddOption("Copy SteamID  (" .. steamID .. ")", function()
		SetClipboardText(steamID)
		PDCity.ShowToast("Copied " .. steamID .. " to clipboard.")
	end):SetIcon("icon16/page_copy.png")

	menu:AddOption("Copy SteamID64  (" .. steamID64 .. ")", function()
		SetClipboardText(steamID64)
		PDCity.ShowToast("Copied " .. steamID64 .. " to clipboard.")
	end):SetIcon("icon16/page_copy.png")

	menu:AddSpacer()

	menu:AddOption("Open Steam Profile", function()
		ply:ShowProfile()
	end):SetIcon("icon16/world_go.png")

	menu:Open()

end

function PLAYER_ROW:OnMousePressed(code)
	if code == MOUSE_RIGHT then
		self:OpenPlayerMenu()
	end
end

function PLAYER_ROW:Think()

	local ply = self.Player

	if not IsValid(ply) then
		-- Player left - drop the row. SetZPos first so the layout
		-- rebuilds rather than leaving a gap.
		self:SetZPos(9999)
		self:Remove()
		return
	end

	-- PDCity.GetDisplayName (core/sh_rpname.lua) prefers a set RP name
	-- (/name /rpname /n) over the real Steam nick.
	local displayName = PDCity.GetDisplayName(ply)
	if self.CachedName ~= displayName then
		self.CachedName = displayName
		self.Name:SetText(self.CachedName)
	end

	local jobName = team.GetName(ply:Team()) or ""
	if self.CachedJob ~= jobName then
		self.CachedJob = jobName
		self.Job:SetText(jobName)
		self.Job:SetTextColor(team.GetColor(ply:Team()) or PDCity.THEME.TextDim)
	end

	if self.CachedPing ~= ply:Ping() then
		self.CachedPing = ply:Ping()
		self.Ping:SetText(self.CachedPing .. "ms")
	end

	-- Staff label: "Owner" for PDCity.IsOwner (SteamID list OR the ULX
	-- "owner" group - see core/sh_permissions.lua), otherwise the raw
	-- usergroup for anything else in STAFF_GROUPS there. Plain "user"
	-- shows nothing - most players aren't staff, and an empty badge for
	-- the common case is the least noisy default.
	local staffText = ""
	if PDCity.IsOwner(ply) then
		staffText = "Owner"
	elseif PDCity.IsStaff(ply) then
		local group = ply:GetUserGroup()
		staffText = string.upper(string.sub(group, 1, 1)) .. string.sub(group, 2)
	end

	-- Donator label: PDCity.GetRank (core/sh_f4_catalogue.lua) reads a
	-- plain NWString client-side, so this is free. "normal" is the
	-- unpaid default and shows nothing, same reasoning as staffText.
	local rankText = ""
	local rank = PDCity.GetRank(ply)
	if rank == "supporter" then
		rankText = "Supporter"
	elseif rank == "goat" then
		rankText = "GOAT"
	end

	local badgeText = staffText
	if rankText ~= "" then
		badgeText = badgeText ~= "" and (badgeText .. " \xC2\xB7 " .. rankText) or rankText
	end

	if self.CachedBadge ~= badgeText then
		self.CachedBadge = badgeText
		self.Badge:SetText(badgeText)
	end

	-- Sorted by team, then entity index, so jobs group together.
	self:SetZPos(ply:Team() * 100 + ply:EntIndex())

end

function PLAYER_ROW:Paint(w, h)

	local ply = self.Player
	if not IsValid(ply) then return end

	local bg = PDCity.THEME.Panel
	if self:IsHovered() then bg = PDCity.THEME.PanelHover end

	draw.RoundedBox(4, 0, 0, w, h, bg)

	-- Team colour strip down the left, matching the F4 job cards.
	surface.SetDrawColor(team.GetColor(ply:Team()) or PDCity.THEME.Accent)
	surface.DrawRect(0, 0, 3, h)

	if ply == LocalPlayer() then
		surface.SetDrawColor(PDCity.THEME.Accent)
		surface.DrawOutlinedRect(0, 0, w, h, 1)
	end

end

vgui.Register("PDCityScoreRow", PLAYER_ROW, "DPanel")

--[[---------------------------------------------------------
	The board itself
-----------------------------------------------------------]]

local SCOREBOARD = {}

function SCOREBOARD:Init()

	self.Header = self:Add("DPanel")
	self.Header:Dock(TOP)
	self.Header:SetTall(60)
	self.Header.Paint = function(pnl, w, h)
		draw.RoundedBoxEx(8, 0, 0, w, h, PDCity.THEME.TitleBar, true, true, false, false)
		draw.SimpleText(GetHostName(), "PDCity_Title", 18, 20, PDCity.THEME.Text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
		draw.SimpleText(player.GetCount() .. " / " .. game.MaxPlayers() .. " players    -    right click a player for their SteamID",
			"PDCity_Small", 18, 42, PDCity.THEME.TextDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end

	self.Scores = self:Add("DScrollPanel")
	self.Scores:Dock(FILL)
	self.Scores:DockMargin(10, 10, 10, 10)

	self.Rows = {}

end

function SCOREBOARD:PerformLayout()
	self:SetSize(BOARD_WIDTH, ScrH() - 220)
	self:SetPos(ScrW() / 2 - BOARD_WIDTH / 2, 110)
end

function SCOREBOARD:Paint(w, h)
	draw.RoundedBox(8, 0, 0, w, h, PDCity.THEME.Background)
end

function SCOREBOARD:Think()

	-- Add a row for any player that doesn't have one yet. Rows remove
	-- themselves when their player disconnects (see PLAYER_ROW:Think),
	-- so this only ever has to handle additions.
	for _, ply in player.Iterator() do
		if not IsValid(self.Rows[ply]) then
			local row = vgui.Create("PDCityScoreRow")
			row:Setup(ply)
			self.Rows[ply] = row
			self.Scores:AddItem(row)
		end
	end

end

vgui.Register("PDCityScoreboard", SCOREBOARD, "EditablePanel")

--[[---------------------------------------------------------
	Hooks
-----------------------------------------------------------]]

--[[---------------------------------------------------------
	Registered as hooks rather than as GM:ScoreboardShow/Hide.

	pdcity derives from sandbox, which derives from base, and base
	DOES define these - table.Inherit copies them onto our gamemode
	table for any key we haven't set ourselves. Defining GM:ScoreboardShow
	here would usually win, but only if this file has run by the time
	the gamemode is registered, which makes it a load-order dependency.

	A hook sidesteps that completely: hook.Call runs hooks before the
	gamemode function and, per lua/includes/modules/hook.lua, a hook
	returning a non-nil value returns early and the gamemode function
	never runs. So returning true here reliably suppresses base's
	scoreboard no matter what order things loaded in.
-----------------------------------------------------------]]

local board

hook.Add("ScoreboardShow", "pdcity_ScoreboardShow", function()

	if not IsValid(board) then
		board = vgui.Create("PDCityScoreboard")
	end

	board:Show()
	board:MakePopup()
	-- Keyboard input off so holding TAB doesn't eat movement keys, but
	-- mouse stays on - the right-click menu needs it.
	board:SetKeyboardInputEnabled(false)

	return true
end)

hook.Add("ScoreboardHide", "pdcity_ScoreboardHide", function()
	if IsValid(board) then board:Hide() end
	return true
end)
