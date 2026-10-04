--[[---------------------------------------------------------
	"!welcome"/"!motd" (server triggers via the "pdcity_welcome" net
	message, core/sv_content.lua) - used to open its OWN small popup with
	the 3 onboarding step cards. That content now lives in the F1
	dashboard's own Welcome tab (cl_f1_menu.lua's CreateWelcomePanel), so
	this just opens THAT instead of keeping a second copy of the same
	cards around - one screen, not two saying almost the same thing.
-----------------------------------------------------------]]

local function OpenWelcome()
	PDCity.OpenF1Menu("Welcome")
end

net.Receive("pdcity_welcome", OpenWelcome)

concommand.Add("pdcity_welcome", OpenWelcome)
