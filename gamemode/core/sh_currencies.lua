--[[---------------------------------------------------------
	Custom Currencies - owner-defined ADDITIONAL currencies (loyalty
	points, a premium currency, event tokens, ...) alongside the
	gamemode's own built-in Money (core/sv_money.lua, untouched by this).

	A currency is just { ID, Name, Symbol, Icon } - defined once here
	(owner-only, F4 admin editor's "Currencies" tab), persisted server-
	side (core/sv_currencies.lua), synced to every client the same way
	Activities/Custom NPCs are. Balances are per-player, per-currency
	(core/sv_currencies.lua's PDCity.AddCurrency/PDCity.RemoveCurrency/
	PDCity.GetCurrencyBalance), stored in the player's own profile next
	to Money and Inventory.
-----------------------------------------------------------]]

PDCity.CURRENCIES = PDCity.CURRENCIES or {}

function PDCity.GetCurrencyByID(id)
	for _, c in ipairs(PDCity.CURRENCIES) do
		if c.ID == id then return c end
	end
end
