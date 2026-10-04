if CLIENT then return end

util.AddNetworkString("pdcity_toolgun_tools_sync")
util.AddNetworkString("pdcity_toolgun_tools_admin")

PDCity.TOOLGUN_TOOLS = PDCity.TOOLGUN_TOOLS or {}

local TOOLGUN_PATH = "pdcity/toolgun_tools.json"

local GMOD_TOOLS = {
	"axis", "balloon", "button", "cam", "colour", "dynamite", "elasticity",
	"eyeposer", "finger", "gravitgun", "hudcomposer", "lamp", "magnetic",
	"motor", "nail", "nocollide", "physprop", "pulley", "remover", "rope",
	"slider", "spring", "thrusters", "torch", "trails", "weight", "wheel",
	"weld", "winch"
}

local function SaveToolgunTools()
	file.CreateDir("pdcity")
	file.Write(TOOLGUN_PATH, util.TableToJSON(PDCity.TOOLGUN_TOOLS, true))
end

local function LoadToolgunTools()
	local raw = file.Read(TOOLGUN_PATH, "DATA")
	if not raw then return end

	local stored = util.JSONToTable(raw)
	if istable(stored) then
		PDCity.TOOLGUN_TOOLS = stored
	else
		PDCity.TOOLGUN_TOOLS = {}
	end
end

LoadToolgunTools()

function PDCity.GetAvailableTools()
	return GMOD_TOOLS
end

function PDCity.SyncToolgunTools(ply)
	net.Start("pdcity_toolgun_tools_sync")
		net.WriteString(util.TableToJSON(PDCity.TOOLGUN_TOOLS))
	if IsValid(ply) then net.Send(ply) else net.Broadcast() end
end

function PDCity.CanUseTool(ply, toolName)
	if not IsValid(ply) then return false end
	if not PDCity.TOOLGUN_TOOLS[toolName] then return true end

	local toolConfig = PDCity.TOOLGUN_TOOLS[toolName]

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

hook.Add("CanTool", "pdcity_ToolgunToolsAccess", function(ply, trace, tool)
	if tool == "gmod_tool" then
		local mode = ply:GetInfo("gmod_toolmode")
		if mode and mode ~= "" then
			if not PDCity.CanUseTool(ply, mode) then
				return false
			end
		end
	end
end)

net.Receive("pdcity_toolgun_tools_admin", function(len, ply)
	if not PDCity.IsOwner(ply) then return end

	local data = util.JSONToTable(net.ReadString() or "")
	if not istable(data) then return end

	PDCity.TOOLGUN_TOOLS = data
	SaveToolgunTools()
	PDCity.SyncToolgunTools()
end)

hook.Add("PlayerSpawn", "pdcity_ToolgunToolsSync", function(ply)
	PDCity.SyncToolgunTools(ply)
end)

hook.Add("PlayerInitialSpawn", "pdcity_ToolgunToolsSync", function(ply)
	PDCity.SyncToolgunTools(ply)
end)
