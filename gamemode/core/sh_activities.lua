--[[---------------------------------------------------------
	Job Activities - lets staff tie a job to an existing entity class
	from the F4 admin editor's "Activities" tab (cl_f4_admin.lua), and
	names a hook that fires when a player triggers it.

	Deliberately minimal by design, not by oversight: there's no built-in
	timer, cooldown, or money/XP reward here at all - what happens on
	trigger is whatever the server's modification addon
	(addons/pdroleplay_modification) hooks onto, via
	hook.Add(activity.HookName, ...) or the generic
	hook.Add("PDCity_ActivityUsed"/"PDCity_ActivityFilled", ...)
	(core/sv_activities.lua fires both, every time). That's the whole
	point: this is the wiring, not the gameplay - a meth-cook/weed-
	grower/bus-driver style loop gets built on top of it, one hook.Add
	away, without ever touching this file or the admin UI again.

	An activity's Class is a real entity class someone already made -
	either a bespoke SENT (addons/pdroleplay_modification/entities/entities/,
	per that addon's own README) or an existing F4 shop item bought
	through the normal catalogue (core/sh_f4_catalogue.lua's Entities
	tab handles "staff can buy/sell this" already; Activities is the
	separate, orthogonal piece of "and here's what happens when someone
	interacts with it"). There's no separate placement system here -
	whatever gets the entity into the world (the F4 shop, the Q menu, a
	map spawn) is unrelated to this file.

	TriggerType decides what actually fires the hook:
	  "use"     - the player presses +use on the entity (default). Only
	              ever fires for an entity that already implements Use
	              itself - GMod's own PlayerUse hook never reaches a
	              plain physics prop with no Use behavior of its own,
	              activity or not.
	  "collide" - another entity touches it (call
	              PDCity.FireActivityCollide(self, other) from the
	              entity's own ENT:StartTouch - there's no generic engine
	              hook for touch events the way there is for Use).
	              FillClasses optionally limits which entity classes
	              count (nil/empty = anything touching it counts).

	Persisted server-side (core/sv_activities.lua) as
	data/pdcity/activities.json and synced to clients on join and
	whenever an owner changes it, same pattern as the F4/Job catalogues.

	Activity fields:
	  ID          unique integer, generated when added
	  Name        display name (admin UI only - never shown to players)
	  Class       the entity class this activity applies to (unique
	              across activities)
	  Jobs        list of job IDs allowed to trigger it (nil/empty = everyone)
	  TriggerType "use" or "collide"
	  FillClasses collide kind only: list of entity classes that count as
	              a valid fill item (nil/empty = anything touching it counts)
	  HookName    the hook.Run name fired on trigger - auto-suggested from
	              Name, editable to anything
-----------------------------------------------------------]]

PDCity.ACTIVITIES = PDCity.ACTIVITIES or {}

-- Turns a display name into a safe hook-name suggestion, e.g.
-- "Meth Cook" -> "PDCity_Activity_Meth_Cook". Purely a convenience
-- default shown in the admin form - the HookName actually stored on an
-- activity is whatever string was submitted, editable to anything.
function PDCity.SuggestActivityHookName(name)
	local slug = tostring(name or ""):gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", "")
	if slug == "" then slug = "Activity" end
	return "PDCity_Activity_" .. slug
end

function PDCity.GetActivityByID(id)
	for _, activity in ipairs(PDCity.ACTIVITIES) do
		if activity.ID == id then return activity end
	end
end

-- First activity whose Class matches, or nil. Classes are unique across
-- activities (enforced on add/edit, core/sv_activities.lua) so there's
-- never more than one match.
function PDCity.GetActivityForClass(class)
	for _, activity in ipairs(PDCity.ACTIVITIES) do
		if activity.Class == class then return activity end
	end
end
