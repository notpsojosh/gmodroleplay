--[[---------------------------------------------------------
	Owner-only tool for setting the Staff Menu's jail "void" spot
	(core/sv_staff_jail_spot.lua) - where a superadmin's Jail action on
	the Staff Menu (cl_staff_menu.lua) sends someone. Meant to be
	somewhere outside the map's skybox/playable area, well away from
	anything a jailed player could interact with.

	  Left click   - set the spot to where you're aiming, facing the
	                 direction you're facing

	Separate from the Jail Spawn tool (pdcity_jailspawn.lua), which adds
	MULTIPLE in-map RP jail cell points for the arrest system - this is
	ONE fixed point for staff punishment instead.
-----------------------------------------------------------]]

TOOL.Category = "PD Roleplay"
TOOL.Name = "#tool.pdcity_staffjailspot.name"

TOOL.Information = {
	{ name = "left" },
}

if CLIENT then
	language.Add("tool.pdcity_staffjailspot.name", "Staff Jail Spot (Owner)")
	language.Add("tool.pdcity_staffjailspot.desc", "Set where the Staff Menu's Jail action sends someone")
	language.Add("tool.pdcity_staffjailspot.left", "Set the staff jail spot here")
end

local function CheckOwner(tool)
	local ply = tool:GetOwner()
	if PDCity.IsOwner(ply) then return true end
	if SERVER then ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Only the server owner can use the Staff Jail Spot tool.") end
	return false
end

function TOOL:LeftClick(trace)
	if not CheckOwner(self) then return false end
	if not trace.Hit then return false end
	if CLIENT then return true end

	local ply = self:GetOwner()
	local pos = trace.HitPos + Vector(0, 0, 4)
	local yaw = ply:EyeAngles().y

	PDCity.SetStaffJailSpot(pos, yaw)
	ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Staff jail spot set for this map.")
	return true
end

function TOOL.BuildCPanel(panel)
	panel:AddControl("Header", {
		Description = "Owner-only. Left click anywhere, facing the direction you want, to set where the Staff Menu's Jail action sends someone on THIS map - ideally somewhere outside the skybox, well away from anything they could reach. Per-map: a new map needs its own spot set before the Jail action works there.",
	})
end
