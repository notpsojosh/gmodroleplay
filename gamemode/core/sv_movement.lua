-- Realistic movement speeds for PD City

local WALK_SPEED = 120 -- 100 * 1.2 (20% faster)
local RUN_SPEED = 240 -- 209 * 1.15 (15% faster)
local CROUCH_SPEED_FRACTION = 0.35
local JUMP_POWER = 190

local function ApplyMovementSpeeds(ply)
    ply:SetWalkSpeed(WALK_SPEED)
    ply:SetRunSpeed(RUN_SPEED)
    ply:SetCrouchedWalkSpeed(CROUCH_SPEED_FRACTION)
    ply:SetJumpPower(JUMP_POWER)
end

hook.Add("PlayerSpawn", "pdcity_MovementSpeeds", ApplyMovementSpeeds)
hook.Add("PlayerInitialSpawn", "pdcity_MovementSpeeds", ApplyMovementSpeeds)

-- Make players heavy in physics terms so props colliding with them (or
-- players leaning/pushing against props) barely move them. The player's
-- physics shadow isn't ready the instant PlayerSpawn fires, hence the delay.
local PLAYER_PHYS_MASS = 50000

local function FixPlayerPhysMass(ply)
    timer.Simple(0, function()
        if not IsValid(ply) then return end
        local phys = ply:GetPhysicsObject()
        if IsValid(phys) then
            phys:SetMass(PLAYER_PHYS_MASS)
        end
    end)
end

hook.Add("PlayerSpawn", "pdcity_HeavyPlayerPhys", FixPlayerPhysMass)
hook.Add("PlayerInitialSpawn", "pdcity_HeavyPlayerPhys", FixPlayerPhysMass)
