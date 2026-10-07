--[[
	ToolController
	The tool belt in a round: the HUD row, the tool you hold in your left hand,
	and what each tool shows you. The server decides everything that matters
	(charges, cooldowns, what a tool detects); this only presents it.

	  [5-9] / LB      pick a tool            [T] / RT   use it
	  FIELD RADIO     teammates' positions at the edge of the screen; static
	                  rises when something is near
	  RESONANCE METER bars on the device and a ticking that speeds up
	  SIGNAL TRACKER  the needle and a marker point the way for a while
	  THERMAL VIEWER  a cold palette; living teammates glow warm, anything else
	                  (the Observer, something wearing a friend) shows cold
	  ANOMALY LENS    nearby changes shimmer for a moment
	  INSTANT CAMERA  a flash; anyone nearby sees it too
	  TRIPWIRE SENSOR placed sensors flash a marker for the whole team
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local Net = require(ReplicatedStorage.Shared.Net)
local Equipment = require(ReplicatedStorage.Shared.Catalog.Equipment)
local EquipmentModels = require(ReplicatedStorage.Shared.EquipmentModels)
local Util = require(ReplicatedStorage.Shared.Util.Util)
local State = require(script.Parent.Parent.State)
local Registry = require(script.Parent.Parent.Registry)
local Kit = require(script.Parent.Parent.UI.Kit)

local ToolController = {}

local player = Players.LocalPlayer
local C = Kit.C

local gui: ScreenGui
local belt: Frame
local slotViews = {}
local meterFrame: Frame
local meterBars = {}
local radioLayer: Frame
local thermalGrade: ColorCorrectionEffect
local highlights: { [Instance]: Highlight } = {}
local viewmodel: Model? = nil
local viewmodelId: string? = nil
local vmCF = CFrame.new()
local meterBarsValue = 0
local lastTick = 0
local trackTarget: Vector3? = nil
local trackUntil = 0

local function tools()
	return (State.tools and State.tools.tools) or {}
end

local function selectedId(): string?
	local s = State.tools
	local t = s and s.tools and s.tools[s.selected or 0]
	return t and t.id
end

------------------------------------------------------------------------------------
-- HUD belt
------------------------------------------------------------------------------------

local function renderBelt()
	for _, v in slotViews do
		v.frame:Destroy()
	end
	slotViews = {}
	local list = tools()
	belt.Visible = #list > 0
	for i, t in list do
		local item = Equipment.get(t.id)
		local selected = State.tools.selected == i
		local frame = Kit.frame({ Size = UDim2.fromOffset(74, 86), BackgroundColor3 = C.Black, BackgroundTransparency = if selected then 0.15 else 0.5, LayoutOrder = i, Parent = belt })
		Kit.corner(frame, 4)
		local stroke = Kit.stroke(frame, if selected then (item and Equipment.RarityColors[item.rarity] or C.Text) else C.Line, if selected then 2 else 1, if selected then 0 else 0.4)
		local vp = Kit.new("ViewportFrame", { Size = UDim2.fromOffset(58, 46), Position = UDim2.fromOffset(8, 6), BackgroundTransparency = 1, Parent = frame })
		pcall(EquipmentModels.preview, t.id, vp)
		local key = if State.inputType == "Keyboard" then tostring(i + 4) else ""
		Kit.text({ Text = key, Size = UDim2.fromOffset(16, 14), Position = UDim2.fromOffset(4, 2), FontFace = Kit.F.Mono, TextSize = 11, TextColor3 = C.Muted, Parent = frame })
		local info = ""
		if t.charges then
			info = "x" .. t.charges
		elseif t.charge then
			info = string.format("%ds", math.floor(t.charge))
		elseif t.ready and t.ready > 0 then
			info = string.format("%ds", math.ceil(t.ready))
		end
		Kit.text({ Text = info, Size = UDim2.fromOffset(30, 14), Position = UDim2.new(1, -34, 0, 2), TextXAlignment = Enum.TextXAlignment.Right, FontFace = Kit.F.Mono, TextSize = 11, TextColor3 = C.TextDim, Parent = frame })
		Kit.text({ Text = string.upper(item and item.name or t.id), Size = UDim2.new(1, -6, 0, 26), Position = UDim2.fromOffset(3, 56), TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = true, FontFace = Kit.F.Heading, TextSize = 10, TextColor3 = if selected then C.Text else C.TextDim, Parent = frame })
		slotViews[i] = { frame = frame, stroke = stroke }
	end
	meterFrame.Visible = selectedId() == "RESONANCE_METER"
end

------------------------------------------------------------------------------------
-- In hand
------------------------------------------------------------------------------------

local function updateViewmodel(dt: number)
	local id = if State.status == "ALIVE" then selectedId() else nil
	if id ~= viewmodelId then
		if viewmodel then
			viewmodel:Destroy()
			viewmodel = nil
		end
		viewmodelId = id
		if id then
			local m = EquipmentModels.build(id)
			if m then
				-- a gloved hand holding it
				local glove = player:GetAttribute("GloveColor")
				local hand = Instance.new("Part")
				hand.Name = "Hand"
				hand.Size = Vector3.new(0.5, 0.3, 0.7)
				hand.CFrame = m:GetPivot() * CFrame.new(0.05, -0.35, 0.25)
				hand.Color = if typeof(glove) == "Color3" then glove else Color3.fromRGB(176, 150, 130)
				hand.Material = if typeof(glove) == "Color3" then Enum.Material.Fabric else Enum.Material.SmoothPlastic
				hand.Anchored = true
				hand.CanCollide = false
				hand.CanQuery = false
				hand.CastShadow = false
				hand.Parent = m
				m.Parent = Workspace.CurrentCamera
				viewmodel = m
				vmCF = Workspace.CurrentCamera.CFrame
			end
		end
	end
	local m = viewmodel
	if not m then
		return
	end
	local camera = Workspace.CurrentCamera
	local target = camera.CFrame * CFrame.new(-0.62, -0.62, -1.35) * CFrame.Angles(math.rad(8), math.rad(14), 0)
	vmCF = vmCF:Lerp(target, Util.damp(18, dt))
	local t = os.clock()
	local sway = CFrame.new(math.noise(t * 0.8, 3) * 0.02, math.noise(t * 0.8, 4) * 0.02, 0)
	m:PivotTo(vmCF * sway)
	-- live details on the devices
	if viewmodelId == "RESONANCE_METER" then
		for _, d in m:GetChildren() do
			local bar = d:GetAttribute("Bar")
			if bar and d:IsA("BasePart") then
				d.Color = if bar <= meterBarsValue then (if bar >= 4 then Color3.fromRGB(230, 90, 70) else Color3.fromRGB(120, 230, 140)) else Color3.fromRGB(50, 60, 50)
			end
		end
	elseif viewmodelId == "SIGNAL_TRACKER" then
		local needle = m:FindFirstChild("Needle") :: BasePart?
		if needle and trackTarget and os.clock() < trackUntil then
			local rel = camera.CFrame:PointToObjectSpace(trackTarget)
			local angle = math.atan2(rel.X, -rel.Z)
			needle.CFrame = m:GetPivot() * CFrame.new(0, 0.17, -0.1) * CFrame.Angles(0, -angle, 0) * CFrame.new(0, 0, -0.08)
		end
	end
end

------------------------------------------------------------------------------------
-- Tool effects
------------------------------------------------------------------------------------

-- Field radio: teammates at the edge of the screen while you hold it.
local function updateRadio()
	radioLayer:ClearAllChildren()
	if selectedId() ~= "FIELD_RADIO" or State.status ~= "ALIVE" then
		return
	end
	local camera = Workspace.CurrentCamera
	local viewport = camera.ViewportSize
	for _, p in Players:GetPlayers() do
		if p ~= player and p:GetAttribute("Status") == "ALIVE" then
			local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				local rel = camera.CFrame:PointToObjectSpace(root.Position)
				local angle = math.atan2(rel.X, -rel.Z)
				local dist = (root.Position - camera.CFrame.Position).Magnitude
				local x = viewport.X / 2 + math.sin(angle) * viewport.X * 0.4
				local y = viewport.Y / 2 - math.cos(angle) * viewport.Y * 0.38
				local chip = Kit.text({ Text = string.format("%s  %dm", string.upper(p.DisplayName), math.floor(dist / 3.5)), Size = UDim2.fromOffset(180, 20), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(x, y), TextXAlignment = Enum.TextXAlignment.Center, FontFace = Kit.F.Mono, TextSize = 13, TextColor3 = Color3.fromRGB(150, 230, 170), TextStrokeTransparency = 0.5, Parent = radioLayer })
				chip.ZIndex = 3
			end
		end
	end
	-- static rises when it is near
	if State.observerDistance < 50 and os.clock() - lastTick > 0.9 then
		lastTick = os.clock()
		Registry.AudioController:Play("RadioStatic", nil, { volume = 0.3 + (1 - State.observerDistance / 50) * 0.7 })
	end
end

-- Thermal: a cold world, warm friends, cold impostors.
local function setHighlight(model: Instance, color: Color3?)
	local h = highlights[model]
	if not color then
		if h then
			h:Destroy()
			highlights[model] = nil
		end
		return
	end
	if not h then
		h = Instance.new("Highlight")
		h.DepthMode = Enum.HighlightDepthMode.Occluded
		h.OutlineTransparency = 0.6
		h.FillTransparency = 0.35
		h.Adornee = model
		h.Parent = gui
		highlights[model] = h
	end
	h.FillColor = color
	h.OutlineColor = color
end

local WARM = Color3.fromRGB(255, 150, 60)
local COLD = Color3.fromRGB(90, 160, 255)

local function updateThermal()
	local on = player:GetAttribute("Thermal") == true and State.status == "ALIVE"
	thermalGrade.Enabled = on
	local seen = {}
	if on then
		local camPos = Workspace.CurrentCamera.CFrame.Position
		for _, p in Players:GetPlayers() do
			if p ~= player and p.Character and p:GetAttribute("Status") == "ALIVE" then
				seen[p.Character] = true
				setHighlight(p.Character, WARM)
			end
		end
		for _, m in Workspace:GetChildren() do
			if m:IsA("Model") and m:GetAttribute("Mimic") and m.PrimaryPart and (m.PrimaryPart.Position - camPos).Magnitude < 40 then
				seen[m] = true
				setHighlight(m, COLD)
			end
		end
		for _, m in CollectionService:GetTagged("Observer") do
			if m:IsDescendantOf(Workspace) and m.PrimaryPart and (m.PrimaryPart.Position - camPos).Magnitude < 40 then
				seen[m] = true
				setHighlight(m, COLD)
			end
		end
	end
	for model in highlights do
		if not seen[model] or not model.Parent then
			setHighlight(model, nil)
		end
	end
end

local function shimmer(at: Vector3)
	local holder = Instance.new("Part")
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.Transparency = 1
	holder.Size = Vector3.new(0.2, 0.2, 0.2)
	holder.CFrame = CFrame.new(at)
	holder.Parent = Workspace
	local e = Instance.new("ParticleEmitter")
	e.Rate = 30
	e.Lifetime = NumberRange.new(0.6, 1.2)
	e.Speed = NumberRange.new(0.5, 1.5)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0) })
	e.Color = ColorSequence.new(Color3.fromRGB(200, 220, 255))
	e.LightEmission = 0.8
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	e.Parent = holder
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(190, 210, 255)
	light.Range = 6
	light.Brightness = 0.8
	light.Parent = holder
	task.delay(1.6, function()
		e.Enabled = false
		light.Enabled = false
	end)
	Debris:AddItem(holder, 3)
