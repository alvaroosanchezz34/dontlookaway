--[[
	SecurityCamController
	The security feed for players who are out of the round (taken, shut in or
	outside): a button over the spectator view opens the building's cameras.
	The server decides everything (SecurityCamService): this only asks for a
	camera and draws the feed, its static and the tape's hold bar from the
	player's attributes (CamIndex, CamState, CamHold).

	Keys: C open / close, Q and E (or the arrows) change camera. On touch and
	gamepad the on-screen buttons do the same.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Net = require(ReplicatedStorage.Shared.Net)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local State = require(script.Parent.Parent.State)
local Registry = require(script.Parent.Parent.Registry)

local SecurityCamController = {}

local player = Players.LocalPlayer
local active = false
local index = 1
local gui: ScreenGui
local openButton: TextButton
local feed: Frame
local label: TextLabel
local stateLabel: TextLabel
local rec: TextLabel
local holdFill: Frame
local noise: { Frame } = {}

local FONT = Enum.Font.Code
local WHITE = Color3.fromRGB(226, 226, 220)
local RED = Color3.fromRGB(220, 50, 40)

local function running(): boolean
	local s = State.round.state
	return s == "STARTING" or s == "EXPLORING" or s == "OBJECTIVE" or s == "ESCAPE"
end

local function eligible(): boolean
	return running() and (State.status == "DEAD" or State.status == "ESCAPED")
end

local function camList(): { BasePart }
	local list = {}
	local folder = Workspace:FindFirstChild("SecurityCams")
	if folder then
		for _, part in folder:GetChildren() do
			if part:IsA("BasePart") and part:GetAttribute("Index") then
				table.insert(list, part)
			end
		end
	end
	table.sort(list, function(a, b)
		return (a:GetAttribute("Index") :: number) < (b:GetAttribute("Index") :: number)
	end)
	return list
end

local function select(i: number)
	local list = camList()
	if #list == 0 then
		return
	end
	index = (i - 1) % #list + 1
	Net.event("SecurityCam"):FireServer(index)
end

local function setActive(on: boolean)
	if on and (not eligible() or #camList() == 0) then
		return
	end
	active = on
	feed.Visible = on
	openButton.Text = if on then "BACK  [C]" else "SECURITY CAMERAS  [C]"
	if on then
		select(index)
	else
		Net.event("SecurityCam"):FireServer(0)
	end
end

local function text(props): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Font = FONT
	t.TextColor3 = WHITE
	t.TextStrokeTransparency = 0.6
	for k, v in props do
		(t :: any)[k] = v
	end
	return t
end

local function button(props, onClick: () -> ()): TextButton
	local b = Instance.new("TextButton")
	b.Font = FONT
	b.TextColor3 = WHITE
	b.BackgroundColor3 = Color3.new(0, 0, 0)
	b.BackgroundTransparency = 0.35
	b.AutoButtonColor = true
	for k, v in props do
		(b :: any)[k] = v
	end
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = b
	b.Activated:Connect(onClick)
	return b
end

function SecurityCamController:IsActive(): boolean
	return active
end

function SecurityCamController:Init()
	gui = Instance.new("ScreenGui")
	gui.Name = "SecurityCams"
	gui.DisplayOrder = 6
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = player:WaitForChild("PlayerGui")

	openButton = button({ Text = "SECURITY CAMERAS  [C]", TextSize = 16, Size = UDim2.fromOffset(260, 40), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -164), Visible = false, Parent = gui }, function()
		setActive(not active)
	end)

	feed = Instance.new("Frame")
	feed.Name = "Feed"
	feed.Size = UDim2.fromScale(1, 1)
	feed.BackgroundTransparency = 1
	feed.Visible = false
	feed.Parent = gui
	-- static: a few grey bars that jump every frame (cheap on every device)
	for i = 1, 14 do
		local bar = Instance.new("Frame")
		bar.BorderSizePixel = 0
		bar.BackgroundColor3 = Color3.fromRGB(150, 150, 146)
		bar.BackgroundTransparency = 1
		bar.Size = UDim2.new(1, 0, 0, 3)
		bar.ZIndex = 2
		bar.Parent = feed
		noise[i] = bar
	end
	local blank = Instance.new("Frame")
	blank.Name = "Blank"
	blank.Size = UDim2.fromScale(1, 1)
	blank.BackgroundColor3 = Color3.fromRGB(12, 12, 12)
	blank.BackgroundTransparency = 1
	blank.BorderSizePixel = 0
	blank.ZIndex = 1
	blank.Parent = feed
	label = text({ Text = "", TextSize = 20, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, -80, 0, 28), Position = UDim2.fromOffset(40, 36), ZIndex = 3, Parent = feed })
	rec = text({ Text = "● REC", TextSize = 18, TextColor3 = RED, TextXAlignment = Enum.TextXAlignment.Right, Size = UDim2.new(0, 120, 0, 28), Position = UDim2.new(1, -160, 0, 36), ZIndex = 3, Parent = feed })
	stateLabel = text({ Text = "", TextSize = 22, Size = UDim2.new(1, 0, 0, 60), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.45), ZIndex = 3, Parent = feed })
	text({ Text = "Your camera holds it still. The tape only lasts a few seconds.", TextSize = 14, TextTransparency = 0.25, Size = UDim2.new(1, 0, 0, 20), Position = UDim2.new(0, 0, 1, -120), ZIndex = 3, Parent = feed })
	local holdBack = Instance.new("Frame")
	holdBack.Size = UDim2.new(0, 260, 0, 6)
	holdBack.AnchorPoint = Vector2.new(0.5, 0)
	holdBack.Position = UDim2.new(0.5, 0, 1, -96)
	holdBack.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	holdBack.BorderSizePixel = 0
	holdBack.ZIndex = 3
	holdBack.Parent = feed
	holdFill = Instance.new("Frame")
	holdFill.Size = UDim2.fromScale(1, 1)
	holdFill.BackgroundColor3 = WHITE
	holdFill.BorderSizePixel = 0
	holdFill.ZIndex = 4
	holdFill.Parent = holdBack
	button({ Text = "<", TextSize = 22, Size = UDim2.fromOffset(56, 48), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 24, 0.5, 0), ZIndex = 3, Parent = feed }, function()
		select(index - 1)
	end)
	button({ Text = ">", TextSize = 22, Size = UDim2.fromOffset(56, 48), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -24, 0.5, 0), ZIndex = 3, Parent = feed }, function()
		select(index + 1)
	end)
