--[[
	SpectatorController
	After you are taken (or escape) you watch the survivors: an over-the-shoulder
	view that follows where they look. Players waiting in the lobby can spectate a
	running round too.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local Util = require(ReplicatedStorage.Shared.Util.Util)
local State = require(script.Parent.Parent.State)
local Registry = require(script.Parent.Parent.Registry)
local Kit = require(script.Parent.Parent.UI.Kit)

local SpectatorController = {}

SpectatorController.Changed = Signal.new()

local C = Kit.C
local player = Players.LocalPlayer
local active = false
local fromLobby = false
local index = 1
local gui: ScreenGui
local nameLabel: TextLabel
local smoothed: CFrame? = nil

local function targets(): { Player }
	local list = {}
	for _, p in Players:GetPlayers() do
		if p ~= player and p:GetAttribute("Status") == "ALIVE" and p.Character and p.Character:FindFirstChild("Head") then
			table.insert(list, p)
		end
	end
	table.sort(list, function(a, b)
		return a.UserId < b.UserId
	end)
	return list
end

function SpectatorController:IsActive(): boolean
	return active
end

function SpectatorController:Begin(lobby: boolean?)
	active = true
	fromLobby = lobby == true
	index = 1
	smoothed = nil
	gui.Enabled = true
	if fromLobby then
		State.setUIOpen(false)
	end
	SpectatorController.Changed:Fire(true)
end

function SpectatorController:Stop()
	if not active then
		return
	end
	active = false
	gui.Enabled = false
	SpectatorController.Changed:Fire(false)
end

local function cycle(dir: number)
	local list = targets()
	if #list == 0 then
		return
	end
	index = (index - 1 + dir) % #list + 1
	smoothed = nil
	Kit.sound("UIClick")
end

local function camera(dt: number): CFrame?
	if not active then
		return nil
	end
	local list = targets()
	if #list == 0 then
		nameLabel.Text = "NOBODY LEFT TO WATCH"
		local map = Workspace:GetAttribute("LobbyCamera")
		local overview = CFrame.lookAt(Vector3.new(80, 60, 190), Vector3.new(80, 0, 60))
		return if State.round.state == "LOBBY" and typeof(map) == "CFrame" then map else overview
	end
	index = math.clamp(index, 1, #list)
	local target = list[index]
	local character = target.Character :: Model
	local head = character:FindFirstChild("Head") :: BasePart
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local pitch = character:GetAttribute("LookPitch") or 0
	local yawCF = if root then (root.CFrame - root.CFrame.Position) else (head.CFrame - head.CFrame.Position)
	local look = yawCF * CFrame.Angles(pitch * 0.7, 0, 0)
	local desired = CFrame.new(head.Position) * look * CFrame.new(1.6, 0.9, 6.5)
	-- keep the camera out of walls
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local offset = desired.Position - head.Position
	local hit = Workspace:Raycast(head.Position, offset, params)
	if hit then
		desired = CFrame.new(hit.Position - offset.Unit * 0.6) * look
	end
	smoothed = if smoothed then smoothed:Lerp(desired, Util.damp(8, dt)) else desired
	nameLabel.Text = "WATCHING  " .. string.upper(target.DisplayName)
	return smoothed
end

function SpectatorController:Init()
	gui = Kit.screen("Spectator", 4)
	local bar = Kit.frame({ Size = UDim2.fromOffset(640, 64), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -40), BackgroundColor3 = C.Black, BackgroundTransparency = 0.4, Parent = gui })
	Kit.corner(bar, 6)
	Kit.button({ Text = "<", Size = UDim2.fromOffset(56, 48), Position = UDim2.fromOffset(8, 8), Parent = bar }, function()
		cycle(-1)
	end)
	Kit.button({ Text = ">", Size = UDim2.fromOffset(56, 48), Position = UDim2.new(1, -64, 0, 8), Parent = bar }, function()
		cycle(1)
	end)
	nameLabel = Kit.text({ Text = "", Size = UDim2.new(1, -150, 1, 0), Position = UDim2.fromOffset(75, 0), TextXAlignment = Enum.TextXAlignment.Center, FontFace = Kit.F.Heading, TextSize = 18, Parent = bar })
	local leave = Kit.button({ Text = "STOP WATCHING", Size = UDim2.fromOffset(200, 40), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -116), TextSize = 14, Parent = gui }, function()
		SpectatorController:Stop()
	end)
	leave.Name = "Leave"
	gui.Enabled = false
end

function SpectatorController:Start()
	Registry.CameraController:SetOverride("Spectator", 20, function(dt)
		return camera(dt)
	end)
	Registry.InputController.Action:Connect(function(action, began)
		if not active or not began then
			return
		end
		if action == "SpectateNext" then
			cycle(1)
		elseif action == "SpectatePrev" then
			cycle(-1)
		end
	end)
	State.StatusChanged:Connect(function()
		local leave = gui:FindFirstChild("Leave", true)
		if leave then
			leave.Visible = State.status == "LOBBY"
		end
		if State.status == "ALIVE" or State.status == "MENU" then
			self:Stop()
		end
	end)
	State.RoundChanged:Connect(function()
		if State.round.state == "RESULTS" or State.round.state == "RETURNING" or State.round.state == "LOBBY" then
			self:Stop()
		end
	end)
end

return SpectatorController