end

local function flashAt(at: Vector3)
	local holder = Instance.new("Part")
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.Transparency = 1
	holder.Size = Vector3.new(0.2, 0.2, 0.2)
	holder.CFrame = CFrame.new(at)
	holder.Parent = Workspace
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(240, 244, 255)
	light.Range = 26
	light.Brightness = 4
	light.Shadows = true
	light.Parent = holder
	Debris:AddItem(holder, 0.14)
end

local function onEvent(p)
	if type(p) ~= "table" then
		return
	end
	if p.kind == "gear" then
		State.gear = p.gear
		State.GearChanged:Fire(p.gear)
	elseif p.kind == "purchased" or p.kind == "upgraded" then
		Registry.AudioController:PlayUI("UIPurchase")
		Registry.AudioController:PlayUI("UICoin")
	elseif p.kind == "meter" then
		meterBarsValue = p.bars or 0
		for i, bar in meterBars do
			bar.BackgroundColor3 = if i <= meterBarsValue then (if i >= 4 then C.Danger else Color3.fromRGB(150, 230, 170)) else C.Line
		end
		if meterBarsValue > 0 and os.clock() - lastTick > 1.2 - meterBarsValue * 0.2 then
			lastTick = os.clock()
			Registry.AudioController:Play("DeviceTick", nil, { volume = 0.4 + meterBarsValue * 0.1 })
		end
		if p.observer then
			Registry.AudioController:Play("RadioStatic", nil, { volume = 0.4 })
		end
	elseif p.kind == "track" and typeof(p.at) == "Vector3" then
		trackTarget = p.at
		trackUntil = os.clock() + (p.duration or 20)
		Registry.HUDController:GuideMarker(p.at, "SIGNAL")
	elseif p.kind == "lens" and type(p.spots) == "table" then
		for _, at in p.spots do
			if typeof(at) == "Vector3" then
				shimmer(at)
			end
		end
		if #p.spots == 0 then
			Registry.HUDController:Hint("Nothing shimmers here.", 2)
		end
	elseif p.kind == "flash" and typeof(p.at) == "Vector3" then
		flashAt(p.at)
		if p.by == player.UserId then
			Registry.EffectsController:Flash(Color3.fromRGB(245, 245, 255), 0.55, 0.4)
		end
	elseif p.kind == "sensor" and typeof(p.at) == "Vector3" then
		Registry.HUDController:GuideMarker(p.at, "MOTION")
		Registry.HUDController:Caption("[" .. string.upper(p.owner or "a") .. "'S SENSOR: MOTION]", 2.5, "sound")
	end
