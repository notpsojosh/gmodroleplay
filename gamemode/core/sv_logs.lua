--[[---------------------------------------------------------
	Per-player admin logs, written alongside each player's profile:
	  data/pdcity/players/<steamid64>/logs/<category>.txt

	Categories:
	  damage.txt  - PvP damage dealt AND received, kills and deaths
	  props.txt   - prop spawns
	  tools.txt   - every tool use, with extra detail for the Precision
	                tool (push/pull + move data) and AdvDupe2 pastes
	                (entity count + unfreeze-after-paste setting)

	Every line is timestamped; other players are always identified as
	"RP name (STEAM_0:...)" so an admin can search either.

	Buffered in memory per player/category and flushed periodically
	(same pattern as core/sv_gamelog.lua) rather than a disk write on
	every single call - "props" logs via PlayerSpawnedProp, which fires
	once per prop, so an un-buffered version of this made every single
	entity in a big AdvDupe2 paste do its own synchronous file write,
	which was real, measurable lag on top of however long the paste
	itself takes.
-----------------------------------------------------------]]

local FLUSH_INTERVAL = 60
local FLUSH_AT_LINES = 200

-- [steamid64][category] = { line, line, ... }
local Buffers = {}

local function FlushOne(steamid64, category, lines)
	if #lines == 0 then return end

	local dir = PDCity.PlayerDataDir(steamid64) .. "/logs"
	file.CreateDir(dir)
	file.Append(dir .. "/" .. category .. ".txt", table.concat(lines))
end

local function FlushAll()
	for steamid64, categories in pairs(Buffers) do
		for category, lines in pairs(categories) do
			FlushOne(steamid64, category, lines)
			categories[category] = {}
		end
	end
end

timer.Create("pdcity_playerlog_flush", FLUSH_INTERVAL, 0, FlushAll)
hook.Add("ShutDown", "pdcity_playerlog_flush", FlushAll)

-- So an admin checking a player's logs right after they leave isn't
-- looking at data up to a minute stale.
hook.Add("PlayerDisconnected", "pdcity_playerlog_flush_on_leave", function(ply)
	local steamid64 = ply:SteamID64()
	local categories = Buffers[steamid64]
	if not categories then return end

	for category, lines in pairs(categories) do
		FlushOne(steamid64, category, lines)
	end
	Buffers[steamid64] = nil
end)

