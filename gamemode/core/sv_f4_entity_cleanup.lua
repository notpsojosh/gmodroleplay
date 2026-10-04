--[[---------------------------------------------------------
	Job-restricted F4 entities (core/sh_f4_catalogue.lua's Jobs list, or
	core/sh_f4_entities.lua's VisibleCheck - e.g. the Money Printer's
	police-only restriction) disappear the moment their owner
	switches to a job that couldn't buy them anymore - a Farmer's plant
	pots stick around if they become a Mechanic, a police-only Money
	Printer goes if an officer demotes to Citizen, and so on.

	Ownership is whatever core/sv_f4_entities.lua's purchase handler
	already set (ent:SetCreator(ply)) - nothing new to track. Reuses
	PDCity.HasF4JobAccess (the same job-eligibility check the F4 menu
	itself uses to hide a card) rather than a separate rule, so this
	always matches whatever the menu currently says a job can/can't buy.

	OnPlayerChangedTeam is a native, generic hook - covers every way a
	job can change (F4 selection, an admin command, anything else),
	not just core/sv_jobs.lua's own PDCity.ApplyJob path.
-----------------------------------------------------------]]

local function GetCatalogEntryForClass(class)
	for _, cfg in ipairs(PDCity.GetAllF4Entities()) do
		if cfg.Class == class then return cfg end
	end
end

hook.Add("OnPlayerChangedTeam", "pdcity_RemoveJobLockedEntities", function(ply, before, after)
	if not IsValid(ply) then return end

	for _, ent in ipairs(ents.GetAll()) do
		if IsValid(ent) and ent:GetCreator() == ply then
			local class = ent:GetClass()

			-- A shipment crate holds N of a job-restricted item without
			-- being that class itself (ent_pdcity_shipment.lua) - check
			-- what it's actually carrying instead of its own class.
			if class == "ent_pdcity_shipment" and isfunction(ent.GetItemClass) then
				class = ent:GetItemClass()
			end

			local cfg = GetCatalogEntryForClass(class)
			if cfg and not PDCity.HasF4JobAccess(ply, cfg) then
				ent:Remove()
			end
		end
	end
end)
