--[[---------------------------------------------------------
	Server side of Job Activities (core/sh_activities.lua): definition
	persistence, the F4 admin editor's Activities-tab actions, the
	developer code console's actions, and the runtime triggers
	(Use / collide / custom code).
-----------------------------------------------------------]]

util.AddNetworkString("pdcity_activity_sync")
util.AddNetworkString("pdcity_activity_admin")
util.AddNetworkString("pdcity_activity_code")
util.AddNetworkString("pdcity_activity_setcode_result")
util.AddNetworkString("pdcity_activity_flow")
util.AddNetworkString("pdcity_devconsole_open")
util.AddNetworkString("pdcity_flow_wait_display")
util.AddNetworkString("pdcity_open_interface")

-- "!devcode" - opens the Developer Console (cl_dev_console.lua), the
-- narrow owner/developer-only panel for writing an Activity's custom
-- code. Same relay pattern as core/sv_tickets.lua's !report/!support/
-- !ticket - default priority, since core/sv_chat.lua's own PlayerSay
-- handler already passes every "!"-prefixed message through untouched.
hook.Add("PlayerSay", "pdcity_DevConsoleChatCommand", function(ply, text)
	if string.lower(string.Trim(text)) ~= "!devcode" then return end
	if not PDCity.IsDeveloper(ply) then return end

	net.Start("pdcity_devconsole_open")
	net.Send(ply)

	return ""
end)

local ACTIVITIES_PATH = "pdcity/activities.json"
local nextActivityID = 1

