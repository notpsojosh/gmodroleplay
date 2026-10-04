--[[---------------------------------------------------------
	Server side of the F1 "Site Admin" panel (cl_site_admin.lua):
	persists core/sh_site_content.lua's PDCity.SITE_CONTENT to
	data/pdcity/site_content.json, validates every change, and
	broadcasts the result to all clients so the welcome screen and F1
	menu update live.

	Gated at PDCity.IsOwner specifically, not PDCity.IsStaff like the F4
	catalogue editor - this controls public-facing branding/marketing
	content (workshop link, welcome screen, news posts), not day-to-day
	shop management, so it stays at the same trust level as the F4
	editor's OWN role/whitelist-management actions. Every action re-checks
	this here regardless of what the client's UI already hides.
-----------------------------------------------------------]]

util.AddNetworkString("pdcity_site_sync")
util.AddNetworkString("pdcity_site_admin")

local SAVE_PATH = "pdcity/site_content.json"

local MAX_URL_LEN = 500
local MAX_TITLE_LEN = 80
local MAX_BODY_LEN = 1000
local MAX_BUTTON_LEN = 40
local MAX_IMAGE_LEN = 200
local MAX_POSTS = 100

local defaultsSeeded = false

local function SaveSiteContent()
	file.CreateDir("pdcity")
	file.Write(SAVE_PATH, util.TableToJSON({
		Content = PDCity.SITE_CONTENT,
		DefaultsSeeded = defaultsSeeded,
	}, true))
end

local function LoadSiteContent()
	local raw = file.Read(SAVE_PATH, "DATA")
	local data = raw and util.JSONToTable(raw)

	if raw and not data then
		ErrorNoHalt("[" .. PDCity.BRAND_TAG .. "] " .. SAVE_PATH .. " was unreadable - keeping the built-in defaults.\n")
		return
	end

	if data then
		if istable(data.Content) then
			if isstring(data.Content.WorkshopURL) then
				PDCity.SITE_CONTENT.WorkshopURL = data.Content.WorkshopURL
			end
			if istable(data.Content.WelcomeSteps) then
				for i = 1, 3 do
					local step = data.Content.WelcomeSteps[i]
					if istable(step) then
						PDCity.SITE_CONTENT.WelcomeSteps[i] = {
							Title = isstring(step.Title) and step.Title or "",
							Body = isstring(step.Body) and step.Body or "",
							Button = isstring(step.Button) and step.Button or "",
							Image = isstring(step.Image) and step.Image or "",
						}
					end
				end
			end
			if istable(data.Content.BlogPosts) then
				PDCity.SITE_CONTENT.BlogPosts = data.Content.BlogPosts
			end
		end
		defaultsSeeded = data.DefaultsSeeded == true
	end

	if not defaultsSeeded then
		defaultsSeeded = true
		SaveSiteContent()
	end
end
LoadSiteContent()

local function BroadcastSiteContent(ply)
	net.Start("pdcity_site_sync")
		net.WriteString(util.TableToJSON(PDCity.SITE_CONTENT))
	if IsValid(ply) then
		net.Send(ply)
	else
		net.Broadcast()
	end
end

hook.Add("PlayerInitialSpawn", "pdcity_SyncSiteContent", function(ply)
	timer.Simple(1, function()
		if IsValid(ply) then BroadcastSiteContent(ply) end
	end)
end)

--[[---------------------------------------------------------
	Admin actions
-----------------------------------------------------------]]

local function TrimTo(str, maxLen)
	str = isstring(str) and string.Trim(str) or ""
	if #str > maxLen then str = str:sub(1, maxLen) end
	return str
end

