--[[
	ShopPanel
	The research supply room: EQUIPMENT (flashlights, batteries, tools) with a
	turning 3D preview and stats, UPGRADES, LOADOUT (which tools go on the belt),
	COSMETICS and CHALLENGES. Everything here is a request: the server checks
	ownership, level and Echoes and answers every request (Net "ShopResult")
	with a fresh snapshot behind it.

	How it behaves
	  * every item reads at a glance: EQUIPPED, OWNED, LOCKED (level / how to
	    earn it), a price you can pay, or a price you can't
	  * select an item to see what it is and does before buying it
	  * buying asks once (CONFIRM, with what is left after), then the button
	    waits for the server's answer: a second click can't send a second
	    request, and no answer within a few seconds says so instead of hanging
	  * the answer shows in the status line: what you bought, or why not
	  * mouse, keyboard, gamepad (every card and button is selectable) and touch
	Echoes are earned by playing. Equipment can never be bought with Robux;
	the premium store is a separate panel (PremiumPanel).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")

local Net = require(ReplicatedStorage.Shared.Net)
local Equipment = require(ReplicatedStorage.Shared.Catalog.Equipment)
local Cosmetics = require(ReplicatedStorage.Shared.Catalog.Cosmetics)
local Achievements = require(ReplicatedStorage.Shared.Catalog.Achievements)
local EquipmentModels = require(ReplicatedStorage.Shared.EquipmentModels)
local Util = require(ReplicatedStorage.Shared.Util.Util)
local State = require(script.Parent.Parent.State)
local Kit = require(script.Parent.Kit)

local ShopPanel = {}

local C = Kit.C

local KIND_ORDER = { FLASHLIGHT = 1, BATTERY = 2, TOOL = 3 }
local RARITY_ORDER = { COMMON = 1, UNCOMMON = 2, RARE = 3, EPIC = 4, LEGENDARY = 5 }
-- how long a request may wait for the server's answer
local ANSWER_TIMEOUT = 6

local function fetchGear()
	local ok, data = pcall(function()
		return Net.func("GetGear"):InvokeServer()
	end)
	if ok and type(data) == "table" then
		State.gear = data
		return data
	end
	return State.gear
end

local function rarityColor(rarity: string?): Color3
	return Equipment.RarityColors[rarity or "COMMON"] or C.TextDim
end

------------------------------------------------------------------------------------
-- Item state: one vocabulary for every card and detail pane
------------------------------------------------------------------------------------

-- EQUIPPED | OWNED | LOCKED | AFFORD | POOR | NONE
function ShopPanel.stateOf(entry: any, balance: number): string
	if entry.equipped then
		return "EQUIPPED"
	elseif entry.owned then
		return "OWNED"
	elseif entry.locked or (entry.lock ~= nil and not entry.price) then
		return "LOCKED"
	elseif entry.price then
		return if balance >= entry.price then "AFFORD" else "POOR"
	end
	return "NONE"
end

local STATE_COLOR = {
	EQUIPPED = C.Accent,
	OWNED = C.Good,
	LOCKED = C.Muted,
	AFFORD = C.Text,
	POOR = C.Warning,
	NONE = C.Muted,
}

local function chipText(state: string, entry: any): string
	if state == "EQUIPPED" then
		return "EQUIPPED"
	elseif state == "OWNED" then
		return "OWNED"
	elseif state == "LOCKED" then
		if entry.level and entry.locked then
			return "LEVEL " .. tostring(entry.level)
		end
		return tostring(entry.lock or "LOCKED")
	elseif state == "AFFORD" or state == "POOR" then
		return "◈ " .. Util.formatNumber(entry.price)
	end
	return ""
end

-- A small status chip (rounded, outlined in the state's colour).
local function chip(parent: Instance, text: string, color: Color3, props: { [string]: any }?)
	local f: Frame = Kit.frame({ Size = UDim2.fromOffset(0, 20), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = C.Black, BackgroundTransparency = 0.35, Parent = parent })
	if props then
		for k, v in props do
			(f :: any)[k] = v
		end
	end
	Kit.corner(f, 3)
	Kit.stroke(f, color, 1, 0.35)
	Kit.padding(f, 0, 8)
	Kit.text({ Text = text, Size = UDim2.fromOffset(0, 20), AutomaticSize = Enum.AutomaticSize.X, FontFace = Kit.F.Mono, TextSize = 12, TextColor3 = color, TextWrapped = false, Parent = f })
	return f
end

-- One line of a stat comparison: value and the difference to what you carry now.
local function statLine(parent: Instance, label: string, value: number, current: number?, order: number, higherIsBetter: boolean?, fmt: string?)
	local row = Kit.frame({ Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1, LayoutOrder = order, Parent = parent })
	Kit.text({ Text = label, Size = UDim2.fromScale(0.5, 1), FontFace = Kit.F.Light, TextSize = 14, TextColor3 = C.TextDim, Parent = row })
	local text = string.format(fmt or "%g", value)
	local color = C.Text
	if current and math.abs(current - value) > 1e-3 then
		local better = if higherIsBetter == false then value < current else value > current
		local diff = value - current
		text ..= string.format("  (%s%s)", if diff > 0 then "+" else "", string.format(fmt or "%g", diff))
		color = if better then C.Accent else C.Muted
	end
	Kit.text({ Text = text, Size = UDim2.fromScale(0.5, 1), Position = UDim2.fromScale(0.5, 0), TextXAlignment = Enum.TextXAlignment.Right, FontFace = Kit.F.Mono, TextSize = 14, TextColor3 = color, Parent = row })
end

-- A ViewportFrame showing a turning model of `id`.
local function preview(parent: Instance, id: string, props: { [string]: any }, spin: boolean?)
	local viewport = Kit.new("ViewportFrame", {
		BackgroundColor3 = C.Black,
		BackgroundTransparency = 0.2,
		Size = UDim2.fromScale(1, 1),
		Parent = parent,
	})
	for k, v in props do
		viewport[k] = v
	end
	Kit.corner(viewport, 4)
	local model = EquipmentModels.preview(id, viewport)
	if model and spin and model.PrimaryPart then
		local base = model:GetPivot()
		local angle = 0
		local conn
		conn = RunService.RenderStepped:Connect(function(dt)
			if not viewport.Parent then
				conn:Disconnect()
				return
			end
			angle += dt * 0.6
			model:PivotTo(base * CFrame.Angles(0, angle, 0))
		end)
	end
	return viewport
end

------------------------------------------------------------------------------------
-- Requests: confirm once, then wait for the server's answer
------------------------------------------------------------------------------------

type Ctx = {
	body: Frame,
	status: TextLabel,
	balance: () -> number,
	isOpen: () -> boolean,
	render: () -> (),
	openPremium: (() -> ())?,
}

local waiting: { [string]: { button: TextButton?, text: string, expires: number } } = {}

local function setStatus(ctx: Ctx, text: string, color: Color3?)
	ctx.status.Text = text
	ctx.status.TextColor3 = color or C.TextDim
	ctx.status.TextTransparency = 1
	Kit.tween(ctx.status, 0.25, { TextTransparency = 0 })
end

local function keyOf(action: string, id: string?): string
	return action .. ":" .. (id or "")
end

-- Sends one request; the button (if any) waits for the answer.
local function request(ctx: Ctx, remote: string, action: string, id: string?, payload: any, button: TextButton?)
	local key = keyOf(action, id)
	if waiting[key] then
		return -- already waiting for this one
	end
	waiting[key] = { button = button, text = if button then button.Text else "", expires = os.clock() + ANSWER_TIMEOUT }
	if button then
		button.Text = "…"
		button.Active = false
		button.AutoButtonColor = false
	end
	Net.event(remote):FireServer(action, payload)
	task.delay(ANSWER_TIMEOUT, function()
		local w = waiting[key]
		if w and os.clock() >= w.expires then
			waiting[key] = nil
			if w.button and w.button.Parent then
				w.button.Text = w.text
				w.button.Active = true
			end
			if ctx.isOpen() then
				setStatus(ctx, "No answer from the supply room. Nothing was spent; try again.", C.Warning)
			end
		end
	end)
end

-- The server answered (Net ShopResult).
local function resolve(ctx: Ctx, result: any)
	local key = keyOf(result.action or "", result.id)
	local w = waiting[key]
	waiting[key] = nil
	if w and w.button and w.button.Parent and not result.ok then
		w.button.Text = w.text
		w.button.Active = true
	end
	if not ctx.isOpen() then
		return
	end
	if result.ok then
		local item = Equipment.get(result.id or "") or Cosmetics.get(result.id or "")
		local upgrade = Equipment.UpgradesById[result.id or ""]
		local name = (item and item.name) or (upgrade and upgrade.name) or ""
		local text = if result.action == "buy" then "Purchased: " .. name .. "." elseif result.action == "upgrade" then "Upgraded: " .. name .. "." elseif result.action == "equip" then "Equipped: " .. name .. "." elseif result.action == "loadout" then "Loadout saved." else "Done."
		setStatus(ctx, text, C.Good)
	else
		setStatus(ctx, tostring(result.reason or "That didn't work."), C.Warning)
	end
end

-- A modal question over the panel: what it costs and what is left after.
local function confirm(ctx: Ctx, title: string, price: number, detail: string?, onYes: () -> ())
	local overlay = Kit.new("TextButton", { Text = "", AutoButtonColor = false, Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.Black, BackgroundTransparency = 0.25, ZIndex = 40, Selectable = false, Parent = ctx.body })
	local box = Kit.frame({ Size = UDim2.fromOffset(520, 230), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), BackgroundColor3 = C.Panel, ZIndex = 41, Parent = overlay })
	Kit.corner(box, 6)
	Kit.stroke(box, C.Line, 1, 0.1)
	local scale = Kit.new("UIScale", { Scale = 0.94, Parent = box })
	Kit.tween(scale, 0.18, { Scale = 1 })
	Kit.text({ Text = "CONFIRM PURCHASE", Size = UDim2.new(1, -48, 0, 18), Position = UDim2.fromOffset(24, 20), FontFace = Kit.F.Mono, TextSize = 13, TextColor3 = C.Muted, ZIndex = 42, Parent = box })
	Kit.text({ Text = title, Size = UDim2.new(1, -48, 0, 30), Position = UDim2.fromOffset(24, 40), FontFace = Kit.F.Heading, TextSize = 24, ZIndex = 42, Parent = box })
	local left = ctx.balance() - price
	Kit.text({
		Text = string.format("◈ %s Echoes   ·   %s left after%s", Util.formatNumber(price), Util.formatNumber(math.max(0, left)), if detail then "\n" .. detail else ""),
		Size = UDim2.new(1, -48, 0, 44),
		Position = UDim2.fromOffset(24, 78),
		FontFace = Kit.F.Light,
		TextSize = 16,
		TextColor3 = C.TextDim,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 42,
		Parent = box,
	})
	local function close()
		overlay:Destroy()
	end
	local yes = Kit.button({ Text = "CONFIRM", Size = UDim2.fromOffset(220, 46), Position = UDim2.new(0, 24, 1, -70), Style = "primary", ZIndex = 42, Parent = box }, function()
		close()
		onYes()
	end)
	Kit.button({ Text = "CANCEL", Size = UDim2.fromOffset(220, 46), Position = UDim2.new(1, -244, 1, -70), ZIndex = 42, Parent = box }, function()
		Kit.sound("UIBack")
		close()
	end)
	overlay.Activated:Connect(close)
	if State.inputType == "Gamepad" then
		GuiService.SelectedObject = yes
	end
	return overlay
end

-- The shared card behaviour: hover / selection feedback and a slight lift.
local function cardFeedback(card: GuiButton, stroke: UIStroke, rest: number, isSelected: () -> boolean)
	local scale = Kit.new("UIScale", { Parent = card })
	local function hover(on: boolean)
		if isSelected() then
			return
		end
		Kit.tween(card, 0.12, { BackgroundTransparency = if on then 0.05 else 0.2 })
		Kit.tween(stroke, 0.12, { Transparency = if on then 0.1 else rest })
		Kit.tween(scale, 0.12, { Scale = if on then 1.02 else 1 })
	end
	card.MouseEnter:Connect(function()
		Kit.sound("UIHover")
		hover(true)
	end)
	card.MouseLeave:Connect(function()
		hover(false)
	end)
	card.SelectionGained:Connect(function()
		hover(true)
	end)
	card.SelectionLost:Connect(function()
		hover(false)
	end)
end

------------------------------------------------------------------------------------
-- EQUIPMENT
------------------------------------------------------------------------------------

local selectedId: string? = nil -- kept across re-renders after a purchase

local function equipmentTab(ctx: Ctx, content: Frame, gear: any)
	local list = Kit.frame({ Size = UDim2.new(0.62, -12, 1, 0), BackgroundTransparency = 1, Parent = content })
	local detail = Kit.frame({ Size = UDim2.new(0.38, 0, 1, 0), Position = UDim2.fromScale(0.62, 0), BackgroundColor3 = C.PanelLight, BackgroundTransparency = 0.25, Parent = content })
	Kit.corner(detail, 4)
	local scroll = Kit.scroll(list)
	Kit.padding(scroll, 4)
	Kit.new("UIGridLayout", { CellSize = UDim2.fromOffset(196, 182), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = scroll })

	local current = Equipment.get(gear.flashlight or "FL_STARTER")
	local currentBattery = Equipment.get(gear.battery or "BAT_STANDARD")
	local balance = gear.echoes or 0
	local selectedCard: GuiButton? = nil

	local function showDetail(entry: any)
		detail:ClearAllChildren()
		Kit.padding(detail, 16)
		local item = Equipment.get(entry.id)
		if not item then
			return
		end
		selectedId = entry.id
		local state = ShopPanel.stateOf(entry, balance)
		local view = Kit.frame({ Size = UDim2.new(1, 0, 0, 220), BackgroundTransparency = 1, Parent = detail })
		preview(view, item.id, {}, true)
		local info = Kit.frame({ Size = UDim2.new(1, 0, 1, -290), Position = UDim2.fromOffset(0, 230), BackgroundTransparency = 1, Parent = detail })
		Kit.list(info, 4)
		Kit.text({ Text = item.rarity .. "  ·  " .. (Equipment.KindNames[item.kind] or item.kind), Size = UDim2.new(1, 0, 0, 16), FontFace = Kit.F.Mono, TextSize = 13, TextColor3 = rarityColor(item.rarity), LayoutOrder = 1, Parent = info })
		Kit.text({ Text = item.name, Size = UDim2.new(1, 0, 0, 28), FontFace = Kit.F.Heading, TextSize = 22, LayoutOrder = 2, Parent = info })
		local chipRow = Kit.frame({ Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1, LayoutOrder = 3, Parent = info })
		chip(chipRow, chipText(state, entry), STATE_COLOR[state])
		local text = item.description or ""
		if item.beam and item.beam.feel then
			text ..= "\n" .. item.beam.feel
		end
		Kit.text({ Text = text, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, FontFace = Kit.F.Light, TextSize = 15, TextColor3 = C.TextDim, LayoutOrder = 4, Parent = info })
		Kit.frame({ Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = C.Line, LayoutOrder = 5, Parent = info })
		if item.kind == "FLASHLIGHT" then
			statLine(info, "RANGE", item.range, current and current.range, 6)
			statLine(info, "BEAM WIDTH", item.angle, current and current.angle, 7)
			statLine(info, "OUTPUT", item.power, current and current.power, 8, true, "%.2f")
			statLine(info, "BATTERY USE", math.floor(item.drain * 100 + 0.5), current and math.floor(current.drain * 100 + 0.5), 9, false)
			if item.steady then
				Kit.text({ Text = "Never stutters on a weak battery.", Size = UDim2.new(1, 0, 0, 20), FontFace = Kit.F.Light, TextSize = 14, TextColor3 = C.Accent, LayoutOrder = 10, Parent = info })
			end
		elseif item.kind == "BATTERY" then
			statLine(info, "CAPACITY", item.capacity, currentBattery and currentBattery.capacity, 6, true, "%d%%")
		else
			if item.charges then
				statLine(info, "USES PER NIGHT", item.charges, nil, 6)
			end
			if item.charge then
				statLine(info, "SECONDS OF USE", item.charge, nil, 7)
			end
			if item.cooldown then
				statLine(info, "RECHARGE (s)", item.cooldown, nil, 8)
			end
		end
		-- the action
		local label, onClick, style = nil, nil, "ghost"
		if state == "EQUIPPED" then
			label = if item.kind == "TOOL" then "ON YOUR BELT" else "EQUIPPED"
		elseif state == "OWNED" then
			if item.kind == "TOOL" then
				label = "ADD IT IN LOADOUT"
			else
				label, style = "EQUIP", "primary"
				onClick = function(b)
					request(ctx, "Gear", "equip", item.id, item.id, b)
				end
			end
		elseif state == "LOCKED" then
			label = "REACH LEVEL " .. tostring(entry.level)
		elseif state == "AFFORD" then
			label, style = "BUY  ·  ◈ " .. Util.formatNumber(entry.price), "primary"
			onClick = function(b)
				confirm(ctx, item.name, entry.price, if item.kind ~= "TOOL" then "It is equipped straight away." else "It goes on your belt if there is room.", function()
					request(ctx, "Gear", "buy", item.id, item.id, b)
				end)
			end
		elseif state == "POOR" then
			label = string.format("NEED ◈ %s MORE", Util.formatNumber(entry.price - balance))
		end
		if label then
			local b: TextButton
			b = Kit.button({ Text = label, Size = UDim2.new(1, 0, 0, 44), Position = UDim2.new(0, 0, 1, -44), TextSize = 15, Style = style, Parent = detail }, function()
				if onClick then
					onClick(b)
				end
			end)
			b.Active = onClick ~= nil
			if not onClick then
				b.TextColor3 = C.Muted
			end
		end
	end

	local entries = table.clone(gear.items or {})
	table.sort(entries, function(a, b)
		local ia, ib = Equipment.get(a.id), Equipment.get(b.id)
		if not ia or not ib then
			return a.id < b.id
		end
		if ia.kind ~= ib.kind then
			return KIND_ORDER[ia.kind] < KIND_ORDER[ib.kind]
		end
		if ia.rarity ~= ib.rarity then
			return RARITY_ORDER[ia.rarity] < RARITY_ORDER[ib.rarity]
		end
		return (ia.price or 0) < (ib.price or 0)
	end)
	local firstEntry, firstCard = nil, nil
	for i, entry in entries do
		local item = Equipment.get(entry.id)
		if item then
			local state = ShopPanel.stateOf(entry, balance)
			local card = Kit.new("TextButton", { Text = "", AutoButtonColor = false, BackgroundColor3 = C.PanelLight, BackgroundTransparency = 0.2, LayoutOrder = i, Selectable = true, Parent = scroll })
			Kit.corner(card, 4)
			local rest = if entry.owned then 0.35 else 0.75
			local stroke = Kit.stroke(card, if state == "EQUIPPED" then C.Accent else rarityColor(item.rarity), 1, rest)
			preview(card, item.id, { Size = UDim2.new(1, -16, 0, 96), Position = UDim2.fromOffset(8, 8), BackgroundTransparency = 0.5 }, false)
			Kit.frame({ Size = UDim2.new(1, -16, 0, 2), Position = UDim2.fromOffset(8, 104), BackgroundColor3 = rarityColor(item.rarity), BackgroundTransparency = 0.2, Parent = card })
			Kit.text({ Text = item.name, Size = UDim2.new(1, -16, 0, 20), Position = UDim2.fromOffset(8, 110), FontFace = Kit.F.Heading, TextSize = 14, TextTruncate = Enum.TextTruncate.AtEnd, Parent = card })
			Kit.text({ Text = item.rarity, Size = UDim2.new(1, -16, 0, 14), Position = UDim2.fromOffset(8, 131), FontFace = Kit.F.Light, TextSize = 11, TextColor3 = rarityColor(item.rarity), Parent = card })
			chip(card, chipText(state, entry), STATE_COLOR[state], { Position = UDim2.fromOffset(8, 152) })
			if state == "LOCKED" then
				-- locked pieces read as locked: dimmed, with what unlocks them
				card.BackgroundTransparency = 0.45
			end
			if entry.id == selectedId or not firstEntry then
				firstEntry, firstCard = entry, card
			end
			cardFeedback(card, stroke, rest, function()
				return card == selectedCard
			end)
			card.Activated:Connect(function()
				Kit.sound("UIClick")
				if selectedCard and selectedCard.Parent then
					selectedCard.BackgroundColor3 = C.PanelLight
				end
				selectedCard = card
				card.BackgroundColor3 = C.Line
				showDetail(entry)
			end)
		end
	end
	if firstEntry and firstCard then
		selectedCard = firstCard
		firstCard.BackgroundColor3 = C.Line
		showDetail(firstEntry)
		if State.inputType == "Gamepad" then
			GuiService.SelectedObject = firstCard
		end
	end
end

------------------------------------------------------------------------------------
-- UPGRADES
------------------------------------------------------------------------------------

local function upgradesTab(ctx: Ctx, content: Frame, gear: any)
	local scroll = Kit.scroll(content)
	Kit.list(scroll, 10)
	local balance = gear.echoes or 0
	for i, entry in gear.upgrades or {} do
		local def = Equipment.UpgradesById[entry.id]
		if def then
			local row = Kit.frame({ Size = UDim2.new(1, -12, 0, 96), BackgroundColor3 = C.PanelLight, BackgroundTransparency = 0.25, LayoutOrder = i, Parent = scroll })
			Kit.corner(row, 4)
			Kit.padding(row, 14)
			Kit.text({ Text = def.name, Size = UDim2.new(0.6, 0, 0, 24), FontFace = Kit.F.Heading, TextSize = 19, Parent = row })
			Kit.text({ Text = def.description .. "   " .. def.per .. " per level", Size = UDim2.new(0.6, 0, 0, 40), Position = UDim2.fromOffset(0, 28), TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, FontFace = Kit.F.Light, TextSize = 14, TextColor3 = C.TextDim, Parent = row })
			-- level pips
			local pips = Kit.frame({ Size = UDim2.fromOffset(200, 12), Position = UDim2.new(0.6, 12, 0, 6), BackgroundTransparency = 1, Parent = row })
			Kit.list(pips, 6, true)
			for l = 1, entry.max do
				local pip = Kit.frame({ Size = UDim2.fromOffset(30, 10), BackgroundColor3 = if l <= entry.level then C.Accent else C.Line, LayoutOrder = l, Parent = pips })
				Kit.corner(pip, 2)
			end
			Kit.text({ Text = string.format("LEVEL %d / %d", entry.level, entry.max), Size = UDim2.fromOffset(200, 18), Position = UDim2.new(0.6, 12, 0, 24), FontFace = Kit.F.Mono, TextSize = 13, TextColor3 = C.TextDim, Parent = row })
			local label, onClick, style = "MAXED", nil, "ghost"
			if entry.level < entry.max then
				if entry.locked then
					label = "REACH LEVEL " .. tostring(entry.needLevel)
				elseif balance >= (entry.price or math.huge) then
					label, style = "UPGRADE  ·  ◈ " .. Util.formatNumber(entry.price), "primary"
					onClick = function(b)
						confirm(ctx, string.format("%s, level %d", def.name, entry.level + 1), entry.price, def.per, function()
							request(ctx, "Gear", "upgrade", entry.id, entry.id, b)
						end)
					end
				else
					label = string.format("NEED ◈ %s MORE", Util.formatNumber((entry.price or 0) - balance))
				end
			end
			local b: TextButton
			b = Kit.button({ Text = label, Size = UDim2.fromOffset(240, 40), Position = UDim2.new(1, -240, 0.5, -20), TextSize = 14, Style = style, Parent = row }, function()
				if onClick then
					onClick(b)
				end
			end)
			b.Active = onClick ~= nil
			if not onClick then
				b.TextColor3 = C.Muted
			end
		end
	end
end

------------------------------------------------------------------------------------
-- LOADOUT
------------------------------------------------------------------------------------

local function loadoutTab(ctx: Ctx, content: Frame, gear: any)
	local slots = gear.slots or Equipment.BaseLoadoutSlots
	local chosen = table.clone(gear.loadout or {})
	Kit.text({ Text = string.format("TOOL BELT  ·  %d SLOTS", slots), Size = UDim2.new(1, 0, 0, 24), FontFace = Kit.F.Heading, TextSize = 18, Parent = content })
	Kit.text({ Text = "Your flashlight and battery are always with you. Choose which tools ride on your belt tonight. Select a tool in a round with 5-9, V cycles, T uses.", Size = UDim2.new(1, 0, 0, 38), Position = UDim2.fromOffset(0, 26), TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, FontFace = Kit.F.Light, TextSize = 14, TextColor3 = C.TextDim, Parent = content })
	local belt = Kit.frame({ Size = UDim2.new(1, 0, 0, 150), Position = UDim2.fromOffset(0, 72), BackgroundTransparency = 1, Parent = content })
	Kit.list(belt, 12, true)
	local pool = Kit.frame({ Size = UDim2.new(1, 0, 1, -300), Position = UDim2.fromOffset(0, 240), BackgroundTransparency = 1, Parent = content })

	local renderAll
	local saveButton: TextButton
	local function markDirty(text: string?)
		setStatus(ctx, text or "Unsaved changes.", C.Warning)
	end
	local function renderBelt()
		belt:ClearAllChildren()
		Kit.list(belt, 12, true)
		for i = 1, Equipment.MaxLoadoutSlots do
			local id = chosen[i]
			local unlocked = i <= slots
			local slot = Kit.new("TextButton", { Text = "", AutoButtonColor = false, Size = UDim2.fromOffset(150, 150), BackgroundColor3 = C.PanelLight, BackgroundTransparency = if unlocked then 0.2 else 0.7, LayoutOrder = i, Selectable = unlocked, Parent = belt })
			Kit.corner(slot, 4)
			Kit.stroke(slot, if id then C.Accent else C.Line, 1, if id then 0.3 else 0.5)
			Kit.text({ Text = tostring(i + 4), Size = UDim2.fromOffset(20, 16), Position = UDim2.fromOffset(8, 6), FontFace = Kit.F.Mono, TextSize = 12, TextColor3 = C.Muted, Parent = slot })
			if not unlocked then
				Kit.text({ Text = "FIELD VEST\nUPGRADE", Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, FontFace = Kit.F.Mono, TextSize = 12, TextColor3 = C.Muted, Parent = slot })
			elseif id then
				local item = Equipment.get(id)
				preview(slot, id, { Size = UDim2.new(1, -16, 0, 96), Position = UDim2.fromOffset(8, 22), BackgroundTransparency = 0.6 }, false)
				Kit.text({ Text = item and item.name or id, Size = UDim2.new(1, -12, 0, 18), Position = UDim2.new(0, 6, 1, -26), TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.AtEnd, FontFace = Kit.F.Heading, TextSize = 12, Parent = slot })
				slot.Activated:Connect(function()
					Kit.sound("UIBack")
					table.remove(chosen, i)
					markDirty()
					renderAll()
				end)
			else
				Kit.text({ Text = "EMPTY", Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, FontFace = Kit.F.Mono, TextSize = 13, TextColor3 = C.Muted, Parent = slot })
			end
		end
	end
	local function renderPool()
		pool:ClearAllChildren()
		local scroll = Kit.scroll(pool)
		Kit.new("UIGridLayout", { CellSize = UDim2.fromOffset(250, 64), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = scroll })
		local any = false
		for i, entry in gear.items or {} do
			local item = Equipment.get(entry.id)
			if item and item.kind == "TOOL" and entry.owned then
				any = true
				local onBelt = table.find(chosen, item.id) ~= nil
				local b = Kit.button({ Text = "", Size = UDim2.fromOffset(250, 64), LayoutOrder = i, Parent = scroll }, function()
					if onBelt then
						table.remove(chosen, table.find(chosen, item.id) :: number)
					elseif #chosen < slots then
						table.insert(chosen, item.id)
					else
						Kit.sound("UIError")
						markDirty("Your belt is full. Select a slot to free it.")
						return
					end
					markDirty()
					renderAll()
				end)
				Kit.frame({ Size = UDim2.new(0, 3, 1, -16), Position = UDim2.fromOffset(8, 8), BackgroundColor3 = rarityColor(item.rarity), Parent = b })
				Kit.text({ Text = item.name, Size = UDim2.new(1, -30, 0, 20), Position = UDim2.fromOffset(20, 10), FontFace = Kit.F.Heading, TextSize = 14, Parent = b })
				Kit.text({ Text = if onBelt then "ON BELT  ·  select to remove" else "select to carry", Size = UDim2.new(1, -30, 0, 16), Position = UDim2.fromOffset(20, 34), FontFace = Kit.F.Mono, TextSize = 11, TextColor3 = if onBelt then C.Accent else C.Muted, Parent = b })
			end
		end
		if not any then
			Kit.text({ Text = "You do not own any tools yet. Buy them under EQUIPMENT: glow sticks, a radio, a camera...", Size = UDim2.new(1, -12, 0, 40), TextWrapped = true, FontFace = Kit.F.Light, TextSize = 15, TextColor3 = C.TextDim, Parent = scroll })
		end
	end
	renderAll = function()
		renderBelt()
		renderPool()
	end
	renderAll()
	saveButton = Kit.button({ Text = "SAVE LOADOUT", Size = UDim2.fromOffset(220, 42), Position = UDim2.new(0.6, 0, 1, -48), TextSize = 15, Style = "primary", Parent = content }, function()
		request(ctx, "Gear", "loadout", "", chosen, saveButton)
	end)
end

------------------------------------------------------------------------------------
-- COSMETICS
------------------------------------------------------------------------------------

-- How a cosmetic that isn't for sale is earned, in plain words.
local function howToEarn(def: any): string
	if def.level then
		return "Unlocks at level " .. tostring(def.level) .. "."
	elseif def.achievement then
		local a = Achievements.ById and Achievements.ById[def.achievement]
		return if a then "Earned with the achievement " .. a.name .. "." else "Earned with an achievement."
	elseif def.pass then
		return "Part of a supporter pack in the premium store."
	elseif def.premium then
		return "Sold in the premium store."
	end
	return ""
end

local cosmeticCategory = "FLASHLIGHT"

local function cosmeticsTab(ctx: Ctx, content: Frame, tabs: any)
	local area = Kit.frame({ Size = UDim2.new(1, 0, 1, -48), Position = UDim2.fromOffset(0, 48), BackgroundTransparency = 1, Parent = content })
	local function render()
		if not ctx.isOpen() or not area.Parent then
			return
		end
		area:ClearAllChildren()
		local ok, data = pcall(function()
			return Net.func("GetShop"):InvokeServer()
		end)
		if not ok or type(data) ~= "table" then
			Kit.text({ Text = "The wardrobe is unavailable right now. Try again in a moment.", Size = UDim2.new(1, 0, 0, 30), TextColor3 = C.TextDim, Parent = area })
			return
		end
		local balance = data.echoes or 0
		local list = Kit.frame({ Size = UDim2.new(0.66, -12, 1, 0), BackgroundTransparency = 1, Parent = area })
		local detail = Kit.frame({ Size = UDim2.new(0.34, 0, 1, 0), Position = UDim2.fromScale(0.66, 0), BackgroundColor3 = C.PanelLight, BackgroundTransparency = 0.25, Parent = area })
		Kit.corner(detail, 4)
		local scroll = Kit.scroll(list)
		Kit.padding(scroll, 4)
		Kit.new("UIGridLayout", { CellSize = UDim2.fromOffset(250, 104), CellPadding = UDim2.fromOffset(12, 12), SortOrder = Enum.SortOrder.LayoutOrder, Parent = scroll })
		local selected: GuiButton? = nil
		local function showDetail(item: any)
			detail:ClearAllChildren()
			Kit.padding(detail, 18)
			local def = Cosmetics.get(item.id) or {}
			local state = ShopPanel.stateOf(item, balance)
			local swatch = Kit.frame({ Size = UDim2.new(1, 0, 0, 120), BackgroundColor3 = C.Black, BackgroundTransparency = 0.2, Parent = detail })
			Kit.corner(swatch, 4)
			if def.glyph and def.glyph ~= "" then
				Kit.text({ Text = def.glyph, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, FontFace = Kit.F.Title, TextSize = 64, Parent = swatch })
			elseif def.light or def.accent or def.color then
				local glow = Kit.frame({ Size = UDim2.fromOffset(64, 64), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), BackgroundColor3 = def.light or def.accent or def.color, Parent = swatch })
				Kit.corner(glow, 32)
				if def.body then
					local body = Kit.frame({ Size = UDim2.fromOffset(110, 18), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.5, 40), BackgroundColor3 = def.body, Parent = swatch })
					Kit.corner(body, 4)
				end
			else
				Kit.text({ Text = string.upper(item.name), Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, FontFace = Kit.F.Heading, TextSize = 20, TextColor3 = C.TextDim, Parent = swatch })
			end
			local info = Kit.frame({ Size = UDim2.new(1, 0, 1, -190), Position = UDim2.fromOffset(0, 132), BackgroundTransparency = 1, Parent = detail })
			Kit.list(info, 6)
			Kit.text({ Text = Cosmetics.CategoryNames[item.category] or item.category, Size = UDim2.new(1, 0, 0, 16), FontFace = Kit.F.Mono, TextSize = 12, TextColor3 = C.Muted, LayoutOrder = 1, Parent = info })
			Kit.text({ Text = item.name, Size = UDim2.new(1, 0, 0, 26), FontFace = Kit.F.Heading, TextSize = 21, LayoutOrder = 2, Parent = info })
			local chipRow = Kit.frame({ Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1, LayoutOrder = 3, Parent = info })
			chip(chipRow, chipText(state, item), STATE_COLOR[state])
			local about = if item.category == "TRAIL" then "Shown only in the Field Office, never during a night." elseif item.category == "EMOTE" then "Use it from the emote wheel." else "Cosmetic only. It changes nothing about how you play."
			if state == "LOCKED" then
				about = howToEarn(def) .. "\n" .. about
			end
			Kit.text({ Text = about, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, FontFace = Kit.F.Light, TextSize = 14, TextColor3 = C.TextDim, LayoutOrder = 4, Parent = info })
			local label, onClick, style = nil, nil, "ghost"
			if item.category == "EMOTE" then
				if state == "AFFORD" then
					label, style = "BUY  ·  ◈ " .. Util.formatNumber(item.price), "primary"
				elseif state == "OWNED" or state == "EQUIPPED" then
					label = "OWNED"
				end
			elseif state == "EQUIPPED" then
				label = "EQUIPPED"
			elseif state == "OWNED" then
				label, style = "EQUIP", "primary"
				onClick = function(b)
					request(ctx, "Shop", "equip", item.id, item.id, b)
				end
			elseif state == "AFFORD" then
				label, style = "BUY  ·  ◈ " .. Util.formatNumber(item.price), "primary"
			elseif state == "POOR" then
				label = string.format("NEED ◈ %s MORE", Util.formatNumber(item.price - balance))
			elseif item.lock == "PASS" and ctx.openPremium then
				label = "SEE THE PREMIUM STORE"
				onClick = function()
					(ctx.openPremium :: () -> ())()
				end
			end
			if state == "AFFORD" then
				onClick = function(b)
					confirm(ctx, item.name, item.price, nil, function()
						request(ctx, "Shop", "buy", item.id, item.id, b)
					end)
				end
			end
			if label then
				local b: TextButton
				b = Kit.button({ Text = label, Size = UDim2.new(1, 0, 0, 44), Position = UDim2.new(0, 0, 1, -44), TextSize = 15, Style = style, Parent = detail }, function()
					if onClick then
						onClick(b)
					end
				end)
				b.Active = onClick ~= nil
				if not onClick then
					b.TextColor3 = C.Muted
				end
			end
		end
		local first, firstCard = nil, nil
		for i, item in data.items do
			if item.category == cosmeticCategory then
				local def = Cosmetics.get(item.id) or {}
				local state = ShopPanel.stateOf(item, balance)
				local card = Kit.new("TextButton", { Text = "", AutoButtonColor = false, BackgroundColor3 = C.PanelLight, BackgroundTransparency = if state == "LOCKED" then 0.45 else 0.2, LayoutOrder = i, Selectable = true, Parent = scroll })
				Kit.corner(card, 4)
				local rest = if state == "EQUIPPED" then 0.2 else 0.6
				local stroke = Kit.stroke(card, if state == "EQUIPPED" then C.Accent else C.Line, 1, rest)
				if def.glyph and def.glyph ~= "" then
					Kit.text({ Text = def.glyph, Size = UDim2.fromOffset(24, 24), Position = UDim2.new(1, -36, 0, 10), TextXAlignment = Enum.TextXAlignment.Center, FontFace = Kit.F.Heading, TextSize = 20, Parent = card })
				elseif def.light or def.accent or def.color then
					local sw = Kit.frame({ Size = UDim2.fromOffset(18, 18), Position = UDim2.new(1, -30, 0, 12), BackgroundColor3 = def.light or def.accent or def.color, Parent = card })
					Kit.corner(sw, 9)
				end
				Kit.text({ Text = item.name, Size = UDim2.new(1, -52, 0, 22), Position = UDim2.fromOffset(12, 10), FontFace = Kit.F.Heading, TextSize = 16, TextTruncate = Enum.TextTruncate.AtEnd, Parent = card })
				Kit.text({ Text = Cosmetics.CategoryNames[item.category] or "", Size = UDim2.new(1, -24, 0, 14), Position = UDim2.fromOffset(12, 34), FontFace = Kit.F.Light, TextSize = 11, TextColor3 = C.Muted, Parent = card })
				chip(card, chipText(state, item), STATE_COLOR[state], { Position = UDim2.new(0, 12, 1, -32) })
				cardFeedback(card, stroke, rest, function()
					return card == selected
				end)
				card.Activated:Connect(function()
					Kit.sound("UIClick")
					if selected and selected.Parent then
						selected.BackgroundColor3 = C.PanelLight
					end
					selected = card
					card.BackgroundColor3 = C.Line
					showDetail(item)
				end)
				if not first or item.id == selectedId then
					first, firstCard = item, card
				end
			end
		end
		if first and firstCard then
			selected = firstCard
			firstCard.BackgroundColor3 = C.Line
			showDetail(first)
		end
	end
	local select = tabs(content, Cosmetics.Categories, function(name)
		cosmeticCategory = name
		render()
	end)
	select(cosmeticCategory)
	return render
