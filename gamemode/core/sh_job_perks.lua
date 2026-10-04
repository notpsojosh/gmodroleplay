--[[---------------------------------------------------------
	Per-class perks unlocked at a given level.

	Deliberately empty for now - what a class actually gets at each
	level hasn't been decided yet, same as what earns XP in the first
	place (see core/sv_job_xp.lua). Add entries here once that's
	settled, e.g.:

		PDCity.JOB_CLASS_PERKS["Police"] = {
			[5]  = "Access to the armoury",
			[10] = "Can requisition a cruiser",
		}

	Keyed by SECTION name (the "job class" - see core/sh_job_xp.lua),
	not by individual job ID, so every rank sharing a section shares
	one perk track and nobody loses progress by getting promoted.
-----------------------------------------------------------]]

PDCity.JOB_CLASS_PERKS = PDCity.JOB_CLASS_PERKS or {}

-- The perk text for reaching exactly this level, if any is defined.
function PDCity.GetPerkForLevel(class, level)
	local perks = PDCity.JOB_CLASS_PERKS[class]
	if not perks then return nil end
	return perks[level]
end

-- Every perk unlocked at or below the given level, in level order -
-- what the F1 "Job Levels" tab shows as "already unlocked".
function PDCity.GetUnlockedPerks(class, level)
	local perks = PDCity.JOB_CLASS_PERKS[class]
	if not perks then return {} end

	local out = {}
	for perkLevel, text in pairs(perks) do
		if perkLevel <= level then
			table.insert(out, { Level = perkLevel, Text = text })
		end
	end
	table.sort(out, function(a, b) return a.Level < b.Level end)
	return out
end

-- The next perk still to come, if any - what the tab shows as "next
-- unlock at level X".
function PDCity.GetNextPerk(class, level)
	local perks = PDCity.JOB_CLASS_PERKS[class]
	if not perks then return nil end

	local best = nil
	for perkLevel, text in pairs(perks) do
		if perkLevel > level and (not best or perkLevel < best.Level) then
			best = { Level = perkLevel, Text = text }
		end
	end
	return best
end
