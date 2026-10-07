--[[
	HUDController
	Minimal HUD. Shows only what matters and fades away when fear is high, so the
	scariest moments have nothing between you and the dark.
	  top-left     objectives and anomaly count
	  top-right    team list
	  bottom-left  flashlight battery, stamina (only when not full)
	  bottom-mid   inventory (4 slots)
	  centre       crosshair dot, interaction prompt, report focus ring
	  layers       toasts, journal/achievement cards, captions, hints
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local Net = require(ReplicatedStorage.Shared.Net)
local Items = require(ReplicatedStorage.Shared.Catalog.Items)
local JournalCatalog = require(ReplicatedStorage.Shared.Catalog.JournalCatalog)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Util = require(ReplicatedStorage.Shared.Util.Util)
local State = require(script.Parent.Parent.State)
local Registry = require(script.Parent.Parent.Registry)
local Kit = require(script.Parent.Parent.UI.Kit)

local HUDController = {}

local player = Players.LocalPlayer
local C = Kit.C

local gui: ScreenGui
local faded: CanvasGroup
local objectivesFrame: Frame
local counter: TextLabel
local teamFrame: Frame
local batteryFill: Frame
local batteryLabel: TextLabel
local staminaFrame: Frame
local staminaFill: Frame
local slotsFrame: Frame
local slotViews = {}
local slotHint: TextLabel
local crosshair: Frame
local promptFrame: Frame
local promptKey: TextLabel
local promptText: TextLabel
local promptBar: Frame
local focusRing: Frame
local focusFill: Frame
local toastList: Frame
local cardLayer: Frame
local captionLabel: TextLabel
local hintLabel: TextLabel
local escapeLabel: TextLabel
local hintToken = 0
local captionToken = 0

------------------------------------------------------------------------------------
-- Construction
------------------------------------------------------------------------------------

local function bar(parent: Instance, label: string, y: number): (Frame, Frame, TextLabel)
	local holder = Kit.frame({ Size = UDim2.fromOffset(260, 30), Position = UDim2.new(0, 0, 0, y), BackgroundTransparency = 1, Parent = parent })
	local text = Kit.text({ Text = label, Size = UDim2.fromOffset(260, 16), FontFace = Kit.F.Heading, TextSize = 13, TextColor3 = C.TextDim, Parent = holder })
	local track = Kit.frame({ Size = UDim2.fromOffset(220, 4), Position = UDim2.fromOffset(0, 20), BackgroundColor3 = C.Line, BackgroundTransparency = 0.2, Parent = holder })
	local fill = Kit.frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.Battery, Parent = track })
	return holder, fill, text
end

local function buildSlots()
	slotsFrame = Kit.frame({ Size = UDim2.fromOffset(4 * 96 + 3 * 10, 96), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -36), BackgroundTransparency = 1, Parent = faded })
	Kit.list(slotsFrame, 10, true)
	for i = 1, GameConfig.Inventory.Slots do
		local slot = Kit.new("TextButton", { AutoButtonColor = false, Text = "", Size = UDim2.fromOffset(96, 96), BackgroundColor3 = C.Panel, BackgroundTransparency = 0.35, LayoutOrder = i, Parent = slotsFrame })
		Kit.corner(slot, 4)
		local stroke = Kit.stroke(slot, C.Line, 1, 0.3)
		local num = Kit.text({ Text = tostring(i), Size = UDim2.fromOffset(20, 16), Position = UDim2.fromOffset(6, 4), FontFace = Kit.F.Mono, TextSize = 12, TextColor3 = C.Muted, Parent = slot })
		local glyph = Kit.text({ Text = "", Size = UDim2.new(1, 0, 0, 40), Position = UDim2.fromOffset(0, 16), TextXAlignment = Enum.TextXAlignment.Center, FontFace = Kit.F.Title, TextSize = 30, Parent = slot })
		local name = Kit.text({ Text = "", Size = UDim2.new(1, -8, 0, 26), Position = UDim2.new(0, 4, 1, -30), TextXAlignment = Enum.TextXAlignment.Center, FontFace = Kit.F.Body, TextSize = 12, TextColor3 = C.TextDim, Parent = slot })
		local count = Kit.text({ Text = "", Size = UDim2.fromOffset(30, 16), Position = UDim2.new(1, -34, 0, 4), TextXAlignment = Enum.TextXAlignment.Right, FontFace = Kit.F.Mono, TextSize = 13, Parent = slot })
		slot.Activated:Connect(function()
			local inv = State.inventory
			if inv.selected == i and inv.slots[i] then
				Net.event("Inventory"):FireServer("use", i)
			else
				Net.event("Inventory"):FireServer("select", i)
			end
		end)
		slotViews[i] = { frame = slot, stroke = stroke, glyph = glyph, name = name, count = count, num = num }
	end
	slotHint = Kit.text({ Text = "", Size = UDim2.fromOffset(420, 18), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -138), TextXAlignment = Enum.TextXAlignment.Center, FontFace = Kit.F.Light, TextSize = 13, TextColor3 = C.Muted, Parent = faded })
