--[[---------------------------------------------------------
	Server side of the rulebook: persists core/sh_rules.lua's PDCity.RULES
	to data/pdcity/rules.json, validates every change, and broadcasts the
	result so every connected player's F1 "Rules" tab (cl_rules.lua)
	updates live. No restart needed to add, reword, or reorder a rule.

	Gated at PDCity.IsOwner, same as the rest of the Site Admin panel -
	re-checked here regardless of what the client's UI already hides.
-----------------------------------------------------------]]

util.AddNetworkString("pdcity_rules_sync")
util.AddNetworkString("pdcity_rules_admin")

local SAVE_PATH = "pdcity/rules.json"

-- Generous, but bounded - these are shown in a menu, not a document
-- reader, and anything past this is a mistake or an attempt to make the
-- net message unsendable.
local MAX_INTRO = 1200
local MAX_TITLE = 80
local MAX_DETAIL = 500
local MAX_UPDATED = 40
local MAX_SECTIONS = 30
local MAX_RULES_PER_SECTION = 60

local function SaveRules()
	file.CreateDir("pdcity")
	file.Write(SAVE_PATH, util.TableToJSON(PDCity.RULES, true))
end

local function LoadRules()
	local raw = file.Read(SAVE_PATH, "DATA")
	if not raw then return end

	local data = util.JSONToTable(raw)
	if not istable(data) or not istable(data.Sections) then
		ErrorNoHalt("[" .. PDCity.BRAND_TAG .. "] " .. SAVE_PATH .. " was unreadable - keeping the built-in default rules.\n")
		return
	end

	PDCity.RULES = data
	PDCity.RULES.Intro = isstring(PDCity.RULES.Intro) and PDCity.RULES.Intro or ""
	PDCity.RULES.Updated = isstring(PDCity.RULES.Updated) and PDCity.RULES.Updated or ""
end
LoadRules()

local function BroadcastRules(ply)
	net.Start("pdcity_rules_sync")
		net.WriteString(util.TableToJSON(PDCity.RULES))
	if IsValid(ply) then net.Send(ply) else net.Broadcast() end
end

hook.Add("PlayerInitialSpawn", "pdcity_SyncRules", function(ply)
	BroadcastRules(ply)
end)

--[[---------------------------------------------------------
	Admin actions
-----------------------------------------------------------]]

local function Clean(value, maxLength)
	if not isstring(value) then return "" end
	return string.sub(string.Trim(value), 1, maxLength)
end

local function ValidSeverity(id)
	for _, sev in ipairs(PDCity.RULE_SEVERITIES) do
		if sev.ID == id then return id end
	end
	return PDCity.RULE_SEVERITIES[1].ID
end

local function SectionAt(index)
	index = tonumber(index)
	if not index then return nil end
	return PDCity.RULES.Sections[index], index
end

net.Receive("pdcity_rules_admin", function(len, ply)
	if not IsValid(ply) or not PDCity.IsOwner(ply) then return end
	if len > 65530 then return end

	local data = util.JSONToTable(net.ReadString() or "")
	if not istable(data) or not isstring(data.Action) then return end

	local p = data.Payload or {}
	local action = data.Action

	if action == "set_header" then
		PDCity.RULES.Intro = Clean(p.Intro, MAX_INTRO)
		PDCity.RULES.Updated = Clean(p.Updated, MAX_UPDATED)

	elseif action == "add_section" then
		if #PDCity.RULES.Sections >= MAX_SECTIONS then
			ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] That's the maximum number of rule sections (" .. MAX_SECTIONS .. ").")
			return
		end

		local title = Clean(p.Title, MAX_TITLE)
		if title == "" then ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Give the section a title.") return end

		table.insert(PDCity.RULES.Sections, { Title = title, Icon = Clean(p.Icon, 300), Rules = {} })

	elseif action == "edit_section" then
		local section = SectionAt(p.Index)
		if not section then return end

		local title = Clean(p.Title, MAX_TITLE)
		if title == "" then ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Give the section a title.") return end

		section.Title = title
		section.Icon = Clean(p.Icon, 300)

	elseif action == "remove_section" then
		local section, index = SectionAt(p.Index)
		if not section then return end
		table.remove(PDCity.RULES.Sections, index)

	elseif action == "move_section" then
		local section, index = SectionAt(p.Index)
		local dir = tonumber(p.Direction)
		if not section or not dir then return end

		local target = index + dir
		if not PDCity.RULES.Sections[target] then return end

		PDCity.RULES.Sections[index], PDCity.RULES.Sections[target] =
			PDCity.RULES.Sections[target], PDCity.RULES.Sections[index]

	elseif action == "add_rule" or action == "edit_rule" then
		local section = SectionAt(p.Section)
		if not section then return end

		section.Rules = section.Rules or {}

		local title = Clean(p.Title, MAX_TITLE)
		if title == "" then ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Give the rule a title.") return end

		local rule = {
			Title = title,
			Detail = Clean(p.Detail, MAX_DETAIL),
			Severity = ValidSeverity(p.Severity),
		}

		if action == "add_rule" then
			if #section.Rules >= MAX_RULES_PER_SECTION then
				ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] That's the maximum number of rules in one section (" .. MAX_RULES_PER_SECTION .. ").")
				return
			end
			table.insert(section.Rules, rule)
		else
			local index = tonumber(p.Index)
			if not index or not section.Rules[index] then return end
			section.Rules[index] = rule
		end

	elseif action == "remove_rule" then
		local section = SectionAt(p.Section)
		local index = tonumber(p.Index)
		if not section or not index or not (section.Rules and section.Rules[index]) then return end
		table.remove(section.Rules, index)

	elseif action == "move_rule" then
		local section = SectionAt(p.Section)
		local index = tonumber(p.Index)
		local dir = tonumber(p.Direction)
		if not section or not index or not dir then return end
		if not (section.Rules and section.Rules[index]) then return end

		local target = index + dir
		if not section.Rules[target] then return end

		section.Rules[index], section.Rules[target] = section.Rules[target], section.Rules[index]

	elseif action == "reset_defaults" then
		PDCity.RULES = PDCity.ExampleRules()

	else
		return
	end

	PDCity.GameLog("staff", ply:Nick() .. " (" .. ply:SteamID() .. ") edited the server rules (" .. action .. ")")
	SaveRules()
	BroadcastRules()
end)
