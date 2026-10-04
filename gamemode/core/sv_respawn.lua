--[[---------------------------------------------------------
	Respawn delays: 20s when another player killed you, 5s for
	everything else (falls, suicide, world). The engine asks
	PlayerDeathThink every tick while you're dead - returning false
	blocks respawning, so the timer is enforced server-side no matter
	how hard the client clicks; once it expires we stop interfering
	and the default press-to-respawn takes over. Done with hook.Add
	rather than defining GM:PlayerDeathThink for the usual reason
	(see cl_scoreboard.lua): a hook returning a value always beats the
	table.Inherit'd base version regardless of load order.

	PvP deaths also raise a paramedic signal:
	  hook.Run("PDCity_ParamedicSignal", victim, pos, attacker)
	Nothing consumes it yet - it's the hook a future paramedic job's
	systems (beacon HUD, revive mechanics) should listen for. Until
	then, any player on a job whose name contains "Paramedic" gets a
	chat ping with the rough location, so the job starts working the
	moment it's added through the F4 job editor, with no change here.
-----------------------------------------------------------]]

local RESPAWN_DELAY_PVP = 5
local RESPAWN_DELAY_OTHER = 5

hook.Add("PlayerDeath", "pdcity_RespawnDelay", function(victim, inflictor, attacker)

	local pvp = IsValid(attacker) and attacker:IsPlayer() and attacker ~= victim
	local delay = pvp and RESPAWN_DELAY_PVP or RESPAWN_DELAY_OTHER

	victim:SetNWFloat("PDCity_RespawnAt", CurTime() + delay)

	if not pvp then return end

	hook.Run("PDCity_ParamedicSignal", victim, victim:GetPos(), attacker)

	for _, p in ipairs(player.GetAll()) do
		local job = PDCity.GetJob(p:Team())
		if job and string.find(job.Name, "Paramedic", 1, true) and p ~= victim then
			p:ChatPrint("[" .. PDCity.BRAND_TAG .. "] MEDICAL ALERT: " .. PDCity.GetDisplayName(victim) .. " is down!")
		end
	end

end)

hook.Add("PlayerDeathThink", "pdcity_RespawnDelay", function(ply)
	if CurTime() < ply:GetNWFloat("PDCity_RespawnAt", 0) then
		return false
	end
	-- Timer's up: return nothing, default press-to-respawn resumes.
end)