end

function HUDController:Init()
	gui = Kit.screen("HUD", 2)
	faded = Kit.new("CanvasGroup", { Name = "Faded", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = gui })
	-- objectives
	objectivesFrame = Kit.frame({ Size = UDim2.fromOffset(460, 300), Position = UDim2.fromOffset(40, 36), BackgroundTransparency = 1, Parent = faded })
	Kit.list(objectivesFrame, 6)
	counter = Kit.text({ Text = "", Size = UDim2.fromOffset(300, 20), Position = UDim2.new(1, -340, 0, 36), TextXAlignment = Enum.TextXAlignment.Right, FontFace = Kit.F.Mono, TextSize = 14, TextColor3 = C.TextDim, Parent = faded })
	-- team list
	teamFrame = Kit.frame({ Size = UDim2.fromOffset(300, 160), Position = UDim2.new(1, -340, 0, 66), BackgroundTransparency = 1, Parent = faded })
	Kit.list(teamFrame, 4, false, Enum.HorizontalAlignment.Right)
	-- battery / stamina
	local bars = Kit.frame({ Size = UDim2.fromOffset(260, 80), Position = UDim2.new(0, 40, 1, -110), BackgroundTransparency = 1, Parent = faded })
	local _, bf, bl = bar(bars, "LIGHT", 0)
	batteryFill, batteryLabel = bf, bl
	local sf
	staminaFrame, sf = bar(bars, "BREATH", 40)
	staminaFill = sf
	staminaFill.BackgroundColor3 = C.Stamina
	buildSlots()
	escapeLabel = Kit.text({ Text = "", Size = UDim2.fromOffset(500, 36), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 34), TextXAlignment = Enum.TextXAlignment.Center, FontFace = Kit.F.Title, TextSize = 28, TextColor3 = C.Text, Visible = false, Parent = gui })
	-- centre
	crosshair = Kit.frame({ Size = UDim2.fromOffset(4, 4), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), BackgroundColor3 = C.Text, BackgroundTransparency = 0.35, Parent = gui })
	Kit.corner(crosshair, 2)
	focusRing = Kit.frame({ Size = UDim2.fromOffset(64, 64), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), BackgroundTransparency = 1, Visible = false, Parent = gui })
	Kit.corner(focusRing, 32)
	Kit.stroke(focusRing, C.Text, 2, 0.5)
	focusFill = Kit.frame({ Size = UDim2.fromOffset(0, 0), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), BackgroundColor3 = C.Text, BackgroundTransparency = 0.75, Parent = focusRing })
	Kit.corner(focusFill, 32)
	promptFrame = Kit.frame({ Size = UDim2.fromOffset(420, 40), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.5, 46), BackgroundTransparency = 1, Visible = false, Parent = gui })
	local keyChip = Kit.frame({ Size = UDim2.fromOffset(54, 30), Position = UDim2.fromOffset(0, 5), BackgroundColor3 = C.Text, BackgroundTransparency = 0.05, Parent = promptFrame })
	Kit.corner(keyChip, 4)
	promptKey = Kit.text({ Text = "E", Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, FontFace = Kit.F.Heading, TextSize = 14, TextColor3 = C.Black, Parent = keyChip })
	promptText = Kit.text({ Text = "", Size = UDim2.fromOffset(350, 40), Position = UDim2.fromOffset(66, 0), FontFace = Kit.F.Body, TextSize = 19, TextStrokeTransparency = 0.7, Parent = promptFrame })
	local promptTrack = Kit.frame({ Size = UDim2.fromOffset(240, 3), Position = UDim2.fromOffset(66, 38), BackgroundColor3 = C.Line, Parent = promptFrame })
	promptBar = Kit.frame({ Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.Text, Parent = promptTrack })
	-- toasts (top centre)
	toastList = Kit.frame({ Size = UDim2.fromOffset(620, 300), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 86), BackgroundTransparency = 1, Parent = gui })
	Kit.list(toastList, 6, false, Enum.HorizontalAlignment.Center)
	cardLayer = Kit.frame({ Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = gui })
	captionLabel = Kit.text({ Text = "", Size = UDim2.fromOffset(1100, 60), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -170), TextXAlignment = Enum.TextXAlignment.Center, FontFace = Kit.F.Body, TextSize = 22, TextStrokeTransparency = 0.4, TextTransparency = 1, Parent = gui })
	hintLabel = Kit.text({ Text = "", Size = UDim2.fromOffset(900, 30), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.5, 96), TextXAlignment = Enum.TextXAlignment.Center, FontFace = Kit.F.Light, TextSize = 18, TextColor3 = C.TextDim, TextTransparency = 1, Parent = gui })
	gui.Enabled = false
