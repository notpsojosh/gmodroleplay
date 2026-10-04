--[[---------------------------------------------------------
	The server rulebook shown on the F1 menu's "Rules" tab (cl_rules.lua),
	owner-editable in-game from the Site Admin panel's "Rules" tab
	(cl_site_admin.lua's BuildRulesTab), persisted and synced by
	core/sv_rules.lua.

	Starts empty. ExampleRules below is a complete example rulebook the
	owner can load from the editor ("Reset to Example Rules") as a
	starting point, then edit or rewrite.

	Shape:
	  Intro    - a paragraph above the rules, blank to hide it
	  Updated  - free text ("March 2025", "v3.1"), blank to hide it
	  Sections - ordered list of { Title, Icon, Rules = { ... } }
	  Rule     - { Title, Detail, Severity }

	Severity is one of PDCity.RULE_SEVERITIES' IDs below and only affects
	how a rule is LABELLED - nothing enforces or auto-punishes off it.
	It's there so players can see at a glance which rules end a session
	and which end an account.

	Guarded with "or" (not a bare assignment) so re-including this file -
	a fast gamemode reload during development - can't stomp whatever
	core/sv_rules.lua already loaded from disk back to these defaults.
-----------------------------------------------------------]]

PDCity.RULE_SEVERITIES = {
	{ ID = "notice",    Label = "GUIDANCE",  Color = Color(120, 175, 255) },
	{ ID = "warning",   Label = "WARNING",   Color = Color(235, 185,  70) },
	{ ID = "kick",      Label = "KICK",      Color = Color(240, 140,  60) },
	{ ID = "ban",       Label = "BAN",       Color = Color(228,  85,  85) },
	{ ID = "permanent", Label = "PERMANENT", Color = Color(196,  60, 110) },
}

-- Defaults live in a function rather than inline in the assignment below
-- so the editor's "Reset to Defaults" has something to reset TO - once
-- PDCity.RULES has been overwritten from disk, the original literal would
-- otherwise be gone for the rest of the session. Returns a fresh table
-- every call, so a reset can't hand out a reference the next edit then
-- mutates in place.
local function ExampleRules()
	return {
		Intro = "These rules apply to every character on your account, in every channel, at all times. " ..
			"Not knowing a rule is not a defence for breaking it. Staff enforce at their own discretion and " ..
			"punishments scale with intent and history - an honest mistake is treated differently to a pattern.",

		Updated = "",

		Sections = {
			{
				Title = "General Conduct",
				Icon = "icon16/shield.png",
				Rules = {
					{ Title = "Treat people like people",
					  Detail = "No harassment, slurs, or discrimination of any kind, in voice, text, or names. Losing a fight is not a reason to start on someone.",
					  Severity = "ban" },
					{ Title = "No cheating or exploiting",
					  Detail = "Scripts, macros, and third-party tools are an instant permanent ban. Map and entity exploits count too - report bugs, don't farm them.",
					  Severity = "permanent" },
					{ Title = "Keep advertising out of chat",
					  Detail = "Don't promote other servers, communities, or paid content without staff permission first.",
					  Severity = "kick" },
					{ Title = "Take disputes to a ticket",
					  Detail = "Staff decisions stand in the moment. If you think one was wrong, open a ticket and it gets reviewed properly.",
					  Severity = "warning" },
				},
			},
			{
				Title = "Roleplay Standards",
				Icon = "icon16/user.png",
				Rules = {
					{ Title = "Stay in character",
					  Detail = "Break character in-game only for an admin situation. Everything else goes in OOC chat.",
					  Severity = "warning" },
					{ Title = "No random deathmatch",
					  Detail = "You need a real in-character reason to attack someone, and they need a chance to react to it. Shooting on sight is not roleplay.",
					  Severity = "ban" },
					{ Title = "New life rule",
					  Detail = "When you die your character forgets that life entirely. Stay away from where it happened for three minutes and don't return to finish anything.",
					  Severity = "kick" },
					{ Title = "No metagaming",
					  Detail = "Anything you learn from OOC chat, Discord, or someone's stream does not exist to your character.",
					  Severity = "kick" },
					{ Title = "Value your life",
					  Detail = "With a gun to your head you comply. Pulling a weapon anyway because you know you'll respawn is not how a person behaves.",
					  Severity = "warning" },
				},
			},
			{
				Title = "Crime and Policing",
				Icon = "icon16/lock.png",
				Rules = {
					{ Title = "Raids need a motive",
					  Detail = "Have an in-character reason before you raid, announce it properly, and leave the same place alone for fifteen minutes afterwards.",
					  Severity = "warning" },
					{ Title = "Police need probable cause",
					  Detail = "Arrests, searches, and raids all need justification. Warrants exist for a reason and are not a formality.",
					  Severity = "warning" },
					{ Title = "Corrupt policing needs approval",
					  Detail = "Dirty cop storylines are allowed and encouraged, but clear them with staff first so they don't read as an officer simply breaking rules.",
					  Severity = "kick" },
					{ Title = "Spawn and safe zones are off limits",
					  Detail = "No mugging, raiding, or killing at spawn, inside the PD lobby, or at the bank entrance.",
					  Severity = "kick" },
				},
			},
			{
				Title = "Building and Props",
				Icon = "icon16/house.png",
				Rules = {
					{ Title = "No prop abuse",
					  Detail = "Prop killing, climbing, blocking, and surfing are all bannable, whether or not anyone was hurt by it.",
					  Severity = "ban" },
					{ Title = "Bases have to be raidable",
					  Detail = "One clear entrance, no invisible or no-collided props, no killboxes, and no fading door stacks.",
					  Severity = "warning" },
					{ Title = "Build things you'd be happy to raid",
					  Detail = "If you'd complain about attacking your own base, it's not a fair base.",
					  Severity = "warning" },
				},
			},
			{
				Title = "Staff and Support",
				Icon = "icon16/cog.png",
				Rules = {
					{ Title = "Open a ticket for help",
					  Detail = "Tickets get picked up in order. Shouting in OOC doesn't move you up the queue.",
					  Severity = "notice" },
					{ Title = "Bring evidence",
					  Detail = "A clip or a screenshot turns a report into a five second decision. Without one, most reports go nowhere.",
					  Severity = "notice" },
					{ Title = "Don't impersonate staff",
					  Detail = "No names, tags, or models suggesting you're a member of staff, in-game or in the Discord.",
					  Severity = "ban" },
				},
			},
		},
	}
end

-- Global so core/sv_rules.lua's "reset_defaults" action (Site Admin's
-- "Reset to Example Rules" button) can load it on request.
PDCity.ExampleRules = ExampleRules

