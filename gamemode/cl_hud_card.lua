--[[---------------------------------------------------------
	Bottom-left HUD card: portrait, job, money, custom currencies,
	health/armor bars - in place of the stock HL2 health/armor/suit HUD
	(a plain number over a stone texture, doesn't match this gamemode's
	own theme at all and shows nothing about job/money). That stock HUD
	is hidden below via GM:HUDShouldDraw so the two don't both show at
	once.

	Colours, scale, opacity, title, font, text sizes, health/armor icons,
	and which custom currencies show are all owner-editable
	(core/sv_hud_settings.lua, cl_hud_editor.lua) - PDCity.HUD_SETTINGS,
	synced on join. DEFAULT_SETTINGS below is what this draws with before
	that first sync lands.
-----------------------------------------------------------]]

local noDraw = {
	["CHudHealth"] = true,
	["CHudBattery"] = true,
	["CHudSuitPower"] = true,
}

function GM:HUDShouldDraw(name)
	if noDraw[name] then return false end
	return true
end

local DEFAULT_SETTINGS = PDCity.DefaultHUDSettings() -- core/sh_hud_settings.lua

local function Settings()
	local live = PDCity.HUD_SETTINGS
	if not istable(live) then return DEFAULT_SETTINGS end
	return live
end

--[[---------------------------------------------------------
	The card's own fonts, one per PDCity.HUD_TEXT_ELEMENTS entry
	("PDCity_HUDCard_Title", "PDCity_HUDCard_Stat"...). Sized from the
	owner's text sizes x Card Scale, in the owner's chosen family (or the
	Site Theme's). surface.CreateFont is too costly to run every frame, so
	they're only rebuilt when that combination actually changes.
-----------------------------------------------------------]]
local FONT_PREFIX = "PDCity_HUDCard_"
local builtFontKey

local function HUDFont(key)
	return FONT_PREFIX .. key
end

-- Returns { [elementKey] = pixel size } for this frame.
local function EnsureFonts(settings, scale)
	local family = settings.Font
	if not isstring(family) or family == "" then
		family = istable(PDCity.SITE_THEME) and isstring(PDCity.SITE_THEME.FontFamily) and PDCity.SITE_THEME.FontFamily or "Roboto"
	end

	-- The player's own readable mode (cl_accessibility.lua) beats the
	-- owner's card font.
	if PDCity.IsReadableMode() then
		family = PDCity.READABLE_FONT
		scale = scale * PDCity.READABLE_TEXT_SCALE
	end

	local sizes = {}
	local key = family
	for _, element in ipairs(PDCity.HUD_TEXT_ELEMENTS) do
		local size = math.Round(PDCity.GetHUDTextSize(settings, element) * scale)
		sizes[element.Key] = size
		key = key .. "|" .. size
	end

	if key ~= builtFontKey then
		builtFontKey = key
		for _, element in ipairs(PDCity.HUD_TEXT_ELEMENTS) do
			surface.CreateFont(HUDFont(element.Key), {
				font = family,
				size = sizes[element.Key],
				weight = element.Weight,
				antialias = true,
			})
		end
	end

	return sizes
end

local BASE_CARD_W = 366
local BASE_PORTRAIT_SIZE = 76
local BASE_PAD = 14
local BASE_ICON_BOX = 22
local BASE_BAR_H = 16
local BASE_ROW_GAP = 8
local BASE_PILL_H = 24
local BASE_CHIP_H = 26
local BASE_BRAND_H = 26

-- Shrinks (never wraps) `text` until it fits `maxW` at `font`, appending
-- "..." once it has to cut anything - used for the character name below
-- the portrait, which has to stay inside the portrait's own width
-- regardless of how long a name someone's picked (core/sv_rpname.lua
-- allows up to 18 characters).
local function FitText(text, font, maxW)
	surface.SetFont(font)
	if select(1, surface.GetTextSize(text)) <= maxW then return text end

	while #text > 1 do
		text = string.sub(text, 1, #text - 1)
		if select(1, surface.GetTextSize(text .. "...")) <= maxW then break end
	end

	return text .. "..."
end

--[[---------------------------------------------------------
	Portrait - a real 3D render of the player's current model
	(PDCity.BuildPortrait, cl_theme.lua - same function the Jobs/Arrest/
	Staff menus already use for "who is this" cards), not a Steam
	avatar - more fitting for showing the character you're actually
	playing, and this gamemode already has the function for it.

	Built once per model+size (not every HUDPaint) and repositioned/
	redrawn via SetPos + PaintManual, same technique as an always-on-screen
	AvatarImage would use - a DModelPanel is a real VGUI panel, not
	something a draw.* call can create.
-----------------------------------------------------------]]
local portraitHolder
local portraitForModel
local portraitForSize

local function EnsurePortrait(model, size)
	if not model or model == "" then return end
	if portraitForModel == model and portraitForSize == size and IsValid(portraitHolder) then return end
	portraitForModel = model
	portraitForSize = size

	if IsValid(portraitHolder) then portraitHolder:Remove() end

	portraitHolder = vgui.Create("DPanel")
	portraitHolder:SetSize(size, size)
	portraitHolder:SetMouseInputEnabled(false)
	-- Drawn only by HUDPaint's PaintManual below. Without this, VGUI's own
	-- paint pass ALSO drew it each frame at a slightly different moment of
	-- the model's idle animation, leaving a ghosted second head.
	portraitHolder:SetPaintedManually(true)
	portraitHolder.Paint = function(self, w, h)
		draw.RoundedBox(8, 0, 0, w, h, PDCity.THEME.TitleBar)
	end

	-- PDCity.BuildPortrait's own FOV (28) is tuned for the bigger "who is
	-- this" cards elsewhere (Jobs/Arrest/Staff menus) - at this card's
	-- much smaller box, the same framing left the character looking
	-- small with empty space around them. A narrower FOV here zooms in
	-- (bigger-looking character, same camera position/framing math
	-- otherwise) without touching the shared function every other
	-- portrait in the gamemode also relies on.
	local modelPanel = PDCity.BuildPortrait(portraitHolder, model)
	if IsValid(modelPanel) then modelPanel:SetFOV(18) end
end

local function LerpColor(frac, from, to)
	return Color(
		Lerp(frac, from.r, to.r),
		Lerp(frac, from.g, to.g),
		Lerp(frac, from.b, to.b)
	)
end

-- Settings' HealthLow/HealthHigh/ArmorLow/ArmorHigh are plain {r,g,b}
-- tables (as synced over net/JSON - Color() userdata doesn't survive
-- that round trip), converted here into real Colors right before use.
local function TableToColorLocal(t, fallback)
	if not istable(t) then return Color(fallback.r, fallback.g, fallback.b) end
	return Color(t.r or fallback.r, t.g or fallback.g, t.b or fallback.b)
end

-- Small hand-drawn icons (a medical cross, a shield) rather than a glyph
-- from a font - emoji/symbol coverage in a surface.CreateFont is never
-- guaranteed across every client's system fonts, these render identically
-- everywhere. Both take the same (cx, cy, size, color) shape so a caller
-- never needs per-icon-type positioning math. Overridden per the owner's
-- HUD settings (an icon16 path or URL) via DrawIconOrDefault below.
local function DrawCrossIcon(cx, cy, size, color)
	surface.SetDrawColor(color)
	local thick = math.max(2, math.floor(size * 0.32))
	surface.DrawRect(cx - thick / 2, cy - size / 2, thick, size)
	surface.DrawRect(cx - size / 2, cy - thick / 2, size, thick)
end

-- A shield tapering to a single point at the bottom has more of its area
-- up top, so centring its bounding box on cy reads as sitting slightly
-- LOW (the eye weighs the wide top more than the narrow point) - shifted
-- up a touch to compensate, rather than centring the raw geometry.
local function DrawShieldIcon(cx, cy, size, color)
	local w, h = size, size * 1.08
	local midY = cy - h * 0.08
	surface.SetDrawColor(color)
	draw.NoTexture()
	surface.DrawPoly({
		{ x = cx - w / 2, y = midY - h / 2 },
		{ x = cx + w / 2, y = midY - h / 2 },
		{ x = cx + w / 2, y = midY + h * 0.12 },
		{ x = cx, y = midY + h / 2 },
		{ x = cx - w / 2, y = midY + h * 0.12 },
	})
end

-- iconPath ("" = none set) overrides the hand-drawn default with a real
-- resolved icon (PDCity.GetIconMaterial, cl_theme.lua - a silkicon path
-- or a fetched http(s) image), same resolution every Icon field in this
-- gamemode already uses. Falls back to the default shape while a URL's
-- fetch is still in flight (GetIconMaterial returns nil until it lands).
local function DrawIconOrDefault(iconPath, defaultFn, cx, cy, size, color)
	if iconPath and iconPath ~= "" then
		local mat = PDCity.GetIconMaterial(iconPath)
		if mat then
			surface.SetDrawColor(255, 255, 255, 255)
			surface.SetMaterial(mat)
			surface.DrawTexturedRect(cx - size / 2, cy - size / 2, size, size)
			return
		end
	end
	defaultFn(cx, cy, size, color)
end

local BAR_TRACK = Color(0, 0, 0, 150)
local MONEY_ACCENT = Color(235, 195, 90)

--[[---------------------------------------------------------
	Layout, top to bottom within the text column (right of the portrait):
	a compact job pill (icon dot + name, coloured per-job), a money chip
	right below it (coin icon + amount), then one chip per displayed
	custom currency (core/sh_currencies.lua, owner-picked in the HUD
	editor), then two full-width status bars (health, armor) along the
	card's bottom - each with its own icon and a right-aligned number
	OUTSIDE the bar rather than text stamped on top of the fill.

	The whole card is scaled by a single multiplier (the HUD editor's
	"Card Scale") and grows taller automatically to fit however many
	currency chips are displayed - not a fixed height that clips or
	leaves dead space depending on how many currencies the owner's set up.

	Deliberately borderless (no surface.DrawOutlinedRect anywhere in this
	file) - draw.RoundedBox has no matching "rounded outline" primitive,
	so stroking a ROUNDED shape's edge with a SQUARE outline rect used to
	visibly clip the corners. Shadows + colour contrast carry the
	definition instead.
-----------------------------------------------------------]]
hook.Add("HUDPaint", "pdcity_HUDCard", function()
	local ply = LocalPlayer()
	local settings = Settings()
	local S = math.Clamp(tonumber(settings.Scale) or 1.0, 0.6, 1.8)

	if not IsValid(ply) or not ply:Alive() then
		if IsValid(portraitHolder) then portraitHolder:SetVisible(false) end
		return
	end

	local textSizes = EnsureFonts(settings, S)

	-- Rows grow to fit bigger text instead of letting it overflow; at the
	-- default text sizes these all come out at exactly the BASE_* values.
	local PAD = BASE_PAD * S
	local PORTRAIT_SIZE = BASE_PORTRAIT_SIZE * S
	local ICON_BOX = math.max(BASE_ICON_BOX * S, textSizes.Stat + S)
	local BAR_H = BASE_BAR_H * S
	local ROW_GAP = BASE_ROW_GAP * S
	local PILL_H = math.max(BASE_PILL_H * S, math.max(textSizes.Job, textSizes.Name) + 4 * S)
	local CHIP_H = math.max(BASE_CHIP_H * S, textSizes.Amount + 9 * S)
	local widthFrac = math.Clamp(tonumber(settings.Width) or 100, PDCity.HUD_WIDTH_MIN, PDCity.HUD_WIDTH_MAX) / 100
	local heightFrac = math.Clamp(tonumber(settings.Height) or 100, PDCity.HUD_HEIGHT_MIN, PDCity.HUD_HEIGHT_MAX) / 100
	-- Never wider than the screen, whatever Scale x Width comes to.
	local CARD_W = math.min(BASE_CARD_W * S * widthFrac, ScrW() - 28)
	local BRAND_H = math.max(BASE_BRAND_H * S, textSizes.Title + 2 * S)
	local LOGO_SIZE = BRAND_H - 4 * S

	local cardAlpha = math.Clamp(tonumber(settings.CardOpacity) or 100, 0, 100) / 100
	local chipAlpha = math.Clamp(tonumber(settings.ChipOpacity) or 100, 0, 100) / 100
	local chipColor = ColorAlpha(PDCity.THEME.Panel, PDCity.THEME.Panel.a * chipAlpha)

	local displayedCurrencies = {}
	for _, id in ipairs(settings.DisplayedCurrencies or {}) do
		local currency = PDCity.GetCurrencyByID(id)
		if currency then table.insert(displayedCurrencies, currency) end
	end

	-- Height auto-fits whatever's actually shown - the info column (job
	-- pill + money chip + one chip per displayed currency) vs the
	-- portrait, whichever's taller, plus the two bar rows at the bottom.
	local infoColH = PILL_H + ROW_GAP + CHIP_H + (#displayedCurrencies * (CHIP_H + ROW_GAP))
	local topBlockH = math.max(PORTRAIT_SIZE, infoColH)
	local barsBlockH = ICON_BOX * 2 + ROW_GAP
	local fixedH = PAD * 2 + BRAND_H + ROW_GAP + ROW_GAP * 1.5 + barsBlockH

	-- Card Height above 100% adds its extra to the portrait/info block;
	-- the portrait grows into it (capped so it can't eat the text column),
	-- and the portrait + info column are centred in whatever's left.
	-- Clamped so the whole card always stays on screen - a card taller
	-- than the screen pushed the portrait's top off it, and a DModelPanel
	-- PaintManual()'d partly off-screen draws nothing at all.
	local extraH = (fixedH + topBlockH) * (heightFrac - 1)
	extraH = math.max(0, math.min(extraH, ScrH() - 28 - fixedH - topBlockH))
	topBlockH = topBlockH + extraH
	local maxPortrait = math.max(PORTRAIT_SIZE, math.min(CARD_W * 0.4, BASE_PORTRAIT_SIZE * 3 * S))
	PORTRAIT_SIZE = math.min(PORTRAIT_SIZE + extraH, topBlockH, maxPortrait)
	local CARD_H = fixedH + topBlockH

	local cardX, cardY = 14, ScrH() - CARD_H - 14
	local job = PDCity.GetJob(ply:Team())
	local jobColor = (job and job.Color) or PDCity.THEME.Accent

	PDCity.DrawShadow(cardX, cardY, CARD_W, CARD_H, 10, cardAlpha)
	-- Fully opaque by default rather than the shared PDCity.THEME.Background's
	-- alpha 230 - this card sits directly over gameplay rather than a dimmed
	-- menu backdrop. The owner can lower it (HUD editor's Card Opacity).
	draw.RoundedBox(10, cardX, cardY, CARD_W, CARD_H, ColorAlpha(PDCity.THEME.Background, 255 * cardAlpha))

	--[[-------------------------------------------------------
		Branding row - the server logo (or a placeholder square if it
		hasn't loaded) + the card title, above the portrait/job row.
	---------------------------------------------------------]]
	local brandX, brandY = cardX + PAD, cardY + PAD
	if PDCity.LOGO_MAT and not PDCity.LOGO_MAT:IsError() then
		surface.SetDrawColor(255, 255, 255, 255)
		surface.SetMaterial(PDCity.LOGO_MAT)
		surface.DrawTexturedRect(brandX, brandY, LOGO_SIZE, LOGO_SIZE)
	else
		draw.RoundedBox(5, brandX, brandY, LOGO_SIZE, LOGO_SIZE, ColorAlpha(PDCity.THEME.Accent, 40 * chipAlpha))
		surface.SetDrawColor(PDCity.THEME.Accent)
		surface.DrawOutlinedRect(brandX, brandY, LOGO_SIZE, LOGO_SIZE, 1)
	end

	local title = isstring(settings.Title) and settings.Title ~= "" and settings.Title or PDCity.BRAND_NAME
	local titleX = brandX + LOGO_SIZE + 9 * S
	title = FitText(title, HUDFont("Title"), cardX + CARD_W - PAD - titleX)
	draw.SimpleText(title, HUDFont("Title"), titleX, brandY + LOGO_SIZE / 2, PDCity.THEME.Text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

	-- Portrait, with a soft shadow and a subtle neutral frame drawn behind
	-- it (so it reads as a border, not an outline on top hiding the
	-- model's edges).
	local topY = cardY + PAD + BRAND_H + ROW_GAP
	local px, py = cardX + PAD + 4, topY + (topBlockH - PORTRAIT_SIZE) / 2
	PDCity.DrawShadow(px - 3, py - 3, PORTRAIT_SIZE + 6, PORTRAIT_SIZE + 6, 8)
	draw.RoundedBox(8, px - 3, py - 3, PORTRAIT_SIZE + 6, PORTRAIT_SIZE + 6, PDCity.THEME.Border)
	EnsurePortrait(ply:GetModel(), math.Round(PORTRAIT_SIZE))
	if IsValid(portraitHolder) then
		portraitHolder:SetVisible(true)
		portraitHolder:SetPos(px, py)

		-- PaintManual()'d from HUDPaint (outside the normal per-frame VGUI
		-- paint pass DModelPanel expects) can leave the PREVIOUS
		-- character's model still faintly visible behind the new one for
		-- a frame or two after switching - the scissored 3D draw doesn't
		-- always fully overwrite what was already in the colour/depth
		-- buffer at those pixels. An explicit clear of just this rect,
		-- right before painting, guarantees nothing old survives.
		render.SetScissorRect(px, py, px + PORTRAIT_SIZE, py + PORTRAIT_SIZE, true)
		render.Clear(0, 0, 0, 0, true, true)
		render.SetScissorRect(0, 0, 0, 0, false)

		portraitHolder:PaintManual()
	end

	--[[-------------------------------------------------------
		Job pill - a compact chip (small dot + name), not a solid block of
		colour with text stamped on it.
	---------------------------------------------------------]]
	local textX = px + PORTRAIT_SIZE + 14
	-- The info column's own top, centred beside the portrait.
	py = topY + (topBlockH - infoColH) / 2
	local textRight = cardX + CARD_W - PAD
	local jobName = (job and job.Name) or "Citizen"

	surface.SetFont(HUDFont("Job"))
	local jobTextW = select(1, surface.GetTextSize(jobName))
	local pillW = jobTextW + 34 * S
	local dotSize = 8 * S

	draw.RoundedBox(6, textX, py, pillW, PILL_H, ColorAlpha(jobColor, 55 * chipAlpha))
	draw.RoundedBox(dotSize / 2, textX + 10 * S, py + PILL_H / 2 - dotSize / 2, dotSize, dotSize, jobColor)
	draw.SimpleText(jobName, HUDFont("Job"), textX + 26 * S, py + PILL_H / 2, PDCity.THEME.Text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

	-- Character's current name, to the right of the job pill on the same
	-- row - ALWAYS the character's own name (PDCity_CharacterName,
	-- core/sv_accounts.lua's roster, synced on PDCity_CharacterSelected
	-- and kept in sync by core/sv_rpname.lua's /name), never the
	-- player's Steam nick - deliberately not PDCity.GetDisplayName,
	-- which falls back to that. Shrunk to fit whatever space is left
	-- before the card's own right edge, rather than wrapping.
	local nameX = textX + pillW + 10
	local characterName = ply:GetNWString("PDCity_CharacterName", "")
	local nameText = FitText(characterName ~= "" and characterName or "Unnamed", HUDFont("Name"), textRight - nameX)
	draw.SimpleText(nameText, HUDFont("Name"), nameX, py + PILL_H / 2, PDCity.THEME.Text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

	--[[-------------------------------------------------------
		Money chip, then one chip per displayed custom currency
		(core/sh_currencies.lua) - same visual shape as money, just reading
		PDCity.MY_CURRENCY_BALANCES (cl_currencies.lua) instead of the
		NWInt Money uses, and the currency's own Icon field instead of the
		fixed coin.
	---------------------------------------------------------]]
	-- `glyph` (optional) draws a short label centered ON the fallback
	-- circle itself - Money's "$" used to render this way before the
	-- money chip and the (later-added) custom currency chips were merged
	-- into this one shared helper, which dropped it. Only shown on the
	-- ROUND fallback icon, not over a real resolved image (a currency
	-- with its own Icon set already has something meaningful there).
	local function DrawAmountChip(y, iconPath, iconFallbackColor, text, glyph)
		draw.RoundedBox(6, textX, y, textRight - textX, CHIP_H, chipColor)

		local iconSize = CHIP_H - 8
		local iconCX, iconCY = textX + 8 + iconSize / 2, y + CHIP_H / 2
		local usedFallback = true

		if iconPath and iconPath ~= "" then
			local mat = PDCity.GetIconMaterial(iconPath)
			if mat then
				usedFallback = false
				surface.SetDrawColor(255, 255, 255, 255)
				surface.SetMaterial(mat)
				surface.DrawTexturedRect(iconCX - iconSize / 2, iconCY - iconSize / 2, iconSize, iconSize)
			end
		end

		if usedFallback then
			draw.RoundedBox(iconSize / 2, textX + 8, y + CHIP_H / 2 - iconSize / 2, iconSize, iconSize, iconFallbackColor)
			if glyph then
				draw.SimpleText(glyph, "PDCity_Small", iconCX, iconCY, Color(40, 32, 10), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
			end
		end

		draw.SimpleText(text, HUDFont("Amount"), textX + 12 + iconSize, y + CHIP_H / 2, PDCity.THEME.Text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end

	local moneyY = py + PILL_H + ROW_GAP
	DrawAmountChip(moneyY, "", MONEY_ACCENT, "$" .. string.Comma(ply:GetNWInt("PDCity_Money", 0)), "$")

	local chipY = moneyY + CHIP_H + ROW_GAP
	for _, currency in ipairs(displayedCurrencies) do
		local balance = (PDCity.MY_CURRENCY_BALANCES or {})[currency.ID] or 0
		DrawAmountChip(chipY, currency.Icon, PDCity.THEME.Accent, string.Comma(balance) .. " " .. currency.Symbol)
		chipY = chipY + CHIP_H + ROW_GAP
	end

	--[[-------------------------------------------------------
		Health/armor bars - identical geometry for both, so they come out
		the same length with their icons lined up in a clean column,
		rather than each bar computing its own sizes off its own height.
	---------------------------------------------------------]]
	local barsX = px - 3
	local barsRight = textRight
	local barsW = barsRight - barsX

	surface.SetFont(HUDFont("Stat"))
	local numW = select(1, surface.GetTextSize("100")) + 4 * S

	local barX = barsX + ICON_BOX + 8
	local barW = barsW - ICON_BOX - 8 - numW - 8
	local trackColor = ColorAlpha(BAR_TRACK, BAR_TRACK.a * chipAlpha)

	local function StatusBar(rowY, ratio, colorLow, colorHigh, iconFn, iconPath, valueText)
		local iconCX, iconCY = barsX + ICON_BOX / 2, rowY + ICON_BOX / 2

		draw.RoundedBox(6, barsX, rowY, ICON_BOX, ICON_BOX, chipColor)
		DrawIconOrDefault(iconPath, iconFn, iconCX, iconCY, ICON_BOX * 0.5, Color(235, 235, 240))

		local barY = rowY + (ICON_BOX - BAR_H) / 2

		draw.RoundedBox(BAR_H / 2, barX, barY, barW, BAR_H, trackColor)
		if ratio > 0 then
			-- A single Lerp'd colour (shifting low->high as the value
			-- rises) rather than a gradient painted across the fill -
			-- draw.RoundedBox has no gradient primitive, so this is the
			-- same "rounded pill, colour reflects the value" bar most
			-- modern game HUDs actually use.
			local fillW = math.max(BAR_H, barW * ratio)
			local fillColor = LerpColor(ratio, colorLow, colorHigh)
			draw.RoundedBox(BAR_H / 2, barX, barY, fillW, BAR_H, fillColor)
			-- Glossy highlight along the top third of the fill.
			surface.SetDrawColor(255, 255, 255, 35)
			surface.DrawRect(barX + 2, barY + 1, math.max(0, fillW - 4), math.max(0, BAR_H * 0.3))
		end

		draw.SimpleText(valueText, HUDFont("Stat"), barsRight, rowY + ICON_BOX / 2, PDCity.THEME.Text, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
	end

	local maxHealth = math.max(1, ply:GetMaxHealth())
	local healthRatio = math.Clamp(ply:Health() / maxHealth, 0, 1)
	local armor = math.Clamp(ply:Armor(), 0, 100)

	local healthColorLow = TableToColorLocal(settings.HealthLow, DEFAULT_SETTINGS.HealthLow)
	local healthColorHigh = TableToColorLocal(settings.HealthHigh, DEFAULT_SETTINGS.HealthHigh)
	local armorColorLow = TableToColorLocal(settings.ArmorLow, DEFAULT_SETTINGS.ArmorLow)
	local armorColorHigh = TableToColorLocal(settings.ArmorHigh, DEFAULT_SETTINGS.ArmorHigh)

	local healthY = cardY + CARD_H - PAD - ICON_BOX * 2 - ROW_GAP
	StatusBar(healthY, healthRatio, healthColorLow, healthColorHigh, DrawCrossIcon, settings.HealthIcon, tostring(math.max(0, math.Round(ply:Health()))))

	local armorY = healthY + ICON_BOX + ROW_GAP
	StatusBar(armorY, armor / 100, armorColorLow, armorColorHigh, DrawShieldIcon, settings.ArmorIcon, tostring(armor))

end)
