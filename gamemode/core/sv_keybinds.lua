--[[---------------------------------------------------------
	Server side of the per-player hotkeys (core/sh_keybinds.lua for the
	action list, cl_f1_menu.lua's "Keybinds" tab for the UI).

	Bindings are stored in the player's profile, so they persist across
	sessions, and the server is what watches for the keypress - the
	client never decides whether an action runs, it only says which key
	it would like to use.
-----------------------------------------------------------]]

util.AddNetworkString("pdcity_keybinds_sync")
util.AddNetworkString("pdcity_keybinds_set")
util.AddNetworkString("pdcity_keybinds_menu")

-- Normalises the account's keybind table in place, filling in the
-- default for any action the player has never set. Account-scoped, not
-- per-character - a key preference isn't a roleplay trait of one
-- specific character.
local function GetKeybinds(ply)
	local account = PDCity.GetAccount(ply)
	if not account then return nil end

	if not istable(account.Keybinds) then
		account.Keybinds = {}
	end

	for _, def in ipairs(PDCity.KEYBINDS) do
		if account.Keybinds[def.ID] == nil then
			account.Keybinds[def.ID] = def.Default
		end
	end

	return account.Keybinds
end

-- Exposed for anything outside this file that needs a player's chosen
-- key for one action WITHOUT going through the Actions dispatch below
-- (currently unused since the only consumer — siren hold-vs-tap — was
-- removed with the vehicle system).
function PDCity.GetPlayerKeybind(ply, id)
	local binds = GetKeybinds(ply)
	return binds and binds[id]
end

local function SyncKeybinds(ply)
	local binds = GetKeybinds(ply)
	if not binds then return end

	net.Start("pdcity_keybinds_sync")
		net.WriteString(util.TableToJSON(binds))
	net.Send(ply)
end

--[[---------------------------------------------------------
	The actions themselves
-----------------------------------------------------------]]

local Actions = {}

function Actions.thirdperson(ply)
	-- Reuses the existing toggle (core/sv_thirdperson.lua) so the key
	-- and "!tpp" end up doing exactly the same thing.
	net.Start("PDCity_ToggleThirdperson")
	net.Send(ply)
end

function Actions.logs(ply)
	-- Staff gate lives in PDCity.SendLogListing (core/sv_gamelog.lua) -
	-- a non-staff player pressing the key just gets nothing.
	PDCity.SendLogListing(ply, "")
end

function Actions.warrants(ply)
	-- Government gate lives in PDCity.SendWarrantList (core/sv_wanted.lua) -
	-- a non-eligible player pressing the key just gets the same chat
	-- denial the pdcity_warrants concommand gives.
	PDCity.SendWarrantList(ply)
end

function Actions.staffmenu(ply)
	-- Owner/superadmin gate lives client-side (cl_staff_menu.lua), same
	-- as the F1/F4 menus' own concommand relay (GM:ShowSpare2 in
	-- init.lua) - relayed via ConCommand rather than server-pushed data
	-- since the Staff Menu's contents (every connected player, their
	-- job/usergroup/moderation state) are already fully visible to the
	-- client with no extra networking needed. A non-eligible player
	-- pressing the key just opens nothing (or types the concommand
	-- directly - same thing, the real gate is server-side per ACTION in
	-- core/sv_staff_menu.lua, not this).
	ply:ConCommand("pdcity_staffmenu")
end

function Actions.carradio(ply)
	-- Same relay pattern as staffmenu above - the client already has
	-- the full station list synced (core/sv_radio.lua), so there's no
	-- server-pushed data needed here, just "open now".
	ply:ConCommand("pdcity_openradio")
end

function Actions.noclip(ply)
	local want = ply:GetMoveType() ~= MOVETYPE_NOCLIP

	-- Deliberately routed through the gamemode's own noclip rule
	-- (GM:PlayerNoClip in shared.lua) rather than re-checking the job
	-- here, so "who may noclip" stays defined in exactly one place -
	-- and the player still gets its explanatory chat message.
	if not GAMEMODE:PlayerNoClip(ply, want) then return end

	ply:SetMoveType(want and MOVETYPE_NOCLIP or MOVETYPE_WALK)
