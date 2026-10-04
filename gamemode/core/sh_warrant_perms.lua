--[[---------------------------------------------------------
	Who can approve/deny warrant requests (core/sv_wanted.lua) - used to
	be hardcoded to "Government, class level 5+". Now a configurable set
	of rules, any ONE of which is enough to qualify, editable via the F1
	Site Admin panel's "Warrant Approvers" tab (cl_site_admin.lua):

	  Groups      - ULX usergroup names (e.g. "admin") - anyone in one of
	                these groups qualifies regardless of job.
	  Jobs        - specific job IDs - anyone currently on one of these
	                jobs qualifies regardless of level.
	  ClassLevels - [job Section name] = minimum level - anyone whose
	                CURRENT job is in that class at or above that level
	                qualifies (this is what "Government level 5+" used to
	                be, just no longer fixed to one class/level pair).

	Owner/superadmin can always approve regardless of these rules, same
	as every other high-trust bypass in this codebase.

	Starts with no rules - only the owner and superadmins can approve
	until the owner adds some in Site Admin.
-----------------------------------------------------------]]

PDCity.WARRANT_PERMS = PDCity.WARRANT_PERMS or {
	Groups = {},
	Jobs = {},
	ClassLevels = {},
}

if CLIENT then

	net.Receive("pdcity_warrant_perms_sync", function()
		local data = util.JSONToTable(net.ReadString() or "")
		if not istable(data) then return end

		PDCity.WARRANT_PERMS = data
		hook.Run("PDCity_SiteContentUpdated")
	end)

end
