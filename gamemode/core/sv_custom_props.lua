--[[---------------------------------------------------------
	Server side of Custom Props (core/sh_custom_props.lua): persistence,
	the Prop Copier tool's own creation request, and re-registering every
	saved definition's dynamic entity class on boot (scripted_ents
	registrations don't survive a restart on their own).
-----------------------------------------------------------]]

util.AddNetworkString("pdcity_customprop_sync")
util.AddNetworkString("pdcity_customprop_create")
util.AddNetworkString("pdcity_customprop_remove")

local PROPS_PATH = "pdcity/custom_props.json"
local nextPropID = 1

local function SaveCustomProps()
	file.CreateDir("pdcity")
	file.Write(PROPS_PATH, util.TableToJSON({
		Props = PDCity.CUSTOM_PROPS,
		NextID = nextPropID,
	}, true))
end

local function LoadCustomProps()
	local raw = file.Read(PROPS_PATH, "DATA")
	if not raw then return end

	local data = util.JSONToTable(raw)
	if not data then
		ErrorNoHalt("[" .. PDCity.BRAND_TAG .. "] " .. PROPS_PATH .. " was unreadable - keeping the built-in defaults.\n")
		return
	end

	if istable(data.Props) then PDCity.CUSTOM_PROPS = data.Props end
	if isnumber(data.NextID) then nextPropID = math.max(nextPropID, data.NextID) end

	for _, def in ipairs(PDCity.CUSTOM_PROPS) do
		PDCity.RegisterCustomPropClass(def)
	end
end

LoadCustomProps()

local function BroadcastCustomProps(ply)
	net.Start("pdcity_customprop_sync")
		net.WriteString(util.TableToJSON(PDCity.CUSTOM_PROPS))
	if IsValid(ply) then
		net.Send(ply)
	else
		net.Broadcast()
	end
end

hook.Add("PlayerInitialSpawn", "pdcity_SyncCustomProps", function(ply)
	BroadcastCustomProps(ply)
end)

-- Sent by the Prop Copier tool (entities/weapons/gmod_tool/stools/pdcity_propcopier.lua)
-- after the owner picks a model (by clicking an existing prop) and
-- types a name. Owner-only, same as every other content-creation action
-- in this gamemode.
net.Receive("pdcity_customprop_create", function(len, ply)
	if not PDCity.IsOwner(ply) then return end

	local name = string.Trim(net.ReadString() or "")
	local model = net.ReadString()

	if name == "" then
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Name can't be empty.")
		return
	end
	if not util.IsValidModel(model) then
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Not a recognised model.")
		return
	end

	local def = { ID = nextPropID, Name = name, Model = model }
	nextPropID = nextPropID + 1

	table.insert(PDCity.CUSTOM_PROPS, def)
	PDCity.RegisterCustomPropClass(def)
	SaveCustomProps()
	BroadcastCustomProps()

	PDCity.GameLog("staff", ply:Nick() .. " (" .. ply:SteamID() .. ") created custom prop \"" .. name .. "\" ("
		.. PDCity.CustomPropClass(def.ID) .. ", model " .. model .. ")")

	ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Created \"" .. name .. "\" - spawnable from the Q menu's \"PD Roleplay (Custom)\" category, or add it to the F4 shop / a Job Activity using its class: " .. PDCity.CustomPropClass(def.ID))
end)

-- Removes a DEFINITION - not a placed instance (those are ordinary
-- entities by this point, remove them with the normal remover tool like
-- anything else). Existing instances already in the world keep working
-- until the next restart (their class stays registered for the rest of
-- this server session) but won't be spawnable again after that, since
-- LoadCustomProps above won't re-register a definition that's gone.
net.Receive("pdcity_customprop_remove", function(len, ply)
	if not PDCity.IsOwner(ply) then return end

	local id = net.ReadUInt(32)
	for i, def in ipairs(PDCity.CUSTOM_PROPS) do
		if def.ID == id then
			table.remove(PDCity.CUSTOM_PROPS, i)
			SaveCustomProps()
			BroadcastCustomProps()
			ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Removed \"" .. def.Name .. "\" - it'll stop being spawnable after the next restart.")
			return
		end
	end
end)