end

function ToolController:Select(index: number)
	if State.status ~= "ALIVE" then
		return
	end
	if index >= 1 and index <= #tools() then
		Net.event("Tool"):FireServer("select", index)
	end
end

function ToolController:Use()
	local s = State.tools
	if State.status ~= "ALIVE" or State.uiOpen or not s or (s.selected or 0) < 1 then
		return
	end
	local camera = Workspace.CurrentCamera
	Net.event("Tool"):FireServer("use", s.selected, camera.CFrame.Position, camera.CFrame.LookVector)
	local id = selectedId()
	if id == "INSTANT_CAMERA" then
		Registry.AudioController:PlayUI("CameraShutter")
	end
end

function ToolController:Init()
	gui = Kit.screen("Tools", 2)
	belt = Kit.frame({ Size = UDim2.fromOffset(400, 86), AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -40, 1, -36), BackgroundTransparency = 1, Visible = false, Parent = gui })
	Kit.list(belt, 6, true, Enum.HorizontalAlignment.Right)
	meterFrame = Kit.frame({ Size = UDim2.fromOffset(150, 40), AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -40, 1, -132), BackgroundColor3 = C.Black, BackgroundTransparency = 0.45, Visible = false, Parent = gui })
	Kit.corner(meterFrame, 4)
	for i = 1, 5 do
		local bar = Kit.frame({ Size = UDim2.fromOffset(18, 6 + i * 5), AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 14 + (i - 1) * 25, 1, -6), BackgroundColor3 = C.Line, Parent = meterFrame })
		meterBars[i] = bar
	end
	radioLayer = Kit.frame({ Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = gui })
	thermalGrade = Instance.new("ColorCorrectionEffect")
	thermalGrade.Name = "Thermal"
	thermalGrade.Saturation = -1
	thermalGrade.Contrast = 0.35
	thermalGrade.Brightness = 0.05
	thermalGrade.TintColor = Color3.fromRGB(150, 170, 255)
	thermalGrade.Enabled = false
	thermalGrade.Parent = Lighting
end

function ToolController:Start()
	Net.event("ToolState").OnClientEvent:Connect(function(p)
		if type(p) == "table" then
			State.tools = p
			renderBelt()
		end
	end)
	Net.event("ToolEvent").OnClientEvent:Connect(onEvent)
	State.InputTypeChanged:Connect(renderBelt)
	State.StatusChanged:Connect(function()
		if State.status ~= "ALIVE" then
			State.tools = { tools = {}, selected = 0 }
			renderBelt()
		end
	end)
	Registry.InputController.Action:Connect(function(action, began)
		if not began or State.status ~= "ALIVE" or State.uiOpen then
			return
		end
		local idx = tonumber(string.match(action, "^Tool(%d)$"))
		if idx then
			self:Select(idx)
		elseif action == "CycleTool" then
			local s = State.tools
			local n = #tools()
			if n > 0 then
				self:Select((s.selected or 0) % n + 1)
			end
		elseif action == "UseTool" then
			self:Use()
		end
	end)
	local acc = 0
	RunService.RenderStepped:Connect(function(dt)
		updateViewmodel(dt)
		acc += dt
		if acc > 0.15 then
			acc = 0
			updateRadio()
			updateThermal()
		end
	end)
end

return ToolController
