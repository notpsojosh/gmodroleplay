--[[---------------------------------------------------------
	Admin-editable half of the Jobs system: custom jobs and job
	categories added in-game via the F4 admin editor's Jobs/Categories
	tabs (cl_f4_admin.lua). The hardcoded jobs in core/sh_jobs.lua stay
	there - this file only holds what the owner adds/removes at runtime,
	mirroring core/sh_f4_catalogue.lua for the Entities tab.

	The admin form only covers the basics (name, models, salary,
	category) - richer per-job detail (Weapons, Description, Skins,
	Bodygroups, a specific Color) isn't editable through the form.
	Hand-edit data/pdcity/job_catalogue.json while the server's down to
	add those; it's pretty-printed for that, same as profile.json.

	Persisted server-side (core/sv_job_catalogue.lua) and synced to
	clients on join and whenever the owner changes it. PDCity.SECTIONS
	(core/sh_jobs.lua) is the shared category list for both hardcoded
	and custom jobs - this file doesn't keep a separate one.

	Custom job fields (all optional except ID/Name):
	  ID       unique integer >= PDCity.CUSTOM_JOB_ID_BASE, generated
	           when added, also used as the job's team ID
	  Name     display name
	  Models   pool of model paths, one picked at random on spawn
	  Salary   whole number, 0 = none
	  Section  which PDCity.SECTIONS entry this groups under
	  Color    team/HUD color (defaults to a mid-gray if not hand-set)
-----------------------------------------------------------]]

PDCity.CUSTOM_JOB_ID_BASE = 1000

-- Replaced wholesale by disk load (server) / network sync (client) -
-- see core/sv_job_catalogue.lua and cl_f4_admin.lua.
PDCity.CUSTOM_JOBS = PDCity.CUSTOM_JOBS or {}

-- Registers (or re-registers) the GMod team for every custom job so
-- players can actually select/become them. Safe to call repeatedly -
-- team.SetUp just overwrites the existing registration. Called once
-- after the initial load/sync and again any time the catalogue changes.
function PDCity.RegisterCustomJobTeams()
	for id, job in pairs(PDCity.CUSTOM_JOBS) do
		team.SetUp(id, job.Name, job.Color or Color(150, 150, 150))
	end
end

PDCity.RegisterCustomJobTeams()
