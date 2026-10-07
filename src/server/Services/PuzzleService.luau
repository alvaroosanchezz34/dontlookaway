--[[
	PuzzleService
	Server logic for every puzzle fixture in the building:
	  POWER    fuse box (3 fuses) + breaker panel (pattern from the maintenance log)
	  CODE     keypad door (code split over two notes) + security override lever
	  SYMBOLS  archive cabinet with four symbol dials (markings painted on walls)
	  DOORS    cassette in the closet hall dictates the order of four closet doors
	  OFFERING three belongings returned to the Quiet Room table
	  (secret) boarded passage pried open with the crowbar
	All inputs are validated and all state lives here; clients only display it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Net = require(ReplicatedStorage.Shared.Net)
local Util = require(ReplicatedStorage.Shared.Util.Util)
local Registry = require(script.Parent.Parent.Registry)
local Art = require(script.Parent.Parent.Map.Art)

local PuzzleService = {}

local ctx = nil

local CLOSET_NAMES = { "AMBER", "WHITE", "GREEN", "BLUE" }
local OFFER_ITEMS = { "MUSIC_BOX", "DOLL", "CANDLE" }

local function tagged(tag: string, root: Instance)
	for _, inst in CollectionService:GetTagged(tag) do
		if inst:IsDescendantOf(root) then
			return inst
		end
	end
	return nil
end

local function taggedAll(tag: string, root: Instance)
	local list = {}
	for _, inst in CollectionService:GetTagged(tag) do
		if inst:IsDescendantOf(root) then
			table.insert(list, inst)
		end
	end
	return list
end

local function notify(player: Player, text: string)
	Net.fire(player, "Notify", { kind = "info", text = text })
end

local function nearPlayers(position: Vector3, radius: number): { Player }
	local list = {}
	for _, p in Registry.PlayerService:GetAlive() do
		local root = Util.getRoot(p)
		if root and (root.Position - position).Magnitude <= radius then
			table.insert(list, p)
		end
	end
	return list
end

local function solved(kind: string, position: Vector3?)
	Registry.ProgressionService:PuzzleSolved(kind, if position then nearPlayers(position, 80) else Registry.PlayerService:GetAlive())
end

local function isChosen(kind: string): boolean
	return ctx ~= nil and table.find(ctx.state.puzzles, kind) ~= nil
end

------------------------------------------------------------------------------------
-- Setup
------------------------------------------------------------------------------------

function PuzzleService:Setup(map, state, rng)
	local root = map.Root
	ctx = {
		map = map,
		state = state,
		rng = rng,
		fuseBox = tagged("FuseBox", root),
		breaker = tagged("BreakerPanel", root),
		keypad = tagged("Keypad", root),
		override = tagged("SecurityOverride", root),
		cabinet = tagged("SymbolCabinet", root),
		offering = tagged("OfferingTable", root),
		recorder = tagged("TapeRecorder", root),
		lamps = taggedAll("ClosetLamp", root),
		breakers = { false, false, false, false, false },
		dials = { 1, 1, 1, 1 },
		closetProgress = 0,
		tapeInserted = false,
		tapePlaying = false,
		offered = { false, false, false },
		keypadSolved = false,
		keypadWrong = 0,
		lastKeypadTry = {},
		overridePulled = false,
		cabinetOpen = false,
	}
	-- initial dial positions never match the solution
	if ctx.cabinet then
		for i = 1, 4 do
			local idx = rng:Int(1, #Art.Symbols)
			if state.symbols[i] and Art.Symbols[idx] == state.symbols[i] then
				idx = idx % #Art.Symbols + 1
			end
			ctx.dials[i] = idx
			self:RenderDial(i)
		end
	end
	for i = 1, 5 do
		self:RenderBreaker(i)
	end
	-- keypad readout
	if ctx.keypad then
		local readout = ctx.keypad:FindFirstChild("Readout", true)
		if readout and readout:IsA("TextLabel") then
			readout.Text = if isChosen("CODE") then "----" else "OFFLINE"
		end
	end
end

------------------------------------------------------------------------------------
-- POWER
------------------------------------------------------------------------------------

function PuzzleService:RenderBreaker(i: number)
	if not ctx or not ctx.breaker then
		return
	end
	local lever = ctx.breaker:FindFirstChild("Lever" .. i)
	if not lever then
		return
	end
	local base = lever:GetAttribute("BaseCFrame")
	if typeof(base) ~= "CFrame" then
		base = lever.CFrame * CFrame.Angles(math.rad(-20), 0, 0) -- remove the built-in down tilt
		lever:SetAttribute("BaseCFrame", base)
	end
	local up = ctx.breakers[i]
	lever.CFrame = base * CFrame.new(0, if up then 0.5 else -0.1, 0) * CFrame.Angles(math.rad(if up then -25 else 25), 0, 0)
	lever.Color = if up then Color3.fromRGB(190, 186, 170) else Color3.fromRGB(150, 40, 34)
end

local function checkPower()
	local state = ctx.state
	if state.power or state.fuses < 3 then
		return
	end
	for i = 1, 5 do
		if ctx.breakers[i] ~= state.breakerPattern[i] then
			return
		end
	end
	state.power = true
	state.subProgress.POWER = nil
	local status = ctx.breaker and ctx.breaker:FindFirstChild("Status")
	if status then
		status.Color = Color3.fromRGB(200, 236, 200)
	end
	Registry.LightingService:SetPower(true)
	Registry.AudioService:Play2DAll("PowerOn")
	Net.fireAll("Notify", { kind = "objective", text = "POWER RESTORED" })
	Net.fireAll("Effect", { name = "PowerSurge" })
	Registry.ObjectiveService:ReleaseLock("POWER")
	Registry.HorrorDirector:OnMilestone("power")
	solved("POWER", ctx.breaker and ctx.breaker:GetPivot().Position)
end

local function onFuseBox(player: Player, target: Instance): boolean
	if not ctx or not ctx.fuseBox or not target:IsDescendantOf(ctx.fuseBox) then
		return false
	end
	local state = ctx.state
	if state.fuses >= 3 then
		notify(player, if state.power then "The fuse box hums." else "All three fuses are in. Now the breakers.")
		return false
	end
	if not Registry.InventoryService:Has(player, "FUSE") then
		notify(player, string.format("The fuse box needs three fuses. %d/3 inserted.", state.fuses))
		return false
	end
	Registry.InventoryService:Remove(player, "FUSE", 1)
	state.fuses += 1
	local fuse = ctx.fuseBox:FindFirstChild("Fuse" .. state.fuses)
	if fuse then
		fuse.Transparency = 0
	end
	local lamp = ctx.fuseBox:FindFirstChild("Lamp" .. state.fuses)
	if lamp then
		lamp.Color = Color3.fromRGB(230, 200, 140)
	end
	Registry.AudioService:PlayAt("FuseInsert", ctx.fuseBox:GetPivot().Position)
	if state.fuses >= 3 then
		state.subProgress.POWER = "Set the breakers (see the maintenance log)"
	end
	Registry.ObjectiveService:Push()
	checkPower()
	return true
end

local function onBreaker(player: Player, target: Instance): boolean
	if not ctx or not ctx.breaker or not target:IsDescendantOf(ctx.breaker) then
		return false
	end
	local i = target:GetAttribute("Index")
	if type(i) ~= "number" or i < 1 or i > 5 then
		return false
	end
	if ctx.state.power then
		notify(player, "Leave them. The lights are on.")
		return false
	end
	ctx.breakers[i] = not ctx.breakers[i]
	PuzzleService:RenderBreaker(i)
	Registry.AudioService:PlayAt("BreakerFlip", target.Position)
	if ctx.state.fuses < 3 then
		notify(player, "Nothing. The fuse box is still empty.")
	end
	checkPower()
	return true
end

------------------------------------------------------------------------------------
-- CODE
------------------------------------------------------------------------------------

local function keypadDoor()
	if not ctx then
		return nil
	end
	for _, rec in ctx.map.Doors do
		if rec.model and rec.model:GetAttribute("Kind") == "keypad" then
			return rec.model
		end
	end
	return nil
end

local function onKeypad(player: Player, target: Instance): boolean
	if not ctx or not ctx.keypad or not target:IsDescendantOf(ctx.keypad) then
		return false
	end
	if not isChosen("CODE") then
		notify(player, "The keypad is dead. This door won't open tonight.")
		return false
	end
	if ctx.keypadSolved then
		notify(player, "The door is open.")
		return false
	end
	Net.fire(player, "PuzzleState", { type = "keypad", open = true })
	return true
end

function PuzzleService:SubmitCode(player: Player, code: any)
	if not ctx or not ctx.keypad or not isChosen("CODE") or ctx.keypadSolved then
		return
	end
	if type(code) ~= "string" or not string.match(code, "^%d%d%d%d$") then
		return
	end
	local head = Util.getHead(player)
	if not head or (head.Position - ctx.keypad:GetPivot().Position).Magnitude > 14 then
		return
	end
	local now = os.clock()
	if ctx.lastKeypadTry[player] and now - ctx.lastKeypadTry[player] < 0.8 then
		return
	end
	ctx.lastKeypadTry[player] = now
	local readout = ctx.keypad:FindFirstChild("Readout", true) :: TextLabel?
	local pos = ctx.keypad:GetPivot().Position
	if code == ctx.state.code then
		ctx.keypadSolved = true
		if readout then
			readout.Text = "OPEN"
		end
		Registry.AudioService:PlayAt("KeypadOk", pos)
		local door = keypadDoor()
		if door then
			Registry.DoorService:Unlock(door)
			Registry.DoorService:SetOpen(door, true, { player = player })
		end
		Net.fire(player, "PuzzleState", { type = "keypad", open = false, result = "ok" })
		Registry.ObjectiveService:SetSubProgress("CODE", "Pull the override in the security office")
	else
		ctx.keypadWrong += 1
		if readout then
			readout.Text = "ERROR"
			task.delay(1.2, function()
				if readout.Parent and not ctx.keypadSolved then
					readout.Text = "----"
				end
			end)
		end
		Registry.AudioService:PlayAt("KeypadError", pos)
		Net.fire(player, "PuzzleState", { type = "keypad", open = true, result = "error" })
		if ctx.keypadWrong % 3 == 0 then
			Registry.HorrorDirector:AddDread(6, "keypad")
		end
	end
end

local function onOverride(player: Player, target: Instance): boolean
	if not ctx or not ctx.override or not target:IsDescendantOf(ctx.override) then
		return false
	end
	if not isChosen("CODE") then
		notify(player, "The override does nothing. The panel is disconnected.")
		return false
	end
	if ctx.overridePulled then
		return false
	end
	if not ctx.keypadSolved then
		notify(player, "The override is locked behind the security door.")
		return false
	end
	ctx.overridePulled = true
	if target:IsA("BasePart") then
		target.CFrame = target.CFrame * CFrame.Angles(math.rad(-50), 0, 0)
	end
	Registry.AudioService:PlayAt("BreakerFlip", target.Position)
	Registry.ObjectiveService:SetSubProgress("CODE", nil)
	Registry.ObjectiveService:ReleaseLock("CODE")
	solved("CODE", target.Position)
	return true
end

------------------------------------------------------------------------------------
-- SYMBOLS
------------------------------------------------------------------------------------

function PuzzleService:RenderDial(i: number)
	if not ctx or not ctx.cabinet then
		return
	end
	local face = ctx.cabinet:FindFirstChild("DialFace" .. i)
	local gui = face and face:FindFirstChild("Face")
	local plate = gui and gui:FindFirstChild("Plate")
	if not plate then
		return
	end
	local old = plate:FindFirstChild("Symbol")
	if old then
		old:Destroy()
	end
	Art.symbol(plate, Art.Symbols[ctx.dials[i]], Color3.fromRGB(30, 26, 24), 3)
end

local function onDial(player: Player, target: Instance): boolean
	if not ctx or not ctx.cabinet or not target:IsDescendantOf(ctx.cabinet) then
		return false
	end
	if ctx.cabinetOpen then
		return false
	end
	local i = target:GetAttribute("Index")
	if type(i) ~= "number" or i < 1 or i > 4 then
		return false
	end
	ctx.dials[i] = ctx.dials[i] % #Art.Symbols + 1
	PuzzleService:RenderDial(i)
	Registry.AudioService:PlayAt("DialTurn", target.Position)
	if not isChosen("SYMBOLS") then
		return true
	end
	for d = 1, 4 do
		if Art.Symbols[ctx.dials[d]] ~= ctx.state.symbols[d] then
			return true
		end
	end
	ctx.cabinetOpen = true
	local drawer = ctx.cabinet:FindFirstChild("Drawer")
	if drawer and drawer:IsA("BasePart") then
		drawer.CFrame = drawer.CFrame * CFrame.new(0, 0, -1.4)
	end
	Registry.AudioService:PlayAt("LockRelease", target.Position)
	Registry.ObjectiveService:ReleaseLock("SYMBOLS")
	solved("SYMBOLS", target.Position)
	return true
end

------------------------------------------------------------------------------------
-- DOORS
------------------------------------------------------------------------------------

local function closetDoors()
	local list = {}
	for _, rec in ctx.map.Doors do
		if rec.model and rec.model:GetAttribute("Kind") == "closet" then
			list[rec.model:GetAttribute("Closet")] = rec.model
		end
	end
	return list
end

local function setLamp(index: number, on: boolean)
	for _, lamp in ctx.lamps do
		if lamp:GetAttribute("Index") == index then
			local bulb = lamp:FindFirstChild("Bulb")
			if bulb then
				local lit = bulb:GetAttribute("LitColor")
				bulb.Color = if on and typeof(lit) == "Color3" then lit else (if typeof(lit) == "Color3" then lit:Lerp(Color3.new(), 0.6) else bulb.Color)
				local light = bulb:FindFirstChildOfClass("PointLight")
				if light then
					light.Enabled = on
				end
			end
		end
	end
end

local function playTape()
	if ctx.tapePlaying or not ctx.recorder then
		return
	end
	ctx.tapePlaying = true
	local pos = ctx.recorder:GetPivot().Position
	local listeners = nearPlayers(pos, 60)
	Registry.AudioService:PlayAtFor(listeners, "TapeInsert", pos)
	local lines = { "[TAPE] ...is this recording? ...okay. Maintenance, B1." , "[TAPE] If the closets lock again, open them in this order. Nothing else works." }
	for n, idx in ctx.state.doorOrder do
		local ordinal = ({ "First", "Then", "Then", "And last" })[n]
		table.insert(lines, string.format("[TAPE] %s... the %s light. Door %s.", ordinal, CLOSET_NAMES[idx], ({ "I", "II", "III", "IV" })[idx]))
	end
	table.insert(lines, "[TAPE] ...and don't open them if you hear breathing. ...click.")
	task.spawn(function()
		for _, line in lines do
			local audience = nearPlayers(pos, 60)
			Net.fireList(audience, "Caption", { text = line, duration = 4.2, speaker = "tape" })
			Registry.AudioService:PlayAtFor(audience, "Whisper", pos, { volume = 0.5 })
			task.wait(4.5)
		end
		ctx.tapePlaying = false
	end)
	Registry.ObjectiveService:SetSubProgress("DOORS", "Open the closets in the order from the tape")
end

local function onRecorder(player: Player, target: Instance): boolean
	if not ctx or not ctx.recorder or not target:IsDescendantOf(ctx.recorder) then
		return false
	end
	if not isChosen("DOORS") then
		notify(player, "Empty. The tape that belongs here is gone.")
		return false
	end
	if not ctx.tapeInserted then
		if not Registry.InventoryService:Has(player, "TAPE") then
			notify(player, "It needs a cassette.")
			return false
		end
		Registry.InventoryService:Remove(player, "TAPE", 1)
		ctx.tapeInserted = true
		target:SetAttribute("Prompt", "Play tape")
	end
	playTape()
	return true
end

function PuzzleService:OnClosetDoor(player: Player, door: Model): boolean
	if not ctx then
		return false
	end
	if not isChosen("DOORS") then
		Registry.AudioService:PlayAt("DoorLocked", door:GetPivot().Position)
		notify(player, "It won't move.")
		return false
	end
	if ctx.state.locks.DOORS then
		return false
	end
	if not ctx.tapeInserted then
		Registry.AudioService:PlayAt("DoorLocked", door:GetPivot().Position)
		notify(player, "Four doors. Four lights. Something must tell you the order.")
		return false
	end
	local index = door:GetAttribute("Closet")
	local expected = ctx.state.doorOrder[ctx.closetProgress + 1]
	if index == expected then
		ctx.closetProgress += 1
		Registry.DoorService:SetOpen(door, true, { player = player })
		setLamp(index, true)
		if ctx.closetProgress >= 4 then
			Registry.ObjectiveService:SetSubProgress("DOORS", nil)
			Registry.ObjectiveService:ReleaseLock("DOORS")
			solved("DOORS", door:GetPivot().Position)
		end
	else
		-- wrong order: every door slams and the lights die
		Registry.AudioService:PlayAt("KnockDoor", door:GetPivot().Position)
		for i, d in closetDoors() do
			Registry.DoorService:SetOpen(d, false, { slam = true, silent = i ~= index })
			setLamp(i, false)
		end
		ctx.closetProgress = 0
		Registry.HorrorDirector:AddDread(5, "closets")
		notify(player, "Wrong. They all slam shut.")
	end
	return true
end

------------------------------------------------------------------------------------
-- OFFERING
------------------------------------------------------------------------------------

local function onOffering(player: Player, target: Instance): boolean
	if not ctx or not ctx.offering or not target:IsDescendantOf(ctx.offering) then
		return false
	end
	local i = target:GetAttribute("Index")
	local itemId = target:GetAttribute("ItemId")
	if type(i) ~= "number" or not OFFER_ITEMS[i] or itemId ~= OFFER_ITEMS[i] then
		return false
	end
	if not isChosen("OFFERING") then
		notify(player, "The table is bare. Nothing is missing tonight.")
		return false
	end
	if ctx.offered[i] then
		return false
	end
	if not Registry.InventoryService:Has(player, itemId) then
		local names = { MUSIC_BOX = "music box", DOLL = "doll", CANDLE = "candle" }
		notify(player, "An outline of a " .. names[itemId] .. " in the dust.")
		return false
	end
	Registry.InventoryService:Remove(player, itemId, 1)
	ctx.offered[i] = true
	local placed = Registry.InventoryService:SpawnPickup(itemId, CFrame.new(target.Position - Vector3.new(0, 0.7, 0)), { parent = ctx.offering })
	if placed then
		placed:RemoveTag("Pickup")
		local hit = placed:FindFirstChild("Hitbox")
		if hit then
			hit:Destroy()
		end
	end
	Registry.AudioService:PlayAt("Place", target.Position)
	local count = 0
	for _, v in ctx.offered do
		if v then
			count += 1
		end
	end
	Registry.ObjectiveService:SetSubProgress("OFFERING", string.format("Return the three belongings  %d/3", count))
	if count >= 3 then
		Registry.AudioService:PlayAt("MusicBox", target.Position)
		Registry.ObjectiveService:SetSubProgress("OFFERING", nil)
		Registry.ObjectiveService:ReleaseLock("OFFERING")
		solved("OFFERING", target.Position)
	end
	return true
end

------------------------------------------------------------------------------------
-- Secret passage
------------------------------------------------------------------------------------

local function onBoards(player: Player, target: Instance): boolean
	local boards = target:FindFirstAncestorWhichIsA("Model")
	if not boards or not boards:HasTag("BoardedPassage") then
		return false
	end
	if not Registry.InventoryService:Has(player, "CROWBAR") then
		notify(player, "Nailed shut. You'd need something to pry them loose.")
		return false
	end
	Registry.AudioService:PlayAt("BoardsBreak", target:IsA("BasePart") and target.Position or boards:GetPivot().Position)
	for _, p in boards:GetDescendants() do
		if p:IsA("BasePart") then
			if p.Name == "Blocker" then
				p:Destroy()
			else
				p.Anchored = false
				p.CanCollide = true
				p.CollisionGroup = "Ghost"
			end
		end
	end
	boards:RemoveTag("BoardedPassage")
	task.delay(6, function()
		if boards.Parent then
			boards:Destroy()
		end
	end)
	return true
end

function PuzzleService:Clear()
	ctx = nil
end

function PuzzleService:Init()
	local IS = Registry.InteractionService
	IS:Register("FuseBox", onFuseBox)
	IS:Register("Breaker", onBreaker)
	IS:Register("Keypad", onKeypad)
	IS:Register("Override", onOverride)
	IS:Register("SymbolDial", onDial)
	IS:Register("TapeRecorder", onRecorder)
	IS:Register("Offering", onOffering)
	IS:Register("Boards", onBoards)
	Net.on("Puzzle", function(player, kind, payload)
		if not Registry.PlayerService:IsAlive(player) then
			return
		end
		if kind == "keypad" then
			PuzzleService:SubmitCode(player, payload)
		end
	end)
end

return PuzzleService
