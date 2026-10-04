--[[---------------------------------------------------------
	Car radio - client side. Hotkey opens the station list
	(core/sh_keybinds.lua's "carradio" action, relayed the same way the
	Staff Menu's own key is: server tells this client to run a
	concommand, since the client already has everything it needs
	synced). Playback itself is driven entirely by watching each
	vehicle's own PDCity_RadioStation NWInt (set server-side in
	core/sv_radio.lua) rather than a dedicated "now playing" net
	message - every client near a vehicle sees the same NWVar and
	reaches the same conclusion independently, PLAYING PLAYER included.
-----------------------------------------------------------]]

local stations = {} -- flat list, synced from the server

net.Receive("pdcity_radio_sync", function()
	local ok, data = pcall(util.JSONToTable, net.ReadString())
	stations = (ok and istable(data)) and data or {}
	hook.Run("PDCity_RadioStationsUpdated")
end)

local function GetStation(id)
	for _, station in ipairs(stations) do
		if station.ID == id then return station end
	end
end

-- Personal listening volume, not synced to anyone else - each client's
-- radio channels are their own local sound.PlayURL playback, so there's
-- nothing server-side for this to touch. Archived so it's remembered
-- across sessions, same as any other client preference in this codebase.
local RADIO_VOLUME = CreateClientConVar("pdcity_radio_volume", "1", true, false, PDCity.BRAND_NAME .. " car radio playback volume (0-1)", 0, 1)

--[[---------------------------------------------------------
	Playback - one sound.PlayURL channel per vehicle currently playing
	something, tracked by Entity index. Polled on a short timer rather
	than every single Think (nothing here needs frame-perfect timing
	except the position update below, which does run every Think).
-----------------------------------------------------------]]
local activeChannels = {} -- [entIndex] = { channel = IGModAudioChannel or false (loading), stationID = n }

-- Declared here, not up by RADIO_VOLUME's own definition - this needs
-- activeChannels as an upvalue, and a local declared AFTER a function
-- literal is invisible to it (Lua resolves that as a global lookup
-- instead, which would have been nil and made every SetVolume loop
-- below crash with "table expected, got nil" the first time the slider
-- moved).
cvars.AddChangeCallback("pdcity_radio_volume", function(name, old, new)
	local vol = math.Clamp(tonumber(new) or 1, 0, 1)
	for _, entry in pairs(activeChannels) do
		if IsValid(entry.channel) then
			entry.channel:SetVolume(vol)
		end
	end
end, "PDCity_RadioVolumeSync")

local function StopChannel(idx)
	local entry = activeChannels[idx]
	if not entry then return end
	if IsValid(entry.channel) then
		entry.channel:Stop()
	end
	activeChannels[idx] = nil
end

local function StartChannel(vehicle, station)
	local idx = vehicle:EntIndex()
	StopChannel(idx)

	activeChannels[idx] = { channel = false, stationID = station.ID }

	sound.PlayURL(station.URL, "3d noblock", function(channel, errID, errName)
		local entry = activeChannels[idx]
		-- The vehicle could be gone, or already switched to a different
		-- station, by the time this async callback actually fires.
		if not entry or entry.stationID ~= station.ID then
			if IsValid(channel) then channel:Stop() end
			return
		end

		if not IsValid(channel) then
			activeChannels[idx] = nil
			return
		end

		entry.channel = channel
		channel:Set3DFadeDistance(150, 2000)
		channel:SetPos(vehicle:GetPos())
		channel:SetVolume(RADIO_VOLUME:GetFloat())

		-- Best-effort sync to where the station should already be, so
		-- someone who walks up to a vehicle mid-song doesn't hear it
		-- restart from the beginning - only works for a genuinely
		-- seekable stream (a finite audio file URL, not a live radio
		-- feed). A live stream doesn't just ignore SetTime, it throws
		-- ("Cannot use SetTime on a block streamed audio channel"), so
		-- this is wrapped in pcall rather than assumed safe - every
		-- default station is a live feed and would hit this on literally
		-- every play otherwise.
		local startedAt = vehicle:GetNWFloat("PDCity_RadioStartTime", 0)
		if startedAt > 0 then
			pcall(channel.SetTime, channel, CurTime() - startedAt, true)
		end

		channel:Play()
	end)