end

------------------------------------------------------------------------------------
-- Updates
------------------------------------------------------------------------------------

function HUDController:SetPrompt(key: string?, text: string?, isHold: boolean?, progress: number?)
	if not key or State.status ~= "ALIVE" and State.status ~= "LOBBY" then
		promptFrame.Visible = false
		return
	end
	promptFrame.Visible = true
	promptKey.Text = if isHold then "HOLD " .. key else key
	promptText.Text = text or ""
	promptBar.Parent.Visible = isHold == true
	promptBar.Size = UDim2.fromScale(progress or 0, 1)
end

function HUDController:SetFocus(progress: number?)
	if not progress then
		focusRing.Visible = false
		return
	end
	focusRing.Visible = true
	local size = 64 * progress
	focusFill.Size = UDim2.fromOffset(size, size)
	focusRing.Size = UDim2.fromOffset(64 - 16 * progress, 64 - 16 * progress)
end

function HUDController:Hint(text: string, duration: number?)
	hintToken += 1
	local token = hintToken
	hintLabel.Text = text
	Kit.tween(hintLabel, 0.4, { TextTransparency = 0 })
	task.delay(duration or 4, function()
		if token == hintToken then
			Kit.tween(hintLabel, 0.8, { TextTransparency = 1 })
		end
	end)
end

function HUDController:Caption(text: string, duration: number?, speaker: string?)
	if not State.settings.subtitles and speaker ~= "tape" then
		return
	end
	captionToken += 1
	local token = captionToken
	captionLabel.Text = text
	captionLabel.FontFace = if speaker == "tape" then Kit.F.Type else Kit.F.Body
	captionLabel.TextColor3 = if speaker == "whisper" then C.TextDim else C.Text
	Kit.tween(captionLabel, 0.3, { TextTransparency = 0 })
	task.delay(duration or 3.5, function()
		if token == captionToken then
			Kit.tween(captionLabel, 0.6, { TextTransparency = 1 })
		end
	end)
end

