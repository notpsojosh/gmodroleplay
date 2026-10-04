--[[---------------------------------------------------------
	Proximity voice chat: hear whoever is physically near you, not
	your whole team from anywhere on the map - the base gamemode's own
	default (gamemodes/base/gamemode/player.lua:754) is
	"same team, non-spatial", which table.Inherit copies onto this
	gamemode's table.

	Defining our own GM:PlayerCanHearPlayersVoice only reliably wins
	over that inherited copy if this file happens to load after
	table.Inherit runs - a load-order dependency, not something to
	rely on. Using hook.Add instead sidesteps it entirely: per
	hook.lua's Call(), a hook returning a non-nil value always runs
	before the gamemode function and short-circuits it, regardless of
	load order. Same fix as cl_scoreboard.lua's ScoreboardShow/Hide.

	The actual rule lives in core/sh_voice.lua's PDCity.CanHearVoice -
	shared so cl_voice.lua's "who can hear you" list is always
	answering the exact same question the server is enforcing here,
	not a client-side guess that could drift out of sync with it.
-----------------------------------------------------------]]

hook.Add("PlayerCanHearPlayersVoice", "pdcity_ProximityVoice", function(listener, talker)
	return PDCity.CanHearVoice(listener, talker)
end)