end

--[[---------------------------------------------------------
	Listening for the keys
-----------------------------------------------------------]]

hook.Add("PlayerButtonDown", "pdcity_Keybinds", function(ply, button)

	if not IsValid(ply) or not ply:Alive() then return end

	-- Don't fire while they're typing, or while the keybind menu is
	-- open - otherwise picking "M" as your noclip key also toggles
	-- noclip the moment you press it.
	if ply:IsTyping() then return end
	if ply.pdcity_KeybindMenuOpen then return end

	local binds = GetKeybinds(ply)
	if not binds then return end

	for id, key in pairs(binds) do
		if key == button and Actions[id] then
			Actions[id](ply)
			return
		end
	end

end)

--[[---------------------------------------------------------
	Client requests
-----------------------------------------------------------]]

net.Receive("pdcity_keybinds_set", function(len, ply)
	if not IsValid(ply) then return end

	local data = util.JSONToTable(net.ReadString() or "")
	if not istable(data) then return end

	local binds = GetKeybinds(ply)
	if not binds then return end

	for id, key in pairs(data) do
		-- Only known actions, and only real key enums (0 = unbound,
		-- KEY_LAST is 159). Anything else is ignored rather than stored.
		if PDCity.GetKeybindDef(id) and isnumber(key) and key >= 0 and key <= 159 then
			binds[id] = math.floor(key)
		end
	end

	PDCity.MarkAccountDirty(ply)
	SyncKeybinds(ply)
end)

-- Client tells us when the rebinding UI is open so we can ignore keys
-- while they're choosing one.
net.Receive("pdcity_keybinds_menu", function(len, ply)
	if not IsValid(ply) then return end
	ply.pdcity_KeybindMenuOpen = net.ReadBool()
end)

--[[---------------------------------------------------------
	Suppressing native game binds (weapon slots, reload, etc.) while ANY
	PD Roleplay menu is open - reported as "the game's other hotkeys
	activate" while typing in an admin panel's text fields.

	IsTyping() and the PDCity_KeybindMenuOpen flag above only ever
	gated OUR OWN custom keybind actions (Actions table above) - neither
	one touches the native engine bind system at all (weapon-slot keys
	in particular are notorious for firing regardless of vgui keyboard
	focus, since the client-side focus check that normally suppresses
	game input doesn't cover them the way it does movement/use). This is
	the actual, separate fix for that: PlayerBindPress fires server-side
	for every bind the client presses, INCLUDING ones vgui focus alone
	doesn't stop; returning true here cancels it outright.

	pdcity_AnyMenuOpen is set from cl_menu_dim.lua's own EnableDim/
	DisableDim - already the single source of truth for "is a PD
	Roleplay menu open right now" (every menu already pushes/pops it),
	so this needed no new client-side tracking of its own.
-----------------------------------------------------------]]

util.AddNetworkString("pdcity_menu_open_state")

net.Receive("pdcity_menu_open_state", function(len, ply)
	if not IsValid(ply) then return end
	ply.pdcity_AnyMenuOpen = net.ReadBool()
end)

-- F1/F4's own toggle binds are deliberately exempt - they're documented
-- elsewhere (cl_staff_menu.lua's own header) as bypassing normal vgui-
-- focus suppression ON PURPOSE, specifically so the SAME key that opened
-- a menu also closes it. Blanket-suppressing every bind here would have
-- newly broken that (pressing F1 again while F1, or the F4 Admin Editor
-- nested inside F4, is open would do nothing instead of closing it).
local EXEMPT_BINDS = {
	["gm_showhelp"] = true,  -- F1
	["gm_showspare2"] = true, -- F4
}

hook.Add("PlayerBindPress", "pdcity_SuppressBindsWhileMenuOpen", function(ply, bind, pressed)
	if ply.pdcity_AnyMenuOpen and not EXEMPT_BINDS[bind] then return true end
end)

hook.Add("PlayerInitialSpawn", "pdcity_SyncKeybinds", function(ply)
	if ply:IsBot() then return end
	timer.Simple(1, function()
		if IsValid(ply) then SyncKeybinds(ply) end
	end)
end)