end

local function render()
	local cams = camList()
	local cam = cams[index]
	label.Text = if cam then tostring(cam:GetAttribute("Label")) else "NO CAMERAS"
	local state = player:GetAttribute("CamState")
	local hold = player:GetAttribute("CamHold") or 0
	local live = state == "LIVE"
	local blank = feed:FindFirstChild("Blank") :: Frame
	stateLabel.Text = if state == "STATIC" then "NO SIGNAL\nthe cameras need the building's power" elseif state == "REWIND" then string.format("REWINDING TAPE  %d", math.ceil(-hold)) else ""
	blank.BackgroundTransparency = if live then 1 else 0.25
	rec.Visible = live and (os.clock() % 1 < 0.6)
	local c = GameConfig.SecurityCams
	holdFill.Size = if live then UDim2.fromScale(math.clamp(hold / c.HoldTime, 0, 1), 1) else UDim2.fromScale(0, 1)
	local reduced = State.settings and (State.settings.reducedEffects or State.settings.reduceFlashes)
	for _, bar in noise do
		if live or reduced then
			bar.BackgroundTransparency = if live and not reduced and math.random() < 0.15 then 0.85 else 1
		else
			bar.BackgroundTransparency = math.random() * 0.5 + 0.3
		end
		bar.Position = UDim2.fromScale(0, math.random())
	end
end

function SecurityCamController:Start()
	Registry.CameraController:SetOverride("SecurityCam", 30, function()
		if not active then
			return nil
		end
		local cam = camList()[index]
		if not cam then
			return nil
		end
		render()
		-- a slow, cheap pan: an old camera's motor
		local pan = math.sin(os.clock() * 0.25) * math.rad(6)
		return cam.CFrame * CFrame.new(0, 0, -0.8) * CFrame.Angles(0, pan, 0), 70
	end)
	local function refresh()
		local can = eligible() and #camList() > 0
		openButton.Visible = can
		if active and not can then
			setActive(false)
		end
	end
	State.StatusChanged:Connect(refresh)
	State.RoundChanged:Connect(refresh)
	task.spawn(function()
		while true do
			task.wait(1)
			refresh()
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not eligible() then
			return
		end
		local key = input.KeyCode
		if key == Enum.KeyCode.C then
			setActive(not active)
		elseif active and (key == Enum.KeyCode.Q or key == Enum.KeyCode.Left or key == Enum.KeyCode.DPadLeft) then
			select(index - 1)
		elseif active and (key == Enum.KeyCode.E or key == Enum.KeyCode.Right or key == Enum.KeyCode.DPadRight) then
			select(index + 1)
		end
	end)
end

return SecurityCamController
