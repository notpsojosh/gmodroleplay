--[[---------------------------------------------------------
	Owner-toggleable on/off switch for the whole job-class XP/levelling
	system (core/sh_xp.lua, core/sv_job_xp.lua) - editable in-game via
	the F1 Site Admin panel's "XP System" tab (cl_site_admin.lua), no
	restart needed.

	When OFF: core/sv_job_xp.lua's PDCity.AddJobXP no-ops (nothing
	accumulates), core/sv_jobs.lua's PDCity.ApplyJob skips
	job.RequiredLevel checks entirely (nothing stays locked behind a
	system that's turned off), and the F1 "Job Levels" tab / F4 job
	card level badges hide accordingly (cl_f1_menu.lua, cl_f4_menu.lua).

	See XP_SYSTEM.md (next to SETUP.md) for how to actually grant XP
	from your own activities, and how level-based rewards work - this
	file only holds the on/off switch itself.
-----------------------------------------------------------]]

if PDCity.XP_ENABLED == nil then PDCity.XP_ENABLED = true end

if CLIENT then

	-- Reuses the same "PDCity_SiteContentUpdated" hook core/sh_site_content.lua
	-- and core/sh_warrant_perms.lua fire - the F1 Site Admin panel's
	-- RefreshAllPanels already listens for that on every one of its tabs,
	-- so this setting's tab picks it up for free with no extra wiring.
	net.Receive("pdcity_xp_settings_sync", function()
		PDCity.XP_ENABLED = net.ReadBool()
		hook.Run("PDCity_SiteContentUpdated")
	end)

end