-- Accessibility: a short label on a ring around the crosshair, pointing to where
-- a meaningful sound came from. It follows the sound while it fades.
function HUDController:SoundIndicator(position: Vector3, text: string)
	local holder = Kit.frame({ Size = UDim2.fromOffset(200, 26), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, Parent = gui })
	local chip = Kit.frame({ Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.Black, BackgroundTransparency = 0.4, Parent = holder })
	Kit.corner(chip, 4)
	local arrow = Kit.text({ Text = "▲", Size = UDim2.fromOffset(22, 22), Position = UDim2.fromOffset(4, 2), TextXAlignment = Enum.TextXAlignment.Center, FontFace = Kit.F.Heading, TextSize = 16, Parent = chip })
	Kit.text({ Text = string.upper(text), Size = UDim2.new(1, -32, 1, 0), Position = UDim2.fromOffset(28, 0), FontFace = Kit.F.Mono, TextSize = 13, TextColor3 = C.TextDim, Parent = chip })
	local start = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - start
		if t > 2.6 or not holder.Parent then
			conn:Disconnect()
			holder:Destroy()
			return
		end
		local camera = workspace.CurrentCamera
		local rel = camera.CFrame:PointToObjectSpace(position)
		local angle = math.atan2(rel.X, -rel.Z)
		local radius = 0.2
		holder.Position = UDim2.fromScale(0.5 + math.sin(angle) * radius * 0.6, 0.5 - math.cos(angle) * radius)
		arrow.Rotation = math.deg(angle)
		local alpha = math.clamp((t - 1.8) / 0.8, 0, 1)
		chip.BackgroundTransparency = 0.4 + alpha * 0.6
		for _, d in chip:GetChildren() do
			if d:IsA("TextLabel") then
				d.TextTransparency = alpha
			end
		end
	end)
end

function HUDController:Toast(text: string, kind: string?, sub: string?)
	local color = if kind == "danger" then C.Danger elseif kind == "warning" then Color3.fromRGB(214, 190, 140) elseif kind == "team" then Color3.fromRGB(190, 206, 220) else C.Text
	local toast = Kit.frame({ Size = UDim2.fromOffset(560, if sub then 52 else 36), BackgroundColor3 = C.Black, BackgroundTransparency = 0.45, Parent = toastList })
	Kit.corner(toast, 4)
	local label = Kit.text({ Text = text, Size = UDim2.new(1, -24, 0, 30), Position = UDim2.fromOffset(12, 3), TextXAlignment = Enum.TextXAlignment.Center, FontFace = Kit.F.Heading, TextSize = 17, TextColor3 = color, Parent = toast })
	local subLabel = nil
	if sub then
		subLabel = Kit.text({ Text = sub, Size = UDim2.new(1, -24, 0, 18), Position = UDim2.fromOffset(12, 30), TextXAlignment = Enum.TextXAlignment.Center, FontFace = Kit.F.Mono, TextSize = 13, TextColor3 = C.TextDim, Parent = toast })
	end
	toast.BackgroundTransparency = 1
	label.TextTransparency = 1
	Kit.tween(toast, 0.25, { BackgroundTransparency = 0.45 })
	Kit.tween(label, 0.25, { TextTransparency = 0 })
	task.delay(3.4, function()
		Kit.tween(toast, 0.6, { BackgroundTransparency = 1 })
		Kit.tween(label, 0.6, { TextTransparency = 1 })
		if subLabel then
			Kit.tween(subLabel, 0.6, { TextTransparency = 1 })
		end
		Debris:AddItem(toast, 0.7)
	end)
	-- never pile up
	local count = 0
	for _, c in toastList:GetChildren() do
		if c:IsA("Frame") then
			count += 1
		end
	end
	if count > 4 then
		for _, c in toastList:GetChildren() do
			if c:IsA("Frame") and c ~= toast then
				c:Destroy()
				break
			end
		end
	end
end

