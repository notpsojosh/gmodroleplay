--[[---------------------------------------------------------
	Server side of the car radio: persistence, admin add/remove, and the
	actual play/stop requests. Playback state lives on the VEHICLE
	entity itself via NWVars - GMod already replicates those to every
	client that can see the entity, so there's no separate "tell
	everyone nearby" broadcast to write or keep in sync; a client just
	watches the vehicle's own NWInt (cl_radio_menu.lua).
-----------------------------------------------------------]]

local SAVE_PATH = "pdcity/radio_stations.json"

-- A handful of long-running public internet radio streams, seeded once
-- ever (same "only the very first time, never again" pattern
-- core/sv_f4_catalogue.lua uses for its own default items) so a fresh
-- server has something to pick from immediately, but removing/editing
-- any of these afterward sticks permanently like anything else here.
-- Every URL below was actually curl-checked (200 + audio/mpeg, or a
-- valid Icecast response) right before this list was written, not
-- assumed - a couple of originally-planned SomaFM channels ("thebridge",
-- "bagel") came back 404 and were dropped rather than included
-- unverified.
local DEFAULT_STATIONS = {
	{ ID = 1, Name = "SomaFM - Groove Salad", URL = "http://ice1.somafm.com/groovesalad-128-mp3" },
	{ ID = 2, Name = "SomaFM - Drone Zone", URL = "http://ice1.somafm.com/dronezone-128-mp3" },
	{ ID = 3, Name = "SomaFM - Indie Pop Rocks", URL = "http://ice1.somafm.com/indiepop-128-mp3" },
	{ ID = 4, Name = "Radio Paradise - Main Mix", URL = "http://stream.radioparadise.com/mp3-192" },
	{ ID = 5, Name = "SomaFM - Lush", URL = "http://ice1.somafm.com/lush-128-mp3" },
	{ ID = 6, Name = "SomaFM - Secret Agent", URL = "http://ice1.somafm.com/secretagent-128-mp3" },
	{ ID = 7, Name = "SomaFM - Space Station Soma", URL = "http://ice1.somafm.com/spacestation-128-mp3" },
	{ ID = 8, Name = "SomaFM - Deep Space One", URL = "http://ice1.somafm.com/deepspaceone-128-mp3" },
	{ ID = 9, Name = "SomaFM - Beat Blender", URL = "http://ice1.somafm.com/beatblender-128-mp3" },
	{ ID = 10, Name = "SomaFM - Suburbs of Goa", URL = "http://ice1.somafm.com/suburbsofgoa-128-mp3" },
	{ ID = 11, Name = "SomaFM - Boot Liquor", URL = "http://ice1.somafm.com/bootliquor-128-mp3" },
	{ ID = 12, Name = "SomaFM - Dub Step Beyond", URL = "http://ice1.somafm.com/dubstep-128-mp3" },
	{ ID = 13, Name = "SomaFM - Folk Forward", URL = "http://ice1.somafm.com/folkfwd-128-mp3" },
	{ ID = 14, Name = "SomaFM - Illinois Street Lounge", URL = "http://ice1.somafm.com/illstreet-128-mp3" },
	{ ID = 15, Name = "SomaFM - Metal", URL = "http://ice1.somafm.com/metal-128-mp3" },
	{ ID = 16, Name = "SomaFM - PopTron", URL = "http://ice1.somafm.com/poptron-128-mp3" },
	{ ID = 17, Name = "SomaFM - The Trip", URL = "http://ice1.somafm.com/thetrip-128-mp3" },
	{ ID = 18, Name = "SomaFM - Seven Inch Soul", URL = "http://ice1.somafm.com/7soul-128-mp3" },
	{ ID = 19, Name = "SomaFM - Sonic Universe", URL = "http://ice1.somafm.com/sonicuniverse-128-mp3" },
	{ ID = 20, Name = "SomaFM - Groove Salad Classic", URL = "http://ice1.somafm.com/gsclassic-128-mp3" },
	{ ID = 21, Name = "SomaFM - Digitalis", URL = "http://ice1.somafm.com/digitalis-128-mp3" },
	{ ID = 22, Name = "SomaFM - Doomed", URL = "http://ice1.somafm.com/doomed-128-mp3" },
	{ ID = 23, Name = "SomaFM - Underground 80s", URL = "http://ice1.somafm.com/u80s-128-mp3" },
	{ ID = 24, Name = "SomaFM - Covers", URL = "http://ice1.somafm.com/covers-128-mp3" },
	{ ID = 25, Name = "SomaFM - Reggae", URL = "http://ice1.somafm.com/reggae-128-mp3" },
	{ ID = 26, Name = "SomaFM - Left Coast 70s", URL = "http://ice1.somafm.com/seventies-128-mp3" },
	{ ID = 27, Name = "SomaFM - Cliqhop IDM", URL = "http://ice1.somafm.com/cliqhop-128-mp3" },
	{ ID = 28, Name = "SomaFM - Fluid", URL = "http://ice1.somafm.com/fluid-128-mp3" },
	{ ID = 29, Name = "SomaFM - Vaporwaves", URL = "http://ice1.somafm.com/vaporwaves-128-mp3" },
	{ ID = 30, Name = "SomaFM - Synphaera", URL = "http://ice1.somafm.com/synphaera-128-mp3" },
	{ ID = 31, Name = "SomaFM - Black Rock FM", URL = "http://ice1.somafm.com/brfm-128-mp3" },
	{ ID = 32, Name = "Radio Paradise - Mellow Mix", URL = "http://stream.radioparadise.com/mellow-192" },
	{ ID = 33, Name = "Radio Paradise - Rock Mix", URL = "http://stream.radioparadise.com/rock-192" },
	{ ID = 34, Name = "Radio Paradise - World Etc", URL = "http://stream.radioparadise.com/world-etc-192" },
}

