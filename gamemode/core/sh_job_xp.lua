--[[---------------------------------------------------------
	What a "job class" is, for XP purposes.

	A class is a job's Section (core/sh_jobs.lua) - "Police", not
	"Police Sergeant". Every rank within a section shares one XP pool
	and one level, so getting promoted from Trainee to Sergeant never
	resets progress, and every section is automatically a class with
	no extra registration step: PDCity.SECTIONS already grows whenever
	a category is added (built-in or via the F4 admin editor's Jobs
	tab, core/sv_job_catalogue.lua) - core/sv_job_xp.lua just starts
	that section at 0 XP the first time anyone earns any, same as any
	other profile field that's never been touched.
-----------------------------------------------------------]]

function PDCity.GetJobClass(jobID)
	local job = PDCity.GetJob(jobID)
	return job and job.Section or nil
end

-- Every class that currently exists, in the same display order as the
-- F4 menu's section headers.
function PDCity.GetAllJobClasses()
	return PDCity.SECTIONS
end
