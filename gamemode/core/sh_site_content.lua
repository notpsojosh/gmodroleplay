--[[---------------------------------------------------------
	Owner-editable public-facing content: the Workshop collection link,
	the three welcome-screen boxes (cl_welcome.lua), and the F1 menu's
	"Welcome" tab news feed (cl_f1_menu.lua). All three used to be
	hardcoded text in those files; this is just the shared data shape +
	defaults. The server (core/sv_site_content.lua) persists the real
	values and syncs them down; the F1 "Site Admin" panel
	(cl_site_admin.lua) is how they get edited in-game, no code edits or
	restarts needed.
-----------------------------------------------------------]]

PDCity.SITE_CONTENT = PDCity.SITE_CONTENT or {
	WorkshopURL = "https://steamcommunity.com/sharedfiles/filedetails/?id=REPLACE_WITH_YOUR_COLLECTION_ID",

	-- Exactly 3 welcome-screen boxes (cl_welcome.lua) - what each one
	-- DOES when clicked (open the workshop link / open F4 / open F1)
	-- stays fixed, only what they say/show is editable. Image is a
	-- material path (e.g. "pdcity/somebanner"), blank = none.
	WelcomeSteps = {
		{ Title = "Get the content", Body = "One workshop collection has every model this server uses. Grab it now or things WILL look broken.", Button = "OPEN COLLECTION", Image = "" },
		{ Title = "Pick a job", Body = "Press F4 to choose who you are: citizen, cop, or something less legal. Jobs level up as you play.", Button = "OPEN JOBS (F4)", Image = "" },
		{ Title = "Learn the ropes", Body = "F1 has everything else: controls, laws, your keybinds and your job levels. Come back to it any time.", Button = "OPEN GUIDE (F1)", Image = "" },
	},

	-- News/update posts shown on the F1 menu's "Welcome" tab, in list
	-- order (newest expected first, but ordering is just whatever the
	-- admin arranges via the panel). Empty until the owner writes one.
	BlogPosts = {},
}

function PDCity.GetWelcomeStep(index)
	return PDCity.SITE_CONTENT.WelcomeSteps[index] or { Title = "", Body = "", Button = "", Image = "" }
end

if CLIENT then

	-- core/sv_site_content.lua sends this on join and after every admin
	-- edit - the cl_welcome.lua/cl_f1_menu.lua panels that display any of
	-- this just read PDCity.SITE_CONTENT directly and rebuild themselves
	-- via the hook below rather than caching their own copy.
	net.Receive("pdcity_site_sync", function()
		local data = util.JSONToTable(net.ReadString() or "")
		if not istable(data) then return end

		PDCity.SITE_CONTENT = data
		hook.Run("PDCity_SiteContentUpdated")
	end)

end
