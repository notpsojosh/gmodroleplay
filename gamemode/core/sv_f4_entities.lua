--[[---------------------------------------------------------
	Server side of the F4 Entities tab: validates and performs purchases
	requested via the pdcity_buyentity concommand. The catalogue lives in
	core/sh_f4_entities.lua; prices are charged against the profile money
	system (core/sv_profiles.lua).
-----------------------------------------------------------]]

local SPAWN_DISTANCE = 80
local BUY_COOLDOWN = 0.6 -- seconds between purchases, per player

local function GetSpawnPos(ply)
	local tr = util.TraceLine({
		start = ply:EyePos(),
		endpos = ply:EyePos() + ply:GetAimVector() * SPAWN_DISTANCE,
		filter = ply,
	})
	return tr.HitPos + tr.HitNormal * 8
end

concommand.Add("pdcity_buyentity", function(ply, cmd, args)
	if not IsValid(ply) or not ply:Alive() then return end

	local cfg = PDCity.GetF4Entity(args[1] or "")
	if not cfg then return end

	-- Job/rank restrictions (core/sh_f4_catalogue.lua) are what the F4
	-- menu uses to hide/gray out cards, but that's client-side display
	-- only - re-check here since this concommand could otherwise be run
	-- directly to buy something the menu wouldn't even show.
	local allowed, reason = PDCity.CanAccessF4Entity(ply, cfg)
	if not allowed then
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] " .. (reason or "You can't buy that."))
		return
	end

	-- Server-enforced rate limit; the concommand comes straight from the
	-- client, so this can't be bypassed by mashing the button or console.
	if (ply.pdcity_NextBuy or 0) > CurTime() then return end
	ply.pdcity_NextBuy = CurTime() + BUY_COOLDOWN

	-- Optional per-entity gate, checked before any money changes hands
	-- (e.g. the money printer's per-player cap). Returns false + an
	-- optional reason string to reject the purchase.
	if cfg.CanBuy then
		local ok, reason = cfg.CanBuy(ply)
		if not ok then
			ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] " .. (reason or "You can't buy that right now."))
			return
		end
	end

	-- Charge first so two rapid purchases can't both pass an affordability
	-- check before either deducts; refund if the spawn itself fails.
	if cfg.Price > 0 and not PDCity.AddMoney(ply, -cfg.Price) then
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] You can't afford that ($" .. cfg.Price .. ").")
		return
	end

	-- A shipment entry spawns a crate holding N of the class rather than
	-- the class itself (entities/entities/ent_pdcity_shipment.lua). The
	-- entry's own Setup/CanBuy still refer to the item, so Setup is
	-- deliberately NOT run against the crate - it would be setting up
	-- the wrong entity.
	local isShipment = (cfg.ShipmentCount or 0) > 1

	local ent = ents.Create(isShipment and "ent_pdcity_shipment" or cfg.Class)
	if not IsValid(ent) then
		if cfg.Price > 0 then PDCity.AddMoney(ply, cfg.Price) end
		ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Couldn't create that entity - purchase refunded.")
		return
	end

	ent:SetPos(GetSpawnPos(ply))

	if isShipment then
		ent:SetItemClass(cfg.Class)
		ent:SetCount(cfg.ShipmentCount)
	elseif cfg.Setup then
		cfg.Setup(ent, ply)
	end

	ent:Spawn()
	ent:Activate()

	-- Same treatment /drop and inventory-drop give a floor weapon (see
	-- core/sv_drop.lua): a freshly bought weapon sits ownerless in front
	-- of the buyer for a moment, and without this anyone standing nearby
	-- (not just the buyer) could walk over it and auto-equip it before the
	-- buyer even picks it up themselves. +USE only, same as everywhere else.
	if ent:IsWeapon() then
		ent.pdcity_DroppedWeapon = true
	end

	-- Assign the entity to the buyer. The raw ents.Create path above
	-- skips the sandbox spawn machinery that normally does this, so
	-- without it the engine creator and prop-protection (CPPI/FPP) owner
	-- would both be left as "world". SetCreator covers ent:GetCreator();
	-- CPPISetOwner covers prop protection (guarded since it only exists
	-- when a CPPI-providing addon like FPP is installed).
	ent:SetCreator(ply)
	if isfunction(ent.CPPISetOwner) then
		ent:CPPISetOwner(ply)
	end

	local what = isShipment
		and ("a shipment of " .. cfg.ShipmentCount .. "x " .. cfg.Name)
		or cfg.Name

	PDCity.GameLog("purchases", ply:Nick() .. " (" .. ply:SteamID() .. ") bought " .. what
		.. (cfg.Price > 0 and (" for $" .. cfg.Price) or " (free)"))

	ply:ChatPrint(cfg.Price > 0
		and ("[" .. PDCity.BRAND_TAG .. "] Bought " .. what .. " for $" .. cfg.Price .. ".")
		or ("[" .. PDCity.BRAND_TAG .. "] Spawned " .. what .. "."))
end)
