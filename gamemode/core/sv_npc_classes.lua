--[[---------------------------------------------------------
	Server side of the F4 admin editor's "NPCs" tab: persists owner-made
	custom NPCs (core/sh_npc_classes.lua's PDCity.CUSTOM_NPCS) to
	data/pdcity/custom_npcs.json and syncs them to clients on join and
	whenever the owner changes the list - same pattern as the F4/Job/
	Activity catalogues.

	This is the NPC DEFINITIONS only (name + model + optional code).
	WHERE any placed instance actually sits is a separate, pre-existing
	system (core/sv_npc_spawns.lua) that already works the same way for
	built-in NPCs - nothing here duplicates that.

	Code works exactly like a Job Activity's (core/sv_activities.lua's
	own Custom Code section - same compile-on-load/compile-on-set,
	pcall-wrapped execution, and privacy treatment: never broadcast to
	plain clients, only ever sent back to the specific developer editing
	it) so an owner-made NPC can react to being used (buy/sell an item,
	whatever) without needing a Job Activity at all - a Custom NPC's
	entity class is shared across every NPC definition
	(entities/entities/ent_pdcity_custom_npc.lua), so it was never a
	valid Activity target the way a Custom Prop's own unique class is.
-----------------------------------------------------------]]

util.AddNetworkString("pdcity_customnpc_sync")
util.AddNetworkString("pdcity_customnpc_admin")
util.AddNetworkString("pdcity_customnpc_code")
util.AddNetworkString("pdcity_customnpc_setcode_result")

local NPCS_PATH = "pdcity/custom_npcs.json"
local nextNPCID = 1

local CompiledNPCCode = {} -- [npcID] = function, or nil if none/failed to compile

local function CompileNPCCode(id, code)
	if not isstring(code) or code == "" then
		CompiledNPCCode[id] = nil
		return true
	end

	local func, err = CompileString(code, "pdcity_customnpc_" .. id, false)
	if not isfunction(func) then
		return false, tostring(func or err or "compile error")
	end

	CompiledNPCCode[id] = func
	return true
end

-- Runs a Custom NPC's compiled code, if it has any - called from
-- entities/entities/ent_pdcity_custom_npc.lua's own ENT:Use, alongside
-- the generic "PDCity_CustomNPCUsed" hook it already fires unconditionally.
-- pcall'd so a mistake in someone's code can't take the whole gamemode
-- down with it - same reasoning as core/sv_activities.lua's own
-- RunActivityCode.
function PDCity.RunCustomNPCCode(npc, ent, ply)
	local func = CompiledNPCCode[npc.ID]
	if not func then return end

	local ok, err = pcall(func, ent, ply, npc)
	if not ok then
		ErrorNoHalt("[" .. PDCity.BRAND_TAG .. "] Custom NPC #" .. npc.ID .. " (" .. npc.Name .. ")'s code errored: " .. tostring(err) .. "\n")
	end
end

local function SanitizedForClient(npc)
	if not npc.Code then return npc end

	local copy = {}
	for k, v in pairs(npc) do copy[k] = v end
	copy.Code = nil
	copy.HasCode = true
	return copy
end

local function SaveCustomNPCs()
	file.CreateDir("pdcity")
	file.Write(NPCS_PATH, util.TableToJSON({
		NPCs = PDCity.CUSTOM_NPCS,
		NextID = nextNPCID,
	}, true))
end

local function LoadCustomNPCs()
	local raw = file.Read(NPCS_PATH, "DATA")
	if not raw then return end

	local data = util.JSONToTable(raw)
	if not data then
		ErrorNoHalt("[" .. PDCity.BRAND_TAG .. "] " .. NPCS_PATH .. " was unreadable - keeping the built-in defaults.\n")
		return
	end

	if istable(data.NPCs) then PDCity.CUSTOM_NPCS = data.NPCs end
	if isnumber(data.NextID) then nextNPCID = math.max(nextNPCID, data.NextID) end

	for _, npc in ipairs(PDCity.CUSTOM_NPCS) do
		if npc.Code then
			local ok, err = CompileNPCCode(npc.ID, npc.Code)
			if not ok then
				ErrorNoHalt("[" .. PDCity.BRAND_TAG .. "] Custom NPC #" .. npc.ID .. " (" .. tostring(npc.Name) .. ")'s saved code failed to compile: " .. err .. "\n")
			end
		end
	end
end

LoadCustomNPCs()