-- A thought written in the notebook (soft guidance), under the objectives.
local noteToken = 0
function HUDController:NoteHint(text: string, duration: number?)
	noteToken += 1
	local token = noteToken
	local holder = gui:FindFirstChild("NoteHint")
	if holder then
		holder:Destroy()
	end
	local note = Kit.frame({ Name = "NoteHint", Size = UDim2.fromOffset(470, 0), AutomaticSize = Enum.AutomaticSize.Y, Position = UDim2.fromOffset(40, 300), BackgroundColor3 = Color3.fromRGB(214, 206, 184), BackgroundTransparency = 0.12, Parent = gui })
	Kit.corner(note, 3)
	Kit.padding(note, 10, 14)
	local label = Kit.text({ Text = text, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, FontFace = Kit.F.Type, TextSize = 17, TextColor3 = Color3.fromRGB(34, 30, 26), TextWrapped = true, Parent = note })
	note.BackgroundTransparency = 1
	label.TextTransparency = 1
	Kit.tween(note, 0.5, { BackgroundTransparency = 0.12 })
	Kit.tween(label, 0.5, { TextTransparency = 0 })
	Kit.sound("PaperRustle")
	task.delay(duration or 8, function()
		if token == noteToken and note.Parent then
			Kit.tween(note, 1, { BackgroundTransparency = 1 })
			Kit.tween(label, 1, { TextTransparency = 1 })
			Debris:AddItem(note, 1.1)
		end
	end)
end

-- Short coaching line for new players (bottom centre, above the prompt).
local coachToken = 0
function HUDController:Coach(text: string, duration: number?)
	coachToken += 1
	local token = coachToken
	local existing = gui:FindFirstChild("Coach")
	if existing then
		existing:Destroy()
	end
	local chip = Kit.frame({ Name = "Coach", Size = UDim2.fromOffset(0, 40), AutomaticSize = Enum.AutomaticSize.X, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -200), BackgroundColor3 = C.Black, BackgroundTransparency = 0.35, Parent = gui })
	Kit.corner(chip, 4)
	Kit.padding(chip, 0, 18)
	local label = Kit.text({ Text = text, Size = UDim2.fromOffset(0, 40), AutomaticSize = Enum.AutomaticSize.X, TextXAlignment = Enum.TextXAlignment.Center, FontFace = Kit.F.Body, TextSize = 17, Parent = chip })
	chip.BackgroundTransparency = 1
	label.TextTransparency = 1
	Kit.tween(chip, 0.35, { BackgroundTransparency = 0.35 })
	Kit.tween(label, 0.35, { TextTransparency = 0 })
	task.delay(duration or 5, function()
		if token == coachToken and chip.Parent then
			Kit.tween(chip, 0.6, { BackgroundTransparency = 1 })
			Kit.tween(label, 0.6, { TextTransparency = 1 })
			Debris:AddItem(chip, 0.7)
		end
	end)
end

-- Last-resort guidance: a faint marker toward a place for a few seconds.
function HUDController:GuideMarker(at: Vector3, text: string?)
	local marker = Kit.frame({ Size = UDim2.fromOffset(160, 44), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, Parent = gui })
	local diamond = Kit.frame({ Size = UDim2.fromOffset(14, 14), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, 10), Rotation = 45, BackgroundTransparency = 1, Parent = marker })
	Kit.stroke(diamond, C.Text, 2, 0.2)
	local label = Kit.text({ Text = string.upper(text or ""), Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 24), TextXAlignment = Enum.TextXAlignment.Center, FontFace = Kit.F.Mono, TextSize = 12, TextColor3 = C.TextDim, Parent = marker })
	local start = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - start
		if t > 15 or not marker.Parent or State.status ~= "ALIVE" then
			conn:Disconnect()
			marker:Destroy()
			return
		end
		local camera = workspace.CurrentCamera
		local viewport = camera.ViewportSize
		local screen, onScreen = camera:WorldToViewportPoint(at)
		local x, y = screen.X, screen.Y
		if not onScreen or screen.Z < 0 then
			-- clamp to the screen edge in the right direction
			local rel = camera.CFrame:PointToObjectSpace(at)
			local angle = math.atan2(rel.X, -rel.Z)
			x = viewport.X / 2 + math.sin(angle) * viewport.X * 0.42
			y = viewport.Y / 2 - math.cos(angle) * viewport.Y * 0.4
		end
		marker.Position = UDim2.fromOffset(x, y)
		local alpha = math.clamp((t - 12) / 3, 0, 1)
		label.TextTransparency = alpha
		local stroke = diamond:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Transparency = 0.2 + alpha * 0.8
		end
	end)
