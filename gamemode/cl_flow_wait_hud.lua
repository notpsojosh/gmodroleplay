--[[---------------------------------------------------------
	Countdown shown while a Flowchart "Wait" node (core/sv_activities.lua)
	is running - "Processing 4s", "Waiting 12s", whatever the node's own
	optional Label field is set to (defaults to "Waiting"). Purely a
	display: the actual wait is timed server-side (timer.Simple), this
	just mirrors it so the player isn't left staring at nothing wondering
	if anything happened.

	Only one at a time - a second "pdcity_flow_wait_display" simply
	replaces whatever's currently showing, same as how only one flow chain
	can realistically be running against one player's own action at once.
-----------------------------------------------------------]]

local activeWait = nil -- { Label = "...", EndTime = CurTime() + seconds }

net.Receive("pdcity_flow_wait_display", function()
	local label = net.ReadString()
	local seconds = net.ReadFloat()

	activeWait = { Label = label, EndTime = CurTime() + math.max(0, seconds) }
end)

hook.Add("HUDPaint", "pdcity_DrawFlowWaitCountdown", function()
	if not activeWait then return end

	local remaining = activeWait.EndTime - CurTime()
	if remaining <= 0 then
		activeWait = nil
		return
	end

	local text = activeWait.Label .. " " .. string.format("%.1f", remaining) .. "s"

	draw.SimpleTextOutlined(text, "PDCity_Heading", ScrW() / 2, ScrH() * 0.62,
		PDCity.THEME.Text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 2, PDCity.THEME.Background)
end)
