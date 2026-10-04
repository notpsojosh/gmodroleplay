include("shared.lua")
include("doors/cl_config.lua")
include("doors/cl_doors.lua")
include("cl_spawnmenu.lua")
include("cl_notice.lua")
include("cl_toast.lua")
include("cl_hints.lua")
include("cl_worldtips.lua")
include("cl_menu_dim.lua")
include("cl_search_models.lua")
include("gui/IconEditor.lua")
include("cl_theme.lua")
include("cl_site_theme.lua")
include("cl_accessibility.lua") -- after cl_site_theme.lua: wraps PDCity.ApplySiteTheme
include("cl_weapon_selection.lua")
include("cl_character_select.lua")
include("cl_character_admin.lua")
include("cl_character_models_admin.lua")
include("cl_currencies.lua")
include("cl_hud_card.lua")
include("cl_hud_editor.lua")
include("cl_site_theme_editor.lua")
include("cl_rules.lua") -- before cl_f1_menu.lua: it calls PDCity.BuildRulesTab
include("cl_f1_menu.lua")
include("cl_f4_menu.lua")
include("cl_staff_menu.lua")
include("cl_precision_restrict.lua")
include("cl_give_confirm.lua")
include("cl_thirdperson.lua")
include("cl_arrest_menu.lua")
include("cl_warrant_request.lua")
include("cl_warrant_approval.lua")
include("cl_jail_hud.lua")
include("cl_bail_menu.lua")
include("cl_printer_menu.lua")
include("cl_f4_admin.lua")
include("cl_site_admin.lua")
include("cl_whitelist_menu.lua")
include("cl_radio_menu.lua")
include("cl_inventory.lua")
include("cl_weapon_safety.lua")
include("cl_scoreboard.lua")
include("cl_tickets.lua")
include("cl_dev_console.lua")
include("cl_flow_editor.lua")
include("cl_flow_wait_hud.lua")
include("cl_interfaces.lua")
include("cl_custom_props.lua")
include("cl_entity_labels.lua")
include("cl_xp_crate_menu.lua")
include("cl_welcome.lua")
include("cl_logviewer.lua")
include("cl_chat.lua")
include("cl_respawn.lua")
include("cl_voice.lua")

function GM:Initialize()
    print("[" .. PDCity.BRAND_TAG .. "] Client Initialize")
end

function GM:LimitHit(name)
    local str = "#SBoxLimit_" .. name
    local translated = language.GetPhrase(str)
    if str == translated then
        translated = string.format(language.GetPhrase("hint.hitXlimit"), language.GetPhrase(name))
    end

    self:AddNotify(translated, NOTIFY_ERROR, 6)
    surface.PlaySound("buttons/button10.wav")
end

function GM:OnUndo(name, strCustomString)
    local text = strCustomString

    if not text then
        local strId = "#Undone_" .. name
        text = language.GetPhrase(strId)
        if strId == text then
            text = string.format(language.GetPhrase("hint.undoneX"), language.GetPhrase(name))
        end
    end

    self:AddNotify(text, NOTIFY_UNDO, 2)
    surface.PlaySound("buttons/button15.wav")
end

function GM:HUDPaint()
    local ply = LocalPlayer()
    if not IsValid(ply) then return end

    draw.SimpleText("Props: " .. ply:GetCount("props") .. " / " .. PDCity.MAX_PROPS, "DermaDefault", 10, 10, color_white)
end