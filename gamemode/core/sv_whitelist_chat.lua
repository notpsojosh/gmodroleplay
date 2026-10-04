--[[---------------------------------------------------------
	"!whitelist" chat command - opens the department whitelist/blacklist
	panel (cl_whitelist_menu.lua) for anyone who can actually manage at
	least one department (core/sv_whitelist.lua's PDCity.CanManageDepartment -
	their own level 6+ in a whitelist-only category, or superadmin/owner).
	Same minimal PlayerSay pattern as core/sv_thirdperson.lua's "!tpp" -
	its own header comment explains why this can't live in core/sv_chat.lua
	itself (that file explicitly defers every "!"-prefixed message to
	separate hooks like this one).
-----------------------------------------------------------]]

local function CanManageAnyDepartment(ply)
	if PDCity.IsSuperAdminPlus(ply) then return true end

	for _, section in ipairs(PDCity.SECTIONS) do
		if PDCity.IsSectionWhitelistOnly(section) and PDCity.CanManageDepartment(ply, section) then
			return true
		end
	end

	return false
end

hook.Add("PlayerSay", "pdcity_WhitelistChatCommand", function(ply, text)
	if string.lower(string.Trim(text)) ~= "!whitelist" then return end

	if not CanManageAnyDepartment(ply) then
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] You don't have whitelist access to any department.")
		return ""
	end

	PDCity.OpenWhitelistPanelFor(ply)
	return ""
end)
