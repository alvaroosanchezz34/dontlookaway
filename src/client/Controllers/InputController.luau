--[[
	InputController
	One action layer for keyboard & mouse, gamepad and touch.
	Gameplay code listens to actions ("Sprint", "Interact", ...) and never to raw
	keys, so every device works the same way. Touch buttons call :Trigger().
]]

local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local State = require(script.Parent.Parent.State)

local InputController = {}

InputController.Action = Signal.new() -- (actionName, began: boolean)

local BINDINGS = {
	Sprint = { Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL3 },
	Interact = { Enum.KeyCode.E, Enum.KeyCode.ButtonX },
	Flashlight = { Enum.KeyCode.F, Enum.KeyCode.ButtonY },
	Report = { Enum.UserInputType.MouseButton2, Enum.KeyCode.Q, Enum.KeyCode.ButtonL2 },
	Ping = { Enum.KeyCode.G, Enum.UserInputType.MouseButton3, Enum.KeyCode.ButtonR1 },
	Slot1 = { Enum.KeyCode.One },
	Slot2 = { Enum.KeyCode.Two },
	Slot3 = { Enum.KeyCode.Three },
	Slot4 = { Enum.KeyCode.Four },
	SlotNext = { Enum.KeyCode.DPadRight },
	SlotPrev = { Enum.KeyCode.DPadLeft },
	UseItem = { Enum.KeyCode.R, Enum.KeyCode.DPadUp },
	DropItem = { Enum.KeyCode.X, Enum.KeyCode.DPadDown },
	Notes = { Enum.KeyCode.Tab, Enum.KeyCode.ButtonSelect },
	Pause = { Enum.KeyCode.P, Enum.KeyCode.M, Enum.KeyCode.ButtonStart },
	Journal = { Enum.KeyCode.J },
	Emote = { Enum.KeyCode.B, Enum.KeyCode.ButtonR3 },
	Admin = { Enum.KeyCode.F8 },
	SpectateNext = { Enum.KeyCode.D, Enum.KeyCode.Right, Enum.KeyCode.ButtonR1 },
	SpectatePrev = { Enum.KeyCode.A, Enum.KeyCode.Left, Enum.KeyCode.ButtonL1 },
	Back = { Enum.KeyCode.ButtonB },
	-- tool belt
	Tool1 = { Enum.KeyCode.Five },
	Tool2 = { Enum.KeyCode.Six },
	Tool3 = { Enum.KeyCode.Seven },
	Tool4 = { Enum.KeyCode.Eight },
	Tool5 = { Enum.KeyCode.Nine },
	CycleTool = { Enum.KeyCode.V, Enum.KeyCode.ButtonL1 },
	UseTool = { Enum.KeyCode.T, Enum.KeyCode.ButtonR2 },
}

InputController.Bindings = BINDINGS

-- Label shown in prompts for each action, per device.
local LABELS = {
	Keyboard = { Interact = "E", Flashlight = "F", Report = "RMB", Sprint = "SHIFT", Ping = "G", UseItem = "R", DropItem = "X", Notes = "TAB", Pause = "P", Journal = "J", Emote = "B", CycleTool = "V", UseTool = "T", Tools = "5-9" },
	Gamepad = { Interact = "X", Flashlight = "Y", Report = "LT", Sprint = "L3", Ping = "RB", UseItem = "D-UP", DropItem = "D-DOWN", Notes = "VIEW", Pause = "MENU", Journal = "VIEW", Emote = "R3", CycleTool = "LB", UseTool = "RT", Tools = "LB" },
	Touch = { Interact = "TAP", Flashlight = "LIGHT", Report = "HOLD EYE", Sprint = "RUN", Ping = "PING", UseItem = "USE", DropItem = "DROP", Notes = "NOTES", Pause = "MENU", Journal = "JOURNAL", Emote = "EMOTE", CycleTool = "TOOL", UseTool = "USE TOOL", Tools = "TOOL" },
}

local held: { [string]: boolean } = {}
local lookup: { [any]: { string } } = {}

for action, inputs in BINDINGS do
	for _, input in inputs do
		lookup[input] = lookup[input] or {}
		table.insert(lookup[input], action)
	end
end

function InputController:Label(action: string): string
	local set = LABELS[State.inputType] or LABELS.Keyboard
	return set[action] or action
end

function InputController:IsHeld(action: string): boolean
	return held[action] == true
end

function InputController:Trigger(action: string, began: boolean)
	if held[action] == began then
		return
	end
	held[action] = began
	InputController.Action:Fire(action, began)
end

local function actionsFor(input: InputObject): { string }?
	if input.KeyCode ~= Enum.KeyCode.Unknown then
		return lookup[input.KeyCode]
	end
	return lookup[input.UserInputType]
end

local function setInputType(t: string)
	if State.inputType ~= t then
		State.inputType = t
		State.InputTypeChanged:Fire(t)
	end
end

local function classify(input: InputObject)
	local t = input.UserInputType
	if t == Enum.UserInputType.Touch then
		setInputType("Touch")
	elseif t.Name:match("^Gamepad") then
		setInputType("Gamepad")
	elseif t == Enum.UserInputType.Keyboard or t.Name:match("^Mouse") then
		if t ~= Enum.UserInputType.MouseMovement or input.Delta.Magnitude > 2 then
			setInputType("Keyboard")
		end
	end
end

function InputController:Init()
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		State.inputType = "Touch"
	elseif UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
		State.inputType = "Gamepad"
	end
	UserInputService.InputBegan:Connect(function(input, processed)
		classify(input)
		local actions = actionsFor(input)
		if not actions then
			return
		end
		for _, action in actions do
			-- typing in chat never triggers actions (except the admin toggle)
			if not processed or action == "Admin" or (action == "Pause" and input.KeyCode == Enum.KeyCode.ButtonStart) then
				self:Trigger(action, true)
			end
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		local actions = actionsFor(input)
		if not actions then
			return
		end
		for _, action in actions do
			self:Trigger(action, false)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		classify(input)
	end)
	UserInputService.LastInputTypeChanged:Connect(function(t)
		if t == Enum.UserInputType.Touch then
			setInputType("Touch")
		elseif t.Name:match("^Gamepad") then
			setInputType("Gamepad")
		end
	end)
	-- releasing focus (alt-tab) must not leave actions stuck
	UserInputService.WindowFocusReleased:Connect(function()
		for action, isHeld in held do
			if isHeld then
				self:Trigger(action, false)
			end
		end
	end)
end

return InputController
