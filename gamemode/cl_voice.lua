--[[---------------------------------------------------------
	Client side of proximity voice chat. core/sv_voice.lua decides who
	receives the audio at all - everything here only makes what you DO
	hear sound and look right, and has no effect on who can hear whom.

	Two effects:
	  - Volume fades out approaching the hearing range instead of
	    holding at full volume right up to a hard cutoff.
	    Player:SetVoiceVolumeScale is a purely local mix knob (it does
	    not change what's sent to anyone), so it's safe to drive from
	    here with no server involvement.
	  - A small in-world marker over anyone talking nearby, since the
	    base gamemode's own voice indicator
	    (gamemodes/base/gamemode/cl_voice.lua) is a flat list in the
	    corner and gives no sense of WHERE the sound is coming from -
	    the whole point of proximity chat.
-----------------------------------------------------------]]

-- [ply] = current fade scale (0-1). Computed once per player per
-- frame in Think and read back by the render hook below, rather than
-- recomputing the distance in a hook that can run more than once a
-- frame.
local FadeScale = {}

hook.Add("Think", "pdcity_VoiceFade", function()

	local me = LocalPlayer()
	if not IsValid(me) then return end

	for _, ply in ipairs(player.GetAll()) do

		if ply == me or not ply:IsSpeaking() then
			FadeScale[ply] = nil
		else
			local dist = me:GetPos():Distance(ply:GetPos())
			local scale = 1 - math.Clamp(
				(dist - PDCity.VOICE_FADE_START) / (PDCity.VOICE_HEAR_DISTANCE - PDCity.VOICE_FADE_START),
				0, 1
			)

			ply:SetVoiceVolumeScale(scale)
			FadeScale[ply] = scale
		end

	end

end)

hook.Add("PlayerDisconnected", "pdcity_VoiceFadeCleanup", function(ply)
	FadeScale[ply] = nil
end)

--[[---------------------------------------------------------
	"Who can hear you" - left-hand list shown only while you're
	actually transmitting, so it's not clutter the rest of the time.

	Built with PDCity.CanHearVoice (core/sh_voice.lua) - the same
	predicate the server uses to decide what to actually send - rather
	than re-deriving "in range" here, so this can never show a name
	the server would disagree with. Works identically for a bot: bots
	are ordinary Player entities with a position, so one standing near
	you shows up here exactly like a real player would, even though
	bots can never BE the talker (no mic) - handy for testing the
	range/list behaviour without needing a second human.
-----------------------------------------------------------]]

local function GetHearingListeners(me)
	local out = {}

	for _, ply in ipairs(player.GetAll()) do
		if PDCity.CanHearVoice(ply, me) then
			table.insert(out, ply)
		end
	end

	table.sort(out, function(a, b) return PDCity.GetDisplayName(a) < PDCity.GetDisplayName(b) end)
	return out
end

hook.Add("HUDPaint", "pdcity_VoiceHearerList", function()

	local me = LocalPlayer()
	if not IsValid(me) or not me:IsSpeaking() then return end

	local listeners = GetHearingListeners(me)

	local x, y, w = 20, ScrH() * 0.4, 220
	local lineH = 20
	local rows = math.max(#listeners, 1)
	local h = 34 + rows * lineH

	draw.RoundedBox(6, x, y, w, h, Color(PDCity.THEME.Panel.r, PDCity.THEME.Panel.g, PDCity.THEME.Panel.b, 225))
	draw.SimpleText("Can hear you:", "PDCity_Small", x + 10, y + 10, PDCity.THEME.Accent, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

	if #listeners == 0 then
		draw.SimpleText("(nobody in range)", "PDCity_Small", x + 10, y + 30, PDCity.THEME.TextDim, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
	else
		for i, ply in ipairs(listeners) do
			draw.SimpleText(PDCity.GetDisplayName(ply), "PDCity_Small", x + 10, y + 30 + (i - 1) * lineH, PDCity.THEME.Text, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
		end
	end

end)

hook.Add("PostDrawOpaqueRenderables", "pdcity_VoiceIcons", function()

	local me = LocalPlayer()
	if not IsValid(me) then return end

	for ply, scale in pairs(FadeScale) do

		if IsValid(ply) and scale > 0 then

			local headPos = ply:EyePos() + Vector(0, 0, 9)
			local ang = Angle(0, me:EyeAngles().y - 90, 90)
			local alpha = 255 * scale

			cam.Start3D2D(headPos, ang, 0.1)
				draw.RoundedBox(6, -66, -6, 12, 12, Color(90, 230, 130, alpha))
				draw.SimpleTextOutlined(PDCity.GetDisplayName(ply), "PDCity_Small", -48, 0,
					Color(235, 237, 240, alpha), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 1, Color(0, 0, 0, alpha))
			cam.End3D2D()

		end

	end

end)