end

-- Big card for a new journal entry, achievement or level.
function HUDController:Card(title: string, heading: string, body: string?, color: Color3?)
	local card = Kit.frame({ Size = UDim2.fromOffset(460, 128), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 40, 0, 240), BackgroundColor3 = C.Panel, BackgroundTransparency = 0.08, Parent = cardLayer })
	Kit.corner(card, 4)
	Kit.stroke(card, color or C.Line, 1, 0.1)
	Kit.frame({ Size = UDim2.new(0, 3, 1, 0), BackgroundColor3 = color or C.Text, Parent = card })
	Kit.text({ Text = title, Size = UDim2.new(1, -40, 0, 18), Position = UDim2.fromOffset(22, 14), FontFace = Kit.F.Mono, TextSize = 13, TextColor3 = color or C.TextDim, Parent = card })
	Kit.text({ Text = heading, Size = UDim2.new(1, -40, 0, 34), Position = UDim2.fromOffset(22, 34), FontFace = Kit.F.Title, TextSize = 26, Parent = card })
	if body then
		Kit.text({ Text = body, Size = UDim2.new(1, -40, 0, 44), Position = UDim2.fromOffset(22, 72), FontFace = Kit.F.Light, TextSize = 14, TextColor3 = C.TextDim, TextYAlignment = Enum.TextYAlignment.Top, Parent = card })
	end
	Kit.tween(card, TweenInfo.new(0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Position = UDim2.new(1, -40, 0, 240) })
	task.delay(5, function()
		Kit.tween(card, TweenInfo.new(0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.In), { Position = UDim2.new(1, 520, 0, 240) })
		Debris:AddItem(card, 0.6)
	end)
end

local function renderObjectives()
	for _, c in objectivesFrame:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	local data = State.objectives
	for i, item in data.list or {} do
		local row = Kit.frame({ Size = UDim2.fromOffset(460, if item.primary then 28 else 24), BackgroundTransparency = 1, LayoutOrder = i, Parent = objectivesFrame })
		if item.hint then
			-- a soft-guidance line: where to go, in the notebook's hand
			Kit.text({ Text = item.text, Size = UDim2.new(1, -22, 1, 0), Position = UDim2.fromOffset(22, 0), FontFace = Kit.F.Type, TextSize = 15, TextColor3 = Color3.fromRGB(214, 206, 184), TextStrokeTransparency = 0.7, Parent = row })
			continue
		end
		local box = Kit.frame({ Size = UDim2.fromOffset(10, 10), Position = UDim2.new(0, 0, 0.5, -5), BackgroundColor3 = if item.done then C.Text else C.Panel, BackgroundTransparency = if item.done then 0.1 else 0.5, Parent = row })
		Kit.stroke(box, C.TextDim, 1, 0.2)
		Kit.text({
			Text = item.text,
			Size = UDim2.new(1, -22, 1, 0),
			Position = UDim2.fromOffset(22, 0),
			FontFace = if item.primary then Kit.F.Heading else Kit.F.Body,
			TextSize = if item.primary then 18 else 16,
			TextColor3 = if item.done then C.Muted elseif item.dim then C.TextDim else C.Text,
			TextStrokeTransparency = 0.75,
			Parent = row,
		})
	end
	counter.Text = if (data.quota or 0) > 0 then string.format("ANOMALIES  %d / %d", data.found or 0, data.quota) else ""
end

