--[[---------------------------------------------------------
	Car radio - a hotkey-opened list of streaming radio stations a
	player can play through whichever vehicle they're currently in.
	Audible in 3D from the vehicle itself, not just to the driver, so
	nearby players hear it too.

	The station list is owner/staff-manageable in-game (core/sv_radio.lua's
	admin actions, added from the same menu everyone picks a station
	from) rather than a config file to hand-edit - "the ability for
	admins to add radio stations themselves via link" was the whole
	point of the original version this replaces.
-----------------------------------------------------------]]

PDCity.RADIO_STATIONS = PDCity.RADIO_STATIONS or {}

function PDCity.GetRadioStation(id)
	for _, station in ipairs(PDCity.RADIO_STATIONS) do
		if station.ID == id then return station end
	end
end