local function BroadcastCustomNPCs(ply)
	local sanitized = {}
	for _, npc in ipairs(PDCity.CUSTOM_NPCS) do
		table.insert(sanitized, SanitizedForClient(npc))
	end

	net.Start("pdcity_customnpc_sync")
		net.WriteString(util.TableToJSON(sanitized))
	if IsValid(ply) then
		net.Send(ply)
	else
		net.Broadcast()
	end
end

hook.Add("PlayerInitialSpawn", "pdcity_SyncCustomNPCs", function(ply)
	BroadcastCustomNPCs(ply)
end)

local Actions = {}

function Actions.add(ply, p)
	if not isstring(p.Name) or p.Name == "" then return false, "Name can't be empty." end
	if not isstring(p.Model) or p.Model == "" or not util.IsValidModel(p.Model) then return false, "Not a recognised model." end

	table.insert(PDCity.CUSTOM_NPCS, {
		ID = nextNPCID,
		Name = p.Name,
		Model = p.Model,
	})
	nextNPCID = nextNPCID + 1

	return true
end

function Actions.edit(ply, p)
	local id = tonumber(p.ID)
	local npc = PDCity.GetCustomNPCByID(id)
	if not npc then return false, "That NPC no longer exists." end

	if not isstring(p.Name) or p.Name == "" then return false, "Name can't be empty." end
	if not isstring(p.Model) or p.Model == "" or not util.IsValidModel(p.Model) then return false, "Not a recognised model." end

	npc.Name = p.Name
	npc.Model = p.Model

	-- Every already-placed instance of this NPC picks up the new
	-- name/model on its next server restart (ent_pdcity_custom_npc.lua's
	-- own ENT:Initialize reads live off PDCity.CUSTOM_NPCS) - not
	-- retroactively on already-spawned entities, same "changes apply on
	-- next spawn/restart" convention as a built-in job's model override
	-- (core/sh_jobs.lua).

	return true
end

function Actions.remove(ply, p)
	local id = tonumber(p.ID)
	for i, npc in ipairs(PDCity.CUSTOM_NPCS) do
		if npc.ID == id then
			table.remove(PDCity.CUSTOM_NPCS, i)
			CompiledNPCCode[id] = nil
			return true
		end
	end
	return false, "That NPC no longer exists."
end

-- Developer-gated (PDCity.IsDeveloper, not PDCity.IsOwner) - same split
-- as core/sv_activities.lua's own set_code/get_code, and for the same
-- reason: writing code is the one narrow power a developer holds, not
-- the rest of what this Actions table can do.
local DEVELOPER_ACTIONS = { set_code = true, get_code = true }

function Actions.set_code(ply, p)
	local id = tonumber(p.ID)
	local npc = PDCity.GetCustomNPCByID(id)
	if not npc then return false, "That NPC no longer exists." end

	local code = isstring(p.Code) and p.Code or ""
	local ok, err = CompileNPCCode(id, code)
	if not ok then return false, "Code didn't compile: " .. err end

	npc.Code = (code ~= "") and code or nil

	PDCity.GameLog("staff", ply:Nick() .. " (" .. ply:SteamID() .. ") "
		.. (npc.Code and "set" or "cleared") .. " custom code on NPC #" .. id .. " (" .. npc.Name .. ")")

	return true
end

-- Not a mutation - answers directly, same shape as core/sv_activities.lua's
-- own get_code.
function Actions.get_code(ply, p)
	local id = tonumber(p.ID)
	local npc = PDCity.GetCustomNPCByID(id)
	if not npc then return end

	net.Start("pdcity_customnpc_code")
		net.WriteUInt(id, 32)
		net.WriteString(npc.Code or "")
	net.Send(ply)
end

net.Receive("pdcity_customnpc_admin", function(len, ply)
	local data = util.JSONToTable(net.ReadString() or "")
	if not istable(data) or not isstring(data.Action) then return end

	local isDeveloperAction = DEVELOPER_ACTIONS[data.Action] == true
	if isDeveloperAction then
		if not PDCity.IsDeveloper(ply) then return end
	else
		if not PDCity.IsOwner(ply) then return end
	end

	local handler = Actions[data.Action]
	if not handler then return end

	local ok, err = handler(ply, data.Payload or {})

	if data.Action == "get_code" then return end

	if data.Action == "set_code" then
		net.Start("pdcity_customnpc_setcode_result")
			net.WriteBool(ok)
			net.WriteString(ok and "" or (err or "That action failed."))
		net.Send(ply)
	end

	if ok then
		SaveCustomNPCs()
		BroadcastCustomNPCs()
	else
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] " .. (err or "That action failed."))
	end
end)