local function renderInventory()
	local inv = State.inventory
	for i, view in slotViews do
		local slot = inv.slots and inv.slots[i]
		local selected = inv.selected == i
		view.stroke.Color = if selected then C.Text else C.Line
		view.stroke.Transparency = if selected then 0 else 0.3
		if slot then
			local def = Items.get(slot.id)
			view.glyph.Text = string.sub(def and def.name or slot.id, 1, 1)
			view.glyph.TextColor3 = def and def.color:Lerp(C.Text, 0.5) or C.Text
			view.name.Text = def and def.name or slot.id
			view.count.Text = if slot.count > 1 then "x" .. slot.count else ""
		else
			view.glyph.Text = ""
			view.name.Text = ""
			view.count.Text = ""
		end
	end
	local sel = inv.slots and inv.slots[inv.selected]
	if sel then
		local def = Items.get(sel.id)
		local parts = {}
		if def and def.usable then
			table.insert(parts, "[" .. Registry.InputController:Label("UseItem") .. "] Use")
		end
		table.insert(parts, "[" .. Registry.InputController:Label("DropItem") .. "] Drop")
		slotHint.Text = table.concat(parts, "     ")
	else
		slotHint.Text = ""
	end
end

local function renderTeam()
	for _, c in teamFrame:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	local inRound = {}
	for _, p in State.players do
		if p.status == "ALIVE" or p.status == "DEAD" or p.status == "ESCAPED" then
			table.insert(inRound, p)
		end
	end
	if #inRound <= 1 then
		return
	end
	for i, p in inRound do
		local row = Kit.frame({ Size = UDim2.fromOffset(300, 22), BackgroundTransparency = 1, LayoutOrder = i, Parent = teamFrame })
		local statusText = if p.status == "ALIVE" then "" elseif p.status == "ESCAPED" then "  OUT" else "  TAKEN"
		Kit.text({
			Text = p.name .. statusText,
			Size = UDim2.new(1, -18, 1, 0),
			TextXAlignment = Enum.TextXAlignment.Right,
			FontFace = Kit.F.Body,
			TextSize = 15,
			TextColor3 = if p.status == "ALIVE" then C.Text elseif p.status == "DEAD" then C.Danger else C.Muted,
			TextStrokeTransparency = 0.8,
			Parent = row,
		})
		local dot = Kit.frame({ Size = UDim2.fromOffset(8, 8), Position = UDim2.new(1, -8, 0.5, -4), BackgroundColor3 = if p.status == "ALIVE" then C.Text elseif p.status == "DEAD" then C.Danger else C.Muted, Parent = row })
		Kit.corner(dot, 4)
		if p.userId == player.UserId then
			row.LayoutOrder = 0
		end
	end
end

local function update(dt: number)
	local playing = State.status == "ALIVE"
	gui.Enabled = playing or State.status == "LOBBY"
	faded.Visible = playing
	crosshair.Visible = playing and not State.uiOpen
	if not playing then
		return
	end
	-- fear fades the HUD
	local target = math.clamp(State.fear * 0.85, 0, 0.72)
	faded.GroupTransparency += (target - faded.GroupTransparency) * Util.damp(2, dt)
	local battery = player:GetAttribute("Battery") or 100
	batteryFill.Size = UDim2.fromScale(math.clamp(battery / 100, 0, 1), 1)
	batteryFill.BackgroundColor3 = if battery < GameConfig.Flashlight.LowBatteryThreshold then C.Danger else C.Battery
	batteryLabel.Text = string.format("LIGHT  %d%%%s", math.floor(battery + 0.5), if player:GetAttribute("Flashlight") then "" else "  OFF")
	local stamina = State.stamina / GameConfig.Movement.StaminaMax
	staminaFrame.Visible = stamina < 0.995
	staminaFill.Size = UDim2.fromScale(stamina, 1)
	-- escape timer
	if State.round.state == "ESCAPE" and State.round.escapeEndsAt then
		local remaining = math.max(0, State.round.escapeEndsAt - os.clock())
		escapeLabel.Visible = true
		escapeLabel.Text = "GET OUT   " .. Util.formatTime(remaining)
		escapeLabel.TextColor3 = if remaining < 30 then C.Danger else C.Text
	else
		escapeLabel.Visible = false
	end
