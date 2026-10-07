--[[
	LobbyController
	The Field Office panel (lobby): who is here, who is ready, difficulty (host only),
	READY, INVITE, the countdown, and - if a round is already running - a way to
	spectate it while you wait.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Net = require(ReplicatedStorage.Shared.Net)
local Enums = require(ReplicatedStorage.Shared.Enums)
local Util = require(ReplicatedStorage.Shared.Util.Util)
local State = require(script.Parent.Parent.State)
local Registry = require(script.Parent.Parent.Registry)
local Kit = require(script.Parent.Parent.UI.Kit)

local LobbyController = {}

local C = Kit.C
local player = Players.LocalPlayer
local gui: ScreenGui
local panel: Frame
local list: Frame
local readyButton: TextButton
local countdownLabel: TextLabel
local statusLabel: TextLabel
local diffButtons: { [string]: TextButton } = {}
local spectateButton: TextButton
local hardNote: TextLabel
local amReady = false

local DIFF_TEXT = { NORMAL = "NORMAL", HARD = "HARD", NIGHTMARE = "NIGHTMARE" }

local function render()
	local s = State.lobby
	if not s then
		return
	end
	for _, c in list:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	amReady = false
	for i, p in s.players or {} do
		if p.userId == player.UserId then
			amReady = p.ready
		end
		local row = Kit.frame({ Size = UDim2.new(1, 0, 0, 44), BackgroundColor3 = C.PanelLight, BackgroundTransparency = 0.3, LayoutOrder = i, Parent = list })
		Kit.corner(row, 4)
		Kit.text({ Text = p.name .. (if p.host then "   HOST" else ""), Size = UDim2.new(0.6, -12, 0, 22), Position = UDim2.fromOffset(12, 4), FontFace = Kit.F.Heading, TextSize = 16, Parent = row })
		Kit.text({ Text = string.format("LV %s · %s", tostring(p.level or 1), p.title or "Visitor"), Size = UDim2.new(0.6, -12, 0, 16), Position = UDim2.fromOffset(12, 24), FontFace = Kit.F.Light, TextSize = 12, TextColor3 = C.Muted, Parent = row })
		Kit.text({ Text = if p.ready then "READY" else "WAITING", Size = UDim2.new(0.4, -12, 1, 0), Position = UDim2.fromScale(0.6, 0), TextXAlignment = Enum.TextXAlignment.Right, FontFace = Kit.F.Mono, TextSize = 14, TextColor3 = if p.ready then C.Text else C.Muted, Parent = row })
	end
	local isHost = s.hostUserId == player.UserId
	for name, b in diffButtons do
		local selected = s.difficulty == name
		b.TextColor3 = if selected then C.Black else (if isHost then C.Text else C.Muted)
		b.BackgroundColor3 = if selected then C.Text else C.PanelLight
		b.BackgroundTransparency = if selected then 0 else 0.4
		local available = name == "NORMAL" or (name == "HARD" and s.hardAvailable == true) or (name == "NIGHTMARE" and s.nightmareAvailable == true)
		b.Active = isHost and available
		if not available and not selected then
			b.TextColor3 = C.Line
		end
	end
	hardNote.Text = if not s.hardAvailable then "HARD unlocks after the host's first escape." elseif not s.nightmareAvailable then "NIGHTMARE unlocks after the host escapes on HARD." elseif not isHost then "The host chooses the difficulty." else ""
	readyButton.Text = if amReady then "NOT READY" else "READY"
	readyButton.Visible = not s.roundRunning
	spectateButton.Visible = s.roundRunning == true
	if s.roundRunning then
		statusLabel.Text = "A ROUND IS IN PROGRESS   " .. Util.formatTime(s.roundElapsed or 0)
		countdownLabel.Text = "You will join the next one."
	elseif s.countdown then
		statusLabel.Text = string.format("%d / %d AT THE FIELD OFFICE", #(s.players or {}), s.maxPlayers or 4)
		countdownLabel.Text = string.format("THE DOORS OPEN IN %d", math.ceil(s.countdown))
	else
		statusLabel.Text = string.format("%d / %d AT THE FIELD OFFICE", #(s.players or {}), s.maxPlayers or 4)
		countdownLabel.Text = "Ready up to start. Friends can join you here."
	end
end

function LobbyController:Init()
	gui = Kit.screen("Lobby", 4)
	panel = Kit.frame({ Size = UDim2.fromOffset(460, 720), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -40, 0.5, 0), BackgroundColor3 = C.Panel, BackgroundTransparency = 0.12, Parent = gui })
	Kit.corner(panel, 6)
	Kit.stroke(panel, C.Line, 1, 0.3)
	Kit.text({ Text = "THE FIELD OFFICE", Size = UDim2.new(1, -48, 0, 40), Position = UDim2.fromOffset(24, 20), FontFace = Kit.F.Title, TextSize = 28, Parent = panel })
	statusLabel = Kit.text({ Text = "", Size = UDim2.new(1, -48, 0, 20), Position = UDim2.fromOffset(24, 62), FontFace = Kit.F.Mono, TextSize = 13, TextColor3 = C.TextDim, Parent = panel })
	list = Kit.frame({ Size = UDim2.new(1, -48, 0, 220), Position = UDim2.fromOffset(24, 96), BackgroundTransparency = 1, Parent = panel })
	Kit.list(list, 6)
	Kit.text({ Text = "DIFFICULTY", Size = UDim2.new(1, -48, 0, 20), Position = UDim2.fromOffset(24, 336), FontFace = Kit.F.Heading, TextSize = 14, TextColor3 = C.TextDim, Parent = panel })
	local diffRow = Kit.frame({ Size = UDim2.new(1, -48, 0, 40), Position = UDim2.fromOffset(24, 360), BackgroundTransparency = 1, Parent = panel })
	Kit.list(diffRow, 8, true)
	for i, name in Enums.DifficultyOrder do
		diffButtons[name] = Kit.button({ Text = DIFF_TEXT[name], Size = UDim2.fromOffset(128, 40), TextSize = 14, LayoutOrder = i, Parent = diffRow }, function()
			Net.event("Lobby"):FireServer("difficulty", name)
		end)
	end
	hardNote = Kit.text({ Text = "", Size = UDim2.new(1, -48, 0, 18), Position = UDim2.fromOffset(24, 404), FontFace = Kit.F.Light, TextSize = 12, TextColor3 = C.Muted, Parent = panel })
	countdownLabel = Kit.text({ Text = "", Size = UDim2.new(1, -48, 0, 50), Position = UDim2.fromOffset(24, 440), FontFace = Kit.F.Heading, TextSize = 18, Parent = panel })
	readyButton = Kit.button({ Text = "READY", Size = UDim2.new(1, -48, 0, 58), Position = UDim2.fromOffset(24, 504), TextSize = 20, Style = "primary", Parent = panel }, function()
		Net.event("Lobby"):FireServer("ready", not amReady)
	end)
	spectateButton = Kit.button({ Text = "SPECTATE", Size = UDim2.new(1, -48, 0, 58), Position = UDim2.fromOffset(24, 504), TextSize = 20, Visible = false, Parent = panel }, function()
		Registry.SpectatorController:Begin(true)
	end)
	Kit.button({ Text = "INVITE FRIENDS", Size = UDim2.new(0.5, -30, 0, 44), Position = UDim2.fromOffset(24, 574), TextSize = 14, Parent = panel }, function()
		Net.event("Lobby"):FireServer("invite")
	end)
	Kit.button({ Text = "MENU", Size = UDim2.new(0.5, -30, 0, 44), Position = UDim2.new(0.5, 6, 0, 574), TextSize = 14, Parent = panel }, function()
		Registry.MenuController:SetPaused(true)
	end)
	Kit.text({ Text = "Walk up to the terminals: SUPPLY, LOADOUT, WARDROBE, RECORDS, ORDERS and ORIENTATION. Ready up, then meet at the door.", Size = UDim2.new(1, -48, 0, 40), Position = UDim2.fromOffset(24, 640), FontFace = Kit.F.Light, TextSize = 13, TextColor3 = C.Muted, Parent = panel })
	gui.Enabled = false
end

function LobbyController:Start()
	State.LobbyChanged:Connect(render)
	local function visibility()
		gui.Enabled = State.status == "LOBBY" and not Registry.SpectatorController:IsActive()
	end
	State.StatusChanged:Connect(visibility)
	Registry.SpectatorController.Changed:Connect(visibility)
	visibility()
end

return LobbyController