net.Receive("pdcity_site_admin", function(len, ply)
	if not IsValid(ply) or not PDCity.IsOwner(ply) then return end

	if len > 65530 then return end -- sanity cap before decoding

	local data = util.JSONToTable(net.ReadString() or "")
	if not istable(data) or not isstring(data.Action) then return end

	if data.Action == "set_workshop_url" then
		local url = TrimTo(data.URL, MAX_URL_LEN)
		if url == "" or not (url:StartsWith("http://") or url:StartsWith("https://")) then
			ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] The workshop URL has to start with http:// or https://.")
			return
		end

		PDCity.SITE_CONTENT.WorkshopURL = url
		PDCity.GameLog("staff", ply:Nick() .. " (" .. ply:SteamID() .. ") set the workshop URL to " .. url)
		SaveSiteContent()
		BroadcastSiteContent()
		return
	end

	if data.Action == "set_welcome_step" then
		local index = tonumber(data.Index)
		if not index or index < 1 or index > 3 then return end

		PDCity.SITE_CONTENT.WelcomeSteps[index] = {
			Title = TrimTo(data.Title, MAX_TITLE_LEN),
			Body = TrimTo(data.Body, MAX_BODY_LEN),
			Button = TrimTo(data.Button, MAX_BUTTON_LEN),
			Image = TrimTo(data.Image, MAX_IMAGE_LEN),
		}
		PDCity.GameLog("staff", ply:Nick() .. " (" .. ply:SteamID() .. ") edited welcome-screen box " .. index)
		SaveSiteContent()
		BroadcastSiteContent()
		return
	end

	if data.Action == "add_post" or data.Action == "edit_post" then
		local title = TrimTo(data.Title, MAX_TITLE_LEN)
		local body = TrimTo(data.Body, MAX_BODY_LEN)
		if title == "" or body == "" then
			ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] A post needs both a title and body.")
			return
		end

		local fields = {
			Title = title,
			Body = body,
			LinkText = TrimTo(data.LinkText, MAX_BUTTON_LEN),
			LinkURL = TrimTo(data.LinkURL, MAX_URL_LEN),
			Image = TrimTo(data.Image, MAX_IMAGE_LEN),
		}

		if data.Action == "add_post" then
			if #PDCity.SITE_CONTENT.BlogPosts >= MAX_POSTS then
				ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] That's the maximum number of posts (" .. MAX_POSTS .. ") - remove one first.")
				return
			end

			local maxID = 0
			for _, post in ipairs(PDCity.SITE_CONTENT.BlogPosts) do
				if post.ID > maxID then maxID = post.ID end
			end
			fields.ID = maxID + 1

			table.insert(PDCity.SITE_CONTENT.BlogPosts, 1, fields)
			PDCity.GameLog("staff", ply:Nick() .. " (" .. ply:SteamID() .. ") added F1 news post \"" .. title .. "\"")
		else
			local id = tonumber(data.ID)
			local found = false
			for i, post in ipairs(PDCity.SITE_CONTENT.BlogPosts) do
				if post.ID == id then
					fields.ID = id
					PDCity.SITE_CONTENT.BlogPosts[i] = fields
					found = true
					break
				end
			end
			if not found then return end
			PDCity.GameLog("staff", ply:Nick() .. " (" .. ply:SteamID() .. ") edited F1 news post \"" .. title .. "\"")
		end

		SaveSiteContent()
		BroadcastSiteContent()
		return
	end

	if data.Action == "remove_post" then
		local id = tonumber(data.ID)
		for i, post in ipairs(PDCity.SITE_CONTENT.BlogPosts) do
			if post.ID == id then
				PDCity.GameLog("staff", ply:Nick() .. " (" .. ply:SteamID() .. ") removed F1 news post \"" .. post.Title .. "\"")
				table.remove(PDCity.SITE_CONTENT.BlogPosts, i)
				SaveSiteContent()
				BroadcastSiteContent()
				return
			end
		end
		return
	end

	if data.Action == "reorder_posts" then
		if not istable(data.Order) or #data.Order ~= #PDCity.SITE_CONTENT.BlogPosts then return end

		local byID = {}
		for _, post in ipairs(PDCity.SITE_CONTENT.BlogPosts) do byID[post.ID] = post end

		local newOrder = {}
		for _, id in ipairs(data.Order) do
			local post = byID[tonumber(id)]
			if not post then return end -- unknown ID in the list, reject the whole reorder
			table.insert(newOrder, post)
		end

		PDCity.SITE_CONTENT.BlogPosts = newOrder
		SaveSiteContent()
		BroadcastSiteContent()
		return
	end
end)
