--[[---------------------------------------------------------
	Death screen countdown for core/sv_respawn.lua. Purely display -
	the server blocks early respawns regardless of what this draws.
-----------------------------------------------------------]]

-- Remembers when the current wait began, so the progress bar's total
-- is the real one - inferring it from time-remaining would make a 20s
-- PvP bar visually jump once it dropped under 5s.
local trackedAt, startedAt = 0, 0

hook.Add("HUDPaint", "pdcity_RespawnTimer", function()

	local ply = LocalPlayer()
	if not IsValid(ply) or ply:Alive() then return end

	local respawnAt = ply:GetNWFloat("PDCity_RespawnAt", 0)
	if respawnAt <= 0 then return end

	if respawnAt ~= trackedAt then
		trackedAt = respawnAt
		startedAt = CurTime()
	end

	local w = 320
	local x, y = (ScrW() - w) / 2, ScrH() * 0.72
	local remaining = respawnAt - CurTime()

	draw.RoundedBox(8, x, y, w, 64, PDCity.THEME.TitleBar)

	if remaining > 0 then
		draw.SimpleText("YOU DIED", "PDCity_Heading", x + w / 2, y + 16, Color(220, 90, 80), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
		draw.SimpleText(("Respawn in %.1fs"):format(remaining), "PDCity_Body", x + w / 2, y + 42, PDCity.THEME.Text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

		-- Progress bar draining right-to-left as the wait runs out.
		local total = math.max(respawnAt - startedAt, 0.1)
		local frac = math.Clamp(remaining / total, 0, 1)
		draw.RoundedBox(2, x + 12, y + 58, (w - 24) * frac, 3, PDCity.THEME.Accent)
	else
		draw.SimpleText("Click to respawn", "PDCity_Heading", x + w / 2, y + 32, PDCity.THEME.Text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
	end

end)
