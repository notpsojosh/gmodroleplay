--[[---------------------------------------------------------
	Server-side hotkeys. Each player picks their own key for each
	action; the binding is stored in their profile (core/sv_keybinds.lua)
	so it follows them across sessions and map changes, and the server
	is what listens for the keypress - these aren't client console
	binds, so nothing can be spoofed by rebinding locally.

	Changed in-game from the F1 menu's "Keybinds" tab (cl_f1_menu.lua).

	Defaults are keys GMod leaves unbound out of the box, so a fresh
	player isn't fighting an existing bind on first join.
-----------------------------------------------------------]]

PDCity.KEYBINDS = {
	{
		ID = "thirdperson",
		Name = "Toggle third person",
		Default = KEY_N,
	},
	{
		ID = "noclip",
		Name = "Toggle noclip",
		Note = "Staff only",
		Default = KEY_M,
		StaffOnly = true,
	},
	{
		ID = "logs",
		Name = "Open server logs",
		Note = "Staff only",
		Default = KEY_L,
		StaffOnly = true,
	},
	{
		ID = "warrants",
		Name = "Open warrant requests",
		Note = "Only for whoever's configured as a warrant approver - see F1 Site Admin",
		Default = KEY_U,
	},
	{
		ID = "staffmenu",
		Name = "Open staff menu",
		Note = "Owner/superadmin only",
		Default = KEY_K,
		StaffOnly = true,
	},
	{
		ID = "carradio",
		Name = "Open car radio",
		Note = "Requires being in a vehicle to play a station",
		Default = KEY_J,
	},
}

function PDCity.GetKeybindDef(id)
	for _, def in ipairs(PDCity.KEYBINDS) do
		if def.ID == id then return def end
	end
end