end

function HUDController:Start()
	State.ObjectivesChanged:Connect(renderObjectives)
	State.InventoryChanged:Connect(renderInventory)
	State.InputTypeChanged:Connect(renderInventory)
	State.RoundChanged:Connect(renderTeam)
	Net.event("PlayerStates").OnClientEvent:Connect(function(list)
		if type(list) == "table" then
			State.players = list
			renderTeam()
		end
	end)
	Net.event("Notify").OnClientEvent:Connect(function(p)
		if type(p) ~= "table" then
			return
		end
		if p.kind == "anomaly" then
			self:Toast("ANOMALY REPORTED", "info", (p.sub or "") .. "  " .. (p.text or ""))
		elseif p.kind == "item" then
			self:Toast("+ " .. (p.text or ""), "info")
		elseif p.kind == "objective" then
			Registry.EffectsController:Title(p.text or "", p.sub, if p.sub then 3.4 else 2.6, Kit.F.Heading)
		elseif p.kind == "hint" then
			self:NoteHint(p.text or "")
		else
			self:Toast(p.text or "", p.kind)
		end
	end)
	Net.event("Unlock").OnClientEvent:Connect(function(p)
		if type(p) ~= "table" then
			return
		end
		if p.type == "journal" then
			self:Card(JournalCatalog.format(p.number or 0) .. "  NEW ENTRY", p.name or "", p.description, JournalCatalog.RarityColors[p.rarity] or C.Text)
		elseif p.type == "achievement" then
			self:Card("ACHIEVEMENT", p.name or "", (p.description or "") .. if p.echoes then ("   +" .. p.echoes .. " ECHOES") else "", C.Good)
		elseif p.type == "level" then
			local unlocked = if p.unlocked and #p.unlocked > 0 then "Unlocked: " .. table.concat(p.unlocked, ", ") else nil
			self:Card("LEVEL UP", "LEVEL " .. tostring(p.level), unlocked, C.Text)
		elseif p.type == "cosmetic" then
			self:Toast("Unlocked: " .. (p.name or ""), "info")
		end
	end)
	Net.event("Caption").OnClientEvent:Connect(function(p)
		if type(p) == "table" and type(p.text) == "string" then
			self:Caption(p.text, p.duration, p.speaker)
		end
	end)
	Registry.InputController.Action:Connect(function(action, began)
		if not began or State.status ~= "ALIVE" or State.uiOpen then
			return
		end
		local inv = State.inventory
		local idx = tonumber(string.match(action, "^Slot(%d)$"))
		if idx then
			Net.event("Inventory"):FireServer("select", idx)
		elseif action == "SlotNext" then
			Net.event("Inventory"):FireServer("select", inv.selected % GameConfig.Inventory.Slots + 1)
		elseif action == "SlotPrev" then
			Net.event("Inventory"):FireServer("select", (inv.selected - 2) % GameConfig.Inventory.Slots + 1)
		elseif action == "UseItem" then
			Net.event("Inventory"):FireServer("use", inv.selected)
		elseif action == "DropItem" then
			Net.event("Inventory"):FireServer("drop", inv.selected)
		end
	end)
	-- mouse wheel cycles slots
	game:GetService("UserInputService").InputChanged:Connect(function(input, processed)
		if processed or State.status ~= "ALIVE" or State.uiOpen then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			local inv = State.inventory
			local dir = if input.Position.Z > 0 then -1 else 1
			Net.event("Inventory"):FireServer("select", (inv.selected - 1 + dir) % GameConfig.Inventory.Slots + 1)
		end
	end)
	RunService.RenderStepped:Connect(update)
	renderObjectives()
	renderInventory()
end

return HUDController
