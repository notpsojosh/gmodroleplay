local MAX_PROPS = PDCity.MAX_PROPS

function GM:PlayerSpawnProp(ply, model)
    if ply:IsSuperAdmin() or PDCity.IsOwner(ply) then return true end

    local count = ply:GetCount("props")
    if count >= MAX_PROPS then
        print(string.format("[" .. PDCity.BRAND_TAG .. "] Blocked prop spawn for %s: %d/%d props", ply:Nick(), count, MAX_PROPS))
        ply:LimitHit("props")
        return false
    end

    return true
end

concommand.Add("pdcity_propcount", function(ply)
    if not IsValid(ply) then return end
    local count = ply:GetCount("props")
    ply:ChatPrint(string.format("[" .. PDCity.BRAND_TAG .. "] You currently have %d/%d props spawned.", count, MAX_PROPS))
end)
