--[[---------------------------------------------------------
	Themed toast/notification stack - system messages ("[" .. PDCity.BRAND_TAG .. "] Payday!
	You received your $500 salary.", RP name changes, thirdperson toggle,
	admin action feedback, ...) show up here instead of the chatbox now,
	so the chatbox is reserved for stuff a player actually typed (real
	chat, OOC, PMs, adverts - cl_chat.lua's own separate chat.AddText
	calls, untouched by any of this).

	PDCity.ShowToast(text, accentColor) is the local entry point - called
	directly for purely client-side notices (e.g. cl_scoreboard.lua's
	"Copied SteamID to clipboard"), and via the "pdcity_toast" net message
	below for anything server-triggered. core/sv_notify.lua is the server
	side of that: PDCity.Notify(ply, text) sends it, and it also
	overrides Player:ChatPrint itself so the ~200 existing ChatPrint call
	sites across the gamemode route here automatically, without having
	needed to touch each one individually.
-----------------------------------------------------------]]

local TOAST_LIFETIME = 5
local TOAST_FADE = 0.25
local TOAST_WIDE = 320
local TOAST_TALL = 34 -- minimum; longer messages grow to fit

local container

local function EnsureContainer()
	if IsValid(container) then return container end

	container = vgui.Create("DPanel")
	container:SetSize(TOAST_WIDE, ScrH() - 160)
	container:SetPos(ScrW() - TOAST_WIDE - 20, 80)
	container:SetMouseInputEnabled(false)
	container.Paint = function() end

	return container
end

--[[---------------------------------------------------------
	Message log - every toast is also recorded here, so the F1 admin pages'
	output console (PDCity.BuildMessageConsole, below) can show messages
	that arrived while the full-screen menu was hiding the toasts.
-----------------------------------------------------------]]
local LOG_LIMIT = 200
PDCity.MESSAGE_LOG = PDCity.MESSAGE_LOG or {}

local function LogMessage(text)
	local entry = { Time = os.date("%H:%M:%S"), Text = text }
	table.insert(PDCity.MESSAGE_LOG, entry)
	if #PDCity.MESSAGE_LOG > LOG_LIMIT then table.remove(PDCity.MESSAGE_LOG, 1) end
	hook.Run("PDCity_MessageLogged", entry)
end

function PDCity.ShowToast(text, accentColor)
	if not isstring(text) or text == "" then return end

	LogMessage(text)

	local parent = EnsureContainer()
	accentColor = accentColor or PDCity.THEME.Accent

	local toast = vgui.Create("DPanel", parent)
	toast:Dock(TOP)
	toast:DockMargin(0, 0, 0, 8)
	toast:SetTall(TOAST_TALL)
	toast:SetMouseInputEnabled(false)
	toast.Paint = function(self, w, h)
		draw.RoundedBox(6, 0, 0, w, h, PDCity.THEME.Panel)
		surface.SetDrawColor(accentColor)
		surface.DrawRect(0, 0, 3, h)
	end

	-- The accent bar already marks this as a server message, so the
	-- "[Brand]" prefix is dropped here to leave room for the message.
	local shown = string.gsub(text, "^%[" .. string.PatternSafe(PDCity.BRAND_TAG) .. "%]%s*", "")

	-- Stretches to however many lines the message wraps onto, and the
	-- toast grows with it rather than clipping at a fixed height.
	local label = vgui.Create("DLabel", toast)
	label:Dock(TOP)
	label:DockMargin(12, 8, 10, 0)
	label:SetFont("PDCity_Small")
	label:SetTextColor(PDCity.THEME.Text)
	label:SetWrap(true)
	label:SetAutoStretchVertical(true)
	label:SetText(shown)
	label:SetMouseInputEnabled(false)

	toast.PerformLayout = function(self)
		local wanted = math.max(TOAST_TALL, label:GetTall() + 16)
		if self:GetTall() ~= wanted then self:SetTall(wanted) end
	end
	label.OnSizeChanged = function() toast:InvalidateLayout() end

	toast:SetAlpha(0)
	toast:AlphaTo(255, 0.15, 0)

	timer.Simple(TOAST_LIFETIME, function()
		if not IsValid(toast) then return end
		toast:AlphaTo(0, TOAST_FADE, 0, function()
			if IsValid(toast) then toast:Remove() end
		end)
	end)
