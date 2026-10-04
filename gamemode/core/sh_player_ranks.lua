PDCity.PLAYER_RANKS = PDCity.PLAYER_RANKS or {
	{
		ID = "member",
		Name = "Member",
		Color = Color(100, 170, 255)
	},
	{
		ID = "supporter",
		Name = "Supporter",
		Color = Color(150, 220, 235)
	},
	{
		ID = "vip",
		Name = "VIP",
		Color = Color(255, 215, 0)
	},
	{
		ID = "mvp",
		Name = "MVP",
		Color = Color(255, 165, 0)
	}
}

local PLAYER_RANKS = {}

function PDCity.AddPlayerRank(id, name, color)
	table.insert(PDCity.PLAYER_RANKS, {
		ID = id,
		Name = name,
		Color = color or Color(255, 255, 255)
	})
end

function PDCity.GetPlayerRank(ply)
	if not IsValid(ply) then return nil end

	if SERVER then
		local profile = PDCity.GetProfile(ply)
		if profile and profile.Rank then
			return profile.Rank
		end
		return "member"
	else
		return ply:GetNWString("PDCity_PlayerRank", "member")
	end
end

function PDCity.SetPlayerRank(ply, rankID)
	if not IsValid(ply) or not SERVER then return end

	for _, rank in ipairs(PDCity.PLAYER_RANKS) do
		if rank.ID == rankID then
			ply:SetNWString("PDCity_PlayerRank", rankID)
			local profile = PDCity.GetProfile(ply)
			if profile then
				profile.Rank = rankID
				PDCity.MarkProfileDirty(ply)
			end
			return true
		end
	end
	return false
end

function PDCity.GetRankInfo(rankID)
	for _, rank in ipairs(PDCity.PLAYER_RANKS) do
		if rank.ID == rankID then
			return rank
		end
	end
	return nil
end

function PDCity.GetAllPlayerRanks()
	return PDCity.PLAYER_RANKS
end

if SERVER then
	util.AddNetworkString("pdcity_playerranks_sync")
	util.AddNetworkString("pdcity_playerranks_admin")

	local function SavePlayerRanks()
		file.CreateDir("pdcity")
		file.Write("pdcity/player_ranks.json", util.TableToJSON(PDCity.PLAYER_RANKS, true))
	end

	local function LoadPlayerRanks()
		local raw = file.Read("pdcity/player_ranks.json", "DATA")
		if raw then
			local stored = util.JSONToTable(raw)
			if istable(stored) then
				PDCity.PLAYER_RANKS = stored
			end
		end
	end

	LoadPlayerRanks()

	local function SyncPlayerRanks(ply)
		net.Start("pdcity_playerranks_sync")
			net.WriteString(util.TableToJSON(PDCity.PLAYER_RANKS))
		if IsValid(ply) then net.Send(ply) else net.Broadcast() end
	end

	net.Receive("pdcity_playerranks_admin", function(len, ply)
		if not PDCity.IsOwner(ply) then return end

		local data = util.JSONToTable(net.ReadString() or "")
		if not istable(data) then return end

		if data.Action == "add" then
			for _, rank in ipairs(PDCity.PLAYER_RANKS) do
				if rank.ID == data.ID then return end
			end

			table.insert(PDCity.PLAYER_RANKS, {
				ID = data.ID,
				Name = data.Name,
				Color = Color(data.Color.r or 255, data.Color.g or 255, data.Color.b or 255)
			})

		elseif data.Action == "edit" then
			for _, rank in ipairs(PDCity.PLAYER_RANKS) do
				if rank.ID == data.ID then
					rank.Name = data.Name
					if data.NewID and data.NewID ~= data.ID then
						rank.ID = data.NewID
						for _, p in ipairs(player.GetAll()) do
							local profile = PDCity.GetProfile(p)
							if profile and profile.Rank == data.ID then
								profile.Rank = data.NewID
							end
						end
					end
					rank.Color = Color(data.Color.r or 255, data.Color.g or 255, data.Color.b or 255)
					break
				end
			end

		elseif data.Action == "remove" then
			for i, rank in ipairs(PDCity.PLAYER_RANKS) do
				if rank.ID == data.ID then
					table.remove(PDCity.PLAYER_RANKS, i)
					for _, p in ipairs(player.GetAll()) do
						local profile = PDCity.GetProfile(p)
						if profile and profile.Rank == data.ID then
							profile.Rank = "member"
							PDCity.MarkProfileDirty(p)
						end
					end
					break
				end
			end
		end

		SavePlayerRanks()
		SyncPlayerRanks()
	end)

	hook.Add("PlayerInitialSpawn", "pdcity_SyncPlayerRank", function(ply)
		ply:SetNWString("PDCity_PlayerRank", PDCity.GetPlayerRank(ply))
		SyncPlayerRanks(ply)
	end)
end

if CLIENT then
	net.Receive("pdcity_playerranks_sync", function()
		local ranks = util.JSONToTable(net.ReadString() or "")
		if istable(ranks) then
			PDCity.PLAYER_RANKS = ranks
		end
	end)
end
