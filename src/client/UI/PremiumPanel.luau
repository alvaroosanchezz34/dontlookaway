--[[
	PremiumPanel
	The premium store: what can be bought with Robux (Config/Monetization),
	kept apart from the supply room in look and in words. Prices are always
	in Robux (R$), read from Roblox by the server; the Echoes symbol never
	appears here.

	  * every card says what it gives, exactly (no random rewards)
	  * PENDING SETUP: the id is not set in the Creator Dashboard yet; nothing
	    can be bought and nothing is simulated
	  * OWNED: game passes and finishes you already have
	  * BUY asks the server, which checks and opens Roblox's own purchase
	    prompt; the card then waits for the server's answer (granted,
	    cancelled, or why not). The client never decides that it bought.
	Cosmetic only: equipment, Echoes and upgrades are never sold for Robux.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")

local Net = require(ReplicatedStorage.Shared.Net)
local State = require(script.Parent.Parent.State)
local Kit = require(script.Parent.Kit)

local PremiumPanel = {}

local C = Kit.C
local GOLD = Kit.Theme.Colors.Premium or Color3.fromRGB(214, 186, 120)
-- a purchase prompt can stay open a long time; after this the card gives up
local WAIT_TIMEOUT = 90

local KIND_LABEL = { pass = "GAME PASS  ·  YOURS FOREVER", product = "ITEM" }

local function priceText(item: any): string
	if not item.configured then
		return "PENDING SETUP"
	elseif item.owned then
		return "OWNED"
	elseif type(item.price) == "number" then
		return "R$ " .. tostring(item.price)
	end
	return "R$ —"
end

function PremiumPanel.build(body: Frame, menu: any)
	local closed = false
	local status = Kit.text({ Text = "", Size = UDim2.new(0.6, 0, 0, 24), Position = UDim2.new(0, 0, 1, -36), FontFace = Kit.F.Body, TextSize = 15, TextColor3 = C.TextDim, Parent = body })
	Kit.text({ Text = "ROBUX  ·  COSMETIC ONLY", Size = UDim2.new(0.5, 0, 0, 20), Position = UDim2.fromOffset(0, 4), FontFace = Kit.F.Mono, TextSize = 13, TextColor3 = GOLD, Parent = body })
	Kit.text({ Text = "Equipment, Echoes and upgrades are never sold for Robux. Everything here only changes how you look.", Size = UDim2.new(1, 0, 0, 22), Position = UDim2.fromOffset(0, 26), FontFace = Kit.F.Light, TextSize = 15, TextColor3 = C.TextDim, Parent = body })
	local content = Kit.frame({ Size = UDim2.new(1, 0, 1, -124), Position = UDim2.fromOffset(0, 62), BackgroundTransparency = 1, Parent = body })
	local waiting: { [string]: TextButton } = {}

	local function setStatus(text: string, color: Color3?)
		status.Text = text
		status.TextColor3 = color or C.TextDim
	end

	local render
	render = function()
		if closed then
			return
		end
		content:ClearAllChildren()
		local ok, data = pcall(function()
			return Net.func("GetPremium"):InvokeServer()
		end)
		if not ok or type(data) ~= "table" then
			Kit.text({ Text = "The store can't be reached right now. Try again in a moment.", Size = UDim2.new(1, 0, 0, 30), TextColor3 = C.TextDim, Parent = content })
			return
		end
		local scroll = Kit.scroll(content)
		Kit.padding(scroll, 4)
		Kit.new("UIGridLayout", { CellSize = UDim2.fromOffset(420, 238), CellPadding = UDim2.fromOffset(14, 14), SortOrder = Enum.SortOrder.LayoutOrder, Parent = scroll })
		local anyPending = false
		local firstButton: TextButton? = nil
		for i, item in data.items or {} do
			if not item.configured then
				anyPending = true
			end
			local card = Kit.frame({ BackgroundColor3 = C.Panel, BackgroundTransparency = 0.05, LayoutOrder = i, Parent = scroll })
			Kit.corner(card, 6)
			Kit.stroke(card, if item.owned then C.Good elseif item.configured then GOLD else C.Line, 1, if item.configured then 0.45 else 0.7)
			Kit.padding(card, 18)
			Kit.text({ Text = if item.repeatable then "THANK-YOU  ·  CAN BE BOUGHT AGAIN" else (KIND_LABEL[item.kind] or "ITEM"), Size = UDim2.new(1, 0, 0, 16), FontFace = Kit.F.Mono, TextSize = 12, TextColor3 = if item.configured then GOLD else C.Muted, Parent = card })
			Kit.text({ Text = item.name or item.key, Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 20), FontFace = Kit.F.Heading, TextSize = 23, Parent = card })
			Kit.text({ Text = item.description or "", Size = UDim2.new(1, 0, 0, 58), Position = UDim2.fromOffset(0, 54), FontFace = Kit.F.Light, TextSize = 14, TextColor3 = C.TextDim, TextYAlignment = Enum.TextYAlignment.Top, Parent = card })
			if item.grants and #item.grants > 0 then
				Kit.text({ Text = "GIVES:  " .. table.concat(item.grants, "  ·  "), Size = UDim2.new(1, 0, 0, 34), Position = UDim2.fromOffset(0, 114), FontFace = Kit.F.Mono, TextSize = 12, TextColor3 = C.Muted, TextYAlignment = Enum.TextYAlignment.Top, Parent = card })
			end
			local price = Kit.text({ Text = priceText(item), Size = UDim2.new(0.45, 0, 0, 44), Position = UDim2.new(0, 0, 1, -44), FontFace = Kit.F.Heading, TextSize = 20, TextColor3 = if item.owned then C.Good elseif item.configured then GOLD else C.Muted, Parent = card })
			price.TextXAlignment = Enum.TextXAlignment.Left
			local canBuy = item.configured and not item.owned and data.canShop
			local label = if not item.configured then "NOT AVAILABLE YET" elseif item.owned then "OWNED" elseif not data.canShop then "OPEN FROM THE MENU" else "BUY"
			local b: TextButton
			b = Kit.button({ Text = label, Size = UDim2.new(0.52, 0, 0, 44), Position = UDim2.new(0.48, 0, 1, -44), TextSize = 15, Style = if canBuy then "primary" else "ghost", Parent = card }, function()
				if not canBuy or waiting[item.key] then
					return
				end
				waiting[item.key] = b
				b.Text = "WAITING FOR ROBLOX…"
				b.Active = false
				setStatus("Complete the purchase in Roblox's window.", C.TextDim)
				Net.event("Premium"):FireServer("prompt", item.key)
				task.delay(WAIT_TIMEOUT, function()
					if waiting[item.key] == b then
						waiting[item.key] = nil
						if b.Parent then
							b.Text = label
							b.Active = true
						end
					end
				end)
			end)
			b.Active = canBuy
			if canBuy then
				b.BackgroundColor3 = GOLD
				firstButton = firstButton or b
			else
				b.TextColor3 = C.Muted
			end
		end
		if anyPending then
			setStatus("Some items are waiting for their Roblox ids (see docs/TIENDA_PREMIUM.md).", C.Muted)
		end
		if State.inputType == "Gamepad" and firstButton then
			GuiService.SelectedObject = firstButton
		end
	end

	local function onResult(result: any)
		local b = waiting[result.key or ""]
		waiting[result.key or ""] = nil
		if result.ok then
			local granted = if type(result.granted) == "table" and #result.granted > 0 then ": " .. table.concat(result.granted, ", ") else ""
			setStatus("Thank you. Added to your wardrobe" .. granted .. ".", C.Good)
			Kit.sound("UIPurchase")
			task.defer(render)
		else
			setStatus(tostring(result.reason or "The purchase didn't go through."), C.Warning)
			if b and b.Parent then
				b.Text = "BUY"
				b.Active = true
			end
		end
	end
	local conn = Net.event("PremiumResult").OnClientEvent:Connect(function(result)
		if closed or type(result) ~= "table" then
			return
		end
		-- a panel being torn down must never break the event for the others
		pcall(onResult, result)
	end)
	body.Destroying:Connect(function()
		closed = true
		conn:Disconnect()
	end)
	render()
	if menu.openShop then
		Kit.button({ Text = "SUPPLY ROOM", Size = UDim2.fromOffset(190, 42), Position = UDim2.new(1, -350, 1, -42), TextSize = 14, Parent = body }, function()
			menu.openShop()
		end)
	end
	menu.backButton(body)
end

return PremiumPanel
