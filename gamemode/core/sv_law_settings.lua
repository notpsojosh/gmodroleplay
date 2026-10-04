--[[---------------------------------------------------------
	Server side of the F1 Site Admin panel's "Laws & Rewards" tab:
	persists core/sh_laws.lua's PDCity.LAWS/PDCity.LAW_REWARDS to
	data/pdcity/law_settings.json, validates every change, and broadcasts
	the result so core/sv_arrests.lua's arrest/bail/disconnect-penalty
	logic (and every connected officer's arrest menu dropdown) updates
	live - no restart needed to add a law or retune what an arrest pays.

	Gated at PDCity.IsOwner, same as the rest of the Site Admin panel -
	re-checked here regardless of what the client's UI already hides.
-----------------------------------------------------------]]

util.AddNetworkString("pdcity_law_settings_sync")
util.AddNetworkString("pdcity_law_settings_admin")

local SAVE_PATH = "pdcity/law_settings.json"

local function SaveLawSettings()
	file.CreateDir("pdcity")
	file.Write(SAVE_PATH, util.TableToJSON({
		Laws = PDCity.LAWS,
		Rewards = PDCity.LAW_REWARDS,
	}, true))
end

local function LoadLawSettings()
	local raw = file.Read(SAVE_PATH, "DATA")
	if not raw then return end

	local data = util.JSONToTable(raw)
	if not istable(data) then
		ErrorNoHalt("[" .. PDCity.BRAND_TAG .. "] " .. SAVE_PATH .. " was unreadable - keeping the built-in default laws/rewards.\n")
		return
	end

	if istable(data.Laws) then PDCity.LAWS = data.Laws end
	if istable(data.Rewards) then
		for key, default in pairs(PDCity.LAW_REWARDS) do
			if isnumber(data.Rewards[key]) then PDCity.LAW_REWARDS[key] = data.Rewards[key] end
		end
	end
end
LoadLawSettings()

local function BroadcastLawSettings(ply)
	net.Start("pdcity_law_settings_sync")
		net.WriteString(util.TableToJSON({ Laws = PDCity.LAWS, Rewards = PDCity.LAW_REWARDS }))
	if IsValid(ply) then net.Send(ply) else net.Broadcast() end
end

hook.Add("PlayerInitialSpawn", "pdcity_SyncLawSettings", function(ply)
	BroadcastLawSettings(ply)
end)

--[[---------------------------------------------------------
	Admin actions
-----------------------------------------------------------]]

local function ValidateLaw(p)
	local name = isstring(p.Name) and string.Trim(p.Name) or ""
	if name == "" then return false, "Enter a name for the law." end
	if #name > 40 then return false, "Law names can be at most 40 characters." end

	local minMinutes = math.floor(tonumber(p.MinMinutes) or 0)
	local maxMinutes = math.floor(tonumber(p.MaxMinutes) or 0)
	if minMinutes < 1 then return false, "Minimum duration must be at least 1." end
	if maxMinutes < minMinutes then return false, "Maximum duration can't be less than the minimum." end

	return { Name = name, MinMinutes = minMinutes, MaxMinutes = maxMinutes }
end

net.Receive("pdcity_law_settings_admin", function(len, ply)
	if not IsValid(ply) or not PDCity.IsOwner(ply) then return end
	if len > 65530 then return end

	local data = util.JSONToTable(net.ReadString() or "")
	if not istable(data) or not isstring(data.Action) then return end

	if data.Action == "add_law" then
		local law, err = ValidateLaw(data.Payload or {})
		if not law then ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] " .. err) return end
		table.insert(PDCity.LAWS, law)

	elseif data.Action == "edit_law" then
		local index = tonumber(data.Payload and data.Payload.Index)
		if not index or not PDCity.LAWS[index] then return end

		local law, err = ValidateLaw(data.Payload or {})
		if not law then ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] " .. err) return end
		PDCity.LAWS[index] = law

	elseif data.Action == "remove_law" then
		local index = tonumber(data.Payload and data.Payload.Index)
		if not index or not PDCity.LAWS[index] then return end
		table.remove(PDCity.LAWS, index)

	elseif data.Action == "move_law" then
		local index = tonumber(data.Payload and data.Payload.Index)
		local dir = tonumber(data.Payload and data.Payload.Direction)
		if not index or not dir or not PDCity.LAWS[index] then return end

		local target = index + dir
		if not PDCity.LAWS[target] then return end

		PDCity.LAWS[index], PDCity.LAWS[target] = PDCity.LAWS[target], PDCity.LAWS[index]

	elseif data.Action == "set_rewards" then
		local p = data.Payload or {}
		for key in pairs(PDCity.LAW_REWARDS) do
			local value = tonumber(p[key])
			if value and value >= 0 then
				PDCity.LAW_REWARDS[key] = math.floor(value)
			end
		end

	else
		return
	end

	PDCity.GameLog("staff", ply:Nick() .. " (" .. ply:SteamID() .. ") changed the laws/jail-reward settings")
	SaveLawSettings()
	BroadcastLawSettings()
end)
