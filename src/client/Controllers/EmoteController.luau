--[[
	EmoteController
	Purely cosmetic emotes animated procedurally on R15 joints (no animation
	assets needed), an emote wheel, and lobby-only trails.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Net = require(ReplicatedStorage.Shared.Net)
local Cosmetics = require(ReplicatedStorage.Shared.Catalog.Cosmetics)
local State = require(script.Parent.Parent.State)
local Registry = require(script.Parent.Parent.Registry)
local Kit = require(script.Parent.Parent.UI.Kit)

local EmoteController = {}

local DURATION = 2.6
local wheel: Frame
local trails: { [Model]: Trail } = {}

local function joint(character: Model, partName: string, motorName: string): Motor6D?
	local part = character:FindFirstChild(partName)
	local m = part and part:FindFirstChild(motorName)
	return if m and m:IsA("Motor6D") then m else nil
end

-- returns transforms for (rightShoulder, leftShoulder, neck, waist, rightElbow) at time t (0..1)
local POSES = {
	wave = function(t)
		local w = math.sin(t * math.pi * 6) * 0.45
		return CFrame.Angles(0, 0, math.rad(150)) * CFrame.Angles(0, w, 0), nil, nil, nil, CFrame.Angles(math.rad(-20), 0, 0)
	end,
	point = function()
		return CFrame.Angles(math.rad(90), 0, 0), nil, CFrame.Angles(math.rad(-5), 0, 0), nil, nil
	end,
	shrug = function(t)
		local s = math.sin(math.min(1, t * 3) * math.pi / 2)
		return CFrame.Angles(0, 0, math.rad(25 * s)), CFrame.Angles(0, 0, math.rad(-25 * s)), CFrame.Angles(0, 0, math.rad(8 * s)), nil, CFrame.Angles(math.rad(-60 * s), 0, 0)
	end,
	salute = function()
		return CFrame.Angles(math.rad(70), math.rad(-30), math.rad(60)), nil, nil, nil, CFrame.Angles(math.rad(-110), 0, 0)
	end,
	look = function(t)
		return nil, nil, CFrame.Angles(0, math.sin(t * math.pi * 2) * 1.0, 0), CFrame.Angles(0, math.sin(t * math.pi * 2) * 0.3, 0), nil
	end,
	hush = function()
		return CFrame.Angles(math.rad(60), 0, math.rad(-35)), nil, CFrame.Angles(math.rad(-6), 0, 0), nil, CFrame.Angles(math.rad(-120), 0, 0)
	end,
	bow = function(t)
		local s = math.sin(math.min(1, t * 2.5) * math.pi / 2)
		return nil, nil, CFrame.Angles(math.rad(-15 * s), 0, 0), CFrame.Angles(math.rad(-45 * s), 0, 0), nil
	end,
}

local function animateCharacters()
	local now = Workspace:GetServerTimeNow()
	local models = {}
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(models, p.Character)
		end
	end
	-- mimics emote too (badly)
	for _, m in Workspace:GetChildren() do
		if m:IsA("Model") and m:GetAttribute("Mimic") then
			table.insert(models, m)
		end
	end
	for _, character in models do
		do
			local emote = character:GetAttribute("Emote")
			local at = character:GetAttribute("EmoteAt")
			local speed = character:GetAttribute("EmoteSpeed")
			local duration = DURATION / (if type(speed) == "number" and speed > 0 then speed else 1)
			if type(emote) == "string" and type(at) == "number" and now - at < duration and POSES[emote] then
				local t = (now - at) / duration
				local rs, ls, neck, waist, re = POSES[emote](t)
				local function apply(m: Motor6D?, cf: CFrame?)
					if m and cf then
						m.Transform = cf
					end
				end
				apply(joint(character, "RightUpperArm", "RightShoulder"), rs)
				apply(joint(character, "LeftUpperArm", "LeftShoulder"), ls)
				apply(joint(character, "Head", "Neck"), neck)
				apply(joint(character, "UpperTorso", "Waist"), waist)
				apply(joint(character, "RightLowerArm", "RightElbow"), re)
			end
		end
	end
end

local function updateTrails()
	for _, p in Players:GetPlayers() do
		local character = p.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local effect = p:GetAttribute("TrailEffect")
		local wants = root ~= nil and p:GetAttribute("Status") == "LOBBY" and effect ~= nil and effect ~= "none"
		local existing = character and trails[character]
		if wants and not existing and character and root then
			local a0 = Instance.new("Attachment")
			a0.Position = Vector3.new(0, -2.4, 0.4)
			a0.Parent = root
			local a1 = Instance.new("Attachment")
			a1.Position = Vector3.new(0, -1.2, 0.4)
			a1.Parent = root
			local trail = Instance.new("Trail")
			trail.Attachment0 = a0
			trail.Attachment1 = a1
			trail.Lifetime = 0.8
			trail.LightEmission = if effect == "ember" then 0.7 else 0.1
			trail.Color = ColorSequence.new(p:GetAttribute("TrailColor") or Color3.new(1, 1, 1))
			trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) })
			trail.Parent = root
			trails[character] = trail
		elseif not wants and existing and character then
			existing:Destroy()
			trails[character] = nil
		end
	end
	for character, trail in trails do
		if not character.Parent then
			trail:Destroy()
			trails[character] = nil
		end
	end
end

function EmoteController:OpenWheel()
	if State.status ~= "ALIVE" and State.status ~= "LOBBY" then
		return
	end
	for _, c in wheel:GetChildren() do
		if c:IsA("GuiButton") then
			c:Destroy()
		end
	end
	local owned = State.profile and State.profile.owned or {}
	local list = {}
	for _, item in Cosmetics.List do
		if item.category == "EMOTE" and (item.default or owned[item.id]) then
			table.insert(list, item)
		end
	end
	for i, item in list do
		local angle = (i - 1) / #list * math.pi * 2 - math.pi / 2
		local button = Kit.button({ Text = string.upper(item.name), Size = UDim2.fromOffset(150, 46), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, math.cos(angle) * 170, 0.5, math.sin(angle) * 170), Parent = wheel }, function()
			Net.event("Emote"):FireServer(item.id)
			EmoteController:CloseWheel()
		end)
		button.LayoutOrder = i
	end
	wheel.Visible = true
	State.setUIOpen(true)
end

function EmoteController:CloseWheel()
	if wheel.Visible then
		wheel.Visible = false
		State.setUIOpen(false)
	end
end

function EmoteController:Init()
	local gui = Kit.screen("EmoteWheel", 6)
	wheel = Kit.frame({ Size = UDim2.fromOffset(520, 520), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), BackgroundTransparency = 1, Visible = false, Parent = gui })
	Kit.text({ Text = "EMOTE", Size = UDim2.fromOffset(200, 30), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), TextXAlignment = Enum.TextXAlignment.Center, FontFace = Kit.F.Heading, TextColor3 = Kit.C.TextDim, Parent = wheel })
end

function EmoteController:Start()
	Registry.InputController.Action:Connect(function(action, began)
		if action == "Emote" and began then
			if wheel.Visible then
				self:CloseWheel()
			else
				self:OpenWheel()
			end
		elseif action == "Back" and began then
			self:CloseWheel()
		end
	end)
	RunService.Stepped:Connect(animateCharacters)
	task.spawn(function()
		while true do
			task.wait(0.5)
			updateTrails()
		end
	end)
end

return EmoteController