end

------------------------------------------------------------------------------------
-- CHALLENGES
------------------------------------------------------------------------------------

local function challengesTab(content: Frame)
	local snap = State.challenges
	local scroll = Kit.scroll(content)
	Kit.list(scroll, 8)
	if type(snap) ~= "table" then
		Kit.text({ Text = "Challenges load once your record is ready.", Size = UDim2.new(1, 0, 0, 30), TextColor3 = C.TextDim, Parent = scroll })
		return
	end
	local order = 0
	local function heading(text: string, resetsIn: number?)
		order += 1
		local row = Kit.frame({ Size = UDim2.new(1, -12, 0, 36), BackgroundTransparency = 1, LayoutOrder = order, Parent = scroll })
		Kit.text({ Text = text, Size = UDim2.fromScale(0.6, 1), FontFace = Kit.F.Heading, TextSize = 20, Parent = row })
		if resetsIn then
			local h = math.floor(resetsIn / 3600)
			local text2 = if h >= 24 then string.format("NEW IN %dd %dh", h // 24, h % 24) else string.format("NEW IN %dh %02dm", h, math.floor(resetsIn % 3600 / 60))
			Kit.text({ Text = text2, Size = UDim2.fromScale(0.4, 1), Position = UDim2.fromScale(0.6, 0), TextXAlignment = Enum.TextXAlignment.Right, FontFace = Kit.F.Mono, TextSize = 13, TextColor3 = C.Muted, Parent = row })
		end
	end
	local function row(c: any)
		order += 1
		local f = Kit.frame({ Size = UDim2.new(1, -12, 0, 64), BackgroundColor3 = C.PanelLight, BackgroundTransparency = if c.done then 0.45 else 0.2, LayoutOrder = order, Parent = scroll })
		Kit.corner(f, 4)
		Kit.padding(f, 12)
		Kit.text({ Text = (if c.done then "✓  " else "") .. c.text, Size = UDim2.new(0.62, 0, 0, 22), FontFace = Kit.F.Heading, TextSize = 16, TextColor3 = if c.done then C.Accent else C.Text, Parent = f })
		Kit.text({ Text = string.format("+%d ECHOES   +%d XP", c.echoes or 0, c.xp or 0), Size = UDim2.new(0.38, 0, 0, 22), Position = UDim2.fromScale(0.62, 0), TextXAlignment = Enum.TextXAlignment.Right, FontFace = Kit.F.Mono, TextSize = 13, TextColor3 = C.TextDim, Parent = f })
		local bar = Kit.frame({ Size = UDim2.new(0.62, 0, 0, 6), Position = UDim2.new(0, 0, 1, -8), BackgroundColor3 = C.Line, Parent = f })
		Kit.corner(bar, 3)
		local fill = Kit.frame({ Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.Accent, Parent = bar })
		Kit.corner(fill, 3)
		Kit.tween(fill, 0.6, { Size = UDim2.fromScale(math.clamp((c.progress or 0) / math.max(1, c.goal or 1), 0, 1), 1) })
		Kit.text({ Text = string.format("%d / %d", c.progress or 0, c.goal or 1), Size = UDim2.new(0.38, 0, 0, 16), Position = UDim2.new(0.62, 0, 1, -16), TextXAlignment = Enum.TextXAlignment.Right, FontFace = Kit.F.Mono, TextSize = 12, TextColor3 = C.Muted, Parent = f })
	end
	heading("DAILY", snap.dailyResetsIn)
	for _, c in snap.daily or {} do
		row(c)
	end
	heading("WEEKLY", snap.weeklyResetsIn)
	for _, c in snap.weekly or {} do
		row(c)
	end
	order += 1
	Kit.text({ Text = string.format("Daily challenges completed: %d", snap.dailiesDone or 0), Size = UDim2.new(1, -12, 0, 30), FontFace = Kit.F.Light, TextSize = 14, TextColor3 = C.Muted, LayoutOrder = order, Parent = scroll })
end

------------------------------------------------------------------------------------

--[[
	Builds the panel into `body`. ctx.tabs / ctx.backButton are the menu helpers;
	ctx.openPremium (optional) opens the premium store. `start` picks the tab.
]]
function ShopPanel.build(body: Frame, menu: any, start: string?)
	local content = Kit.frame({ Size = UDim2.new(1, 0, 1, -116), Position = UDim2.fromOffset(0, 52), BackgroundTransparency = 1, Parent = body })
	-- the wallet: always visible, top right
	local wallet = Kit.frame({ Size = UDim2.fromOffset(0, 34), AutomaticSize = Enum.AutomaticSize.X, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 2), BackgroundColor3 = C.Black, BackgroundTransparency = 0.3, Parent = body })
	Kit.corner(wallet, 4)
	Kit.stroke(wallet, C.Line, 1, 0.3)
	Kit.padding(wallet, 0, 14)
	local walletLabel = Kit.text({ Text = "", Size = UDim2.fromOffset(0, 34), AutomaticSize = Enum.AutomaticSize.X, FontFace = Kit.F.Mono, TextSize = 15, TextWrapped = false, Parent = wallet })
	-- footer: the answer to the last request, and what this tab is
	local status = Kit.text({ Text = "", Size = UDim2.new(0.5, 0, 0, 24), Position = UDim2.new(0, 0, 1, -36), FontFace = Kit.F.Body, TextSize = 15, TextColor3 = C.TextDim, Parent = body })
	local note = Kit.text({ Text = "", Size = UDim2.new(0.34, 0, 0, 24), Position = UDim2.new(0.5, -170, 1, -36), TextXAlignment = Enum.TextXAlignment.Right, FontFace = Kit.F.Light, TextSize = 13, TextColor3 = C.Muted, Parent = body })
	local tab = start or "EQUIPMENT"
	local closed = false
	local balance = 0
	local cosmeticsRender: (() -> ())? = nil
	local ctx: Ctx
	local function isOpen(): boolean
		return not closed and content.Parent ~= nil
	end
	local function setWallet(echoes: number, level: number?)
		balance = echoes
		walletLabel.Text = string.format("◈ %s ECHOES%s", Util.formatNumber(echoes), if level then "   ·   LEVEL " .. tostring(level) else "")
	end
	local function render()
		if not isOpen() then
			return
		end
		content:ClearAllChildren()
		cosmeticsRender = nil
		local gear = if tab == "COSMETICS" or tab == "CHALLENGES" then State.gear else fetchGear()
		local profile = State.profile
		setWallet((gear and gear.echoes) or (profile and profile.echoes) or 0, (gear and gear.level) or (profile and profile.level))
		note.Text = if tab == "COSMETICS" then "Cosmetic only. Nothing here helps you survive." else "Earned by playing. Equipment is never sold for Robux."
		if tab == "COSMETICS" then
			cosmeticsRender = cosmeticsTab(ctx, content, menu.tabs)
			return
		elseif tab == "CHALLENGES" then
			challengesTab(content)
			return
		end
		if type(gear) ~= "table" then
			Kit.text({ Text = "The supply room is unavailable right now. Try again in a moment.", Size = UDim2.new(1, 0, 0, 30), TextColor3 = C.TextDim, Parent = content })
			return
		end
		if tab == "EQUIPMENT" then
			equipmentTab(ctx, content, gear)
		elseif tab == "UPGRADES" then
			upgradesTab(ctx, content, gear)
		elseif tab == "LOADOUT" then
			loadoutTab(ctx, content, gear)
		end
	end
	ctx = {
		body = body,
		status = status,
		balance = function()
			return balance
		end,
		isOpen = isOpen,
		render = render,
		openPremium = menu.openPremium,
	}
	local select = menu.tabs(body, { "EQUIPMENT", "UPGRADES", "LOADOUT", "COSMETICS", "CHALLENGES" }, function(name)
		tab = name
		status.Text = ""
		render()
	end)
	local conns = {}
	-- the server answers every request
	table.insert(conns, Net.event("ShopResult").OnClientEvent:Connect(function(result)
		if type(result) ~= "table" or closed then
			return
		end
		-- a panel being torn down must never break the event for the others
		pcall(function()
			resolve(ctx, result)
			if result.ok and isOpen() then
				if tab == "COSMETICS" and cosmeticsRender then
					task.defer(cosmeticsRender)
				elseif tab ~= "CHALLENGES" then
					task.defer(render)
				end
			end
		end)
	end))
	-- a fresh gear snapshot (after a purchase, a level up) updates the wallet
	table.insert(conns, State.GearChanged:Connect(function()
		if isOpen() and State.gear then
			setWallet(State.gear.echoes or balance, State.gear.level)
		end
	end))
	table.insert(conns, State.ProfileChanged:Connect(function(p)
		if isOpen() and type(p) == "table" and tab == "COSMETICS" then
			setWallet(p.echoes or balance, p.level)
		end
	end))
	table.insert(conns, State.ChallengesChanged:Connect(function()
		if tab == "CHALLENGES" then
			task.defer(render)
		end
	end))
	body.Destroying:Connect(function()
		closed = true
		table.clear(waiting)
		for _, c in conns do
			c:Disconnect()
		end
	end)
	select(tab)
	if menu.openPremium then
		Kit.button({ Text = "PREMIUM STORE", Size = UDim2.fromOffset(190, 42), Position = UDim2.new(1, -350, 1, -42), TextSize = 14, Parent = body }, function()
			menu.openPremium()
		end)
	end
	menu.backButton(body)
end

return ShopPanel
