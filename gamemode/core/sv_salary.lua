--[[---------------------------------------------------------
	Salary payouts. Every player whose job defines a Salary > 0 (see
	core/sh_jobs.lua) is paid on the server's wall clock at :00, :15,
	:30 and :45 - not "every 15 minutes since you joined", so everyone
	gets paid at the same moment regardless of connect time.
-----------------------------------------------------------]]

-- Which quarter-hour we last paid, so the polling timer (which fires
-- many times inside a given minute) only ever pays each quarter once.
local lastPaidQuarter

timer.Create("pdcity_Salary", 5, 0, function()

	local minute = tonumber(os.date("%M"))
	if minute % 15 ~= 0 then return end

	local quarterKey = os.date("%Y%m%d%H%M")
	if quarterKey == lastPaidQuarter then return end
	lastPaidQuarter = quarterKey

	for _, ply in ipairs(player.GetHumans()) do

		local job = PDCity.GetJob(ply:Team())
		local salary = job and job.Salary or 0

		if salary > 0 then
			PDCity.AddMoney(ply, salary)
			ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Payday! You received your $" .. salary .. " salary.")
		end

	end

end)