local defaultsSeeded = false

local function SaveStations()
	file.CreateDir("pdcity")
	file.Write(SAVE_PATH, util.TableToJSON({
		Stations = PDCity.RADIO_STATIONS,
		DefaultsSeeded = defaultsSeeded,
	}, true))
end

local function LoadStations()
	local raw = file.Read(SAVE_PATH, "DATA")
	local data = raw and util.JSONToTable(raw)

	if raw and not data then
		ErrorNoHalt("[" .. PDCity.BRAND_TAG .. "] " .. SAVE_PATH .. " was unreadable - keeping the built-in defaults.\n")
		return
	end

	if data then
		if istable(data.Stations) then
			PDCity.RADIO_STATIONS = data.Stations
		end
		defaultsSeeded = data.DefaultsSeeded == true
	end

	if not defaultsSeeded then
		for _, station in ipairs(DEFAULT_STATIONS) do
			local already = false
			for _, existing in ipairs(PDCity.RADIO_STATIONS) do
				if existing.ID == station.ID then already = true break end
			end
			if not already then
				table.insert(PDCity.RADIO_STATIONS, table.Copy(station))
			end
		end

		defaultsSeeded = true
		SaveStations()
	end
end

LoadStations()

util.AddNetworkString("pdcity_radio_sync")
local function BroadcastStations(ply)
	net.Start("pdcity_radio_sync")
		net.WriteString(util.TableToJSON(PDCity.RADIO_STATIONS))
	if IsValid(ply) then
		net.Send(ply)
	else
		net.Broadcast()
	end
end

hook.Add("PlayerInitialSpawn", "pdcity_SyncRadioStations", function(ply)
	timer.Simple(1, function()
		if IsValid(ply) then BroadcastStations(ply) end
	end)
end)

--[[---------------------------------------------------------
	Admin add/remove - owner/staff only (matches the F4 catalogue's own
	gate), re-checked here regardless of what the client's UI already
	hides, same reasoning as everywhere else in this codebase.
-----------------------------------------------------------]]
util.AddNetworkString("pdcity_radio_admin")

net.Receive("pdcity_radio_admin", function(len, ply)
	if not IsValid(ply) or not PDCity.IsStaff(ply) then return end

	local data = util.JSONToTable(net.ReadString() or "")
	if not istable(data) or not isstring(data.Action) then return end

	if data.Action == "add" then
		local name = isstring(data.Name) and string.Trim(data.Name) or ""
		local url = isstring(data.URL) and string.Trim(data.URL) or ""

		if name == "" or url == "" then
			ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Give the station both a name and a URL.")
			return
		end

		if not (url:StartsWith("http://") or url:StartsWith("https://")) then
			ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Station URL has to start with http:// or https://.")
			return
		end

		local maxID = 0
		for _, station in ipairs(PDCity.RADIO_STATIONS) do
			if station.ID > maxID then maxID = station.ID end
		end

		table.insert(PDCity.RADIO_STATIONS, { ID = maxID + 1, Name = name, URL = url })

		PDCity.GameLog("staff", ply:Nick() .. " (" .. ply:SteamID() .. ") added radio station \"" .. name .. "\" (" .. url .. ")")

		SaveStations()
		BroadcastStations()
		return
	end

	if data.Action == "remove" then
		local id = tonumber(data.ID)
		for i, station in ipairs(PDCity.RADIO_STATIONS) do
			if station.ID == id then
				PDCity.GameLog("staff", ply:Nick() .. " (" .. ply:SteamID() .. ") removed radio station \"" .. station.Name .. "\"")
				table.remove(PDCity.RADIO_STATIONS, i)
				SaveStations()
				BroadcastStations()
				return
			end
		end
		return
	end
end)

--[[---------------------------------------------------------
	Play/stop. State lives on the vehicle entity itself (NWVars), which
	GMod already replicates to every client that can see it - a client
	just watches PDCity_RadioStation change (cl_radio_menu.lua) rather
	than this broadcasting a separate "now playing" message to everyone
	nearby every time someone changes the station.
-----------------------------------------------------------]]
util.AddNetworkString("pdcity_radio_play")
util.AddNetworkString("pdcity_radio_stop")

local function GetPlyVehicle(ply)
	local vehicle = ply:GetVehicle()
	if not IsValid(vehicle) then return nil end
	return vehicle
end

net.Receive("pdcity_radio_play", function(len, ply)
	if not IsValid(ply) or not ply:Alive() then return end

	local vehicle = GetPlyVehicle(ply)
	if not vehicle then
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] You need to be in a vehicle to use the radio.")
		return
	end

	local id = net.ReadUInt(16)
	local station = PDCity.GetRadioStation(id)
	if not station then return end

	vehicle:SetNWInt("PDCity_RadioStation", id)
	vehicle:SetNWFloat("PDCity_RadioStartTime", CurTime())
end)

net.Receive("pdcity_radio_stop", function(len, ply)
	if not IsValid(ply) or not ply:Alive() then return end

	local vehicle = GetPlyVehicle(ply)
	if not vehicle then return end

	vehicle:SetNWInt("PDCity_RadioStation", 0)
end)

-- A vehicle playing radio when it's removed (sold back, map cleanup,
-- ...) has nothing left to tell clients to stop with - GMod already
-- stops caring about NWVars on a removed entity, but the client's own
-- sound.PlayURL channel doesn't know that on its own (cl_radio_menu.lua
-- handles the actual stop client-side by noticing the entity's gone).