end

timer.Create("PDCity_RadioPoll", 1, 0, function()
	for _, vehicle in ipairs(ents.FindByClass("prop_vehicle_*")) do
		local idx = vehicle:EntIndex()
		local stationID = vehicle:GetNWInt("PDCity_RadioStation", 0)
		local entry = activeChannels[idx]

		if stationID == 0 then
			if entry then StopChannel(idx) end
		elseif not entry or entry.stationID ~= stationID then
			local station = GetStation(stationID)
			if station then StartChannel(vehicle, station) end
		end
	end

	-- Clean up anything still tracked for a vehicle that's gone, or
	-- that's stopped playing entirely (NWInt back to 0/unset) but
	-- didn't get caught above because the entity itself is no longer
	-- in ents.FindByClass at all.
	for idx, entry in pairs(activeChannels) do
		local vehicle = Entity(idx)
		if not IsValid(vehicle) or vehicle:GetClass():sub(1, 13) ~= "prop_vehicle_" then
			StopChannel(idx)
		end
	end
end)

-- Follows each playing vehicle's position every frame - a stationary
-- SetPos from the moment it started would leave the audio anchored to
-- wherever the vehicle happened to be when someone hit Play, not where
-- it's actually driven to since.
hook.Add("Think", "PDCity_RadioFollow", function()
	for idx, entry in pairs(activeChannels) do
		if IsValid(entry.channel) then
			local vehicle = Entity(idx)
			if IsValid(vehicle) then
				entry.channel:SetPos(vehicle:GetPos())
			end
		end
	end
end)

--[[---------------------------------------------------------
	Small themed drag slider - stock DNumSlider/DSlider render with the
	default white Derma skin, which was exactly the "horrible white box"
	look every other input in this gamemode has already been reskinned
	away from, so this is a from-scratch flat bar instead of reusing
	either of those. Click-and-drag anywhere on the bar jumps straight to
	that position rather than needing to grab a small handle precisely.
-----------------------------------------------------------]]
local function CreateSlider(parent, value, onChange)
	local slider = vgui.Create("DPanel", parent)
	slider.Value = math.Clamp(value, 0, 1)
	slider:SetCursor("hand")

	local function SetFromCursor(self)
		local mx = self:CursorPos()
		self.Value = math.Clamp(mx / self:GetWide(), 0, 1)
		if onChange then onChange(self.Value) end
	end

	slider.Paint = function(self, w, h)
		local barH = 6
		local barY = h / 2 - barH / 2
		draw.RoundedBox(barH / 2, 0, barY, w, barH, PDCity.THEME.Border)
		draw.RoundedBox(barH / 2, 0, barY, w * self.Value, barH, PDCity.THEME.Accent)

		local knobX = w * self.Value
		local knobSize = self.Dragging and 18 or 14
		draw.RoundedBox(knobSize / 2, knobX - knobSize / 2, h / 2 - knobSize / 2, knobSize, knobSize,
			(self.Dragging or self:IsHovered()) and PDCity.THEME.Accent or PDCity.THEME.Text)
	end

	slider.OnMousePressed = function(self, mcode)
		if mcode ~= MOUSE_LEFT then return end
		self.Dragging = true
		self:MouseCapture(true)
		SetFromCursor(self)
	end
	slider.OnMouseReleased = function(self, mcode)
		if mcode ~= MOUSE_LEFT then return end
		self.Dragging = false
		self:MouseCapture(false)
	end
	slider.Think = function(self)
		if self.Dragging then SetFromCursor(self) end
	end

	return slider
end

