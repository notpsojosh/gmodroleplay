-- The gamemode's single global table: every function, setting and data
-- table lives inside it (PDCity.GetJob, PDCity.THEME, ...). Created here,
-- first, since both init.lua and cl_init.lua include this file before
-- anything else that uses it.
PDCity = PDCity or {}

include("core/sh_brand.lua")
include("player_extension.lua")
include("persistence.lua")
include("save_load.lua")
include("core/sh_permissions.lua")
-- Door system (doors/, MIT-licensed Universal Door System by OPGman,
-- modified - see doors/LICENSE). Before core/sh_door_factions.lua,
-- which registers into its DoorRestrictions table.
include("doors/sh_config.lua")
include("doors/sh_doors.lua")
include("core/sh_rpname.lua")
include("core/sh_jobs.lua")
include("core/sh_job_catalogue.lua")
include("core/sh_whitelist.lua")
include("core/sh_door_factions.lua")
include("core/sh_f4_entities.lua")
include("core/sh_f4_catalogue.lua")
include("core/sh_activities.lua")
include("core/sh_custom_props.lua")
include("core/sh_inventory.lua")
include("core/sh_physgun_whitelist.lua")
include("core/sh_weapon_safety.lua")
include("core/sh_keybinds.lua")
include("core/sh_radio.lua")
include("core/sh_voice.lua")
include("core/sh_xp.lua")
include("core/sh_job_perks.lua")
include("core/sh_job_xp.lua")
include("core/sh_laws.lua")
include("core/sh_rules.lua")
include("core/sh_site_content.lua")
include("core/sh_warrant_perms.lua")
include("core/sh_xp_settings.lua")
include("core/sh_prop_filter.lua")
include("core/sh_npc_classes.lua")
include("core/sh_currencies.lua")
include("core/sh_hud_settings.lua")
include("player_class/player_sandbox.lua")
include("drive/drive_sandbox.lua")
include("editor_player.lua")
include("core/sh_player_spawn.lua")

-- Shared so the client can display the same limit the server enforces (see core/sv_limits.lua)
PDCity.MAX_PROPS = 75

GM.Name = PDCity.BRAND_NAME
GM.Author = "You"
GM.Email = ""
GM.Website = ""

function GM:Initialize()
    print("[" .. PDCity.BRAND_TAG .. "] Shared Initialize")
end

cleanup.Register("props")
cleanup.Register("ragdolls")
cleanup.Register("effects")
cleanup.Register("npcs")
cleanup.Register("constraints")
cleanup.Register("ropeconstraints")
cleanup.Register("sents")

local physgun_limited = CreateConVar("physgun_limited", "0", FCVAR_REPLICATED, "Prevent the Physics Gun from picking up certain map entities.")

function GM:CanTool(ply, trace, mode, tool, button)

    if (mode == "physprop" and trace.Entity:IsValid()) then
        return false
    end

    -- Precision Tool: only Move (3) and Weld (4) modes are allowed. Checked
    -- here (not just hidden in the UI) since precision_mode is a plain
    -- client convar a player could otherwise set directly via console,
    -- bypassing whatever the control panel shows.
    if (mode == "precision") then
        local precisionMode = ply:GetInfoNum("precision_mode", 1)
        if (precisionMode ~= 3 and precisionMode ~= 4) then
            return false
        end
    end

    if (trace.Entity.m_tblToolsAllowed) then

        local vFound = false
        for k, v in pairs(trace.Entity.m_tblToolsAllowed) do
            if (mode == v) then vFound = true end
        end

        if (!vFound) then return false end

    end

    if (trace.Entity.CanTool) then
        return trace.Entity:CanTool(ply, trace, mode, tool, button)
    end

    return true

end

function GM:GravGunPunt(ply, ent)

    if (ent:IsValid() and ent.GravGunPunt) then
        return ent:GravGunPunt(ply)
    end

    -- No BaseClass to fall back to - this gamemode doesn't derive from
    -- one (see the rest of this session's "restore stock defaults"
    -- files). Base gamemode's own default is a flat "return true"
    -- (gamemodes/base/gamemode/gravitygun.lua), so that's what happens
    -- when the entity doesn't have its own override.
    return true

end

function GM:GravGunPickupAllowed(ply, ent)

    if (ent:IsValid() and ent.GravGunPickupAllowed) then
        return ent:GravGunPickupAllowed(ply)
    end

    return true

end

