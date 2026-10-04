--[[---------------------------------------------------------
	Level/XP math shared by every job class (see core/sh_job_xp.lua for
	what a "class" is and core/sv_job_xp.lua for actually granting XP).

	Uses the real Old School RuneScape XP formula rather than
	hand-copying the attached table - it reproduces those exact numbers
	(83, 174, 276, 388, 512, 650, 801, 969, 1154 for levels 2-10) and
	extends the same way OSRS itself does, all the way to 99, so higher
	levels never need a second table pasted in later.
-----------------------------------------------------------]]

-- Job-class level cap. core/sv_job_xp.lua's PDCity.AddJobXP already
-- clamps every grant to whatever this is, and a separate fail-safe
-- there (ClampAllJobXP) sweeps stored profiles back down to it too, for
-- anything already over the cap from before it was lowered here, or
-- from any other path that ever sets JobXP directly.
PDCity.XP_MAX_LEVEL = 10

-- Cumulative XP required to BE each level, precomputed once.
local XP_AT_LEVEL = {}
do
	local points = 0
	XP_AT_LEVEL[1] = 0
	for level = 2, PDCity.XP_MAX_LEVEL do
		points = points + math.floor((level - 1) + 300 * 2 ^ ((level - 1) / 7))
		XP_AT_LEVEL[level] = math.floor(points / 4)
	end
end

function PDCity.XPForLevel(level)
	level = math.Clamp(math.floor(level or 1), 1, PDCity.XP_MAX_LEVEL)
	return XP_AT_LEVEL[level]
end

function PDCity.LevelForXP(xp)
	xp = math.max(0, xp or 0)

	local level = 1
	for l = 2, PDCity.XP_MAX_LEVEL do
		if xp < XP_AT_LEVEL[l] then break end
		level = l
	end

	return level
end

-- level, xp into the current level, xp needed to span the current
-- level (0 at max level - there's nowhere further to go).
function PDCity.XPProgress(xp)
	local level = PDCity.LevelForXP(xp)
	local into = xp - PDCity.XPForLevel(level)
	local span = (level < PDCity.XP_MAX_LEVEL) and (PDCity.XPForLevel(level + 1) - PDCity.XPForLevel(level)) or 0
	return level, into, span
end
