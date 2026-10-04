--[[---------------------------------------------------------
	Owner-only tool: point at ANY existing prop/entity in the world and
	left-click to copy its model into a brand new, genuinely spawnable
	entity (core/sh_custom_props.lua) - not a single placed fixture, a
	real scripted_ents class registered on the fly, same as any
	hand-written SENT from then on: shows up in the Q menu's own
	"PD Roleplay (Custom)" category, and can be added to the F4 shop or
	tied to a Job Activity exactly like any other entity class, no
	further wiring needed either place.

	  Left click  - copy the model you're looking at, name it, done
	  Right click - looking at one of YOUR custom entities? Removes its
	                DEFINITION entirely (after confirming) - every future
	                spawn, not just the one you clicked. core/sv_custom_props.lua's
	                own comment on "pdcity_customprop_remove" covers what
	                happens to instances already out in the world.

	The naming step is a client-only popup (same pattern as the Staff
	Menu's reason prompts, cl_staff_menu.lua) - the actual definition
	only gets created server-side once a name's been confirmed
	(core/sv_custom_props.lua's "pdcity_customprop_create"). Right-click's
	confirmation is the same shape, just Remove/Cancel instead of a text
	entry.
-----------------------------------------------------------]]

TOOL.Category = "PD Roleplay"
TOOL.Name = "#tool.pdcity_propcopier.name"

TOOL.Information = {
	{ name = "left" },
	{ name = "right" },
}

if CLIENT then
	language.Add("tool.pdcity_propcopier.name", "Prop Copier (Owner)")
	language.Add("tool.pdcity_propcopier.desc", "Copy any prop's model into a new spawnable entity")
	language.Add("tool.pdcity_propcopier.left", "Copy the model you're looking at into a new spawnable entity")
	language.Add("tool.pdcity_propcopier.right", "Remove a Custom Prop's definition entirely (aim at one of your own)")
end

local function CheckOwner(tool)
	local ply = tool:GetOwner()
	if PDCity.IsOwner(ply) then return true end
	if SERVER then ply:ChatPrint("[" .. PDCity.BRAND_TAG .. "] Only the server owner can use the Prop Copier tool.") end
	return false
end

--[[---------------------------------------------------------
	Naming popup - client only. Same small-DFrame-with-a-text-entry
	shape as cl_staff_menu.lua's PromptReason (that one's file-local to
	that file, so this is its own copy rather than a shared export).
-----------------------------------------------------------]]
local function PromptName(model, onConfirm)

	local pw, ph = 380, 170

	local popup = vgui.Create("DFrame")
	popup:SetSize(pw, ph)
	popup:Center()
	popup:SetTitle("")
	popup:ShowCloseButton(false)
	popup:MakePopup()
	popup:SetAlpha(0)
	popup:AlphaTo(255, 0.12, 0)
	popup.Paint = function(self, w, h)
		draw.RoundedBox(8, 0, 0, w, h, PDCity.THEME.Background)
		draw.RoundedBoxEx(8, 0, 0, w, 36, PDCity.THEME.TitleBar, true, true, false, false)
		draw.SimpleText("Name This Entity", "PDCity_Heading", 14, 18, PDCity.THEME.Text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end

	local closeBtn = vgui.Create("DLabel", popup)
	closeBtn:SetPos(pw - 28, 9)
	closeBtn:SetSize(18, 18)
	closeBtn:SetFont("PDCity_Heading")
	closeBtn:SetText("x")
	closeBtn:SetTextColor(PDCity.THEME.TextDim)
	closeBtn:SetContentAlignment(5)
	closeBtn:SetCursor("hand")
	closeBtn:SetMouseInputEnabled(true)
	closeBtn.OnMousePressed = function(self, mcode)
		if mcode == MOUSE_LEFT then popup:Close() end
	end

	local modelLabel = vgui.Create("DLabel", popup)
	modelLabel:SetPos(14, 44)
	modelLabel:SetSize(pw - 28, 32)
	modelLabel:SetFont("PDCity_Small")
	modelLabel:SetWrap(true)
	modelLabel:SetText(model)
	modelLabel:SetTextColor(PDCity.THEME.TextDim)

	local entry = vgui.Create("DTextEntry", popup)
	entry:SetPos(14, 82)
	entry:SetSize(pw - 28, 28)
	entry:SetPlaceholderText("Display name...")

	local confirmBtn = vgui.Create("DButton", popup)
	confirmBtn:SetPos(14, 118)
	confirmBtn:SetSize(pw - 28, 26)
	PDCity.StyleButton(confirmBtn, "CREATE")

	local function TrySubmit()
		local name = string.Trim(entry:GetValue() or "")
		if name == "" then
			entry:SetPlaceholderText("Name required - type something first")
			entry:RequestFocus()
			return
		end
		popup:Close()
		onConfirm(name)
	end

	confirmBtn.DoClick = TrySubmit
	entry.OnEnter = TrySubmit

	entry:RequestFocus()

end

--[[---------------------------------------------------------
	Removal confirmation - same small-DFrame shape as PromptName above,
	Remove/Cancel instead of a text entry since removing a definition is
	destructive (every future spawn of this entity stops working, not
	just the one instance under the crosshair).
-----------------------------------------------------------]]
local function PromptConfirmRemove(name, onConfirm)

	local pw, ph = 380, 150

	local popup = vgui.Create("DFrame")
	popup:SetSize(pw, ph)
	popup:Center()
	popup:SetTitle("")
	popup:ShowCloseButton(false)
	popup:MakePopup()
	popup:SetAlpha(0)
	popup:AlphaTo(255, 0.12, 0)
	popup.Paint = function(self, w, h)
		draw.RoundedBox(8, 0, 0, w, h, PDCity.THEME.Background)
		draw.RoundedBoxEx(8, 0, 0, w, 36, PDCity.THEME.TitleBar, true, true, false, false)
		draw.SimpleText("Remove Custom Entity", "PDCity_Heading", 14, 18, PDCity.THEME.Text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
	end

	local closeBtn = vgui.Create("DLabel", popup)
	closeBtn:SetPos(pw - 28, 9)
	closeBtn:SetSize(18, 18)
	closeBtn:SetFont("PDCity_Heading")
	closeBtn:SetText("x")
	closeBtn:SetTextColor(PDCity.THEME.TextDim)
	closeBtn:SetContentAlignment(5)
	closeBtn:SetCursor("hand")
	closeBtn:SetMouseInputEnabled(true)
	closeBtn.OnMousePressed = function(self, mcode)
		if mcode == MOUSE_LEFT then popup:Close() end
	end

	local msgLabel = vgui.Create("DLabel", popup)
	msgLabel:SetPos(14, 44)
	msgLabel:SetSize(pw - 28, 56)
	msgLabel:SetFont("PDCity_Small")
	msgLabel:SetWrap(true)
	msgLabel:SetText("Remove \"" .. name .. "\" entirely? It'll stop being spawnable after the next restart - anything already placed in the world keeps working until then.")
	msgLabel:SetTextColor(PDCity.THEME.TextDim)

	local removeBtn = vgui.Create("DButton", popup)
	removeBtn:SetPos(14, ph - 40)
	removeBtn:SetSize(pw - 28, 26)
	PDCity.StyleButton(removeBtn, "REMOVE", { Accent = Color(190, 70, 70), AccentDim = Color(140, 55, 55) })
	removeBtn.DoClick = function()
		popup:Close()
		onConfirm()
	end

end

function TOOL:LeftClick(trace)
	if not CheckOwner(self) then return false end

	local ent = trace.Entity
	if not IsValid(ent) or ent:IsWorld() or ent:IsPlayer() then
		if SERVER then self:GetOwner():ChatPrint("[" .. PDCity.BRAND_TAG .. "] Aim at an existing prop or entity first.") end
		return false
	end

	local model = ent:GetModel()
	if not isstring(model) or model == "" then
		if SERVER then self:GetOwner():ChatPrint("[" .. PDCity.BRAND_TAG .. "] That doesn't have a model to copy.") end
		return false
	end

	if SERVER then return true end

	-- Client-side prediction can replay LeftClick/RightClick several
	-- times for one physical click (any latency at all makes this more
	-- likely) - without this guard, each replay independently opened its
	-- own popup, reported as "2-3 windows... come up" for a single
	-- click. IsFirstTimePredicted() is GMod's own answer to exactly this -
	-- true only on the real, first run; every replay after it is false.
	if not IsFirstTimePredicted() then return true end

	PromptName(model, function(name)
		net.Start("pdcity_customprop_create")
			net.WriteString(name)
			net.WriteString(model)
		net.SendToServer()
	end)

	return true
end

-- Extracts the numeric ID out of one of our own dynamically-registered
-- classes ("pdcity_customprop_<id>", core/sh_custom_props.lua) - nil for
-- anything else, including a Custom Prop's placed instance that somehow
-- lost its definition already (PDCity.GetCustomPropByID would just find
-- nothing for it, same end result either way).
local function CustomPropIDFromClass(class)
	return tonumber(string.match(class or "", "^pdcity_customprop_(%d+)$"))
end

function TOOL:RightClick(trace)
	if not CheckOwner(self) then return false end

	local ent = trace.Entity
	local id = IsValid(ent) and CustomPropIDFromClass(ent:GetClass())
	if not id then
		if SERVER then self:GetOwner():ChatPrint("[" .. PDCity.BRAND_TAG .. "] That's not one of your Custom Props.") end
		return false
	end

	if SERVER then return true end
	if not IsFirstTimePredicted() then return true end -- see LeftClick's own comment on why

	local def = PDCity.GetCustomPropByID(id)
	local name = def and def.Name or ("Custom Prop #" .. id)

	PromptConfirmRemove(name, function()
		net.Start("pdcity_customprop_remove")
			net.WriteUInt(id, 32)
		net.SendToServer()
	end)

	return true
end

function TOOL.BuildCPanel(panel)
	panel:AddControl("Header", {
		Description = "Owner-only. Left click any existing prop or entity to copy its model into a brand new spawnable entity - it'll show up in the Q menu's \"PD Roleplay (Custom)\" category from then on, and can be added to the F4 shop or a Job Activity like any other entity class. Right click one of your own Custom Props to remove its definition entirely (after confirming).",
	})
end
