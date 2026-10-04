--[[---------------------------------------------------------
	Floating name labels above entities (cl_entity_labels.lua does the
	actual drawing) - a plain networked string per entity, so any code
	that already has an entity in scope can label it with one call.

	Every Custom Prop and Custom NPC sets this automatically from its own
	definition Name the moment it spawns (core/sh_custom_props.lua's
	ENT:Initialize, entities/entities/ent_pdcity_custom_npc.lua's own) -
	"Watermelon", "Empty Barrel", "Kool Aid" show up above themselves
	with zero code needed. PDCity.SetNameplate is there for anything that
	wants to change it afterwards - a Developer Console script updating a
	shake counter's progress onto the label, for instance.
-----------------------------------------------------------]]

function PDCity.SetNameplate(ent, text)
	if not IsValid(ent) then return end
	ent:SetNWString("PDCity_Nameplate", isstring(text) and text or "")
end
