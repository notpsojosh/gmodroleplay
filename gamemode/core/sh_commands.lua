PDCity.COMMANDS = PDCity.COMMANDS or {}

function PDCity.RegisterCommand(category, command, description)
	if not PDCity.COMMANDS[category] then
		PDCity.COMMANDS[category] = {}
	end

	table.insert(PDCity.COMMANDS[category], {
		Command = command,
		Description = description
	})
end

if CLIENT then
	function PDCity.GetCommands()
		return PDCity.COMMANDS
	end
end

if SERVER then

	PDCity.RegisterCommand("Chat", "/ooc <message>", "Global out-of-character chat")
	PDCity.RegisterCommand("Chat", "// <message>", "Global out-of-character chat (shorthand)")
	PDCity.RegisterCommand("Chat", "/pm <name> <message>", "Private message a player")
	PDCity.RegisterCommand("Chat", "/r <message>", "Reply to last PM")
	PDCity.RegisterCommand("Chat", "/advert <message>", "Global advertisement")
	PDCity.RegisterCommand("Chat", "/dwa <message>", "Dark web advert (criminals + staff only)")

	PDCity.RegisterCommand("Character", "/name <name>", "Set your roleplay character name")
	PDCity.RegisterCommand("Character", "/rpname <name>", "Set your roleplay character name")
	PDCity.RegisterCommand("Character", "/n <name>", "Set your roleplay character name (shorthand)")

	PDCity.RegisterCommand("Voice", "/voicearound", "Toggle voice chat to local only")
	PDCity.RegisterCommand("Voice", "/voiceglobal", "Toggle voice chat to global")

	PDCity.RegisterCommand("Admin", "!kick <player>", "Kick a player from the server (staff)")
	PDCity.RegisterCommand("Admin", "!ban <player> [reason]", "Ban a player from the server (staff)")
	PDCity.RegisterCommand("Admin", "!mute <player>", "Mute a player's chat (staff)")
	PDCity.RegisterCommand("Admin", "!unmute <player>", "Unmute a player's chat (staff)")
	PDCity.RegisterCommand("Admin", "!forcename <player> <name>", "Force rename a player (staff)")
	PDCity.RegisterCommand("Admin", "!slay <player>", "Kill a player (staff)")
	PDCity.RegisterCommand("Admin", "!revive <player>", "Revive a dead player (staff)")
	PDCity.RegisterCommand("Admin", "!teleport <player> [destination]", "Teleport player (staff)")
	PDCity.RegisterCommand("Admin", "!noclip", "Toggle noclip mode (staff)")
	PDCity.RegisterCommand("Admin", "!goto <player>", "Teleport to a player (staff)")
	PDCity.RegisterCommand("Admin", "!bring <player>", "Bring a player to you (staff)")
	PDCity.RegisterCommand("Admin", "!freeze <player>", "Freeze a player in place (staff)")
	PDCity.RegisterCommand("Admin", "!unfreeze <player>", "Unfreeze a player (staff)")
	PDCity.RegisterCommand("Admin", "!jail <player> [time]", "Jail a player (staff)")
	PDCity.RegisterCommand("Admin", "!unjail <player>", "Release a jailed player (staff)")
	PDCity.RegisterCommand("Admin", "!warn <player> <reason>", "Warn a player (staff)")

	net.Receive("pdcity_commands_request", function(len, ply)
		net.Start("pdcity_commands_sync")
			net.WriteString(util.TableToJSON(PDCity.COMMANDS))
		net.Send(ply)
	end)

	util.AddNetworkString("pdcity_commands_request")
	util.AddNetworkString("pdcity_commands_sync")
end
