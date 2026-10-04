--[[---------------------------------------------------------
	Named Interfaces - a client-side registry any addon file in this
	gamemode can add a menu to (PDCity.RegisterInterface below), and the
	Flowchart's "Open Interface" node (core/sv_activities.lua) can then
	open by name for whichever player triggered that flow, with no
	further wiring per-interface. Nothing builds these in-game yet (that's
	planned - an in-game interface builder, same spirit as the Flowchart
	itself) - for now they're plain Lua, registered here or in any other
	cl_ file, same shape a hand-written menu would already use.

	Registering one is exactly:
		PDCity.RegisterInterface("My Menu", function(ent, ply)
			-- build and open whatever DFrame/etc you want, same as any
			-- other menu in this gamemode (cl_theme.lua's helpers, etc.)
		end)

	`ent` is the entity that triggered the flow (may be invalid if it's
	since been removed - e.g. a "Remove This Entity" node earlier in the
	same chain), `ply` is always LocalPlayer().
-----------------------------------------------------------]]

PDCity.INTERFACES = PDCity.INTERFACES or {} -- [name] = function(ent, ply)

function PDCity.RegisterInterface(name, buildFn)
	if not isstring(name) or name == "" or not isfunction(buildFn) then return end
	PDCity.INTERFACES[name] = buildFn
end

function PDCity.GetInterfaceNames()
	local names = {}
	for name in pairs(PDCity.INTERFACES) do table.insert(names, name) end
	table.sort(names)
	return names
end

--[[---------------------------------------------------------
	Picker popup - the Flowchart's "Open Interface" node (cl_flow_editor.lua)
	uses this instead of a raw text entry, same "pick, don't type" idea as
	PDCity.OpenEntityClassPicker (cl_f4_admin.lua). Just a plain list, not
	a grid - interfaces have no model/icon to show, only a name.
-----------------------------------------------------------]]
function PDCity.OpenInterfacePicker(onPick)

	local frame = PDCity.OpenPicker("Choose an Interface", 380, 420)

	local top = 48

	local names = PDCity.GetInterfaceNames()

	local scroll = vgui.Create("DScrollPanel", frame)
	scroll:SetPos(16, top + 10)
	scroll:SetSize(348, frame:GetTall() - top - 26)
	PDCity.ApplyFastScroll(scroll)

	if #names == 0 then
		local empty = vgui.Create("DLabel", scroll)
		empty:Dock(TOP)
		empty:SetTall(40)
		empty:SetFont("PDCity_Small")
		empty:SetWrap(true)
		empty:SetText("No interfaces registered yet - see cl_interfaces.lua's own header for how to add one.")
		empty:SetTextColor(PDCity.THEME.TextDim)
	end

	for _, name in ipairs(names) do
		local btn = vgui.Create("DButton", scroll)
		btn:Dock(TOP)
		btn:SetTall(32)
		btn:DockMargin(0, 0, 0, 6)
		PDCity.StyleButton(btn, name, { Accent = PDCity.THEME.Panel, AccentDim = PDCity.THEME.PanelHover, TextColor = PDCity.THEME.Text })
		btn.DoClick = function()
			onPick(name)
			frame:Close()
		end
	end

end

net.Receive("pdcity_open_interface", function()
	local name = net.ReadString()
	local ent = net.ReadEntity()

	local buildFn = PDCity.INTERFACES[name]
	if not buildFn then
		-- Loud, not silent - "Open Interface" pointing at a name nothing
		-- registered is a config mistake (a typo, or the interface was
		-- renamed/removed) the owner testing their own flow needs to see,
		-- same reasoning as core/sv_activities.lua's own code-tag gate.
		ErrorNoHalt("[" .. PDCity.BRAND_TAG .. "] A Flowchart tried to open interface \"" .. tostring(name) .. "\", but nothing's registered under that name.\n")
		return
	end

	buildFn(ent, LocalPlayer())
end)
