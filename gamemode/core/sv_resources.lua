--[[---------------------------------------------------------
	Custom loose assets (materials/pdcity/*) never actually reach a
	connecting client on their own - GMod's automatic content-sending
	only covers the gamemode's own Lua files (AddCSLuaFile) and whatever
	Workshop addons are mounted. A file just sitting in the SERVER's
	materials/ folder is invisible to anyone joining over the network
	unless the server explicitly tells the engine to send it, via
	resource.AddFile - which is what this file does, for every file
	under materials/pdcity/, so a client can actually load the logo
	(cl_theme.lua), the F4 sidebar's shop icon (cl_f4_menu.lua), or
	anything else dropped in there later, without needing a code change
	each time (this is why they were rendering as the engine's own
	"missing texture" checkerboard, or an outright IsError() material,
	for anyone who wasn't already running the server itself with the
	file already on their own local disk).

	No Workshop addon needed for this - that's a valid alternative (and
	the standard way to distribute LARGE content, since it goes over
	Steam's own CDN instead of the server's bandwidth), but for a small
	folder of UI images, resource.AddFile is simpler and needs nothing
	uploaded anywhere.
-----------------------------------------------------------]]

local ASSET_DIR = "pdcity"

local function AddResourcesRecursive(dir)
	local files, folders = file.Find(dir .. "/*", "GAME")

	for _, f in ipairs(files or {}) do
		resource.AddFile(dir .. "/" .. f)
	end

	for _, sub in ipairs(folders or {}) do
		AddResourcesRecursive(dir .. "/" .. sub)
	end
end

AddResourcesRecursive("materials/" .. ASSET_DIR)
