--[[
	Kit
	Minimal UI toolkit used by every screen: consistent typography, spacing,
	colours, hover/press feedback and responsive scaling for phones, tablets,
	monitors and TVs. Black, dark grey, bone white; red only for danger.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Theme = require(ReplicatedStorage.Shared.Theme)
local Registry = require(script.Parent.Parent.Registry)

local Kit = {}

Kit.Theme = Theme
Kit.C = Theme.Colors
Kit.F = Theme.Fonts

local player = Players.LocalPlayer

function Kit.playerGui(): PlayerGui
	return player:WaitForChild("PlayerGui") :: PlayerGui
end

function Kit.new(className: string, props: { [string]: any }?, children: { Instance }?): any
	local inst = Instance.new(className)
	if inst:IsA("GuiObject") then
		(inst :: any).BorderSizePixel = 0
	end
	local parent = nil
	for k, v in props or {} do
		if k == "Parent" then
			parent = v
		else
			(inst :: any)[k] = v
		end
	end
	for _, child in children or {} do
		child.Parent = inst
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

-- Responsive scale: designs are authored for 1080p and scaled down on phones.
function Kit.attachScale(gui: Instance)
	local scale = Kit.new("UIScale", { Parent = gui })
	local function update()
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		local size = camera.ViewportSize
		local s = math.min(size.X / 1920, size.Y / 1080)
		-- small screens get relatively larger UI so touch targets stay usable
		if size.Y < 600 then
			s = math.max(s, size.Y / 760)
		end
		scale.Scale = math.clamp(s, 0.45, 1.6)
	end
	update()
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
	end
	return scale
end

function Kit.screen(name: string, order: number, scaled: boolean?): ScreenGui
	local existing = Kit.playerGui():FindFirstChild(name)
	if existing then
		existing:Destroy()
	end
	local gui = Kit.new("ScreenGui", {
		Name = name,
		DisplayOrder = order,
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = Kit.playerGui(),
	})
	if scaled ~= false then
		Kit.attachScale(gui)
	end
	return gui
end

function Kit.corner(parent: Instance, radius: number?)
	return Kit.new("UICorner", { CornerRadius = UDim.new(0, radius or 6), Parent = parent })
end

function Kit.stroke(parent: Instance, color: Color3?, thickness: number?, transparency: number?)
	return Kit.new("UIStroke", {
		Color = color or Kit.C.Line,
		Thickness = thickness or 1,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

function Kit.padding(parent: Instance, all: number, horizontal: number?)
	return Kit.new("UIPadding", {
		PaddingTop = UDim.new(0, all),
		PaddingBottom = UDim.new(0, all),
		PaddingLeft = UDim.new(0, horizontal or all),
		PaddingRight = UDim.new(0, horizontal or all),
		Parent = parent,
	})
end

function Kit.list(parent: Instance, spacing: number?, horizontal: boolean?, align: Enum.HorizontalAlignment?)
	return Kit.new("UIListLayout", {
		Padding = UDim.new(0, spacing or 8),
		FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = align or Enum.HorizontalAlignment.Left,
		Parent = parent,
	})
end

function Kit.text(props: { [string]: any }): TextLabel
	local defaults = {
		BackgroundTransparency = 1,
		TextColor3 = Kit.C.Text,
		FontFace = Kit.F.Body,
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextWrapped = true,
		RichText = false,
	}
	for k, v in props do
		defaults[k] = v
	end
	return Kit.new("TextLabel", defaults)
end

function Kit.frame(props: { [string]: any }): Frame
	local defaults = { BackgroundColor3 = Kit.C.Panel, BackgroundTransparency = 0 }
	for k, v in props do
		defaults[k] = v
	end
	return Kit.new("Frame", defaults)
end

function Kit.tween(inst: Instance, info: TweenInfo | number, goal: { [string]: any })
	local tweenInfo = if typeof(info) == "number" then TweenInfo.new(info, Enum.EasingStyle.Quad, Enum.EasingDirection.Out) else info
	local t = TweenService:Create(inst, tweenInfo :: TweenInfo, goal)
	t:Play()
	return t
end

local function sound(key: string)
	local audio = Registry.AudioController
	if audio then
		audio:PlayUI(key)
	end
end

Kit.sound = sound

-- A text button with hover / press feedback. style: "primary" | "ghost" | "danger"
function Kit.button(props: { [string]: any }, onClick: (() -> ())?): TextButton
	local style = props.Style or "ghost"
	props.Style = nil
	local defaults = {
		AutoButtonColor = false,
		BackgroundColor3 = if style == "primary" then Kit.C.Text elseif style == "danger" then Kit.C.DangerDim else Kit.C.PanelLight,
		BackgroundTransparency = if style == "ghost" then 0.35 else 0,
		TextColor3 = if style == "primary" then Kit.C.Black else Kit.C.Text,
		FontFace = Kit.F.Heading,
		TextSize = 18,
		Text = "",
		Size = UDim2.fromOffset(220, 48),
		Selectable = true,
	}
	for k, v in props do
		defaults[k] = v
	end
	local button = Kit.new("TextButton", defaults) :: TextButton
	Kit.corner(button, 4)
	local stroke = Kit.stroke(button, Kit.C.Line, 1, if style == "primary" then 1 else 0.3)
	local baseColor = button.BackgroundColor3
	local baseTransparency = button.BackgroundTransparency
	local function hover(on: boolean)
		if on then
			sound("UIHover")
		end
		Kit.tween(button, 0.12, {
			BackgroundTransparency = if on then math.max(0, baseTransparency - 0.25) else baseTransparency,
			BackgroundColor3 = if on and style == "ghost" then Kit.C.Line else baseColor,
		})
		Kit.tween(stroke, 0.12, { Transparency = if on then 0 else (if style == "primary" then 1 else 0.3), Color = if on then Kit.C.Text else Kit.C.Line })
	end
	button.MouseEnter:Connect(function()
		hover(true)
	end)
	button.MouseLeave:Connect(function()
		hover(false)
	end)
	button.SelectionGained:Connect(function()
		hover(true)
	end)
	button.SelectionLost:Connect(function()
		hover(false)
	end)
	-- click feedback: a quick press-in
	local press = Kit.new("UIScale", { Parent = button })
	button.MouseButton1Down:Connect(function()
		Kit.tween(press, 0.06, { Scale = 0.96 })
	end)
	button.MouseButton1Up:Connect(function()
		Kit.tween(press, 0.12, { Scale = 1 })
	end)
	button.MouseLeave:Connect(function()
		Kit.tween(press, 0.12, { Scale = 1 })
	end)
	if onClick then
		button.Activated:Connect(function()
			sound("UIClick")
			onClick()
		end)
	end
	return button
end

-- Simple horizontal slider (0..1) returning the container and a setter.
function Kit.slider(parent: Instance, label: string, value: number, onChange: (number) -> (), format: ((number) -> string)?)
	local row = Kit.frame({ Size = UDim2.new(1, 0, 0, 52), BackgroundTransparency = 1, Parent = parent })
	Kit.text({ Text = label, Size = UDim2.new(0.42, 0, 1, 0), TextSize = 18, TextColor3 = Kit.C.TextDim, Parent = row })
	local valueLabel = Kit.text({ Size = UDim2.new(0.12, 0, 1, 0), Position = UDim2.fromScale(0.88, 0), TextXAlignment = Enum.TextXAlignment.Right, TextSize = 16, FontFace = Kit.F.Mono, Parent = row })
	local track = Kit.new("TextButton", { AutoButtonColor = false, Text = "", Size = UDim2.new(0.42, 0, 0, 6), Position = UDim2.new(0.44, 0, 0.5, -3), BackgroundColor3 = Kit.C.Line, Selectable = true, Parent = row })
	Kit.corner(track, 3)
	local fill = Kit.frame({ Size = UDim2.fromScale(value, 1), BackgroundColor3 = Kit.C.Text, Parent = track })
	Kit.corner(fill, 3)
	local knob = Kit.frame({ Size = UDim2.fromOffset(16, 16), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(value, 0.5), BackgroundColor3 = Kit.C.Text, Parent = track })
	Kit.corner(knob, 8)
	local current = value
	local function set(v: number, fire: boolean?)
		current = math.clamp(v, 0, 1)
		fill.Size = UDim2.fromScale(current, 1)
		knob.Position = UDim2.fromScale(current, 0.5)
		valueLabel.Text = if format then format(current) else string.format("%d%%", math.floor(current * 100 + 0.5))
		if fire then
			onChange(current)
		end
	end
	set(value)
	local dragging = false
	local UserInputService = game:GetService("UserInputService")
	local function fromX(x: number)
		local rel = (x - track.AbsolutePosition.X) / math.max(1, track.AbsoluteSize.X)
		set(rel, true)
	end
	track.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			fromX(input.Position.X)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			fromX(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
	-- gamepad: left / right while selected
	track.SelectionGained:Connect(function()
		track.BackgroundColor3 = Kit.C.Muted
	end)
	track.SelectionLost:Connect(function()
		track.BackgroundColor3 = Kit.C.Line
	end)
	UserInputService.InputBegan:Connect(function(input)
		if game:GetService("GuiService").SelectedObject == track then
			if input.KeyCode == Enum.KeyCode.DPadRight or input.KeyCode == Enum.KeyCode.Right then
				set(current + 0.05, true)
			elseif input.KeyCode == Enum.KeyCode.DPadLeft or input.KeyCode == Enum.KeyCode.Left then
				set(current - 0.05, true)
			end
		end
	end)
	return row, set
end

function Kit.toggle(parent: Instance, label: string, value: boolean, onChange: (boolean) -> ())
	local row = Kit.frame({ Size = UDim2.new(1, 0, 0, 52), BackgroundTransparency = 1, Parent = parent })
	Kit.text({ Text = label, Size = UDim2.new(0.7, 0, 1, 0), TextSize = 18, TextColor3 = Kit.C.TextDim, Parent = row })
	local current = value
	local button
	button = Kit.button({ Size = UDim2.fromOffset(110, 38), Position = UDim2.new(1, -110, 0.5, -19), Text = "", TextSize = 16, Parent = row }, function()
		current = not current
		button.Text = if current then "ON" else "OFF"
		onChange(current)
	end)
	button.Text = if current then "ON" else "OFF"
	return row
end

-- Title + content panel centred on screen.
function Kit.panel(parent: Instance, title: string, size: UDim2): (Frame, Frame)
	local panel = Kit.frame({
		Name = title,
		Size = size,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		BackgroundColor3 = Kit.C.Panel,
		BackgroundTransparency = 0.04,
		Parent = parent,
	})
	Kit.corner(panel, 6)
	Kit.stroke(panel, Kit.C.Line, 1, 0.2)
	Kit.text({ Text = title, FontFace = Kit.F.Title, TextSize = 30, Size = UDim2.new(1, -64, 0, 44), Position = UDim2.fromOffset(32, 24), Parent = panel })
	Kit.frame({ Size = UDim2.new(1, -64, 0, 1), Position = UDim2.fromOffset(32, 76), BackgroundColor3 = Kit.C.Line, Parent = panel })
	local body = Kit.frame({ Name = "Body", Size = UDim2.new(1, -64, 1, -110), Position = UDim2.fromOffset(32, 92), BackgroundTransparency = 1, Parent = panel })
	return panel, body
end

function Kit.scroll(parent: Instance, props: { [string]: any }?): ScrollingFrame
	local defaults = {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = Kit.C.Muted,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Selectable = false,
		Parent = parent,
	}
	for k, v in props or {} do
		defaults[k] = v
	end
	return Kit.new("ScrollingFrame", defaults)
end

return Kit