end

net.Receive("pdcity_toast", function()
	PDCity.ShowToast(net.ReadString())
end)

-- Client-side counterpart of core/sv_notify.lua's override: menus calling
-- LocalPlayer():ChatPrint for their own validation messages ("Pick a
-- class first...") land in a toast + the message log too, not the chatbox.
local PLAYER = FindMetaTable("Player")
local EngineChatPrint = PLAYER.ChatPrint

function PLAYER:ChatPrint(text)
	if self == LocalPlayer() then
		PDCity.ShowToast(text)
	else
		EngineChatPrint(self, text)
	end
end

--[[---------------------------------------------------------
	Output console - a strip showing the message log, newest at the bottom.
	Docked BOTTOM inside `parent`, so callers must create it BEFORE any
	FILL-docked sibling (a FILL docked first claims all the space).
-----------------------------------------------------------]]
local CONSOLE_TALL = 150

function PDCity.BuildMessageConsole(parent)
	local brandPrefix = "^%[" .. string.PatternSafe(PDCity.BRAND_TAG) .. "%]%s*"

	local console = vgui.Create("DPanel", parent)
	console:Dock(BOTTOM)
	console:SetTall(CONSOLE_TALL)
	console:DockMargin(0, 12, 0, 0)
	console:DockPadding(12, 8, 12, 10)
	console.Paint = function(self, w, h)
		draw.RoundedBox(8, 0, 0, w, h, PDCity.THEME.Panel)
	end

	local header = vgui.Create("DPanel", console)
	header:Dock(TOP)
	header:SetTall(22)
	header.Paint = function() end

	local title = vgui.Create("DLabel", header)
	title:Dock(FILL)
	title:SetFont("PDCity_Heading")
	title:SetText("Output")
	title:SetTextColor(PDCity.THEME.Text)

	local clearBtn = vgui.Create("DButton", header)
	clearBtn:Dock(RIGHT)
	clearBtn:SetWide(70)
	PDCity.StyleButton(clearBtn, "Clear", { Accent = PDCity.THEME.Background, AccentDim = PDCity.THEME.PanelHover, TextColor = PDCity.THEME.TextDim })

	local text = vgui.Create("RichText", console)
	text:Dock(FILL)
	text:DockMargin(0, 6, 0, 0)
	text.PerformLayout = function(self)
		self:SetFontInternal("PDCity_Small")
		self:SetBGColor(Color(0, 0, 0, 0))
	end

	local function Append(entry)
		text:InsertColorChange(PDCity.THEME.TextDim.r, PDCity.THEME.TextDim.g, PDCity.THEME.TextDim.b, 255)
		text:AppendText(entry.Time .. "  ")
		text:InsertColorChange(PDCity.THEME.Text.r, PDCity.THEME.Text.g, PDCity.THEME.Text.b, 255)
		text:AppendText(string.gsub(entry.Text, brandPrefix, "") .. "\n")
		text:GotoTextEnd()
	end

	-- Clearing only empties this view - other open consoles keep theirs.
	local clearedUpTo = 0
	local function Rebuild()
		text:SetText("")
		for i = clearedUpTo + 1, #PDCity.MESSAGE_LOG do Append(PDCity.MESSAGE_LOG[i]) end
	end

	clearBtn.DoClick = function()
		clearedUpTo = #PDCity.MESSAGE_LOG
		Rebuild()
	end

	Rebuild()
	hook.Add("PDCity_MessageLogged", console, function(_, entry)
		-- The log drops its oldest entry once full; keep the cleared mark in step.
		if #PDCity.MESSAGE_LOG >= LOG_LIMIT then clearedUpTo = math.max(0, clearedUpTo - 1) end
		Append(entry)
	end)

	return console
end
