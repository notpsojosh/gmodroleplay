--[[---------------------------------------------------------
	Client side of Custom Props (core/sh_custom_props.lua) - registers
	each synced definition's dynamic entity class locally too, so the
	Q menu can build a spawn icon for it and the F4 shop/Job Activity
	systems see a real class exists, same as the server does.
-----------------------------------------------------------]]

net.Receive("pdcity_customprop_sync", function()
	local data = util.JSONToTable(net.ReadString() or "")
	if not istable(data) then return end

	PDCity.CUSTOM_PROPS = data
	for _, def in ipairs(PDCity.CUSTOM_PROPS) do
		PDCity.RegisterCustomPropClass(def)
	end

	hook.Run("PDCity_CustomPropCatalogueUpdated")
end)