--[[---------------------------------------------------------
	Custom code (core/sh_activities.lua's Code field) - owner/developer
	only (PDCity.IsDeveloper, core/sv_developers.lua), written from the
	Developer Console (cl_dev_console.lua) rather than the (owner-only)
	F4 admin editor's Activities tab. Compiled once here, on load and
	whenever it's changed, rather than CompileString-ing fresh on every
	single trigger - cached by activity ID, invalidated by re-assigning
	the cache entry (same "assign a fresh value, don't mutate" idea as
	core/sh_jobs.lua's job-override cache).

	The raw source is NEVER included in BroadcastActivities below -
	SanitizedForClient strips it before anything goes out over
	"pdcity_activity_sync" (which every connected player receives, not
	just staff) - a developer's gameplay logic isn't public information
	the way an activity's name/class/jobs are. It's only ever sent back
	to the specific developer who asked for it (the "get_code" action),
	gated the same way "set_code" is.
-----------------------------------------------------------]]

local CompiledCode = {} -- [activityID] = function, or nil if none/failed to compile

--[[---------------------------------------------------------
	Code tags - lets a Flowchart node ("Run Code Tag") call a specific,
	named chunk of an activity's OWN Developer Console code at that exact
	point in the flow chain, instead of the whole Code file always running
	unconditionally before the flow ever starts (RunActivityCode below).

	PDCity.DefineCodeTag(name, fn) is a global the devcode itself calls to
	REGISTER a tagged function - it doesn't run fn immediately. Re-registered
	fresh (CodeTags[id] wiped first) at the top of every RunActivityCode
	call, so a tag the developer has since removed from their code doesn't
	linger as a stale, callable ghost. activeTagActivityID is only ever
	set while that activity's compiled chunk is actually mid-run, so a
	registration always lands in the right activity's table even though
	PDCity.DefineCodeTag itself takes no activity ID - the devcode author
	never has to know or pass their own activity's ID.

	A tagged function's return value gates the flow chain exactly like the
	"Charge Player" node's affordability check already does: return false
	to stop the chain right there (e.g. "not enough presses yet"), anything
	else (or nothing) lets it continue to the next node.
-----------------------------------------------------------]]

local CodeTags = {} -- [activityID] = { [tagName] = fn }
local activeTagActivityID = nil

function PDCity.DefineCodeTag(name, fn)
	if not activeTagActivityID or not isstring(name) or not isfunction(fn) then return end
	CodeTags[activeTagActivityID] = CodeTags[activeTagActivityID] or {}
	CodeTags[activeTagActivityID][name] = fn
end

local function CompileActivityCode(id, code)
	if not isstring(code) or code == "" then
		CompiledCode[id] = nil
		return true
	end

	local func, err = CompileString(code, "pdcity_activity_" .. id, false)
	if not isfunction(func) then
		return false, tostring(func or err or "compile error")
	end

	CompiledCode[id] = func
	return true
end

local function SanitizedForClient(activity)
	if not activity.Code and not activity.Flow then return activity end

	local copy = {}
	for k, v in pairs(activity) do copy[k] = v end
	if copy.Code then
		copy.Code = nil
		copy.HasCode = true
	end
	if copy.Flow then
		copy.Flow = nil
		copy.HasFlow = true
	end
	return copy
end

--[[---------------------------------------------------------
	Flowchart (core/sh_activities.lua's Flow field) - the owner-accessible,
	no-Lua-required alternative to Code above, built from the F4 admin
	editor's Activities tab (cl_flow_editor.lua's "Edit Flowchart..."
	button) rather than the Developer Console. A flow is a plain ORDERED
	LIST of nodes, run top to bottom - no branching in this first pass
	(see cl_flow_editor.lua's own header for why that's deliberate, not
	a missing feature). Same privacy treatment as Code: never included
	in the normal broadcast (SanitizedForClient strips it too, replacing
	it with a HasFlow flag), only ever sent back to the owner editing it
	(the "get_flow" action).

	Node shape: { Type = "...", <fields specific to that type> }. See
	FLOW_NODE_TYPES immediately below for the full list and what each
	one's fields mean.
-----------------------------------------------------------]]

local FLOW_NODE_TYPES = {
	charge = { Label = "Charge Player", Fields = { "Amount" } },
	give_money = { Label = "Give Player Money", Fields = { "Amount" } },
	give_item = { Label = "Give Item", Fields = { "Class" } },
	chat = { Label = "Chat Message", Fields = { "Text" } },
	wait = { Label = "Wait", Fields = { "Seconds", "Label" } },
	remove_other = { Label = "Remove Touching Item", Fields = {} },
	remove_self = { Label = "Remove This Entity", Fields = {} },
	spawn_entity = { Label = "Spawn Entity", Fields = { "Class" } },
	run_code_tag = { Label = "Run Code Tag (Developer)", Fields = { "Tag" } },
	open_interface = { Label = "Open Interface", Fields = { "Interface" } },
	give_currency = { Label = "Give Currency", Fields = { "Currency", "Amount" } },
	charge_currency = { Label = "Charge Currency", Fields = { "Currency", "Amount" } },
}

local function IsValidFlow(flow)
	if flow == nil then return true end
	if not istable(flow) then return false end
	for _, node in ipairs(flow) do
		if not istable(node) or not isstring(node.Type) or not FLOW_NODE_TYPES[node.Type] then
			return false
		end
	end
	return true
end

-- The actual PLAYER a player-targeted node (charge/give_money/give_item/
-- chat) should act on. `other` IS the player for a Use trigger, but for
-- a Collide trigger it's whatever touched the entity - not necessarily
-- anything with an owner. Player-targeted nodes just skip themselves
-- when there's nobody to act on, rather than erroring the whole flow.
local function ResolvePlayerTarget(other)
	if IsValid(other) and other:IsPlayer() then return other end
	return nil
end

-- Walks a flow from `index` onward. Split out from PDCity.RunActivityFlow
-- so the "wait" node can re-enter here (via timer.Simple) partway
-- through the same list rather than needing its own separate state
-- machine - the for loop just starts wherever it's told to.
local function RunFlowFrom(flow, index, ent, other, activityID)
	for i = index, #flow do
		if not IsValid(ent) then return end -- e.g. removed by an earlier node, or the map's cleaned up mid-wait

		local node = flow[i]

		if node.Type == "wait" then
			local seconds = math.max(0, tonumber(node.Seconds) or 0)

			-- Countdown HUD (cl_flow_wait_hud.lua) - only the player actually
			-- waiting on it sees it, same "only meaningful for a player"
			-- treatment as every other player-targeted node. Purely cosmetic:
			-- the wait itself still elapses server-side via timer.Simple
			-- below regardless of whether anyone's watching it.
			local waitPly = ResolvePlayerTarget(other)
			if waitPly and seconds > 0 then
				local label = isstring(node.Label) and node.Label ~= "" and node.Label or "Waiting"
				net.Start("pdcity_flow_wait_display")
					net.WriteString(label)
					net.WriteFloat(seconds)
				net.Send(waitPly)
			end

			timer.Simple(seconds, function()
				RunFlowFrom(flow, i + 1, ent, other, activityID)
			end)
			return -- the rest of the chain continues from the timer callback instead
		end

		if node.Type == "charge" then
			local ply = ResolvePlayerTarget(other)
			if ply then
				local amount = math.max(0, tonumber(node.Amount) or 0)
				if not PDCity.AddMoney(ply, -amount) then
					ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] You can't afford that ($" .. amount .. ").")
					return -- acts as a gate - nothing after this runs
				end
			end

		elseif node.Type == "give_money" then
			local ply = ResolvePlayerTarget(other)
			if ply then PDCity.AddMoney(ply, math.max(0, tonumber(node.Amount) or 0)) end

		elseif node.Type == "give_item" then
			local ply = ResolvePlayerTarget(other)
			if ply and isstring(node.Class) and node.Class ~= "" then
				PDCity.InventoryAdd(ply, node.Class, 1)
			end

		elseif node.Type == "chat" then
			local ply = ResolvePlayerTarget(other)
			if ply and isstring(node.Text) and node.Text ~= "" then
				ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] " .. node.Text)
			end

		elseif node.Type == "remove_other" then
			if IsValid(other) and not other:IsPlayer() then
				other:Remove()
			end

		elseif node.Type == "remove_self" then
			-- Safe to put anywhere in the chain, not just at the end - the
			-- loop's own IsValid(ent) check at the top of the next
			-- iteration stops anything after this from running once it has.
			ent:Remove()

		elseif node.Type == "spawn_entity" then
			-- Spawns at ent's CURRENT position/angle, so this has to run
			-- before a "Remove This Entity" node earlier in the same chain
			-- if the intent is "replace ent with something else" (the
			-- barrel-swap use case this was built for) - order in the list
			-- is exactly the order these run in, nothing implicit about it.
			-- Re-checked against the live registry (not just at save time,
			-- core/sh_activities.lua's own header on why nodes generally
			-- don't validate deeply) since the class could have stopped
			-- existing since this flow was saved - a removed Custom Prop
			-- definition, for instance.
			if isstring(node.Class) and node.Class ~= "" and scripted_ents.GetStored(node.Class) then
				local spawned = ents.Create(node.Class)
				if IsValid(spawned) then
					spawned:SetPos(ent:GetPos())
					spawned:SetAngles(ent:GetAngles())
					spawned:Spawn()
					spawned:Activate()
				end
			end

		elseif node.Type == "run_code_tag" then
			local tagFn = activityID and isstring(node.Tag) and node.Tag ~= ""
				and CodeTags[activityID] and CodeTags[activityID][node.Tag]

			if not tagFn then
				-- Fails CLOSED, not open - a typo'd/renamed/not-yet-defined
				-- tag used to silently no-op and let the chain fall through
				-- to whatever came next (Spawn Entity, Give Item, ...)
				-- completely unconditionally, on every single trigger - the
				-- gate just never existed. Stopping here instead means a
				-- misconfigured tag is at worst "nothing happens", never
				-- "the reward node fires early".
				ErrorNoHalt("[" .. PDCity.BRAND_TAG .. "] Activity #" .. tostring(activityID) .. "'s Flowchart references code tag \""
					.. tostring(node.Tag) .. "\", but nothing registered that tag (PDCity.DefineCodeTag) on its last run - check the tag name matches exactly, and that the Code actually ran before the Flow (it always does on Use/Collide, so this usually means a typo or missing Code entirely).\n")
				return
			end

			local ok, continueFlow = pcall(tagFn, ent, other)
			if not ok then
				ErrorNoHalt("[" .. PDCity.BRAND_TAG .. "] Activity #" .. tostring(activityID) .. "'s code tag \"" .. node.Tag .. "\" errored: " .. tostring(continueFlow) .. "\n")
				return
			elseif continueFlow == false then
				return -- the tag itself said "stop here" (e.g. not enough presses yet), same gating as "charge"
			end

		elseif node.Type == "open_interface" then
			-- Interfaces (cl_interfaces.lua) are a client-side registry -
			-- the server has no idea what they look like or even whether
			-- the name is real, it just relays the name (and the entity
			-- that triggered this, for context - e.g. an NPC shop menu
			-- knowing which NPC it's shopping) to the one player who
			-- triggered this flow. cl_interfaces.lua's own receiver quietly
			-- no-ops if nothing's registered under that name.
			local ply = ResolvePlayerTarget(other)
			if ply and isstring(node.Interface) and node.Interface ~= "" then
				net.Start("pdcity_open_interface")
					net.WriteString(node.Interface)
					net.WriteEntity(ent)
				net.Send(ply)
			end

		elseif node.Type == "give_currency" then
			local ply = ResolvePlayerTarget(other)
			local currencyID = tonumber(node.Currency)
			if ply and currencyID then
				PDCity.AddCurrency(ply, currencyID, math.max(0, tonumber(node.Amount) or 0))
			end

		elseif node.Type == "charge_currency" then
			local ply = ResolvePlayerTarget(other)
			local currencyID = tonumber(node.Currency)
			if ply and currencyID then
				local amount = math.max(0, tonumber(node.Amount) or 0)
				if not PDCity.RemoveCurrency(ply, currencyID, amount) then
					local currency = PDCity.GetCurrencyByID(currencyID)
					ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] You don't have enough " .. (currency and currency.Name or "currency") .. ".")
					return -- acts as a gate - nothing after this runs, same as "charge"
				end
			end
		end
	end
end

function PDCity.RunActivityFlow(activity, ent, other)
	if not istable(activity.Flow) or #activity.Flow == 0 then return end
	RunFlowFrom(activity.Flow, 1, ent, other, activity.ID)
end

local function SaveActivities()
	file.CreateDir("pdcity")
	file.Write(ACTIVITIES_PATH, util.TableToJSON({
		Activities = PDCity.ACTIVITIES,
		NextID = nextActivityID,
	}, true))
end

local function LoadActivities()
	local raw = file.Read(ACTIVITIES_PATH, "DATA")
	if not raw then return end

	local data = util.JSONToTable(raw)
	if not data then
		ErrorNoHalt("[" .. PDCity.BRAND_TAG .. "] " .. ACTIVITIES_PATH .. " was unreadable - keeping the built-in defaults.\n")
		return
	end

	if istable(data.Activities) then PDCity.ACTIVITIES = data.Activities end
	if isnumber(data.NextID) then nextActivityID = math.max(nextActivityID, data.NextID) end

	for _, activity in ipairs(PDCity.ACTIVITIES) do
		if activity.Code then
			local ok, err = CompileActivityCode(activity.ID, activity.Code)
			if not ok then
				ErrorNoHalt("[" .. PDCity.BRAND_TAG .. "] Activity #" .. activity.ID .. " (" .. tostring(activity.Name) .. ")'s saved code failed to compile: " .. err .. "\n")
			end
		end
	end
end

LoadActivities()

local function BroadcastActivities(ply)
	local sanitized = {}
	for _, activity in ipairs(PDCity.ACTIVITIES) do
		table.insert(sanitized, SanitizedForClient(activity))
	end

	net.Start("pdcity_activity_sync")
		net.WriteString(util.TableToJSON(sanitized))
	if IsValid(ply) then
		net.Send(ply)
	else
		net.Broadcast()
	end
end

hook.Add("PlayerInitialSpawn", "pdcity_SyncActivities", function(ply)
	BroadcastActivities(ply)
end)

--[[---------------------------------------------------------
	Admin actions - owner only, same enforcement pattern as the F4/Job
	catalogues (core/sv_f4_catalogue.lua, core/sv_job_catalogue.lua):
	re-checked here regardless of what the client's UI already hides.
-----------------------------------------------------------]]

-- Real SENTs only (scripted_ents), not weapons/props - Use only ever
-- fires for something that actually implements it, which in practice
-- means a scripted entity.
local function IsValidActivityClass(class)
	return isstring(class) and class ~= "" and scripted_ents.GetStored(class) ~= nil
end

local function IsValidJobList(list)
	if list == nil then return true end
	if not istable(list) then return false end
	for _, id in ipairs(list) do
		if not isnumber(id) then return false end
	end
	return true
end

local function IsValidClassList(list)
	if list == nil then return true end
	if not istable(list) then return false end
	for _, class in ipairs(list) do
		if not isstring(class) or class == "" then return false end
	end
	return true
end

-- Shared shape-building/validation for both add and edit - returns the
-- fields to store, or false+error. `existingID` is nil for add (so the
-- Class-uniqueness check never collides with itself) or the activity's
-- own ID for edit (excluded from that same check).
local function BuildActivityFields(p, existingID)
	if not isstring(p.Name) or p.Name == "" then return false, "Name can't be empty." end
	if not IsValidJobList(p.Jobs) then return false, "Invalid job selection." end
	if not IsValidActivityClass(p.Class) then return false, "Not a recognised entity class." end

	local other = PDCity.GetActivityForClass(p.Class)
	if other and other.ID ~= existingID then
		return false, "That entity class is already tied to another activity."
	end

	if not IsValidClassList(p.FillClasses) then return false, "Invalid fill-item class list." end

	local triggerType = (p.TriggerType == "collide") and "collide" or "use"

	return {
		Name = p.Name,
		Class = p.Class,
		Jobs = p.Jobs,
		TriggerType = triggerType,
		FillClasses = (triggerType == "collide") and p.FillClasses or nil,
		HookName = isstring(p.HookName) and p.HookName ~= "" and p.HookName or PDCity.SuggestActivityHookName(p.Name),
	}
end

local Actions = {}

function Actions.add(ply, p)
	local fields, err = BuildActivityFields(p, nil)
	if not fields then return false, err end

	fields.ID = nextActivityID
	nextActivityID = nextActivityID + 1

	table.insert(PDCity.ACTIVITIES, fields)
	return true
end

function Actions.edit(ply, p)
	local id = tonumber(p.ID)
	local activity
	for _, a in ipairs(PDCity.ACTIVITIES) do
		if a.ID == id then activity = a break end
	end
	if not activity then return false, "That activity no longer exists." end

	local fields, err = BuildActivityFields(p, id)
	if not fields then return false, err end

	fields.ID = id
	-- Code/Flow are edited through their own separate actions
	-- (set_code/set_flow), never through this form - carried over
	-- explicitly rather than wiped, or every plain name/job edit here
	-- would silently delete whatever custom code or flowchart the
	-- activity already had.
	fields.Code = activity.Code
	fields.Flow = activity.Flow

	for k in pairs(activity) do activity[k] = nil end
	for k, v in pairs(fields) do activity[k] = v end

	return true
end

function Actions.remove(ply, p)
	local id = tonumber(p.ID)
	for i, a in ipairs(PDCity.ACTIVITIES) do
		if a.ID == id then
			table.remove(PDCity.ACTIVITIES, i)
			CompiledCode[id] = nil
			return true
		end
	end
	return false, "That activity no longer exists."
end

-- Developer-gated (PDCity.IsDeveloper, not PDCity.IsOwner) - deliberately
-- the ONLY two actions a plain developer can reach through this net
-- message; see the dispatch gate below and core/sv_developers.lua's own
-- header for why that split exists.
local DEVELOPER_ACTIONS = { set_code = true, get_code = true }

function Actions.set_code(ply, p)
	local id = tonumber(p.ID)
	local activity
	for _, a in ipairs(PDCity.ACTIVITIES) do
		if a.ID == id then activity = a break end
	end
	if not activity then return false, "That activity no longer exists." end

	local code = isstring(p.Code) and p.Code or ""
	local ok, err = CompileActivityCode(id, code)
	if not ok then return false, "Code didn't compile: " .. err end

	activity.Code = (code ~= "") and code or nil

	PDCity.GameLog("staff", ply:Nick() .. " (" .. ply:SteamID() .. ") "
		.. (activity.Code and "set" or "cleared") .. " custom code on activity #" .. id .. " (" .. activity.Name .. ")")

	return true
end

-- Not a mutation - doesn't go through the SaveActivities/BroadcastActivities
-- path below at all, it just answers directly with the one activity's raw
-- code (never included in the normal broadcast - see SanitizedForClient).
function Actions.get_code(ply, p)
	local id = tonumber(p.ID)
	local activity
	for _, a in ipairs(PDCity.ACTIVITIES) do
		if a.ID == id then activity = a break end
	end
	if not activity then return end

	net.Start("pdcity_activity_code")
		net.WriteUInt(id, 32)
		net.WriteString(activity.Code or "")
	net.Send(ply)
end

-- set_flow/get_flow are NOT in DEVELOPER_ACTIONS - the flowchart is the
-- owner-accessible, no-Lua alternative to Code (see this file's own
-- Flow section above), so it goes through the normal owner-only gate
-- below like every other Activities-tab action.
function Actions.set_flow(ply, p)
	local id = tonumber(p.ID)
	local activity
	for _, a in ipairs(PDCity.ACTIVITIES) do
		if a.ID == id then activity = a break end
	end
	if not activity then return false, "That activity no longer exists." end

	if not IsValidFlow(p.Flow) then return false, "Invalid flow - unrecognised node type." end

	activity.Flow = (istable(p.Flow) and #p.Flow > 0) and p.Flow or nil

	PDCity.GameLog("staff", ply:Nick() .. " (" .. ply:SteamID() .. ") "
		.. (activity.Flow and "set" or "cleared") .. " the flowchart on activity #" .. id .. " (" .. activity.Name .. ")")

	return true
end

-- Not a mutation - same "answers directly" shape as get_code.
function Actions.get_flow(ply, p)
	local id = tonumber(p.ID)
	local activity
	for _, a in ipairs(PDCity.ACTIVITIES) do
		if a.ID == id then activity = a break end
	end
	if not activity then return end

	net.Start("pdcity_activity_flow")
		net.WriteUInt(id, 32)
		net.WriteString(util.TableToJSON(activity.Flow or {}))
	net.Send(ply)
end

net.Receive("pdcity_activity_admin", function(len, ply)
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

	-- get_code/get_flow answer directly (above) and aren't mutations -
	-- nothing to save/broadcast/error-report for either one.
	if data.Action == "get_code" or data.Action == "get_flow" then return end

	-- set_code gets its own explicit result message (success or the
	-- compile error) rather than making the Developer Console guess from
	-- a ChatPrint the way the other actions' failures work - cl_dev_console.lua
	-- needs to reliably know pass/fail to update its status label, not
	-- just print something to the chat toast feed.
	if data.Action == "set_code" then
		net.Start("pdcity_activity_setcode_result")
			net.WriteBool(ok)
			net.WriteString(ok and "" or (err or "That action failed."))
		net.Send(ply)
	end

	if ok then
		SaveActivities()
		BroadcastActivities()
	else
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] " .. (err or "That action failed."))
	end
end)

--[[---------------------------------------------------------
	Runtime triggers. No timer/reward/cooldown logic here on purpose -
	see core/sh_activities.lua's own header. Both fire the generic hook
	AND, if the activity has one set, its own named hook - see that
	file's header for which to use when.
-----------------------------------------------------------]]

-- Resolves the activity for a given entity. ent.pdcity_ActivityID is an
-- escape hatch for a custom entity that wants to be tied to one SPECIFIC
-- activity regardless of its class (e.g. a multi-tenant entity someone
-- builds themselves) - checked first, falling back to the normal
-- Class-based lookup that covers every ordinary case.
local function ActivityForEntity(ent)
	if ent.pdcity_ActivityID then
		local byID = PDCity.GetActivityByID(ent.pdcity_ActivityID)
		if byID then return byID end
	end
	return PDCity.GetActivityForClass(ent:GetClass())
end

-- Runs an activity's compiled custom code, if it has any - shared by
-- both trigger paths below. pcall'd: a mistake in someone's custom code
-- (a nil index, a typo'd PDCity_ function name...) prints to console
-- like any other Lua error would, but can't take the trigger hooks
-- (or, worse, the whole gamemode) down with it. `...` inside the code
-- receives exactly the same (ent, other, activity) this passes here.
local function RunActivityCode(activity, ent, other)
	local func = CompiledCode[activity.ID]
	if not func then return end

	-- Wiped and rebuilt fresh on every run, right before the code actually
	-- executes and can call PDCity.DefineCodeTag - a tag the developer has
	-- since deleted from their code shouldn't linger as a stale, callable
	-- ghost in a Flow node that still names it.
	CodeTags[activity.ID] = {}
	activeTagActivityID = activity.ID
	local ok, err = pcall(func, ent, other, activity)
	activeTagActivityID = nil

	if not ok then
		ErrorNoHalt("[" .. PDCity.BRAND_TAG .. "] Activity #" .. activity.ID .. " (" .. activity.Name .. ")'s custom code errored: " .. tostring(err) .. "\n")
	end
end

-- PlayerUse fires every server tick for as long as +use is held down on a
-- SIMPLE_USE entity, not once per physical press - without this, holding E
-- for even a fraction of a second could run a shake/press-counter's whole
-- chain (or any other Activity) many times over from a single press. Same
-- "lock until KeyRelease" pattern core/sv_drop.lua's own USE_PICKUP handler
-- and core/sv_inventory.lua's CTRL+USE pickup already use - one activation
-- per press, released the moment the player lets go of E.
local usingLock = {} -- [ply:SteamID()] = the entity they're currently holding +use down on

hook.Add("KeyRelease", "pdcity_ActivityUseRelease", function(ply, key)
	if key ~= IN_USE then return end
	usingLock[ply:SteamID()] = nil
end)

hook.Add("PlayerUse", "pdcity_ActivityUse", function(ply, ent)
	if not IsValid(ent) then return end

	local activity = ActivityForEntity(ent)
	if not activity or activity.TriggerType == "collide" then return end

	if usingLock[ply:SteamID()] == ent then return end
	usingLock[ply:SteamID()] = ent

	if activity.Jobs and #activity.Jobs > 0 and not table.HasValue(activity.Jobs, ply:Team()) then
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Your job can't use this.")
		return false
	end

	hook.Run("PDCity_ActivityUsed", activity, ent, ply)
	if activity.HookName and activity.HookName ~= "" then
		hook.Run(activity.HookName, ent, ply)
	end
	RunActivityCode(activity, ent, ply)
	PDCity.RunActivityFlow(activity, ent, ply)
end)

-- Called from an activity entity's own ENT:StartTouch (a per-entity
-- engine callback, not something a generic hook.Add can catch the way
-- PlayerUse works above) - see core/sh_activities.lua's own header for
-- why. A short per-toucher cooldown stops physics jitter (an item
-- resting against the entity re-triggering StartTouch many times a
-- second) from spamming the hook - "how the fill actually behaves"
-- (does it consume the item? cap how much fits?) is still entirely up
-- to whatever's hooked, this only rate-limits the EVENT itself.
local TOUCH_COOLDOWN = 1
local recentTouches = {} -- [stationEntIndex .. "_" .. otherEntIndex] = CurTime() it last fired

function PDCity.FireActivityCollide(ent, other)
	if not IsValid(ent) or not IsValid(other) then return end

	local activity = ActivityForEntity(ent)
	if not activity or activity.TriggerType ~= "collide" then return end

	if activity.FillClasses and #activity.FillClasses > 0 and not table.HasValue(activity.FillClasses, other:GetClass()) then
		return
	end

	local key = ent:EntIndex() .. "_" .. other:EntIndex()
	if (recentTouches[key] or 0) + TOUCH_COOLDOWN > CurTime() then return end
	recentTouches[key] = CurTime()

	hook.Run("PDCity_ActivityFilled", activity, ent, other)
	if activity.HookName and activity.HookName ~= "" then
		hook.Run(activity.HookName, ent, other)
	end
	RunActivityCode(activity, ent, other)
	PDCity.RunActivityFlow(activity, ent, other)
end
