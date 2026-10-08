--[[
	Panel
	The Marketing Studio window (developer only; toggle with F7):

	  MARKETING STUDIO
	  [Scene01_Door] [Scene02_...] ...
	  [▶ PLAY] [⏸ PAUSE] [↻ RESTART] [■ STOP]
	  Format: [9:16]   Camera: [AUTO]
	  [Hide HUD] [Hide me] [Freeze me] [Mute game] [Loop] [Slow-mo]

	It hides itself while a scene plays (so it is never in the recording) and
	comes back when the scene ends or F7 is pressed.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local Format = require(script.Parent.Parent.Utilities.Format)
local Presets = require(script.Parent.Parent.Cameras.Presets)

local Panel = {}

local C = {
	bg = Color3.fromRGB(12, 12, 14),
	line = Color3.fromRGB(150, 40, 40),
	text = Color3.fromRGB(226, 222, 214),
	dim = Color3.fromRGB(140, 138, 132),
	button = Color3.fromRGB(28, 28, 32),
	active = Color3.fromRGB(120, 30, 30),
}

local gui: ScreenGui? = nil
local window: Frame? = nil
local status: TextLabel? = nil
local selected: string? = nil
local sceneButtons: { [string]: TextButton } = {}
local description: TextLabel? = nil
local toggles: { [string]: TextButton } = {}
local formatButton: TextButton? = nil
local cameraButton: TextButton? = nil
local controller: any = nil
local mounted = false
local openerButton: TextButton? = nil
local lightButton: TextButton? = nil

local function label(parent: Instance, text: string, size: number, color: Color3?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.new(1, 0, 0, size + 6)
	l.Font = Enum.Font.GothamBold
	l.TextSize = size
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextColor3 = color or C.text
	l.Text = text
	l.Parent = parent
	return l
end

local function button(parent: Instance, text: string, width: number, onClick: () -> ()): TextButton
	local b = Instance.new("TextButton")
	b.AutoButtonColor = true
	b.BackgroundColor3 = C.button
	b.BorderSizePixel = 0
	b.Size = UDim2.fromOffset(width, 34)
	b.Font = Enum.Font.GothamMedium
	b.TextSize = 15
	b.TextColor3 = C.text
	b.Text = text
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = b
	b.Parent = parent
	b.Activated:Connect(onClick)
	return b
end

local function row(parent: Instance, order: number, height: number?): Frame
	local f = Instance.new("Frame")
	f.BackgroundTransparency = 1
	f.Size = UDim2.new(1, 0, 0, height or 36)
	f.LayoutOrder = order
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.Padding = UDim.new(0, 6)
	list.Wraps = true
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = f
	f.Parent = parent
	return f
end

local function nextOf(list: { string }, current: string): string
	local i = table.find(list, current) or 0
	return list[i % #list + 1]
end

local function refresh()
	if not controller or not window then
		return
	end
	local state = controller.GetState()
	for name, b in sceneButtons do
		b.BackgroundColor3 = if name == selected then C.active else C.button
	end
	if description and selected then
		local info = controller.SceneInfo(selected)
		description.Text = if info then string.format("%s  —  %s", info.Category, info.Description) else ""
	end
	if formatButton then
		local preset = Format.Presets[state.format]
		formatButton.Text = "Format: " .. (if preset then preset.label else state.format)
	end
	if cameraButton then
		cameraButton.Text = "Camera: " .. state.camera
	end
	if lightButton then
		lightButton.Text = "Light: " .. tostring(state.options.Light or 0)
	end
	for key, b in toggles do
		local on = if key == "TimeScale" then state.options.TimeScale < 1 else state.options[key] == true
		b.BackgroundColor3 = if on then C.active else C.button
	end
	if openerButton then
		openerButton.Visible = not state.playing
	end
	if status then
		local where = if state.building then "in the building" else "no building here: virtual set (start a round for real locations)"
		if state.playing then
			status.Text = string.format("%s  %s  %.1f / %.1f s", if state.paused then "⏸" else "▶", state.scene or "", state.clock, state.duration)
		else
			status.Text = "Ready · " .. where
		end
	end
end

function Panel.setVisible(on: boolean)
	if window then
		window.Visible = on
	end
	local ok, err = pcall(refresh)
	if not ok then
		warn("[Marketing] panel refresh failed: " .. tostring(err))
	end
end

function Panel.isVisible(): boolean
	return window ~= nil and window.Visible
end

function Panel.mount(ctrl: any, config: any)
	controller = ctrl
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local g = Instance.new("ScreenGui")
	g.Name = "MarketingStudioPanel"
	g.ResetOnSpawn = false
	g.DisplayOrder = 1000
	g.IgnoreGuiInset = true
	gui = g
	local w = Instance.new("Frame")
	w.Name = "Window"
	w.BackgroundColor3 = C.bg
	w.BackgroundTransparency = 0.05
	w.BorderSizePixel = 0
	w.AnchorPoint = Vector2.new(0.5, 0.5)
	w.Position = UDim2.fromScale(0.5, 0.5)
	w.Size = UDim2.fromOffset(600, 720)
	w.Visible = false
	local stroke = Instance.new("UIStroke")
	stroke.Color = C.line
	stroke.Thickness = 2
	stroke.Parent = w
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 14)
	pad.PaddingRight = UDim.new(0, 14)
	pad.PaddingTop = UDim.new(0, 12)
	pad.Parent = w
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 8)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = w
	w.Parent = g
	window = w

	local title = label(w, "MARKETING STUDIO", 20, C.line)
	title.LayoutOrder = 1
	local hint = label(w, "Developer only · " .. config.ToggleKey.Name .. " or the 🎬 button to show/hide · hides itself while recording", 12, C.dim)
	hint.LayoutOrder = 2

	-- search + a scrolling list of every scene, grouped by category
	local search = Instance.new("TextBox")
	search.Name = "Search"
	search.LayoutOrder = 3
	search.Size = UDim2.new(1, 0, 0, 30)
	search.BackgroundColor3 = C.button
	search.BorderSizePixel = 0
	search.ClearTextOnFocus = false
	search.PlaceholderText = "Search scenes (name, category, words in the description)"
	search.PlaceholderColor3 = C.dim
	search.Text = ""
	search.TextColor3 = C.text
	search.Font = Enum.Font.Gotham
	search.TextSize = 14
	search.TextXAlignment = Enum.TextXAlignment.Left
	local searchPad = Instance.new("UIPadding")
	searchPad.PaddingLeft = UDim.new(0, 8)
	searchPad.Parent = search
	search.Parent = w

	local sceneList = Instance.new("ScrollingFrame")
	sceneList.Name = "Scenes"
	sceneList.LayoutOrder = 4
	sceneList.Size = UDim2.new(1, 0, 0, 300)
	sceneList.BackgroundTransparency = 1
	sceneList.BorderSizePixel = 0
	sceneList.ScrollBarThickness = 6
	sceneList.CanvasSize = UDim2.new()
	sceneList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 3)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = sceneList
	sceneList.Parent = w

	local headers: { [string]: TextLabel } = {}
	local entries: { { name: string, button: TextButton, info: any } } = {}
	local lastCategory = nil
	for i, name in controller.ListScenes() do
		local info = controller.SceneInfo(name) or { Name = name, Category = "", Description = "", Duration = 0 }
		if info.Category ~= lastCategory then
			lastCategory = info.Category
			local h = label(sceneList, string.upper(info.Category), 13, C.line)
			h.LayoutOrder = i * 2 - 1
			headers[info.Category] = h
		end
		local shortName = string.gsub(name, "^Scene_?", "")
		local b = button(sceneList, string.format("%s   ·  %.0fs", shortName, info.Duration), 520, function()
			selected = name
			refresh()
		end)
		b.LayoutOrder = i * 2
		b.TextSize = 13
		b.TextXAlignment = Enum.TextXAlignment.Left
		b.Size = UDim2.new(1, -10, 0, 26)
		local bp = Instance.new("UIPadding")
		bp.PaddingLeft = UDim.new(0, 8)
		bp.Parent = b
		sceneButtons[name] = b
		table.insert(entries, { name = name, button = b, info = info })
		selected = selected or name
	end
	local function applySearch()
		local q = string.lower(search.Text)
		local visibleCategories: { [string]: boolean } = {}
		for _, e in entries do
			local hay = string.lower(e.name .. " " .. e.info.Category .. " " .. e.info.Description)
			local show = q == "" or string.find(hay, q, 1, true) ~= nil
			e.button.Visible = show
			if show then
				visibleCategories[e.info.Category] = true
			end
		end
		for category, h in headers do
			h.Visible = visibleCategories[category] == true
		end
	end
	search:GetPropertyChangedSignal("Text"):Connect(applySearch)

	-- what the selected scene is
	local desc = label(w, "", 13, C.text)
	desc.LayoutOrder = 5
	desc.TextWrapped = true
	desc.Size = UDim2.new(1, 0, 0, 34)
	desc.Font = Enum.Font.Gotham
	description = desc

	local transport = row(w, 6)
	button(transport, "▶ PLAY", 120, function()
		if not selected then
			return
		end
		if controller.IsPlaying() and controller.GetState().paused then
			controller.ResumeScene()
		else
			controller.PlayScene(selected)
		end
		if controller.GetOption("HidePanelWhilePlaying") then
			Panel.setVisible(false)
		end
		refresh()
	end)
	button(transport, "⏸ PAUSE", 120, function()
		controller.PauseScene()
		refresh()
	end)
	button(transport, "↻ RESTART", 120, function()
		if selected then
			controller.PlayScene(selected)
			if controller.GetOption("HidePanelWhilePlaying") then
				Panel.setVisible(false)
			end
		end
		refresh()
	end)
	button(transport, "■ STOP", 120, function()
		controller.StopScene()
		refresh()
	end)

	local lens = row(w, 7)
	formatButton = button(lens, "Format", 130, function()
		controller.SetFormat(nextOf(Format.Order, controller.GetFormat()))
		refresh()
	end)
	local cams = { "AUTO" }
	for name in Presets do
		table.insert(cams, name)
	end
	table.sort(cams, function(a, b)
		if a == "AUTO" then
			return true
		elseif b == "AUTO" then
			return false
		end
		return a < b
	end)
	lightButton = button(lens, "Light", 90, function()
		controller.SetOption("Light", ((controller.GetOption("Light") or 3) + 1) % 5)
		refresh()
	end)
	cameraButton = button(lens, "Camera", 170, function()
		controller.SetCameraStyle(nextOf(cams, controller.GetCameraStyle()))
		refresh()
	end)

	local opts = row(w, 8, 76)
	for i, spec in { { "HideHUD", "Hide HUD" }, { "HideCharacter", "Hide me" }, { "FreezeCharacter", "Freeze me" }, { "MuteGameAudio", "Mute game" }, { "Loop", "Loop" }, { "TimeScale", "Slow-mo" } } do
		local key = spec[1]
		local b = button(opts, spec[2], 120, function()
			if key == "TimeScale" then
				controller.SetOption("TimeScale", if controller.GetOption("TimeScale") < 1 then 1 else 0.5)
			else
				controller.SetOption(key, not controller.GetOption(key))
			end
			refresh()
		end)
		b.LayoutOrder = i
		toggles[key] = b
	end

	local cinematic = row(w, 9)
	button(cinematic, "Cinematic mode (all on)", 250, function()
		for _, key in { "HideHUD", "HideCharacter", "FreezeCharacter", "MuteGameAudio", "HidePanelWhilePlaying" } do
			controller.SetOption(key, true)
		end
		refresh()
	end)

	status = label(w, "", 14, C.dim)
	;(status :: TextLabel).LayoutOrder = 10

	g.Parent = playerGui

	-- toggle: the keys work even when the game has already handled the input
	-- (it captures the keyboard for its own controls); never while typing
	local keys = { config.ToggleKey }
	for _, k in config.AltToggleKeys or {} do
		table.insert(keys, k)
	end
	local lastToggle = 0
	local function toggle()
		if os.clock() - lastToggle < 0.2 then
			return
		end
		lastToggle = os.clock()
		Panel.setVisible(not Panel.isVisible())
	end
	UserInputService.InputBegan:Connect(function(input)
		if table.find(keys, input.KeyCode) then
			if not UserInputService:GetFocusedTextBox() then
				toggle()
			end
		end
	end)
	-- a small on-screen button too (Studio can keep some function keys for itself);
	-- it hides while a scene plays so it never appears in a recording
	local opener = Instance.new("TextButton")
	opener.Name = "Opener"
	opener.AnchorPoint = Vector2.new(1, 1)
	opener.Position = UDim2.new(1, -16, 1, -16)
	opener.Size = UDim2.fromOffset(46, 46)
	opener.BackgroundColor3 = C.bg
	opener.BackgroundTransparency = 0.2
	opener.BorderSizePixel = 0
	opener.Text = "🎬"
	opener.TextSize = 24
	opener.Font = Enum.Font.GothamBold
	opener.TextColor3 = C.text
	local openerCorner = Instance.new("UICorner")
	openerCorner.CornerRadius = UDim.new(0.5, 0)
	openerCorner.Parent = opener
	local openerStroke = Instance.new("UIStroke")
	openerStroke.Color = C.line
	openerStroke.Parent = opener
	opener.Parent = g
	opener.Activated:Connect(function()
		toggle()
	end)
	openerButton = opener
	controller.Changed:Connect(function(state)
		if not state.playing and window and not window.Visible and controller.GetOption("HidePanelWhilePlaying") then
			-- a scene just ended: bring the panel back
			window.Visible = true
		end
		refresh()
	end)
	-- the game locks the mouse for first person; free it while the panel is open
	-- (bound after the game's camera, which locks the mouse every frame)
	RunService:BindToRenderStep("MarketingPanelMouse", Enum.RenderPriority.Last.Value, function()
		if window and window.Visible then
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			UserInputService.MouseIconEnabled = true
			if controller.IsPlaying() then
				refresh()
			end
		end
	end)
	mounted = true
	refresh()
end

function Panel.unmount()
	if mounted then
		mounted = false
		pcall(function()
			RunService:UnbindFromRenderStep("MarketingPanelMouse")
		end)
	end
	if gui then
		gui:Destroy()
		gui = nil
	end
	window = nil
end

return Panel
