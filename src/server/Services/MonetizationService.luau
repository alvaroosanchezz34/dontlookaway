--[[
	MonetizationService
	Every Robux purchase, in one place (catalogue: Config/Monetization).

	  * Game passes: prompted with PromptGamePassPurchase. When the prompt
	    closes the server asks Roblox again who owns what
	    (UserOwnsGamePassAsync, EconomyService:RefreshPasses): the prompt's
	    own "purchased" flag is never trusted on its own.
	  * Developer Products: prompted with PromptProductPurchase and granted
	    ONLY in ProcessReceipt, which is set here and nowhere else. It is
	    idempotent: each granted PurchaseId is written into the player's
	    record, and a receipt is acknowledged (PurchaseGranted) only after
	    that record has really been saved (DataService:SaveNow). If the save
	    fails the grant is undone in memory and Roblox retries later; a
	    retried receipt that was already granted is acknowledged without
	    granting again.
	  * The client only asks ("prompt <key>"). It never says what it bought.
	  * Unset ids (0): nothing can be prompted; the store shows PENDING SETUP.
	  * Purchases are only started from the menu or the Field Office, never
	    in the middle of a night (no accidental prompts while running).

	Net
	  Premium (client -> server)   "prompt", key
	  GetPremium (function)        the catalogue with this player's state
	  PremiumResult (server -> client) { key, ok, reason, granted }
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

local Net = require(ReplicatedStorage.Shared.Net)
local Monetization = require(ReplicatedStorage.Shared.Config.Monetization)
local Cosmetics = require(ReplicatedStorage.Shared.Catalog.Cosmetics)
local Registry = require(script.Parent.Parent.Registry)

local MonetizationService = {}

-- prices from Roblox, cached: [kind:id] = { price, at }
local priceCache: { [string]: { price: number?, at: number } } = {}
local PRICE_TTL = 600
local lastPrompt: { [Player]: number } = {}
-- the receipts being granted right now ([PurchaseId] = true): two deliveries
-- of the same receipt at once never both grant
local granting: { [string]: boolean } = {}

local function canShop(player: Player): boolean
	local status = Registry.PlayerService:GetStatus(player)
	return status == "MENU" or status == "LOBBY"
end

local function answer(player: Player, key: string, ok: boolean, reason: string?, granted: { string }?)
	Net.fire(player, "PremiumResult", { key = key, ok = ok, reason = reason, granted = granted })
end

-- Does this player already have everything this entry gives?
function MonetizationService:Owns(player: Player, entry: any): boolean
	if entry.kind == "pass" then
		return Registry.EconomyService:OwnsPass(player, entry.key)
	end
	if entry.repeatable then
		return false
	end
	local data = Registry.DataService:Get(player)
	if not data then
		return false
	end
	for _, id in entry.grants or {} do
		if not data.owned[id] then
			return false
		end
	end
	return true
end

local function price(entry: any): number?
	if not Monetization.configured(entry) then
		return nil
	end
	local key = entry.kind .. ":" .. tostring(entry.id)
	local cached = priceCache[key]
	if cached and os.clock() - cached.at < PRICE_TTL then
		return cached.price
	end
	local ok, info = pcall(function()
		return MarketplaceService:GetProductInfo(entry.id, if entry.kind == "pass" then Enum.InfoType.GamePass else Enum.InfoType.Product)
	end)
	local value = if ok and type(info) == "table" and type(info.PriceInRobux) == "number" then info.PriceInRobux else nil
	priceCache[key] = { price = value, at = os.clock() }
	return value
end

-- The catalogue for one player: configured or not, owned, the real price.
function MonetizationService:GetCatalog(player: Player)
	local list = {}
	local function add(entry: any)
		local names = {}
		for _, id in entry.grants or {} do
			local item = Cosmetics.get(id)
			table.insert(names, if item then item.name else id)
		end
		local configured = Monetization.configured(entry)
		table.insert(list, {
			key = entry.key,
			kind = entry.kind,
			name = entry.name,
			description = entry.description,
			grants = names,
			configured = configured,
			owned = configured and self:Owns(player, entry),
			repeatable = entry.repeatable == true,
			price = if configured then price(entry) else nil,
		})
	end
	for _, p in Monetization.GamePasses do
		add(p)
	end
	for _, p in Monetization.Products do
		add(p)
	end
	return { items = list, canShop = canShop(player) }
end

-- The one way a purchase starts: validated here, prompted by Roblox.
function MonetizationService:Prompt(player: Player, kind: string?, key: any)
	if type(key) ~= "string" then
		return
	end
	local entry = Monetization.get(key)
	if not entry or (kind and kind ~= entry.kind) then
		answer(player, tostring(key), false, "That isn't in the store.")
		return
	end
	if not Monetization.configured(entry) then
		answer(player, key, false, "This item isn't set up yet.")
		return
	end
	if not canShop(player) then
		answer(player, key, false, "The store opens from the menu or the Field Office.")
		return
	end
	if self:Owns(player, entry) then
		answer(player, key, false, "You already own this.")
		return
	end
	if entry.kind == "product" and not Registry.DataService:IsPersistent(player) then
		-- nothing could be saved: never take Robux for it
		answer(player, key, false, "Your record can't be saved right now, so the store is closed. Try again later.")
		return
	end
	local now = os.clock()
	if lastPrompt[player] and now - lastPrompt[player] < 1.5 then
		return
	end
	lastPrompt[player] = now
	local ok, err = pcall(function()
		if entry.kind == "pass" then
			MarketplaceService:PromptGamePassPurchase(player, entry.id)
		else
			MarketplaceService:PromptProductPurchase(player, entry.id)
		end
	end)
	if not ok then
		warn("[MonetizationService] prompt failed:", err)
		answer(player, key, false, "Roblox couldn't open the purchase. Try again.")
	end
end

--[[
	What a product gives, applied to a profile. Returns an undo (used when the
	save fails) and the names granted.
]]
local function grant(data: any, entry: any): (() -> (), { string })
	local added = {}
	local names = {}
	local firstSupport = entry.repeatable and (data.supporter or 0) == 0
	if not entry.repeatable or firstSupport then
		for _, id in entry.grants or {} do
			if Cosmetics.get(id) and not data.owned[id] then
				data.owned[id] = true
				table.insert(added, id)
				table.insert(names, Cosmetics.get(id).name)
			end
		end
	end
	if entry.repeatable then
		data.supporter = (data.supporter or 0) + 1
	end
	return function()
		for _, id in added do
			data.owned[id] = nil
		end
		if entry.repeatable then
			data.supporter = math.max(0, (data.supporter or 1) - 1)
		end
	end, names
end

--[[
	The receipt handler (MarketplaceService.ProcessReceipt). Exposed for the
	tests. Returns an Enum.ProductPurchaseDecision.
]]
function MonetizationService.ProcessReceipt(info: any): any
	local NotYet = Enum.ProductPurchaseDecision.NotProcessedYet
	if type(info) ~= "table" or type(info.PurchaseId) ~= "string" then
		return NotYet
	end
	local player = Players:GetPlayerByUserId(info.PlayerId)
	if not player then
		-- they left: Roblox delivers it again next time they join
		return NotYet
	end
	local entry = Monetization.productById(info.ProductId)
	if not entry then
		warn(string.format("[MonetizationService] receipt for unknown product %s (not in Config/Monetization)", tostring(info.ProductId)))
		return NotYet
	end
	local data = Registry.DataService:WaitFor(player, 15)
	if not data or not Registry.DataService:IsPersistent(player) then
		return NotYet
	end
	local purchaseId = info.PurchaseId
	if data.purchases[purchaseId] then
		-- already granted and saved: only the acknowledgement was lost
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	if granting[purchaseId] then
		return NotYet
	end
	granting[purchaseId] = true
	local undo, names = nil, {}
	Registry.DataService:Update(player, function(d)
		undo, names = grant(d, entry)
		d.purchases[purchaseId] = os.time()
	end)
	local saved = undo ~= nil and Registry.DataService:SaveNow(player)
	if not saved then
		-- never acknowledge what isn't saved: take it back, Roblox retries
		Registry.DataService:Update(player, function(d)
			if undo then
				undo()
			end
			d.purchases[purchaseId] = nil
		end)
		granting[purchaseId] = nil
		warn("[MonetizationService] receipt " .. purchaseId .. " not saved; Roblox will retry it")
		return NotYet
	end
	granting[purchaseId] = nil
	Registry.EconomyService:ApplyCosmetics(player)
	Registry.ProgressionService:Push(player)
	answer(player, entry.key, true, nil, names)
	if Registry.AnalyticsService then
		Registry.AnalyticsService:Event(player, "PremiumPurchase", 1, { key = entry.key })
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function MonetizationService:Init()
	Net.on("Premium", function(player, action, key)
		if action == "prompt" then
			MonetizationService:Prompt(player, nil, key)
		end
	end)
	Net.handle("GetPremium", function(player)
		return MonetizationService:GetCatalog(player)
	end)
end

function MonetizationService:Start()
	-- the only ProcessReceipt in the game (a second assignment would replace it)
	MarketplaceService.ProcessReceipt = MonetizationService.ProcessReceipt
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		-- ask Roblox, don't trust the flag
		Registry.EconomyService:RefreshPasses(player)
		for _, p in Monetization.GamePasses do
			if p.id == passId and p.id > 0 then
				local owns = Registry.EconomyService:OwnsPass(player, p.key)
				local names = {}
				for _, id in p.grants do
					local item = Cosmetics.get(id)
					table.insert(names, if item then item.name else id)
				end
				answer(player, p.key, owns, if owns then nil elseif purchased then "Roblox hasn't confirmed it yet. It will appear shortly." else "Purchase cancelled.", if owns then names else nil)
			end
		end
	end)
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, purchased)
		-- the grant comes from ProcessReceipt; this only closes the waiting state
		if purchased then
			return
		end
		local player = Players:GetPlayerByUserId(userId)
		local entry = Monetization.productById(productId)
		if player and entry then
			answer(player, entry.key, false, "Purchase cancelled.")
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastPrompt[player] = nil
	end)
end

return MonetizationService
