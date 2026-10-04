--[[---------------------------------------------------------
	Support ticket system - !report, !support, and !ticket all open the
	same client UI (cl_tickets.lua): a "Submit" tab everyone gets, plus a
	"Tickets" tab only staff see, listing everything anyone's submitted.

	Persisted to data/pdcity/tickets.json (same file.Write/util.TableToJSON
	pattern as core/sv_restrictions.lua's prop_overrides.json) so the
	queue survives a restart - a ticket sent while no admin is online
	would otherwise just vanish.

	Status is "open" (unseen, the default), "in_progress", or "resolved" -
	set by any staff member from the Tickets tab. Every status change runs
	through hook.Run("PDCity_TicketStatusChanged", ...), and a change INTO
	"resolved" additionally runs hook.Run("PDCity_TicketResolved", ...) -
	both plain hooks, not functions to call directly, so anything added
	later (a staff reward system was mentioned as a "maybe eventually")
	can hook.Add onto either without this file ever needing to change.
-----------------------------------------------------------]]

local TICKETS_PATH = "pdcity/tickets.json"
local MAX_MESSAGE_LENGTH = 512

local Tickets = {}
local NextID = 1

local function Save()
	file.CreateDir("pdcity")
	file.Write(TICKETS_PATH, util.TableToJSON({
		Tickets = Tickets,
		NextID = NextID,
	}, true))
end

do
	local raw = file.Read(TICKETS_PATH, "DATA")
	local stored = raw and util.JSONToTable(raw)
	if stored then
		Tickets = stored.Tickets or {}
		NextID = stored.NextID or 1
	end
end

local function D(ply)
	if not IsValid(ply) or not ply:IsPlayer() then return "<unknown>" end
	return ply:Nick() .. " (" .. ply:SteamID() .. ")"
end

local function FindTicket(id)
	for _, ticket in ipairs(Tickets) do
		if ticket.ID == id then return ticket end
	end
end

--[[---------------------------------------------------------
	Networking
-----------------------------------------------------------]]

util.AddNetworkString("pdcity_ticket_open")
util.AddNetworkString("pdcity_ticket_submit")
util.AddNetworkString("pdcity_ticket_list")
util.AddNetworkString("pdcity_ticket_listing")
util.AddNetworkString("pdcity_ticket_setstatus")
util.AddNetworkString("pdcity_ticket_alert")

local function SendListing(ply)
	net.Start("pdcity_ticket_listing")
		net.WriteString(util.TableToJSON(Tickets))
	net.Send(ply)
end

-- Pings every currently-online staff member's Tickets tab (if open) to
-- refresh, and drops a chat line for a brand new ticket specifically -
-- a status change doesn't need shouting at everyone the way a fresh
-- report does.
local function AlertStaff(chatLine)
	for _, ply in ipairs(player.GetAll()) do
		if PDCity.IsStaff(ply) then
			if chatLine then ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] " .. chatLine) end
			net.Start("pdcity_ticket_alert")
			net.Send(ply)
		end
	end
end

--[[---------------------------------------------------------
	Submit - anyone, rate-limited implicitly by nothing (a flood of junk
	tickets is a moderation problem, not something worth over-engineering
	a cooldown for up front).
-----------------------------------------------------------]]

function PDCity.SubmitTicket(ply, message)
	if not IsValid(ply) or not ply:IsPlayer() then return false, "Invalid player." end

	message = string.Trim(message or "")
	if message == "" then return false, "Enter a message first." end
	if #message > MAX_MESSAGE_LENGTH then
		message = string.sub(message, 1, MAX_MESSAGE_LENGTH)
	end

	local ticket = {
		ID = NextID,
		SteamID = ply:SteamID(),
		Name = PDCity.GetDisplayName(ply),
		Message = message,
		Status = "open",
		CreatedAt = os.time(),
		UpdatedAt = os.time(),
	}
	NextID = NextID + 1

	Tickets[#Tickets + 1] = ticket
	Save()

	PDCity.GameLog("tickets", D(ply) .. " opened ticket #" .. ticket.ID .. ": " .. message)
	AlertStaff(D(ply) .. " opened a new support ticket (#" .. ticket.ID .. ") - check the Tickets tab (!ticket).")

	hook.Run("PDCity_TicketCreated", ticket)

	ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Ticket #" .. ticket.ID .. " submitted - staff have been notified.")

	return true, ticket
end

net.Receive("pdcity_ticket_submit", function(len, ply)
	PDCity.SubmitTicket(ply, net.ReadString())
end)

--[[---------------------------------------------------------
	Staff: list and set status
-----------------------------------------------------------]]

net.Receive("pdcity_ticket_list", function(len, ply)
	if not IsValid(ply) or not PDCity.IsStaff(ply) then return end
	SendListing(ply)
end)

local VALID_STATUSES = { open = true, in_progress = true, resolved = true }

function PDCity.SetTicketStatus(ply, id, status)
	if not IsValid(ply) or not PDCity.IsStaff(ply) then return false, "Staff only." end
	if not VALID_STATUSES[status] then return false, "Invalid status." end

	local ticket = FindTicket(id)
	if not ticket then return false, "No such ticket." end

	local oldStatus = ticket.Status
	if oldStatus == status then return true, ticket end

	ticket.Status = status
	ticket.UpdatedAt = os.time()

	if status == "resolved" then
		ticket.ResolvedBy = ply:SteamID()
		ticket.ResolvedByName = PDCity.GetDisplayName(ply)
	end

	Save()

	PDCity.GameLog("tickets", D(ply) .. " set ticket #" .. id .. " to " .. status)
	AlertStaff()

	hook.Run("PDCity_TicketStatusChanged", ticket, oldStatus, status, ply)
	if status == "resolved" then
		hook.Run("PDCity_TicketResolved", ticket, ply)
	end

	-- Let the original submitter know if they're still connected -
	-- SteamID, not an entity reference (they may have reconnected since).
	for _, target in ipairs(player.GetAll()) do
		if target:SteamID() == ticket.SteamID then
			target:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Your ticket #" .. id .. " is now: " .. status:gsub("_", " "))
			break
		end
	end

	return true, ticket
end

net.Receive("pdcity_ticket_setstatus", function(len, ply)
	local id = net.ReadUInt(32)
	local status = net.ReadString()
	PDCity.SetTicketStatus(ply, id, status)
end)

--[[---------------------------------------------------------
	!report, !support, !ticket - all open the same client UI.
	Default priority (not HOOK_HIGH like sv_chat.lua's own handler): every
	"!"-prefixed message already passes straight through that handler
	untouched, same as every other "!"-command in the gamemode.
-----------------------------------------------------------]]

hook.Add("PlayerSay", "pdcity_TicketChatCommand", function(ply, text)
	local cmd = string.lower(string.Trim(text))
	if cmd ~= "!report" and cmd ~= "!support" and cmd ~= "!ticket" then return end

	net.Start("pdcity_ticket_open")
	net.Send(ply)

	return ""
end)
