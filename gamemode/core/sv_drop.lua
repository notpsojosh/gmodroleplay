--[[---------------------------------------------------------
	"/drop" - drops the weapon currently in hand as a world pickup
	(same underlying ents.Create approach sandbox's own Spawn_Weapon
	uses for the Q-menu, in commands.lua - but written separately here
	rather than reusing that function, since it requires SWEP.Spawnable
	and is gated by our own PlayerSpawnSWEP restriction (core/sv_restrictions.lua,
	owner/staff only), neither of which should apply to dropping
	something you already legitimately have).

	Refuses to drop anything tagged pdcity_NoDrop - see
	PDCity.GiveJobWeapons in sv_jobs.lua, which tags every weapon in a
	player's standard spawn loadout (physgun, gravity gun, toolgun,
	keys, and the current job's own weapons like cuffs) right after
	giving it out, so none of that can ever be dropped. Anything else
	(e.g. bought from the F4 shop) is droppable.
-----------------------------------------------------------]]

local DROP_DISTANCE = 64

local function DropCurrentWeapon(ply)

	if not ply:Alive() then return end

	local wep = ply:GetActiveWeapon()
	if not IsValid(wep) then
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] You're not holding anything to drop.")
		return
	end

	local printName = wep:GetPrintName() or wep:GetClass()

	if wep.pdcity_NoDrop then
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] You can't drop your " .. printName .. " - it's part of your standard loadout.")
		return
	end

	local class = wep:GetClass()

	local tr = util.TraceLine({
		start = ply:GetShootPos(),
		endpos = ply:GetShootPos() + ply:GetAimVector() * DROP_DISTANCE,
		filter = ply,
	})

	local ent = ents.Create(class)
	if not IsValid(ent) then
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Couldn't drop that.")
		return
	end

	ent:SetPos(tr.HitPos + tr.HitNormal * 8)
	ent:SetAngles(Angle(0, ply:EyeAngles().y, 0))
	ent:Spawn()
	ent:Activate()

	-- Marks it as "lying on the floor waiting to be picked up" rather
	-- than a live weapon: the hooks below stop anyone vacuuming it up
	-- just by walking over it, so it takes a deliberate +USE.
	ent.pdcity_DroppedWeapon = true

	local phys = ent:GetPhysicsObject()
	if IsValid(phys) then phys:Wake() end

	ply:StripWeapon(class)
	PDCity.GameLog("inventory", ply:Nick() .. " (" .. ply:SteamID() .. ") dropped their " .. printName)
	ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Dropped your " .. printName .. ".")

end

--[[---------------------------------------------------------
	Dropped weapons need +USE to pick up.

	Only weapons tagged pdcity_DroppedWeapon are affected, deliberately:
	a blanket PlayerCanPickupWeapon block would also catch the
	Player:Give() calls that hand out job loadouts
	(PDCity.GiveJobWeapons), which must keep working untouched.
-----------------------------------------------------------]]

local USE_PICKUP_RANGE = 90

hook.Add("PlayerCanPickupWeapon", "pdcity_NoWalkOverPickup", function(ply, wep)
	if not wep.pdcity_DroppedWeapon then return end
	-- Set for exactly one PickupWeapon call by the USE handler below.
	if ply.pdcity_AllowWeaponPickup then return end
	return false
end)

hook.Add("KeyPress", "pdcity_UsePickupWeapon", function(ply, key)
	if key ~= IN_USE then return end
	if not IsValid(ply) or not ply:Alive() then return end

	-- CTRL+USE is the inventory pickup (core/sv_inventory.lua); leave
	-- that alone so the two don't both fire on the same keypress.
	if ply:KeyDown(IN_DUCK) then return end

	local tr = util.TraceLine({
		start = ply:GetShootPos(),
		endpos = ply:GetShootPos() + ply:GetAimVector() * USE_PICKUP_RANGE,
		filter = ply,
	})

	local wep = tr.Entity
	if not IsValid(wep) or not wep:IsWeapon() then return end
	if not wep.pdcity_DroppedWeapon then return end
	if IsValid(wep:GetOwner()) then return end

	ply.pdcity_AllowWeaponPickup = true
	ply:PickupWeapon(wep)
	ply.pdcity_AllowWeaponPickup = nil
end)

hook.Add("PlayerSay", "pdcity_DropWeapon", function(ply, text)
	if string.lower(string.Trim(text)) ~= "/drop" then return end

	DropCurrentWeapon(ply)

	return ""
end)
