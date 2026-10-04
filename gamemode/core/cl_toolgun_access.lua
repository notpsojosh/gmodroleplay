if SERVER then return end

PDCity.TOOLGUN_TOOLS_CACHE = {}

net.Receive("pdcity_toolgun_tools_sync", function()
	local tools = util.JSONToTable(net.ReadString() or "")
	if istable(tools) then
		PDCity.TOOLGUN_TOOLS_CACHE = tools
	end
end)

function PDCity.CanUseTool(toolName)
	local ply = LocalPlayer()
	if not IsValid(ply) then return false end

	local tools = PDCity.TOOLGUN_TOOLS_CACHE
	if not tools[toolName] then return true end

	local toolConfig = tools[toolName]

	if toolConfig.Enabled == false then
		return false
	end

	if not toolConfig.AccessMode or toolConfig.AccessMode == "everyone" then
		return true
	end

	local steamID = ply:SteamID()

	if toolConfig.AccessMode == "whitelist" then
		if not toolConfig.Whitelist then return false end

		for _, entry in ipairs(toolConfig.Whitelist) do
			if entry.Type == "steamid" and entry.Value == steamID then
				return true
			elseif entry.Type == "rank" and PDCity.GetPlayerRank(ply) == entry.Value then
				return true
			elseif entry.Type == "staff" and PDCity.IsStaff(ply) then
				return true
			end
		end
		return false
	end

	if toolConfig.AccessMode == "blacklist" then
		if not toolConfig.Blacklist then return true end

		for _, entry in ipairs(toolConfig.Blacklist) do
			if entry.Type == "steamid" and entry.Value == steamID then
				return false
			elseif entry.Type == "rank" and PDCity.GetPlayerRank(ply) == entry.Value then
				return false
			end
		end
		return true
	end

	return true
end
