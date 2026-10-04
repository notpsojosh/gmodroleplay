--[[---------------------------------------------------------
	Restricts the Precision Tool's control panel to only show Move/Weld.
	The actual enforcement (blocking every other mode from functioning,
	even if set directly via console) lives in GM:CanTool in shared.lua -
	this is just keeping the panel from showing options that don't work.

	Wraps the tool's real BuildCPanel rather than replacing it, since we
	can't inspect the exact mounted workshop copy's internals (it's packed
	in a legacy format we can't extract) - this way whatever it actually
	builds stays intact, we just prune the mode list afterward.
-----------------------------------------------------------]]

local function StripDisallowedModes(panel)

	for _, child in ipairs(panel:GetChildren()) do

		if child.Lines and child.RemoveLine then

			for lineID, line in pairs(table.Copy(child.Lines)) do
				local text = line:GetColumnText(1) or ""
				if not text:find("Move") and not text:find("Weld") then
					child:RemoveLine(lineID)
				end
			end

		elseif child.GetChildren then
			StripDisallowedModes(child)
		end

	end

end

local function TryPatchPrecisionTool()

	local toolSwep = weapons.GetStored("gmod_tool")
	if not toolSwep or not toolSwep.Tool then return false end

	local precisionTool = toolSwep.Tool["precision"]
	if not precisionTool or not precisionTool.BuildCPanel then return false end
	if precisionTool.pdcity_Patched then return true end

	local originalBuildCPanel = precisionTool.BuildCPanel

	precisionTool.BuildCPanel = function(Panel)

		originalBuildCPanel(Panel)

		-- Corrections run here (panel-open time) rather than via an early
		-- cvars.AddChangeCallback, which used to fire RunConsoleCommand
		-- before the tool/player were fully ready and crashed inside the
		-- workshop tool's own precision_setuser handler
		-- (precision.lua:1573, GetInfoNum on a nil value) on every connect.
		local mode = LocalPlayer():GetInfoNum("precision_mode", 3)
		if mode ~= 3 and mode ~= 4 then
			RunConsoleCommand("precision_setmode", "3")
		end

		-- Keeps the "user level" pinned to Normal, so the tool's own existing
		-- logic hides the Advanced/Experimental tier entries (Adv Ballsocket,
		-- Slider, Parent, Repair) without us needing to reimplement that part.
		local userLevel = LocalPlayer():GetInfoNum("precision_user", 1)
		if userLevel ~= 1 then
			RunConsoleCommand("precision_setuser", "1")
		end

		StripDisallowedModes(Panel)

	end

	precisionTool.pdcity_Patched = true
	return true

end

if not TryPatchPrecisionTool() then
	timer.Create("pdcity_PatchPrecisionTool", 0.5, 20, function()
		if TryPatchPrecisionTool() then
			timer.Remove("pdcity_PatchPrecisionTool")
		end
	end)
end