function GM:PhysgunPickup(ply, ent)

    if (ent:GetPersistent() and GetConVarString("sbox_persist"):Trim() != "") then return false end

    if (ent:IsValid() and ent.PhysgunPickup) then
        return ent:PhysgunPickup(ply)
    end

    if (ent.PhysgunDisabled) then return false end

    local EntClass = ent:GetClass()

    if (EntClass == "player") then

        -- Runs on both realms (client-side for local prediction, server
        -- for the authoritative decision) so they have to agree - only
        -- the state-mutating Freeze() call below is server-only.
        if (!(PDCity.IsOwner(ply) or PDCity.IsStaff(ply))) then return false end
        if (ent == ply) then return false end
        if (ent.pdcity_IsCuffed or ent.pdcity_IsJailed) then return false end

        -- Freeze their own movement input immediately - the physgun
        -- positions them fine either way, but without this their own
        -- WASD/jump input fights the beam every tick, since a player
        -- (unlike a prop) has its own independent movement code driving
        -- its position on top of the physics object the beam grabs.
        -- "false" = soft freeze only (block input, don't lock position) -
        -- the beam itself needs freedom to move them while held; a hard
        -- lock only kicks in if they're explicitly right-click frozen
        -- (core/sv_physgun_players.lua's GM:OnPhysgunFreeze).
        if (SERVER) then
            PDCity.SetPlayerFrozen(ent, true, false)
            PDCity.GameLog("staff", ply:Nick() .. " (" .. ply:SteamID() .. ") physgun-picked-up "
                .. ent:Nick() .. " (" .. ent:SteamID() .. ")")
        end

        return true

    end

    if (physgun_limited:GetBool()) then

        if (string.find(EntClass, "prop_dynamic")) then return false end
        if (string.find(EntClass, "prop_door")) then return false end

        if (EntClass == "func_physbox" and ent:HasSpawnFlags(SF_PHYSBOX_MOTIONDISABLED)) then return false end

        if (string.find(EntClass, "prop_") and (ent:HasSpawnFlags(SF_PHYSPROP_MOTIONDISABLED) or ent:HasSpawnFlags(SF_PHYSPROP_PREVENT_PICKUP))) then return false end

        if (EntClass != "func_physbox" and string.find(EntClass, "func_")) then return false end

    end

    -- Owner/staff bypass the whitelist entirely - the same tier that can
    -- physgun other players (checked above) also needs to be able to grab
    -- anything for admin/building purposes, not just what's approved for
    -- everyone else (core/sh_physgun_whitelist.lua).
    if (!(PDCity.IsOwner(ply) or PDCity.IsStaff(ply))) then
        if (!PDCity.IsPhysgunAllowed(ent)) then return false end
    end

    if (SERVER) then

        ply:SendHint("PhysgunFreeze", 2)
        ply:SendHint("PhysgunUse", 8)

    end

    return true

end

function GM:EntityKeyValue(ent, key, value)

    if (key == "gmod_allowphysgun" and value == '0') then
        ent.PhysgunDisabled = true
    end

    if (key == "gmod_allowtools") then
        ent.m_tblToolsAllowed = string.Explode(" ", value)
    end

end

function GM:PlayerNoClip(pl, on)

    if (!IsValid(pl) or pl:InVehicle() or !pl:Alive()) then return false end

    -- Always allowed OUT of noclip, so nobody gets stuck flying if their
    -- job changes mid-flight. Godmode (granted below on the way IN) comes
    -- off here too, so leaving noclip always leaves them vulnerable again
    -- regardless of which branch below granted it.
    if (!on) then
        if (SERVER) then pl:GodDisable() end
        return true
    end

    -- Noclip is a staff-rank perk (core/sh_permissions.lua's PDCity.IsStaff,
    -- moderator and above), not tied to whatever job someone's currently
    -- playing - staff no longer have to leave their character to noclip,
    -- and nobody below staff rank can, regardless of job.
    --
    -- Godmode comes with it - noclipping through the map/props already
    -- makes fall damage and getting crushed by physics a constant risk
    -- that has nothing to do with actual roleplay, same reasoning as
    -- every other admin noclip implementation doing this.
    if (PDCity.IsStaff(pl)) then
        if (SERVER) then pl:GodEnable() end
        return true
    end
    if (PDCity.IsOwner(pl)) then
        if (SERVER) then pl:GodEnable() end
        return true
    end

    if (SERVER) then
        pl:ChatPrint("[" .. PDCity.BRAND_TAG .. "] You need staff rank to noclip.")
    end

    return false

end

function GM:CanProperty(pl, property, ent)

    if (!IsValid(ent)) then return false end

    if (ent.m_tblToolsAllowed) then

        local vFound = false
        for k, v in pairs(ent.m_tblToolsAllowed) do
            if (property == v) then vFound = true end
        end

        if (!vFound) then return false end

    end

    if (property == "bonemanipulate") then

        if (game.SinglePlayer()) then return true end

        if (ent:IsNPC()) then return GetConVarNumber("sbox_bonemanip_npc") != 0 end
        if (ent:IsPlayer()) then return GetConVarNumber("sbox_bonemanip_player") != 0 end

        return GetConVarNumber("sbox_bonemanip_misc") != 0

    end

    if (ent:IsWeapon() and IsValid(ent:GetOwner())) then
        return false
    end

    if (ent.CanProperty) then
        return ent:CanProperty(pl, property)
    end

    return true

end

function GM:CanDrive(pl, ent)

    local classname = ent:GetClass()

    if (ent:IsNPC()) then

        if (classname == "npc_cscanner") then return true end
        if (classname == "npc_clawscanner") then return true end
        if (classname == "npc_manhack") then return true end
        if (classname == "npc_turret_floor") then return true end
        if (classname == "npc_rollermine") then return true end

        return false

    end

    if (classname == "prop_dynamic") then return false end
    if (classname == "prop_door") then return false end

    return true

end

function GM:PlayerDriveAnimate(ply)

    local driving = ply:GetDrivingEntity()
    if (!IsValid(driving)) then return end

    ply:SetPlaybackRate(1)
    ply:ResetSequence(ply:SelectWeightedSequence(ACT_HL2MP_IDLE_MAGIC))

    local DirToEnt = driving:GetPos() - (ply:GetPos() + Vector(0, 0, 50))
    local AimAng = DirToEnt:Angle()

    if (AimAng.p > 180) then
        AimAng.p = AimAng.p - 360
    end

    ply:SetPoseParameter("aim_yaw", 0)
    ply:SetPoseParameter("aim_pitch", AimAng.p)
    ply:SetPoseParameter("move_x", 0)
    ply:SetPoseParameter("move_y", 0)
    ply:SetPoseParameter("move_yaw", 0)
    ply:SetPoseParameter("move_scale", 0)

    AimAng.p = 0
    AimAng.r = 0

    ply:SetRenderAngles(AimAng)
    ply:SetEyeTarget(driving:GetPos())

end