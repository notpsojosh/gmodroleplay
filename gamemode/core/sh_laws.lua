--[[---------------------------------------------------------
	Law list for the arrest menu (core/sv_arrests.lua, cl_arrest_menu.lua),
	plus the jail system's money "rewards" - what an officer earns per
	year of sentence, what bail costs per minute remaining, and the
	penalty for disconnecting mid-sentence. Both owner-editable in-game
	from the F1 Site Admin panel's "Laws & Rewards" tab (cl_site_admin.lua),
	persisted/synced by core/sv_law_settings.lua - what's below is only
	the BUILT-IN DEFAULT, used until a saved config exists (fresh install)
	or if data/pdcity/law_settings.json is ever deleted/corrupt.

	PDCity.LAWS/PDCity.LAW_REWARDS are guarded with "or" (not a bare
	assignment) so re-including this file - e.g. a fast weapon/gamemode
	reload during development - never stomps whatever core/sv_law_settings.lua
	already loaded from disk back to these defaults.

	MinMinutes/MaxMinutes are real minutes - that's what every actual
	game mechanic runs on (the jail countdown, officer pay, bail cost,
	the disconnect penalty). Displayed to players as "years" instead of
	"minutes" is purely a cosmetic RP flourish (1 year = 1 real minute)
	handled at the point of display, not by changing any of the
	underlying numbers.
-----------------------------------------------------------]]

-- Ships empty - every law is added in-game by the owner.
PDCity.LAWS = PDCity.LAWS or {}

PDCity.LAW_REWARDS = PDCity.LAW_REWARDS or {
	PayPerMinute = 250,               -- officer's cut per year (real minute) of a processed sentence
	BailPerMinute = 500,              -- cost to bail someone out, per minute remaining
	DisconnectPenaltyPerMinute = 200, -- fine for disconnecting with time still left on a sentence
}

if CLIENT then

	net.Receive("pdcity_law_settings_sync", function()
		local data = util.JSONToTable(net.ReadString() or "")
		if not istable(data) then return end

		if istable(data.Laws) then PDCity.LAWS = data.Laws end
		if istable(data.Rewards) then PDCity.LAW_REWARDS = data.Rewards end
		hook.Run("PDCity_SiteContentUpdated")
	end)

end