-- Ships empty - the owner writes their own, or loads the examples above.
PDCity.RULES = PDCity.RULES or { Intro = "", Updated = "", Sections = {} }

-- Falls back to the first entry rather than nil for an unrecognised ID, so
-- a rule saved before a severity was renamed still draws a pill instead of
-- erroring out mid-Paint.
function PDCity.GetRuleSeverity(id)
	for _, sev in ipairs(PDCity.RULE_SEVERITIES) do
		if sev.ID == id then return sev end
	end
	return PDCity.RULE_SEVERITIES[1]
end

function PDCity.CountRules()
	local sections, rules = 0, 0
	for _, section in ipairs(PDCity.RULES.Sections or {}) do
		sections = sections + 1
		rules = rules + #(section.Rules or {})
	end
	return sections, rules
end

if CLIENT then

	-- core/sv_rules.lua sends this on join and after every admin edit. The
	-- F1 tab and the editor both read PDCity.RULES directly and rebuild off
	-- the hook rather than caching their own copy, same as every other
	-- synced config in this gamemode.
	net.Receive("pdcity_rules_sync", function()
		local data = util.JSONToTable(net.ReadString() or "")
		if not istable(data) then return end

		PDCity.RULES = data
		hook.Run("PDCity_RulesUpdated")
		hook.Run("PDCity_SiteContentUpdated")
	end)

end
