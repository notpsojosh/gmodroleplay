--[[---------------------------------------------------------
	Which way round the Prop Filter tool's whitelist works
	(core/sv_restrictions.lua / entities/weapons/gmod_tool/stools/
	pdcity_propfilter.lua) - owner-toggleable via the F1 Site Admin
	panel's "Prop Filter" tab, no restart needed.

	  "whitelist" - default-DENY. Nothing spawns for anyone but the
	                owner/superadmins unless explicitly whitelisted.
	  "blacklist" - default-ALLOW. Everything spawns unless explicitly
	                blacklisted.

	Either way, the tool itself still does the same two things (left
	click blacklists, right click whitelists) - this only changes what
	a model with NO override does.
-----------------------------------------------------------]]

if PDCity.PROP_FILTER_MODE == nil then PDCity.PROP_FILTER_MODE = "whitelist" end

if CLIENT then

	net.Receive("pdcity_prop_filter_sync", function()
		PDCity.PROP_FILTER_MODE = net.ReadString()
		hook.Run("PDCity_SiteContentUpdated")
	end)

end