--[[---------------------------------------------------------
	The menu itself
-----------------------------------------------------------]]
local function OpenRadioMenu()
	if IsValid(GAMEMODE.PDCityRadioFrame) then
		GAMEMODE.PDCityRadioFrame:Remove()
		return
	end

	PDCity.PushMenuDim()
	local frameW, frameH = PDCity.ResponsiveFrameSize(560, 720)
	local frame = PDCity.CreateModernFrame("Car Radio", frameW, frameH, function(newW, newH)
		if IsValid( GAMEMODE.PDCityRadioContent ) then
			GAMEMODE.PDCityRadioContent:SetSize(newW - 24, newH - 48 - 12)
		end
	end)
	frame.OnRemove = function() PDCity.PopMenuDim() end
	GAMEMODE.PDCityRadioFrame = frame

	local ply = LocalPlayer()
	local inVehicle = IsValid(ply:GetVehicle())
	local isAdmin = PDCity.IsStaff(ply)

	-- Everything below lives inside one Dock-based column instead of
	-- hand-placed x/y coordinates - that's what was actually making the
	-- menu look lopsided (uneven side margins, a stray gap above Stop
	-- Radio, the Add Station row not lining up with anything above it).
	local content = vgui.Create("DPanel", frame)
	content:SetPos(12, 48 + 12)
	content:SetSize(frame:GetWide() - 24, frame:GetTall() - 48 - 24)
	content.Paint = function() end
	GAMEMODE.PDCityRadioContent = content

	local statusLabel = vgui.Create("DLabel", content)
	statusLabel:Dock(TOP)
	statusLabel:SetTall(22)
	statusLabel:SetFont("PDCity_Small")
	statusLabel:SetContentAlignment(5)
	statusLabel:SetTextColor(inVehicle and PDCity.THEME.TextDim or Color(220, 90, 80))
	statusLabel:SetText(inVehicle and "Playing a station applies to the vehicle you're in." or "Get in a vehicle to play a station.")

	--[[-----------------------------------------------------
		Bottom section built (and Dock(BOTTOM)'d) BEFORE the station
		list's Dock(FILL) scroll panel below - same docking-order fix
		used throughout this codebase (cl_f4_admin.lua's tabs, the
		whitelist panel, ...): whichever panel is docked FIRST claims
		space first, so a FILL panel docked before a BOTTOM one would
		swallow the room this needs.
	-------------------------------------------------------]]
	local bottomHolder = vgui.Create("DPanel", content)
	bottomHolder:Dock(BOTTOM)
	bottomHolder:SetTall(isAdmin and 202 or 88)
	bottomHolder:DockMargin(0, 10, 0, 0)
	bottomHolder.Paint = function(self, w, h)
		draw.RoundedBox(6, 0, 0, w, h, PDCity.THEME.Panel)
	end

	local stopBtn = vgui.Create("DButton", bottomHolder)
	stopBtn:Dock(TOP)
	stopBtn:SetTall(30)
	stopBtn:DockMargin(10, 10, 10, 0)
	PDCity.StyleButton(stopBtn, "Stop Radio", { Accent = PDCity.THEME.PanelHover, AccentDim = PDCity.THEME.TitleBar, TextColor = PDCity.THEME.TextDim })
	stopBtn:SetEnabled(inVehicle)
	stopBtn.DoClick = function()
		net.Start("pdcity_radio_stop")
		net.SendToServer()
	end

	local volumeRow = vgui.Create("DPanel", bottomHolder)
	volumeRow:Dock(TOP)
	volumeRow:SetTall(24)
	volumeRow:DockMargin(10, 10, 10, 0)
	volumeRow.Paint = function() end

	local volumeLabel = vgui.Create("DLabel", volumeRow)
	volumeLabel:Dock(LEFT)
	volumeLabel:SetWide(60)
	volumeLabel:SetFont("PDCity_Small")
	volumeLabel:SetTextColor(PDCity.THEME.TextDim)
	volumeLabel:SetText("Volume")

	local volumePct = vgui.Create("DLabel", volumeRow)
	volumePct:Dock(RIGHT)
	volumePct:SetWide(40)
	volumePct:SetFont("PDCity_Small")
	volumePct:SetTextColor(PDCity.THEME.TextDim)
	volumePct:SetContentAlignment(6)
	volumePct:SetText(math.Round(RADIO_VOLUME:GetFloat() * 100) .. "%")

	local volumeSlider = CreateSlider(volumeRow, RADIO_VOLUME:GetFloat(), function(value)
		RunConsoleCommand("pdcity_radio_volume", tostring(value))
		volumePct:SetText(math.Round(value * 100) .. "%")
	end)
	volumeSlider:Dock(FILL)
	volumeSlider:DockMargin(8, 0, 8, 0)

	if isAdmin then
		local addLabel = vgui.Create("DLabel", bottomHolder)
		addLabel:Dock(TOP)
		addLabel:SetTall(24)
		addLabel:DockMargin(10, 8, 10, 0)
		addLabel:SetFont("PDCity_Small")
		addLabel:SetTextColor(PDCity.THEME.TextDim)
		addLabel:SetText("Add a station (owner/staff only):")

		local nameEntry = vgui.Create("DTextEntry", bottomHolder)
		nameEntry:Dock(TOP)
		nameEntry:SetTall(28)
		nameEntry:DockMargin(10, 4, 10, 0)
		nameEntry:SetPlaceholderText("Station name")

		local urlRow = vgui.Create("DPanel", bottomHolder)
		urlRow:Dock(TOP)
		urlRow:SetTall(28)
		urlRow:DockMargin(10, 6, 10, 10)
		urlRow.Paint = function() end

		local addBtn = vgui.Create("DButton", urlRow)
		addBtn:Dock(RIGHT)
		addBtn:SetWide(80)
		PDCity.StyleButton(addBtn, "Add")

		local urlEntry = vgui.Create("DTextEntry", urlRow)
		urlEntry:Dock(FILL)
		urlEntry:DockMargin(0, 0, 8, 0)
		urlEntry:SetPlaceholderText("Direct stream URL (http/https)")

		addBtn.DoClick = function()
			if nameEntry:GetValue() == "" or urlEntry:GetValue() == "" then
				ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Give the station both a name and a URL.")
				return
			end
			net.Start("pdcity_radio_admin")
				net.WriteString(util.TableToJSON({ Action = "add", Name = nameEntry:GetValue(), URL = urlEntry:GetValue() }))
			net.SendToServer()
			nameEntry:SetValue("")
			urlEntry:SetValue("")
		end
	end

	local listScroll = vgui.Create("DScrollPanel", content)
	listScroll:Dock(FILL)
	listScroll:DockMargin(0, 8, 0, 0)
	PDCity.ApplyFastScroll(listScroll)

	local function RefreshList()
		listScroll:Clear()

		for _, station in ipairs(stations) do
			local row = vgui.Create("DPanel", listScroll)
			row:Dock(TOP)
			row:SetTall(44)
			row:DockMargin(0, 0, 0, 8)
			row.Paint = function(self, w, h)
				draw.RoundedBox(4, 0, 0, w, h, PDCity.THEME.Panel)
			end

			local btnRow = vgui.Create("DPanel", row)
			btnRow:Dock(RIGHT)
			btnRow:SetWide(isAdmin and 158 or 76)
			btnRow:DockMargin(0, 7, 8, 7)
			btnRow.Paint = function() end

			local playBtn = vgui.Create("DButton", btnRow)
			playBtn:Dock(RIGHT)
			playBtn:SetWide(76)
			PDCity.StyleButton(playBtn, "Play")
			playBtn:SetEnabled(inVehicle)
			playBtn.DoClick = function()
				net.Start("pdcity_radio_play")
					net.WriteUInt(station.ID, 16)
				net.SendToServer()
			end

			if isAdmin then
				local removeBtn = vgui.Create("DButton", btnRow)
				removeBtn:Dock(LEFT)
				removeBtn:SetWide(76)
				PDCity.StyleButton(removeBtn, "Remove", { Accent = Color(190, 70, 70), AccentDim = Color(140, 55, 55) })
				removeBtn.DoClick = function()
					net.Start("pdcity_radio_admin")
						net.WriteString(util.TableToJSON({ Action = "remove", ID = station.ID }))
					net.SendToServer()
				end
			end

			local name = vgui.Create("DLabel", row)
			name:Dock(FILL)
			name:DockMargin(12, 0, 10, 0)
			name:SetFont("PDCity_Body")
			name:SetTextColor(PDCity.THEME.Text)
			name:SetContentAlignment(4)
			name:SetText(station.Name)
		end
	end
	RefreshList()
	hook.Add("PDCity_RadioStationsUpdated", frame, RefreshList)

	frame.OnClose = function()
		hook.Remove("PDCity_RadioStationsUpdated", frame)
	end
end

concommand.Add("pdcity_openradio", OpenRadioMenu)
