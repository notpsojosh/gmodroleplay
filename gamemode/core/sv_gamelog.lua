--[[---------------------------------------------------------
	Server-wide category logs (distinct from core/sv_logs.lua, which
	keeps per-player files for admin review of ONE person - this is the
	whole server's activity, one file per category per day).

	On disk:  data/pdcity/gamelogs/<YYYY-MM-DD>/<category>.txt
	so every day is automatically its own dated folder, and every file
	is plain timestamped text - copy the folder out and it's already
	"exported". Lines are buffered in memory and flushed to disk every
	FLUSH_INTERVAL seconds (and on server shutdown), so logging costs
	almost nothing per event.

	Categories: connections, chat, damage, kills, spawns, toolgun,
	money, jobs, arrests, lockpicks, printers, xp, staff, purchases,
	names, doors, inventory, wanted.

	"lockpicks" is written directly by entities/weapons/weapon_pdcity_lockpick.lua
	(bare PDCity.GameLog calls), not through the Wrap() block below -
	same reasoning as chat's own note just below. ("vehicles" used to be
	listed here too - removed along with the whole vehicle system, see
	init.lua's own comment on that removal.)

	Two ways events get in:
	  1. plain hooks (damage, chat, connects, spawns...)
	  2. wrappers around PDCity_* functions (money, jobs, arrests...)
	     - which is why init.lua includes this file LAST: everything it
	     wraps must already exist.

	Export: "pdcity_exportlogs [YYYY-MM-DD]" (server console or owner)
	combines that day's categories into a single file under
	data/pdcity/gamelogs/exports/ and prints the path. No date = today.

	Anything can add its own lines: PDCity.GameLog("category", "text").
-----------------------------------------------------------]]

local BASE_DIR = "pdcity/gamelogs"
local FLUSH_INTERVAL = 120
local FLUSH_AT_LINES = 200 -- also flush early if one category piles up

local Buffers = {}

local function Flush()
	local dir = BASE_DIR .. "/" .. os.date("%Y-%m-%d")

	for category, lines in pairs(Buffers) do
		if #lines > 0 then
			file.CreateDir(dir)
			file.Append(dir .. "/" .. category .. ".txt", table.concat(lines))
			Buffers[category] = {}
		end
	end
end

function PDCity.GameLog(category, text)
	local buf = Buffers[category]
	if not buf then
		buf = {}
		Buffers[category] = buf
	end

	buf[#buf + 1] = "[" .. os.date("%Y-%m-%d %H:%M:%S") .. "] " .. text .. "\n"

	if #buf >= FLUSH_AT_LINES then Flush() end
end

timer.Create("pdcity_gamelog_flush", FLUSH_INTERVAL, 0, Flush)
hook.Add("ShutDown", "pdcity_gamelog_flush", Flush)

local function D(ply)
	if not IsValid(ply) or not ply:IsPlayer() then return "<unknown>" end
	return ply:Nick() .. " (" .. ply:SteamID() .. ")"
end

--[[---------------------------------------------------------
	Generic hooks: connections, chat, damage, kills, spawns
-----------------------------------------------------------]]

hook.Add("PlayerConnect", "pdcity_gamelog", function(name, ip)
	PDCity.GameLog("connections", "CONNECTING: " .. name .. " from " .. tostring(ip))
end)

hook.Add("PlayerInitialSpawn", "pdcity_gamelog", function(ply)
	PDCity.GameLog("connections", "JOINED: " .. D(ply))
end)

hook.Add("PlayerDisconnected", "pdcity_gamelog", function(ply)
	PDCity.GameLog("connections", "LEFT: " .. D(ply))
end)

-- Chat is NOT logged here: core/sv_chat.lua routes every message
-- (local/team/OOC/PM/advert/darkweb) and writes each to its own
-- category itself - a generic PlayerSay logger alongside it would
-- double-log some lines and miss consumed ones depending on hook
-- order.

hook.Add("PlayerHurt", "pdcity_gamelog", function(victim, attacker, healthLeft, dmg)
	if not IsValid(attacker) or not attacker:IsPlayer() or attacker == victim then return end
	PDCity.GameLog("damage", D(attacker) .. " dealt " .. dmg .. " to " .. D(victim) .. " (" .. healthLeft .. " HP left)")
end)

hook.Add("PlayerDeath", "pdcity_gamelog", function(victim, inflictor, attacker)
	if IsValid(attacker) and attacker:IsPlayer() and attacker ~= victim then
		local weapon = IsValid(inflictor) and inflictor:GetClass() or "unknown"
		PDCity.GameLog("kills", D(attacker) .. " killed " .. D(victim) .. " with " .. weapon)
	else
		local cause = (IsValid(attacker) and attacker == victim) and "suicide"
			or (IsValid(inflictor) and inflictor:GetClass() or "world")
		PDCity.GameLog("kills", D(victim) .. " died (" .. cause .. ")")
	end
end)

--[[---------------------------------------------------------
	Spawns - every sandbox spawn type
-----------------------------------------------------------]]

local SPAWN_HOOKS = {
	PlayerSpawnedProp = "prop",
	PlayerSpawnedNPC = "NPC",
	PlayerSpawnedRagdoll = "ragdoll",
	PlayerSpawnedSENT = "entity",
	PlayerSpawnedSWEP = "weapon",
	PlayerSpawnedEffect = "effect",
}

for hookName, label in pairs(SPAWN_HOOKS) do
	hook.Add(hookName, "pdcity_gamelog", function(ply, a, b)
		-- Prop/ragdoll/effect hooks pass (model, ent); NPC/SENT/SWEP/
		-- vehicle pass just (ent). Describe whichever we got.
		local ent = IsValid(b) and b or a
		local desc = isstring(a) and a or (IsValid(ent) and ent:GetClass() or "?")
		PDCity.GameLog("spawns", D(ply) .. " spawned " .. label .. " " .. tostring(desc))
	end)
end

--[[---------------------------------------------------------
	Toolgun - chains onto GM.CanTool AFTER core/sv_logs.lua's own
	wrapper (this file loads last), with the same short collapse window
	since one click can ask CanTool several times.
-----------------------------------------------------------]]

local lastTool = {}
local prevCanTool = GM.CanTool

function GM:CanTool(ply, tr, mode, tool, button)
	local allowed = prevCanTool(self, ply, tr, mode, tool, button)

	if allowed ~= false and IsValid(ply) then
		local key = ply:SteamID64() .. "|" .. tostring(mode)
		if (lastTool[key] or 0) + 0.2 < CurTime() then
			lastTool[key] = CurTime()
			local target = IsValid(tr.Entity) and tr.Entity:GetClass() or "world"
			PDCity.GameLog("toolgun", D(ply) .. " used '" .. tostring(mode) .. "' on " .. target)
		end
	end

	return allowed
end

--[[---------------------------------------------------------
	PD City systems, via wrappers. Each is guarded so a renamed or
	removed function just skips its logging instead of erroring the
	whole file on boot.
-----------------------------------------------------------]]

-- name is a key in the PDCity table, e.g. "AddMoney" for PDCity.AddMoney.
local function Wrap(name, logFn)
	local orig = PDCity[name]
	if not isfunction(orig) then
		ErrorNoHalt("[" .. PDCity.BRAND_TAG .. "] gamelog: no function 'PDCity." .. name .. "' to wrap - that category won't log.\n")
		return
	end

	PDCity[name] = function(...)
		local results = { orig(...) }
		logFn(results, ...)
		return unpack(results)
	end
end

-- Money: every balance change, positive or negative (purchases show
-- up as their deduction lines).
Wrap("AddMoney", function(results, ply, amount)
	if results[1] == false or not isnumber(amount) or amount == 0 then return end
	local verb = amount > 0 and ("gained $" .. amount) or ("spent $" .. -amount)
	PDCity.GameLog("money", D(ply) .. " " .. verb)
end)

Wrap("ApplyJob", function(results, ply, jobID)
	if results[1] ~= true then return end
	local job = PDCity.GetJob(jobID)
	PDCity.GameLog("jobs", D(ply) .. " became " .. (job and job.Name or ("job " .. tostring(jobID))))
end)

Wrap("CuffPlayer", function(results, target, officer)
	PDCity.GameLog("arrests", D(officer) .. " cuffed " .. D(target))
end)

Wrap("UncuffPlayer", function(results, target)
	PDCity.GameLog("arrests", D(target) .. " was uncuffed")
end)

Wrap("JailPlayer", function(results, target, minutes, law, officer)
	PDCity.GameLog("arrests", D(officer) .. " jailed " .. D(target) .. " for " .. tostring(minutes) .. " min (" .. tostring(law) .. ")")
end)

Wrap("ReleaseFromJail", function(results, ply)
	PDCity.GameLog("arrests", D(ply) .. " released from jail")
end)

Wrap("GrantPrinterStealAccess", function(results, ply, ent)
	if not IsValid(ent) then return end
	PDCity.GameLog("printers", D(ply) .. " lockpicked " .. ent.PrintName .. " owned by " .. D(ent.pdcity_Owner))
end)

Wrap("GrantPrinterDestroyXP", function(results, attacker, owner)
	PDCity.GameLog("printers", D(attacker) .. " destroyed a printer owned by " .. D(owner))
end)

Wrap("AddJobXP", function(results, ply, class, amount)
	if not isnumber(amount) or amount <= 0 then return end
	PDCity.GameLog("xp", D(ply) .. " earned " .. amount .. " " .. tostring(class) .. " XP")
end)

-- Staff invisibility toggle (!hide/!unhide, core/sv_staff_commands.lua).
Wrap("SetPlayerHidden", function(results, ply, hidden)
	PDCity.GameLog("staff", D(ply) .. (hidden and " went hidden (!hide)" or " became visible again (!unhide)"))
end)

-- Self-service RP name changes (core/sv_rpname.lua, F1 Character
-- Selection's "Rename" - the old /name chat command this used to wrap,
-- PDCity_TrySetRPNameSelf, is gone) - the forced/unforced admin path
-- logs itself directly, right where the admin and target are both
-- already in scope (see that file). A rename always requires a real
-- name now (no "clear" case - see that function's own header), so unlike
-- the old wrapper there's no blank-name branch to log differently.
Wrap("TryRenameCharacterSlot", function(results, ply, slot, newName)
	if results[1] ~= true then return end
	local shown = results[2]
	PDCity.GameLog("names", D(ply) .. " renamed character " .. tostring(slot) .. " to \"" .. shown .. "\"")
end)

--[[---------------------------------------------------------
	Log viewer (cl_logviewer.lua) - staff only. The client only ever
	asks; every reply is gated on PDCity.IsStaff here, so a non-staff
	client sending these messages by hand gets silence.

	Content is sent as the file's TAIL, compressed - a whole day of
	chat can outgrow the 64KB net-message ceiling, and for a viewer
	the most recent lines are what matters. Full files stay on disk.
-----------------------------------------------------------]]

util.AddNetworkString("pdcity_logs_list")
util.AddNetworkString("pdcity_logs_listing")
util.AddNetworkString("pdcity_logs_read")
util.AddNetworkString("pdcity_logs_content")

local MAX_RAW_TAIL = 200000
local MAX_WIRE = 55000 -- compressed budget, safely under the 64KB net cap

local function DatedDirs()
	local _, dirs = file.Find(BASE_DIR .. "/*", "DATA")
	local out = {}
	for _, d in ipairs(dirs or {}) do
		if d ~= "exports" then out[#out + 1] = d end
	end
	table.sort(out, function(a, b) return a > b end) -- newest first
	return out
end

function PDCity.SendLogListing(ply, date)
	if not IsValid(ply) or not PDCity.IsStaff(ply) then return end

	Flush() -- so what the viewer lists/reads is up to the second

	local dates = DatedDirs()
	if date == "" or not table.HasValue(dates, date) then
		date = dates[1] or os.date("%Y-%m-%d")
	end

	local cats = {}
	for _, f in ipairs(file.Find(BASE_DIR .. "/" .. date .. "/*.txt", "DATA") or {}) do
		cats[#cats + 1] = f:gsub("%.txt$", "")
	end
	table.sort(cats)

	net.Start("pdcity_logs_listing")
		net.WriteString(util.TableToJSON(dates))
		net.WriteString(util.TableToJSON(cats))
		net.WriteString(date)
	net.Send(ply)
end

net.Receive("pdcity_logs_list", function(len, ply)
	PDCity.SendLogListing(ply, net.ReadString() or "")
end)

net.Receive("pdcity_logs_read", function(len, ply)
	if not IsValid(ply) or not PDCity.IsStaff(ply) then return end

	local date = net.ReadString() or ""
	local category = net.ReadString() or ""

	-- The category came from our own listing, but never trust it as a
	-- path fragment - strip anything that could walk the filesystem.
	date = date:gsub("[^%d%-]", "")
	category = category:gsub("[^%w_%-]", "")

	Flush()

	local raw = file.Read(BASE_DIR .. "/" .. date .. "/" .. category .. ".txt", "DATA") or "(no entries)"

	if #raw > MAX_RAW_TAIL then
		raw = raw:sub(-MAX_RAW_TAIL)
		raw = "(older lines truncated - full file on disk)\n" .. (raw:match("\n(.*)$") or raw)
	end

	local compressed = util.Compress(raw)

	-- Pathological worst case (incompressible data): keep halving the
	-- tail until it fits the wire budget.
	while #compressed > MAX_WIRE and #raw > 1000 do
		raw = raw:sub(-math.floor(#raw / 2))
		compressed = util.Compress(raw)
	end

	net.Start("pdcity_logs_content")
		net.WriteString(date)
		net.WriteString(category)
		net.WriteUInt(#compressed, 32)
		net.WriteData(compressed, #compressed)
	net.Send(ply)
end)

--[[---------------------------------------------------------
	Search by player: every category for one date, filtered down to
	lines mentioning a name or SteamID. Every log line is written via
	the shared D(ply) helper ("Nick (STEAM_0:...)"), so a substring
	match against either reliably catches every line that player is
	in, across every category, without needing per-category special
	casing.

	Filtering happens here (server-side, on the FULL file) rather than
	sending whole-category tails to the client and filtering there -
	pdcity_logs_read's tail cap means a match earlier in a big file
	could otherwise be missed entirely; a search should search the
	whole day, not just "whatever fit in the last 200KB".
-----------------------------------------------------------]]

util.AddNetworkString("pdcity_logs_searchplayer")
util.AddNetworkString("pdcity_logs_searchresults")

net.Receive("pdcity_logs_searchplayer", function(len, ply)
	if not IsValid(ply) or not PDCity.IsStaff(ply) then return end

	local date = net.ReadString() or ""
	local query = string.lower(string.Trim(net.ReadString() or ""))

	if query == "" then return end

	Flush()

	local dir = BASE_DIR .. "/" .. date
	local matches = {}

	for _, fname in ipairs(file.Find(dir .. "/*.txt", "DATA") or {}) do
		local category = fname:gsub("%.txt$", "")
		local raw = file.Read(dir .. "/" .. fname, "DATA") or ""

		for line in raw:gmatch("[^\n]+") do
			if string.find(string.lower(line), query, 1, true) then
				matches[#matches + 1] = "[" .. category .. "] " .. line
			end
		end
	end

	local text = table.concat(matches, "\n")
	if text == "" then
		text = "No lines mention \"" .. query .. "\" in any category on " .. date .. "."
	elseif #text > MAX_RAW_TAIL then
		text = "(too many matches - showing the most recent; narrow your search)\n" .. text:sub(-MAX_RAW_TAIL)
	end

	local compressed = util.Compress(text)
	while #compressed > MAX_WIRE and #text > 1000 do
		text = text:sub(-math.floor(#text / 2))
		compressed = util.Compress(text)
	end

	net.Start("pdcity_logs_searchresults")
		net.WriteString(date)
		net.WriteString(query)
		net.WriteUInt(#compressed, 32)
		net.WriteData(compressed, #compressed)
	net.Send(ply)
end)

--[[---------------------------------------------------------
	Export: combine one day's categories into a single file.
-----------------------------------------------------------]]

concommand.Add("pdcity_exportlogs", function(ply, cmd, args)

	if IsValid(ply) and not PDCity.IsOwner(ply) then
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Owner only.")
		return
	end

	Flush() -- so the export always includes up-to-the-second lines

	local date = args[1] or os.date("%Y-%m-%d")
	local dir = BASE_DIR .. "/" .. date

	local files = file.Find(dir .. "/*.txt", "DATA")
	if not files or #files == 0 then
		local msg = "[" .. PDCity.BRAND_TAG .. "] No logs found for " .. date .. "."
		if IsValid(ply) then ply:ChatPrint(msg) else print(msg) end
		return
	end

	local out = { PDCity.BRAND_NAME .. " log export - " .. date .. " (generated " .. os.date("%Y-%m-%d %H:%M:%S") .. ")\n\n" }
	for _, fname in ipairs(files) do
		out[#out + 1] = "===== " .. fname:gsub("%.txt$", ""):upper() .. " =====\n"
		out[#out + 1] = file.Read(dir .. "/" .. fname, "DATA") or ""
		out[#out + 1] = "\n"
	end

	file.CreateDir(BASE_DIR .. "/exports")
	local outName = BASE_DIR .. "/exports/export_" .. date .. "_" .. os.date("%H%M%S") .. ".txt"
	file.Write(outName, table.concat(out))

	local msg = "[" .. PDCity.BRAND_TAG .. "] Exported to garrysmod/data/" .. outName
	if IsValid(ply) then ply:ChatPrint(msg) else print(msg) end

end)
