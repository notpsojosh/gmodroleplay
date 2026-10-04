--[[---------------------------------------------------------
	Draws each entity's "PDCity_Nameplate" NWString (core/sv_nameplates.lua)
	floating above it - a plain 2D label at its world position projected
	to screen, fading out with distance, hidden if the entity isn't
	actually visible on screen right now.

	The candidate LIST (which entities even have a label) only rescans
	every 0.5s via ents.FindInSphere, not every frame - re-checking every
	entity in range every single frame for a string that almost never
	changes would be real, needless cost. Actually DRAWING from that
	cached list still happens every frame (HUDPaint), so a moving prop's
	label still tracks it smoothly between rescans.
-----------------------------------------------------------]]

local MAX_DIST = 2000
local RESCAN_INTERVAL = 0.5
local FADE_START = 1500 -- starts fading beyond this distance, fully gone by MAX_DIST

local labeled = {} -- cached list of entities currently in range with a non-empty nameplate

local function Rescan()
	labeled = {}

	local ply = LocalPlayer()
	if not IsValid(ply) then return end

	for _, ent in ipairs(ents.FindInSphere(ply:GetPos(), MAX_DIST)) do
		if IsValid(ent) and ent:GetNWString("PDCity_Nameplate", "") ~= "" then
			table.insert(labeled, ent)
		end
	end
end

timer.Create("pdcity_EntityLabelRescan", RESCAN_INTERVAL, 0, Rescan)

-- pcall-wrapped per entity - one bad/edge-case entity (e.g. a render bounds
-- query on something mid-removal) throwing here would otherwise take the
-- WHOLE hook down for that frame, silently skipping every other label too
-- and, depending on hook registration order, every HUDPaint hook added
-- after this one - "nothing draws at all" instead of an obvious one-off
-- glitch on one entity.
local function DrawOneLabel(ent, eyePos)
	if not IsValid(ent) then return end

	local text = ent:GetNWString("PDCity_Nameplate", "")
	if text == "" then return end

	local dist = eyePos:Distance(ent:GetPos())
	if dist > MAX_DIST then return end

	-- Top of the entity's own bounding box, not just its origin - a
	-- tall prop's label sits above its actual top instead of
	-- floating at its feet/center.
	local mins, maxs = ent:GetRenderBounds()
	local worldPos = ent:GetPos() + Vector(0, 0, maxs.z + 6)

	local screenPos = worldPos:ToScreen()
	if not screenPos.visible then return end

	local alpha = 255
	if dist > FADE_START then
		alpha = math.Clamp(255 * (1 - (dist - FADE_START) / (MAX_DIST - FADE_START)), 0, 255)
	end
	if alpha <= 2 then return end

	draw.SimpleTextOutlined(text, "PDCity_Small", screenPos.x, screenPos.y,
		ColorAlpha(PDCity.THEME.Text, alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM,
		1, ColorAlpha(PDCity.THEME.Background, alpha))
end

hook.Add("HUDPaint", "pdcity_DrawEntityLabels", function()
	local ply = LocalPlayer()
	if not IsValid(ply) then return end
	local eyePos = ply:EyePos()

	for _, ent in ipairs(labeled) do
		local ok, err = pcall(DrawOneLabel, ent, eyePos)
		if not ok then
			ErrorNoHalt("[" .. PDCity.BRAND_TAG .. "] Entity label draw failed: " .. tostring(err) .. "\n")
		end
	end
end)
