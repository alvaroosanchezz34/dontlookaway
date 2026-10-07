--[[
	MobileControls
	Large, thumb-friendly touch buttons on the right side (the left side is the
	movement thumbstick, the rest of the screen is look). Buttons only appear
	when they are useful: INTERACT shows only when something is in reach.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local State = require(script.Parent.Parent.State)
local Registry = require(script.Parent.Parent.Registry)
local Kit = require(script.Parent.Parent.UI.Kit)

local MobileControls = {}

local C = Kit.C
local gui: ScreenGui
local buttons: { [string]: TextButton } = {}

local function makeButton(name: string, label: string, pos: UDim2, size: number, onDown: () -> (), onUp: (() -> ())?)
	local b = Kit.new("TextButton", {
		Name = name,
		Text = label,
		AutoButtonColor = false,
		Size = UDim2.fromOffset(size, size),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = pos,
		BackgroundColor3 = C.Black,
		BackgroundTransparency = 0.45,
		TextColor3 = C.Text,
		FontFace = Kit.F.Heading,
		TextSize = 15,
		Parent = gui,
	})
	Kit.corner(b, size // 2)
	Kit.stroke(b, C.Text, 1.5, 0.55)
	b.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			b.BackgroundTransparency = 0.15
			onDown()
		end
	end)
	b.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			b.BackgroundTransparency = 0.45
			if onUp then
				onUp()
			end
		end
	end)
	buttons[name] = b
	return b
end

function MobileControls:Init()
	gui = Kit.screen("MobileControls", 4)
	local IC = Registry.InputController
	makeButton("Interact", "USE", UDim2.new(1, -150, 1, -250), 112, function()
		IC:Trigger("Interact", true)
	end, function()
		IC:Trigger("Interact", false)
	end)
	makeButton("Report", "LOOK", UDim2.new(1, -270, 1, -150), 104, function()
		IC:Trigger("Report", true)
	end, function()
		IC:Trigger("Report", false)
	end)
	makeButton("Sprint", "RUN", UDim2.new(1, -110, 1, -120), 96, function()
		IC:Trigger("Sprint", true)
	end, function()
		IC:Trigger("Sprint", false)
	end)
	makeButton("Flashlight", "LIGHT", UDim2.new(1, -110, 1, -370), 84, function()
		IC:Trigger("Flashlight", true)
		IC:Trigger("Flashlight", false)
	end)
	makeButton("Ping", "PING", UDim2.new(1, -230, 1, -360), 78, function()
		Registry.PingController:OpenTouchWheel()
	end)
	makeButton("Notes", "NOTES", UDim2.new(1, -330, 1, -320), 70, function()
		IC:Trigger("Notes", true)
		IC:Trigger("Notes", false)
	end)
	makeButton("ToolCycle", "TOOL", UDim2.new(1, -400, 1, -230), 64, function()
		IC:Trigger("CycleTool", true)
		IC:Trigger("CycleTool", false)
	end)
	makeButton("ToolUse", "USE TOOL", UDim2.new(1, -390, 1, -140), 82, function()
		IC:Trigger("UseTool", true)
	end, function()
		IC:Trigger("UseTool", false)
	end)
	makeButton("Menu", "MENU", UDim2.new(1, -70, 0, 70), 70, function()
		IC:Trigger("Pause", true)
		IC:Trigger("Pause", false)
	end)
	makeButton("Emote", "EMOTE", UDim2.new(1, -180, 0, 70), 70, function()
		IC:Trigger("Emote", true)
		IC:Trigger("Emote", false)
	end)
end

function MobileControls:Start()
	RunService.RenderStepped:Connect(function()
		local touch = State.inputType == "Touch"
		local alive = State.status == "ALIVE"
		local lobby = State.status == "LOBBY"
		gui.Enabled = touch and (alive or lobby) and not State.uiOpen
		if not gui.Enabled then
			return
		end
		local hasTarget = Registry.InteractController:GetTarget() ~= nil
		buttons.Interact.Visible = hasTarget
		buttons.Report.Visible = alive
		buttons.Sprint.Visible = alive
		buttons.Flashlight.Visible = alive
		buttons.Ping.Visible = alive
		buttons.Notes.Visible = alive
		buttons.Emote.Visible = lobby or alive
		local belt = State.tools and State.tools.tools or {}
		buttons.ToolCycle.Visible = alive and #belt > 0
		buttons.ToolUse.Visible = alive and (State.tools.selected or 0) > 0
		buttons.Sprint.Text = if State.sprinting then "RUN •" else "RUN"
		buttons.Flashlight.Text = if Players.LocalPlayer:GetAttribute("Flashlight") then "LIGHT •" else "LIGHT"
	end)
end

return MobileControls
