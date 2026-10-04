--[[---------------------------------------------------------
	Realistic fall damage.

	The engine doesn't call GetFallDamage at all below roughly 600
	units/s of impact speed - ordinary jumps, stairs, and short drops
	never reach that, so they stay damage-free automatically.

	Above that, damage ramps quickly: a moderate fall barely hurts,
	but a genuinely big drop (roughly a 5-story building) is fatal.
-----------------------------------------------------------]]

local SAFE_SPEED = 600 -- below this, no damage (matches the engine's own cutoff)
local LETHAL_SPEED = 850 -- roughly a 5-story drop - should kill outright

function GM:GetFallDamage(ply, speed)

	if (speed <= SAFE_SPEED) then return 0 end
	if (speed >= LETHAL_SPEED) then return 150 end -- comfortably lethal even with bonus health/armor

	local frac = (speed - SAFE_SPEED) / (LETHAL_SPEED - SAFE_SPEED)
	return frac * 100

end
