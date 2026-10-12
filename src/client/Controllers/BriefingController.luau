--[[
	BriefingController
	The case file handed to you as a night begins: a few short pages, a little
	of the Ashgrove story and what the night asks of you. It opens when you
	arrive at the building (round STARTING), can be read at your pace (BACK /
	NEXT, the arrow keys, the D-pad), skipped at any time, and opened again
	from the pause menu (CASE FILE). While it is open the mouse is free; the
	night does not wait, so it closes itself if you are taken or the round ends.

	It never spoils what is in the building: it tells you what the project
	was, what it found, and the rules that keep you alive.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local Net = require(ReplicatedStorage.Shared.Net)
local State = require(script.Parent.Parent.State)
local Registry = require(script.Parent.Parent.Registry)
local Kit = require(script.Parent.Parent.UI.Kit)

local BriefingController = {}

local C = Kit.C
local gui: ScreenGui
local card: Frame? = nil
local page = 1
local open = false

-- The pages. Controls are filled in from the player's own bindings.
local function pages(): { { kicker: string, title: string, body: string } }
	local IC = Registry.InputController
	local function key(action: string): string
		return if IC and IC.Label then IC:Label(action) else action
	end
	return {
		{
			kicker = "CASE FILE 13  ·  PAGE 1",
			title = "THE ASHGROVE OBSERVATION PROJECT",
			body = "Ashgrove was a research building. Its director, Dr. Elias Vale, wanted to document one thing: what happens in a room while nobody is watching it.\n\nFor a year they photographed empty rooms, locked them, and came back. At first, nothing. Then a chair had moved. Then a painting was not the painting it used to be.\n\nThe project was closed. Nobody who worked there will talk about why.",
		},
		{
			kicker = "CASE FILE 13  ·  PAGE 2",
			title = "WHAT THEY FOUND",
			body = "The building changes when nobody is looking at it. Objects move, rooms stretch, doors appear where there were none.\n\nAnd something walks its corridors. The staff called it SUBJECT O-01. It is very tall. It has never been seen moving: everything it does happens between one look and the next.\n\nTonight, you are the ones looking.",
		},
		{
			kicker = "CASE FILE 13  ·  PAGE 3",
			title = "YOUR NIGHT",
			body = string.format(
				"Find what changed. When something is not as it was, look straight at it and hold [%s] to report it. Be sure: a wrong report draws attention.\n\nThe exit has four locks: restore the POWER, solve the two puzzles the building sets tonight, and report enough ANOMALIES. Read every note you find: keys, fuses and clues are in different rooms every night.",
				key("Report")
			),
		},
		{
			kicker = "CASE FILE 13  ·  PAGE 4",
			title = "THE RULES",
			body = "It only moves when nobody is looking at it. If you see it, keep your eyes on it and back away.\n\nIn the dark, looking is not enough: you have to see it. Keep your light on it.\n\nNobody can stare forever. You will blink.\n\nWhen you hear it breathe, turn around.\n\nStay together, so that someone is always watching.",
		},
		{
			kicker = "CASE FILE 13  ·  PAGE 5",
			title = "BEFORE YOU GO IN",
			body = string.format(
				"Flashlight [%s]   ·   Sprint [%s]   ·   Interact [%s]\nReport [%s]   ·   Ping your team [%s]   ·   Notes [%s]\n\nThe power will not last the night. Your battery will not either.\n\nAnd whatever you see in there:\n\ndon't look away.",
				key("Flashlight"),
				key("Sprint"),
				key("Interact"),
				key("Report"),
				key("Ping"),
				key("Notes")
			),
		},
	}
end

local function close()
	if not open then
		return
	end
	open = false
	local c = card
	card = nil
	if c then
		local scale = c:FindFirstChildOfClass("UIScale")
		if scale then
			Kit.tween(scale, 0.18, { Scale = 0.96 })
		end
		Kit.tween(c, 0.2, { BackgroundTransparency = 1 })
		task.delay(0.2, function()
			c:Destroy()
		end)
	end
	local shade = gui:FindFirstChild("Shade")
	if shade then
		shade:Destroy()
	end
	State.setUIOpen(false)
	GuiService.SelectedObject = nil
end

local render

function BriefingController:Open()
	if open then
		return
	end
	open = true
	page = 1
	State.setUIOpen(true)
	Kit.frame({ Name = "Shade", Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.Black, BackgroundTransparency = 0.45, Parent = gui })
	local c = Kit.frame({ Name = "CaseFile", Size = UDim2.fromOffset(1000, 640), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), BackgroundColor3 = C.Paper, BackgroundTransparency = 0.02, Parent = gui })
	Kit.corner(c, 4)
	Kit.stroke(c, C.InkFaint, 1, 0.4)
	local scale = Kit.new("UIScale", { Scale = 0.96, Parent = c })
	Kit.tween(scale, 0.25, { Scale = 1 })
	card = c
	Kit.sound("PaperRustle")
	render()
end

function BriefingController:Close()
	close()
end

function BriefingController:IsOpen(): boolean
	return open
end

local function go(delta: number)
	local list = pages()
	local nextPage = page + delta
	if nextPage > #list then
		Kit.sound("UIClick")
		close()
		return
	end
	if nextPage < 1 then
		return
	end
	page = nextPage
	Kit.sound("PaperRustle")
	render()
end

render = function()
	local c = card
	if not c then
		return
	end
	for _, child in c:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local list = pages()
	local p = list[page]
	-- the file's header and a stamp
	Kit.text({ Text = "ASHGROVE OBSERVATION PROJECT", Size = UDim2.new(1, -96, 0, 20), Position = UDim2.fromOffset(48, 32), FontFace = Kit.F.Type, TextSize = 16, TextColor3 = C.InkFaint, Parent = c })
	Kit.text({ Text = p.kicker, Size = UDim2.new(0, 300, 0, 20), Position = UDim2.new(1, -348, 0, 32), TextXAlignment = Enum.TextXAlignment.Right, FontFace = Kit.F.Type, TextSize = 15, TextColor3 = C.InkFaint, Parent = c })
	Kit.frame({ Size = UDim2.new(1, -96, 0, 1), Position = UDim2.fromOffset(48, 60), BackgroundColor3 = C.InkFaint, BackgroundTransparency = 0.4, Parent = c })
	local stamp = Kit.text({ Text = "CONFIDENTIAL", Size = UDim2.fromOffset(230, 40), Position = UDim2.new(1, -290, 0, 78), Rotation = -8, TextXAlignment = Enum.TextXAlignment.Center, FontFace = Kit.F.Heading, TextSize = 22, TextColor3 = C.DangerDim, TextTransparency = 0.25, Parent = c })
	Kit.stroke(stamp, C.DangerDim, 2, 0.35)
	Kit.text({ Text = p.title, Size = UDim2.new(1, -380, 0, 40), Position = UDim2.fromOffset(48, 80), FontFace = Kit.F.Heading, TextSize = 26, TextColor3 = C.Ink, Parent = c })
	local body = Kit.text({
		Text = p.body,
		Size = UDim2.new(1, -96, 0, 380),
		Position = UDim2.fromOffset(48, 140),
		FontFace = Kit.F.Type,
		TextSize = 21,
		TextColor3 = C.Ink,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		LineHeight = 1.15,
		Parent = c,
	})
	body.TextTransparency = 1
	Kit.tween(body, 0.35, { TextTransparency = 0 })
	-- the page dots
	local dots = Kit.frame({ Size = UDim2.fromOffset(#list * 18, 10), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, -82), BackgroundTransparency = 1, Parent = c })
	Kit.list(dots, 8, true)
	for i = 1, #list do
		local dot = Kit.frame({ Size = UDim2.fromOffset(10, 10), BackgroundColor3 = if i == page then C.Ink else C.InkFaint, BackgroundTransparency = if i == page then 0 else 0.6, LayoutOrder = i, Parent = dots })
		Kit.corner(dot, 5)
	end
	-- the buttons
	local last = page == #list
	local back = Kit.button({ Text = "BACK", Size = UDim2.fromOffset(170, 46), Position = UDim2.new(0, 48, 1, -66), TextSize = 16, Parent = c }, function()
		go(-1)
	end)
	back.Visible = page > 1
	local nextButton = Kit.button({ Text = if last then "ENTER THE BUILDING" else "NEXT", Size = UDim2.fromOffset(if last then 280 else 170, 46), Position = UDim2.new(1, if last then -328 else -218, 1, -66), TextSize = 16, Style = "primary", Parent = c }, function()
		go(1)
	end)
	if not last then
		Kit.button({ Text = "SKIP", Size = UDim2.fromOffset(110, 36), Position = UDim2.new(1, -338, 1, -61), TextSize = 14, Parent = c }, function()
			Kit.sound("UIBack")
			close()
		end)
	end
	if State.inputType == "Gamepad" then
		GuiService.SelectedObject = nextButton
	end
end

function BriefingController:Init()
	gui = Kit.screen("Briefing", 12)
end

function BriefingController:Start()
	-- a new night: the file is handed over as you arrive
	local lastSeed = nil
	Net.event("RoundState").OnClientEvent:Connect(function(p)
		if type(p) ~= "table" then
			return
		end
		if p.state == "STARTING" and p.seed ~= lastSeed then
			lastSeed = p.seed
			task.delay(1.5, function()
				if State.status == "ALIVE" and not State.distortion then
					BriefingController:Open()
				end
			end)
		elseif p.state == "RESULTS" or p.state == "RETURNING" or p.state == "LOBBY" then
			close()
		end
	end)
	State.StatusChanged:Connect(function()
		if State.status ~= "ALIVE" then
			close()
		end
	end)
	-- arrows / D-pad turn the pages, Enter goes on
	UserInputService.InputBegan:Connect(function(input, processed)
		if not open or processed then
			return
		end
		local k = input.KeyCode
		if k == Enum.KeyCode.Right or k == Enum.KeyCode.DPadRight or k == Enum.KeyCode.Return then
			go(1)
		elseif k == Enum.KeyCode.Left or k == Enum.KeyCode.DPadLeft then
			go(-1)
		end
	end)
	Registry.InputController.Action:Connect(function(action, began)
		if began and open and action == "Back" then
			close()
		end
	end)
end

return BriefingController
