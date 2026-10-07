--[[
	PuzzleUI
	* Keypad: a physical-feeling 3x4 pad (mouse, touch, keyboard digits, gamepad)
	* Documents: typewritten paper, remembered in your NOTES for this round
	* Notes (Tab): everything you have read tonight, so clues are never lost
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local Net = require(ReplicatedStorage.Shared.Net)
local State = require(script.Parent.Parent.State)
local Registry = require(script.Parent.Parent.Registry)
local Kit = require(script.Parent.Parent.UI.Kit)

local PuzzleUI = {}

local C = Kit.C
local gui: ScreenGui
local keypad: Frame
local display: TextLabel
local entry = ""
local paper: Frame
local paperTitle: TextLabel
local paperBody: TextLabel
local notesPanel: Frame
local notesList: ScrollingFrame
local openPanel: string? = nil

local function close()
	if keypad then
		keypad.Visible = false
	end
	if paper then
		paper.Visible = false
	end
	if notesPanel then
		notesPanel.Visible = false
	end
	openPanel = nil
	GuiService.SelectedObject = nil
	State.setUIOpen(false)
end

function PuzzleUI:IsOpen(): boolean
	return openPanel ~= nil
end

function PuzzleUI:Close()
	close()
end

local function press(key: string)
	Registry.AudioController:PlayUI("KeypadBeep")
	if key == "C" then
		entry = ""
	elseif key == "OK" then
		if #entry == 4 then
			Net.event("Puzzle"):FireServer("keypad", entry)
		end
		return
	elseif #entry < 4 then
		entry ..= key
	end
	display.Text = entry .. string.rep("-", 4 - #entry)
end

local function openKeypad()
	close()
	entry = ""
	display.Text = "----"
	display.TextColor3 = Color3.fromRGB(150, 230, 170)
	keypad.Visible = true
	openPanel = "keypad"
	State.setUIOpen(true)
	if State.inputType == "Gamepad" then
		GuiService.SelectedObject = keypad:FindFirstChild("Key5", true) :: GuiObject?
	end
end

local function openDocument(doc)
	close()
	paperTitle.Text = doc.title or ""
	paperBody.Text = doc.body or ""
	paper.Visible = true
	openPanel = "paper"
	State.setUIOpen(true)
	-- remember it
	for _, n in State.notes do
		if n.id == doc.id then
			return
		end
	end
	table.insert(State.notes, { id = doc.id, title = doc.title, body = doc.body })
end

local function openNotes()
	close()
	for _, c in notesList:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	if #State.notes == 0 then
		Kit.text({ Text = "You haven't read anything yet tonight.", Size = UDim2.new(1, 0, 0, 30), TextColor3 = C.TextDim, Parent = notesList })
	end
	for i, n in State.notes do
		local block = Kit.frame({ Size = UDim2.new(1, -10, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = Color3.fromRGB(214, 206, 184), LayoutOrder = i, Parent = notesList })
		Kit.padding(block, 14)
		Kit.list(block, 6)
		Kit.text({ Text = n.title, Size = UDim2.new(1, 0, 0, 24), FontFace = Kit.F.Type, TextSize = 20, TextColor3 = Color3.fromRGB(30, 28, 26), Parent = block })
		Kit.text({ Text = n.body, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, FontFace = Kit.F.Type, TextSize = 17, TextColor3 = Color3.fromRGB(40, 36, 32), TextYAlignment = Enum.TextYAlignment.Top, LayoutOrder = 2, Parent = block })
	end
	notesPanel.Visible = true
	openPanel = "notes"
	State.setUIOpen(true)
end

function PuzzleUI:Init()
	gui = Kit.screen("Puzzles", 7)
	-- keypad
	keypad = Kit.frame({ Size = UDim2.fromOffset(330, 470), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), BackgroundColor3 = Color3.fromRGB(34, 36, 38), Visible = false, Parent = gui })
	Kit.corner(keypad, 10)
	Kit.stroke(keypad, Color3.fromRGB(70, 72, 74), 2)
	local screen = Kit.frame({ Size = UDim2.new(1, -48, 0, 70), Position = UDim2.fromOffset(24, 24), BackgroundColor3 = Color3.fromRGB(20, 32, 26), Parent = keypad })
	Kit.corner(screen, 4)
	display = Kit.text({ Text = "----", Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, FontFace = Kit.F.Mono, TextSize = 44, TextColor3 = Color3.fromRGB(150, 230, 170), Parent = screen })
	local keys = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "C", "0", "OK" }
	for i, k in keys do
		local col = (i - 1) % 3
		local row = (i - 1) // 3
		local b = Kit.button({ Name = "Key" .. k, Text = k, Size = UDim2.fromOffset(84, 70), Position = UDim2.fromOffset(24 + col * 96, 112 + row * 82), TextSize = 26, FontFace = Kit.F.Mono, BackgroundColor3 = Color3.fromRGB(150, 150, 146), TextColor3 = Color3.fromRGB(20, 20, 20), Style = "primary", Parent = keypad }, function()
			press(k)
		end)
		b.BackgroundColor3 = if k == "OK" then Color3.fromRGB(170, 196, 170) elseif k == "C" then Color3.fromRGB(196, 170, 160) else Color3.fromRGB(176, 176, 170)
	end
	Kit.button({ Text = "CLOSE", Size = UDim2.fromOffset(120, 34), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 14), Parent = keypad }, close)
	-- paper
	paper = Kit.frame({ Size = UDim2.fromOffset(620, 720), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), BackgroundColor3 = Color3.fromRGB(214, 206, 184), Rotation = -1.2, Visible = false, Parent = gui })
	Kit.new("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(205, 196, 176)), Rotation = 70, Parent = paper })
	Kit.padding(paper, 48)
	paperTitle = Kit.text({ Text = "", Size = UDim2.new(1, 0, 0, 40), FontFace = Kit.F.Type, TextSize = 30, TextColor3 = Color3.fromRGB(30, 28, 26), Parent = paper })
	paperBody = Kit.text({ Text = "", Size = UDim2.new(1, 0, 1, -100), Position = UDim2.fromOffset(0, 60), FontFace = Kit.F.Type, TextSize = 22, TextColor3 = Color3.fromRGB(40, 36, 32), TextYAlignment = Enum.TextYAlignment.Top, Parent = paper })
	local closeHint = Kit.text({ Text = "", Size = UDim2.new(1, 0, 0, 24), Position = UDim2.new(0, 0, 1, -24), TextXAlignment = Enum.TextXAlignment.Right, FontFace = Kit.F.Light, TextSize = 15, TextColor3 = Color3.fromRGB(90, 84, 76), Parent = paper })
	local function updateHint()
		closeHint.Text = "[" .. Registry.InputController:Label("Interact") .. "] put it down     [" .. Registry.InputController:Label("Notes") .. "] notes"
	end
	updateHint()
	State.InputTypeChanged:Connect(updateHint)
	local paperButton = Kit.new("TextButton", { Text = "", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = paper })
	paperButton.Activated:Connect(close)
	-- notes
	local body
	notesPanel, body = Kit.panel(gui, "NOTES", UDim2.fromOffset(760, 760))
	notesPanel.Visible = false
	notesList = Kit.scroll(body, { Size = UDim2.new(1, 0, 1, -50) })
	Kit.list(notesList, 12)
	Kit.button({ Text = "CLOSE", Size = UDim2.fromOffset(140, 40), Position = UDim2.new(1, -140, 1, -40), Parent = body }, close)
end

function PuzzleUI:Start()
	Net.event("PuzzleState").OnClientEvent:Connect(function(p)
		if type(p) ~= "table" then
			return
		end
		if p.type == "keypad" then
			if p.open and not keypad.Visible then
				openKeypad()
			elseif not p.open then
				close()
			end
			if p.result == "error" then
				display.TextColor3 = Color3.fromRGB(230, 120, 110)
				display.Text = "ERROR"
				entry = ""
				task.delay(0.8, function()
					display.TextColor3 = Color3.fromRGB(150, 230, 170)
					display.Text = "----"
				end)
			end
		end
	end)
	Net.event("Document").OnClientEvent:Connect(function(doc)
		if type(doc) == "table" then
			openDocument(doc)
		end
	end)
	Registry.InputController.Action:Connect(function(action, began)
		if not began then
			return
		end
		if action == "Notes" and State.status == "ALIVE" then
			if openPanel == "notes" then
				close()
			elseif not State.uiOpen or openPanel then
				openNotes()
			end
		elseif (action == "Back" or action == "Interact") and openPanel and openPanel ~= "keypad" then
			task.defer(close)
		elseif action == "Back" and openPanel == "keypad" then
			close()
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if openPanel ~= "keypad" or processed then
			return
		end
		local map = {
			[Enum.KeyCode.Zero] = "0", [Enum.KeyCode.One] = "1", [Enum.KeyCode.Two] = "2", [Enum.KeyCode.Three] = "3", [Enum.KeyCode.Four] = "4",
			[Enum.KeyCode.Five] = "5", [Enum.KeyCode.Six] = "6", [Enum.KeyCode.Seven] = "7", [Enum.KeyCode.Eight] = "8", [Enum.KeyCode.Nine] = "9",
			[Enum.KeyCode.KeypadZero] = "0", [Enum.KeyCode.KeypadOne] = "1", [Enum.KeyCode.KeypadTwo] = "2", [Enum.KeyCode.KeypadThree] = "3", [Enum.KeyCode.KeypadFour] = "4",
			[Enum.KeyCode.KeypadFive] = "5", [Enum.KeyCode.KeypadSix] = "6", [Enum.KeyCode.KeypadSeven] = "7", [Enum.KeyCode.KeypadEight] = "8", [Enum.KeyCode.KeypadNine] = "9",
			[Enum.KeyCode.Return] = "OK", [Enum.KeyCode.KeypadEnter] = "OK", [Enum.KeyCode.Backspace] = "C",
		}
		local k = map[input.KeyCode]
		if k then
			press(k)
		end
	end)
	State.StatusChanged:Connect(function()
		if State.status ~= "ALIVE" and openPanel then
			close()
		end
	end)
end

return PuzzleUI