function PDCity.Log(ply, category, text)
	if not IsValid(ply) or ply:IsBot() then return end

	local steamid64 = ply:SteamID64()
	Buffers[steamid64] = Buffers[steamid64] or {}

	local buf = Buffers[steamid64][category]
	if not buf then
		buf = {}
		Buffers[steamid64][category] = buf
	end

	buf[#buf + 1] = "[" .. os.date("%Y-%m-%d %H:%M:%S") .. "] " .. text .. "\n"

	if #buf >= FLUSH_AT_LINES then
		FlushOne(steamid64, category, buf)
		Buffers[steamid64][category] = {}
	end
end

-- "RP name (STEAM_0:1:...)". Nick() is the RP-facing name; today that's
-- the Steam name, and it picks up a proper RP-name system automatically
-- if one is added later.
local function Describe(ply)
	if not IsValid(ply) or not ply:IsPlayer() then return "<unknown>" end
	return ply:Nick() .. " (" .. ply:SteamID() .. ")"
end

--[[---------------------------------------------------------
	Damage and kills
-----------------------------------------------------------]]

hook.Add("PlayerHurt", "pdcity_LogDamage", function(victim, attacker, healthLeft, damageTaken)

	if not IsValid(attacker) or not attacker:IsPlayer() then return end

	if attacker == victim then
		PDCity.Log(victim, "damage", "Hurt themselves for " .. damageTaken .. " damage (" .. healthLeft .. " HP left)")
		return
	end

	PDCity.Log(attacker, "damage", "Dealt " .. damageTaken .. " damage to " .. Describe(victim) .. " (" .. healthLeft .. " HP left)")
	PDCity.Log(victim, "damage", "Took " .. damageTaken .. " damage from " .. Describe(attacker) .. " (" .. healthLeft .. " HP left)")

end)

hook.Add("PlayerDeath", "pdcity_LogDeath", function(victim, inflictor, attacker)

	if IsValid(attacker) and attacker:IsPlayer() and attacker ~= victim then
		local weapon = IsValid(inflictor) and inflictor:GetClass() or "unknown"
		PDCity.Log(attacker, "damage", "KILLED " .. Describe(victim) .. " (with " .. weapon .. ")")
		PDCity.Log(victim, "damage", "DIED to " .. Describe(attacker) .. " (with " .. weapon .. ")")
	else
		local cause = (IsValid(attacker) and attacker == victim) and "suicide"
			or (IsValid(inflictor) and inflictor:GetClass() or "world")
		PDCity.Log(victim, "damage", "DIED (" .. cause .. ")")
	end

end)

--[[---------------------------------------------------------
	Prop spawns. GM:PlayerSpawnedProp lives in core/sv_spawn_defaults.lua;
	this hook rides alongside it.
-----------------------------------------------------------]]

hook.Add("PlayerSpawnedProp", "pdcity_LogProp", function(ply, model, ent)
	PDCity.Log(ply, "props", "Spawned prop " .. model .. " at " .. tostring(ent:GetPos()))
end)

--[[---------------------------------------------------------
	Tool use. Wraps GM:CanTool (server copy only) so a line is written
	whenever a tool click is actually allowed through - anything denied
	by the gamemode never happened, so it isn't logged.
-----------------------------------------------------------]]

local BUTTON_NAMES = {
	[1] = "left-click",
	[2] = "right-click",
	[3] = "reload",
}

-- The toolgun can ask CanTool more than once for a single click, so
-- identical entries within a short window are collapsed into one line.
local lastToolLog = {}

local function DescribeTarget(tr)
	local ent = tr.Entity
	if not IsValid(ent) then return "world" end
	local desc = ent:GetClass()
	if ent:GetModel() then desc = desc .. " [" .. ent:GetModel() .. "]" end
	if ent:IsPlayer() then desc = "player " .. Describe(ent) end
	return desc
end

-- Extra per-tool detail. Precision: mode plus its push/pull (nudge) and
-- move (offset) settings, read from the player's own tool convars.
local function ToolDetail(ply, mode)
	if mode ~= "precision" then return "" end

	local pmode = ply:GetInfoNum("precision_mode", 0)
	local modeName = (pmode == 3 and "Move") or (pmode == 4 and "Weld") or ("mode " .. pmode)

	return string.format(" [Precision: %s | push/pull nudge=%s (percent=%s) | move offset=%s (percent=%s) | rotation=%s]",
		modeName,
		ply:GetInfo("precision_nudge"),
		ply:GetInfo("precision_nudgepercent"),
		ply:GetInfo("precision_offset"),
		ply:GetInfo("precision_offsetpercent"),
		ply:GetInfo("precision_rotation"))
end

local origCanTool = GM.CanTool

function GM:CanTool(ply, tr, mode, tool, button)

	local allowed = origCanTool(self, ply, tr, mode, tool, button)

	if allowed ~= false and IsValid(ply) then

		local key = ply:SteamID64() .. "|" .. tostring(mode) .. "|" .. tostring(button)
		if (lastToolLog[key] or 0) + 0.2 < CurTime() then
			lastToolLog[key] = CurTime()
			local buttonName = BUTTON_NAMES[button] or tostring(button)
			PDCity.Log(ply, "tools",
				"Used tool '" .. tostring(mode) .. "' (" .. buttonName .. ") on " .. DescribeTarget(tr) .. ToolDetail(ply, mode))
		end

	end

	return allowed

end

--[[---------------------------------------------------------
	AdvDupe2 paste results: how many entities were created and whether
	the "unfreeze all after paste" checkbox was on. AdvDupe2 fires
	AdvDupe_FinishPasting with hook.Call(name, nil, ...), so this runs
	regardless of any GM function existing.
-----------------------------------------------------------]]

hook.Add("AdvDupe_FinishPasting", "pdcity_LogAdvDupe", function(pasteData)

	local info = pasteData and pasteData[1]
	if not info then return end

	local ply = info.Player
	if not IsValid(ply) then return end

	local count = table.Count(info.CreatedEntities or {})
	local unfreeze = tobool(ply:GetInfo("advdupe2_paste_unfreeze"))

	PDCity.Log(ply, "tools",
		"AdvDupe2 pasted " .. count .. " entities (unfreeze all after paste: " .. (unfreeze and "YES" or "no") .. ")")

end)
