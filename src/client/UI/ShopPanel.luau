--[[
	ShopPanel
	The research supply room: EQUIPMENT (flashlights, batteries, tools) with a
	turning 3D preview and stats, UPGRADES, LOADOUT (which tools go on the belt),
	COSMETICS and CHALLENGES. Everything here is a request: the server checks
	ownership, level and Echoes and answers with a fresh gear snapshot.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = require(ReplicatedStorage.Shared.Net)
local Equipment = require(ReplicatedStorage.Shared.Catalog.Equipment)
local Cosmetics = require(ReplicatedStorage.Shared.Catalog.Cosmetics)
local EquipmentModels = require(ReplicatedStorage.Shared.EquipmentModels)
local Util = require(ReplicatedStorage.Shared.Util.Util)
local State = require(script.Parent.Parent.State)
local Kit = require(script.Parent.Kit)

local ShopPanel = {}

local C = Kit.C

local KIND_ORDER = { FLASHLIGHT = 1, BATTERY = 2, TOOL = 3 }
local RARITY_ORDER = { COMMON = 1, UNCOMMON = 2, RARE = 3, EPIC = 4, LEGENDARY = 5 }

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
-- EQUIPMENT
------------------------------------------------------------------------------------

local selectedId: string? = nil -- kept across re-renders after a purchase

local function equipmentTab(content: Frame, gear: any)
	local list = Kit.frame({ Size = UDim2.new(0.62, -12, 1, 0), BackgroundTransparency = 1, Parent = content })
	local detail = Kit.frame({ Size = UDim2.new(0.38, 0, 1, 0), Position = UDim2.fromScale(0.62, 0), BackgroundColor3 = C.PanelLight, BackgroundTransparency = 0.25, Parent = content })
	Kit.corner(detail, 4)
	Kit.padding(detail, 16)
	local scroll = Kit.scroll(list)
	Kit.new("UIGridLayout", { CellSize = UDim2.fromOffset(196, 176), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder, Parent = scroll })

	local current = Equipment.get(gear.flashlight or "FL_STARTER")
	local currentBattery = Equipment.get(gear.battery or "BAT_STANDARD")
	local selectedCard: Frame? = nil

	local function showDetail(entry: any)
		detail:ClearAllChildren()
		Kit.padding(detail, 16)
		local item = Equipment.get(entry.id)
		if not item then
			return
		end
		selectedId = entry.id
		local view = Kit.frame({ Size = UDim2.new(1, 0, 0, 230), BackgroundTransparency = 1, Parent = detail })
		preview(view, item.id, {}, true)
		local info = Kit.frame({ Size = UDim2.new(1, 0, 1, -290), Position = UDim2.fromOffset(0, 240), BackgroundTransparency = 1, Parent = detail })
		Kit.list(info, 4)
		Kit.text({ Text = item.rarity .. "  ·  " .. (Equipment.KindNames[item.kind] or item.kind), Size = UDim2.new(1, 0, 0, 16), FontFace = Kit.F.Mono, TextSize = 13, TextColor3 = rarityColor(item.rarity), LayoutOrder = 1, Parent = info })
		Kit.text({ Text = item.name, Size = UDim2.new(1, 0, 0, 28), FontFace = Kit.F.Heading, TextSize = 22, LayoutOrder = 2, Parent = info })
		Kit.text({ Text = item.description or "", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, FontFace = Kit.F.Light, TextSize = 15, TextColor3 = C.TextDim, LayoutOrder = 3, Parent = info })
		Kit.frame({ Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = C.Line, LayoutOrder = 4, Parent = info })
		if item.kind == "FLASHLIGHT" then
			statLine(info, "RANGE", item.range, current and current.range, 5)
			statLine(info, "BEAM WIDTH", item.angle, current and current.angle, 6)
			statLine(info, "OUTPUT", item.power, current and current.power, 7, true, "%.2f")
			statLine(info, "BATTERY USE", math.floor(item.drain * 100 + 0.5), current and math.floor(current.drain * 100 + 0.5), 8, false)
			if item.steady then
				Kit.text({ Text = "Never stutters on a weak battery.", Size = UDim2.new(1, 0, 0, 20), FontFace = Kit.F.Light, TextSize = 14, TextColor3 = C.Accent, LayoutOrder = 9, Parent = info })
			end
		elseif item.kind == "BATTERY" then
			statLine(info, "CAPACITY", item.capacity, currentBattery and currentBattery.capacity, 5, true, "%d%%")
		else
			if item.charges then
				statLine(info, "USES PER NIGHT", item.charges, nil, 5)
			end
			if item.charge then
				statLine(info, "SECONDS OF USE", item.charge, nil, 6)
			end
			if item.cooldown then
				statLine(info, "RECHARGE (s)", item.cooldown, nil, 7)
			end
		end
		-- the action
		local label, action, style = nil, nil, "ghost"
		if entry.owned then
			if entry.equipped then
				label = if item.kind == "TOOL" then "ON YOUR BELT" else "EQUIPPED"
			elseif item.kind == "TOOL" then
				label = "ADD IN LOADOUT"
			else
				label, action = "EQUIP", "equip"
			end
		elseif entry.locked then
			label = "REACH LEVEL " .. tostring(entry.level)
		elseif entry.price then
			local affordable = (gear.echoes or 0) >= entry.price
			label = if affordable then ("BUY  ·  " .. Util.formatNumber(entry.price)) else ("NEED " .. Util.formatNumber(entry.price) .. " ECHOES")
			action = if affordable then "buy" else nil
			style = if affordable then "primary" else "ghost"
		end
		if label then
			local b = Kit.button({ Text = label, Size = UDim2.new(1, 0, 0, 44), Position = UDim2.new(0, 0, 1, -44), TextSize = 15, Style = style, Parent = detail }, function()
				if action then
					Net.event("Gear"):FireServer(action, item.id)
				end
			end)
			b.Active = action ~= nil
			if not action then
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
	local firstEntry = nil
	for i, entry in entries do
		local item = Equipment.get(entry.id)
		if item then
			if not firstEntry or entry.id == selectedId then
				firstEntry = entry
			end
			local card = Kit.new("TextButton", { Text = "", AutoButtonColor = false, BackgroundColor3 = C.PanelLight, BackgroundTransparency = 0.2, LayoutOrder = i, Selectable = true, Parent = scroll })
			Kit.corner(card, 4)
			local stroke = Kit.stroke(card, rarityColor(item.rarity), 1, if entry.owned then 0.35 else 0.75)
			preview(card, item.id, { Size = UDim2.new(1, -16, 0, 96), Position = UDim2.fromOffset(8, 8), BackgroundTransparency = 0.5 }, false)
			Kit.frame({ Size = UDim2.new(1, -16, 0, 2), Position = UDim2.fromOffset(8, 104), BackgroundColor3 = rarityColor(item.rarity), BackgroundTransparency = 0.2, Parent = card })
			Kit.text({ Text = item.name, Size = UDim2.new(1, -16, 0, 20), Position = UDim2.fromOffset(8, 110), FontFace = Kit.F.Heading, TextSize = 14, TextTruncate = Enum.TextTruncate.AtEnd, Parent = card })
			local status = if entry.equipped then "EQUIPPED" elseif entry.owned then "OWNED" elseif entry.locked then ("LEVEL " .. tostring(entry.level)) elseif entry.price then (Util.formatNumber(entry.price) .. " E") else ""
			Kit.text({ Text = status, Size = UDim2.new(1, -16, 0, 16), Position = UDim2.fromOffset(8, 132), FontFace = Kit.F.Mono, TextSize = 12, TextColor3 = if entry.equipped then C.Accent elseif entry.locked then C.Muted else C.TextDim, Parent = card })
			Kit.text({ Text = item.rarity, Size = UDim2.new(1, -16, 0, 14), Position = UDim2.fromOffset(8, 152), FontFace = Kit.F.Light, TextSize = 11, TextColor3 = rarityColor(item.rarity), Parent = card })
			if entry.locked then
				Kit.text({ Text = "LOCKED", Size = UDim2.fromOffset(70, 18), Position = UDim2.new(1, -78, 0, 12), TextXAlignment = Enum.TextXAlignment.Right, FontFace = Kit.F.Mono, TextSize = 12, TextColor3 = C.Muted, Parent = card })
			end
			local function hover(on: boolean)
				if card == selectedCard then
					return
				end
				Kit.tween(card, 0.12, { BackgroundTransparency = if on then 0.05 else 0.2 })
				Kit.tween(stroke, 0.12, { Transparency = if on then 0.1 else (if entry.owned then 0.35 else 0.75) })
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
	if firstEntry then
		showDetail(firstEntry)
	end
end

------------------------------------------------------------------------------------
-- UPGRADES
------------------------------------------------------------------------------------

local function upgradesTab(content: Frame, gear: any)
	local scroll = Kit.scroll(content)
	Kit.list(scroll, 10)
	for i, entry in gear.upgrades or {} do
		local def = Equipment.UpgradesById[entry.id]
		if def then
			local row = Kit.frame({ Size = UDim2.new(1, -12, 0, 92), BackgroundColor3 = C.PanelLight, BackgroundTransparency = 0.25, LayoutOrder = i, Parent = scroll })
			Kit.corner(row, 4)
			Kit.padding(row, 14)
			Kit.text({ Text = def.name, Size = UDim2.new(0.6, 0, 0, 24), FontFace = Kit.F.Heading, TextSize = 19, Parent = row })
			Kit.text({ Text = def.description .. "   " .. def.per .. " per level", Size = UDim2.new(0.6, 0, 0, 36), Position = UDim2.fromOffset(0, 28), TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, FontFace = Kit.F.Light, TextSize = 14, TextColor3 = C.TextDim, Parent = row })
			-- level pips
			local pips = Kit.frame({ Size = UDim2.fromOffset(200, 12), Position = UDim2.new(0.6, 12, 0, 6), BackgroundTransparency = 1, Parent = row })
			Kit.list(pips, 6, true)
			for l = 1, entry.max do
				local pip = Kit.frame({ Size = UDim2.fromOffset(30, 10), BackgroundColor3 = if l <= entry.level then C.Accent else C.Line, LayoutOrder = l, Parent = pips })
				Kit.corner(pip, 2)
			end
			Kit.text({ Text = string.format("LEVEL %d / %d", entry.level, entry.max), Size = UDim2.fromOffset(200, 18), Position = UDim2.new(0.6, 12, 0, 24), FontFace = Kit.F.Mono, TextSize = 13, TextColor3 = C.TextDim, Parent = row })
			local label, action, style = "MAXED", false, "ghost"
			if entry.level < entry.max then
				if entry.locked then
					label = "REACH LEVEL " .. tostring(entry.needLevel)
				elseif (gear.echoes or 0) >= (entry.price or math.huge) then
					label, action, style = "UPGRADE  ·  " .. Util.formatNumber(entry.price), true, "primary"
				else
					label = "NEED " .. Util.formatNumber(entry.price or 0) .. " ECHOES"
				end
			end
			local b = Kit.button({ Text = label, Size = UDim2.fromOffset(230, 40), Position = UDim2.new(1, -230, 0.5, -20), TextSize = 14, Style = style, Parent = row }, function()
				if action then
					Net.event("Gear"):FireServer("upgrade", entry.id)
				end
			end)
			b.Active = action
			if not action then
				b.TextColor3 = C.Muted
			end
		end
	end
end

------------------------------------------------------------------------------------
-- LOADOUT
------------------------------------------------------------------------------------

local function loadoutTab(content: Frame, gear: any)
	local slots = gear.slots or Equipment.BaseLoadoutSlots
	local chosen = table.clone(gear.loadout or {})
	Kit.text({ Text = string.format("TOOL BELT  ·  %d SLOTS", slots), Size = UDim2.new(1, 0, 0, 24), FontFace = Kit.F.Heading, TextSize = 18, Parent = content })
	Kit.text({ Text = "Your flashlight and battery are always with you. Choose which tools ride on your belt tonight. Select a tool in a round with 5-9, V cycles, T uses.", Size = UDim2.new(1, 0, 0, 38), Position = UDim2.fromOffset(0, 26), TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, FontFace = Kit.F.Light, TextSize = 14, TextColor3 = C.TextDim, Parent = content })
	local belt = Kit.frame({ Size = UDim2.new(1, 0, 0, 150), Position = UDim2.fromOffset(0, 72), BackgroundTransparency = 1, Parent = content })
	Kit.list(belt, 12, true)
	local pool = Kit.frame({ Size = UDim2.new(1, 0, 1, -300), Position = UDim2.fromOffset(0, 240), BackgroundTransparency = 1, Parent = content })
	local dirty = Kit.text({ Text = "", Size = UDim2.new(0.6, 0, 0, 20), Position = UDim2.new(0, 0, 1, -44), FontFace = Kit.F.Light, TextSize = 14, TextColor3 = C.Accent, Parent = content })

	local renderAll
	local function save()
		Net.event("Gear"):FireServer("loadout", chosen)
		dirty.Text = "Saved."
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
					dirty.Text = "Unsaved changes."
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
						dirty.Text = "Your belt is full. Click a slot to free it."
						return
					end
					dirty.Text = "Unsaved changes."
					renderAll()
				end)
				Kit.frame({ Size = UDim2.new(0, 3, 1, -16), Position = UDim2.fromOffset(8, 8), BackgroundColor3 = rarityColor(item.rarity), Parent = b })
				Kit.text({ Text = item.name, Size = UDim2.new(1, -30, 0, 20), Position = UDim2.fromOffset(20, 10), FontFace = Kit.F.Heading, TextSize = 14, Parent = b })
				Kit.text({ Text = if onBelt then "ON BELT  ·  click to remove" else "click to carry", Size = UDim2.new(1, -30, 0, 16), Position = UDim2.fromOffset(20, 34), FontFace = Kit.F.Mono, TextSize = 11, TextColor3 = if onBelt then C.Accent else C.Muted, Parent = b })
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
	Kit.button({ Text = "SAVE LOADOUT", Size = UDim2.fromOffset(220, 42), Position = UDim2.new(0.6, 0, 1, -48), TextSize = 15, Style = "primary", Parent = content }, save)
end

------------------------------------------------------------------------------------
-- COSMETICS
------------------------------------------------------------------------------------

local function cosmeticsTab(content: Frame, tabs: any)
	local area = Kit.frame({ Size = UDim2.new(1, 0, 1, -48), Position = UDim2.fromOffset(0, 48), BackgroundTransparency = 1, Parent = content })
	local category = "FLASHLIGHT"
	local function render()
		area:ClearAllChildren()
		local ok, data = pcall(function()
			return Net.func("GetShop"):InvokeServer()
		end)
		if not ok or type(data) ~= "table" then
			Kit.text({ Text = "The shop is unavailable right now.", Size = UDim2.new(1, 0, 0, 30), TextColor3 = C.TextDim, Parent = area })
			return
		end
		local scroll = Kit.scroll(area)
		Kit.new("UIGridLayout", { CellSize = UDim2.fromOffset(250, 128), CellPadding = UDim2.fromOffset(12, 12), SortOrder = Enum.SortOrder.LayoutOrder, Parent = scroll })
		for i, item in data.items do
			if item.category == category then
				local def = Cosmetics.get(item.id)
				local card = Kit.frame({ BackgroundColor3 = C.PanelLight, BackgroundTransparency = 0.2, LayoutOrder = i, Parent = scroll })
				Kit.corner(card, 4)
				Kit.padding(card, 12)
				Kit.stroke(card, if item.equipped then C.Accent else C.Line, 1, if item.equipped then 0.2 else 0.6)
				if def and def.glyph and def.glyph ~= "" then
					Kit.text({ Text = def.glyph, Size = UDim2.fromOffset(24, 24), Position = UDim2.new(1, -24, 0, -2), TextXAlignment = Enum.TextXAlignment.Center, FontFace = Kit.F.Heading, TextSize = 20, Parent = card })
				elseif def and (def.light or def.accent or def.color) then
					local sw = Kit.frame({ Size = UDim2.fromOffset(18, 18), Position = UDim2.new(1, -18, 0, 0), BackgroundColor3 = def.light or def.accent or def.color, Parent = card })
					Kit.corner(sw, 9)
				end
				Kit.text({ Text = item.name, Size = UDim2.new(1, -26, 0, 22), FontFace = Kit.F.Heading, TextSize = 17, Parent = card })
				local info = if item.owned then (if item.equipped then "EQUIPPED" else "OWNED") elseif item.price then (Util.formatNumber(item.price) .. " ECHOES") elseif item.lock then item.lock else ""
				Kit.text({ Text = info, Size = UDim2.new(1, 0, 0, 16), Position = UDim2.fromOffset(0, 26), FontFace = Kit.F.Mono, TextSize = 13, TextColor3 = if item.equipped then C.Accent else C.TextDim, Parent = card })
				local label, action = nil, nil
				if item.category == "EMOTE" then
					label = if item.owned then "OWNED" else (if item.price then "BUY" else nil)
					action = if not item.owned and item.price then "buy" else nil
				elseif item.equipped then
					label = "EQUIPPED"
				elseif item.owned then
					label, action = "EQUIP", "equip"
				elseif item.price then
					label, action = "BUY", "buy"
				elseif item.lock == "PASS" and item.pass then
					label, action = "GET PASS", "pass"
				end
				if label then
					local b = Kit.button({ Text = label, Size = UDim2.new(1, 0, 0, 36), Position = UDim2.new(0, 0, 1, -36), TextSize = 14, Style = if action == "buy" or action == "pass" then "primary" else "ghost", Parent = card }, function()
						if action == "pass" then
							Net.event("Shop"):FireServer("pass", item.pass)
						elseif action then
							Net.event("Shop"):FireServer(action, item.id)
							task.delay(0.5, render)
						end
					end)
					b.Active = action ~= nil
				end
			end
		end
	end
	local select = tabs(content, { "FLASHLIGHT", "BEAM", "GLOVES", "BADGE", "TRAIL", "EMOTE", "TITLE", "UI" }, function(name)
		category = name
		render()
	end)
	select("FLASHLIGHT")
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
	Builds the panel into `body`. ctx.tabs / ctx.backButton are the menu helpers.
	`start` picks the opening tab.
]]
function ShopPanel.build(body: Frame, ctx: any, start: string?)
	local content = Kit.frame({ Size = UDim2.new(1, 0, 1, -110), Position = UDim2.fromOffset(0, 50), BackgroundTransparency = 1, Parent = body })
	local balance = Kit.text({ Text = "", Size = UDim2.new(0.4, 0, 0, 24), Position = UDim2.new(0, 0, 1, -38), FontFace = Kit.F.Mono, TextSize = 16, Parent = body })
	local note = Kit.text({ Text = "Earned by playing. Nothing here can be bought with Robux.", Size = UDim2.new(0.5, 0, 0, 24), Position = UDim2.new(0.22, 0, 1, -38), FontFace = Kit.F.Light, TextSize = 14, TextColor3 = C.Muted, Parent = body })
	local tab = start or "EQUIPMENT"
	local function render()
		if not content.Parent then
			return
		end
		content:ClearAllChildren()
		local gear = if tab == "COSMETICS" or tab == "CHALLENGES" then State.gear else fetchGear()
		local profile = State.profile
		local echoes = (gear and gear.echoes) or (profile and profile.echoes) or 0
		balance.Text = "ECHOES  " .. Util.formatNumber(echoes)
		note.Text = if tab == "COSMETICS" then "Cosmetic only. Nothing here helps you survive." else "Earned by playing. Nothing here can be bought with Robux."
		if tab == "COSMETICS" then
			cosmeticsTab(content, ctx.tabs)
			return
		elseif tab == "CHALLENGES" then
			challengesTab(content)
			return
		end
		if type(gear) ~= "table" then
			Kit.text({ Text = "The supply room is unavailable right now.", Size = UDim2.new(1, 0, 0, 30), TextColor3 = C.TextDim, Parent = content })
			return
		end
		if tab == "EQUIPMENT" then
			equipmentTab(content, gear)
		elseif tab == "UPGRADES" then
			upgradesTab(content, gear)
		elseif tab == "LOADOUT" then
			loadoutTab(content, gear)
		end
	end
	local select = ctx.tabs(body, { "EQUIPMENT", "UPGRADES", "LOADOUT", "COSMETICS", "CHALLENGES" }, function(name)
		tab = name
		render()
	end)
	-- the server answers every purchase with a fresh snapshot
	local conns = {}
	table.insert(conns, State.GearChanged:Connect(function()
		if tab ~= "COSMETICS" and tab ~= "CHALLENGES" then
			task.defer(render)
		end
	end))
	table.insert(conns, State.ChallengesChanged:Connect(function()
		if tab == "CHALLENGES" then
			task.defer(render)
		end
	end))
	body.Destroying:Connect(function()
		for _, c in conns do
			c:Disconnect()
		end
	end)
	select(tab)
	ctx.backButton(body)
end

return ShopPanel
