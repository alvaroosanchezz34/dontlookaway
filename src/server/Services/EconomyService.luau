--[[
	EconomyService
	Echoes (soft currency), the cosmetic shop, equipping, emotes and game passes.
	Nothing sold or earned here affects survival: flashlights share identical stats,
	trails only show in the lobby, emotes are purely visual.

	Game passes and premium products are configured in Config/Monetization
	(MonetizationService runs every Robux purchase). An id of 0 means the pass
	or product is not set up yet; its items are hidden from this shop and no
	prompt is shown. There are no randomized purchases.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

local Net = require(ReplicatedStorage.Shared.Net)
local Enums = require(ReplicatedStorage.Shared.Enums)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Cosmetics = require(ReplicatedStorage.Shared.Catalog.Cosmetics)
local Progression = require(ReplicatedStorage.Shared.Progression)
local Monetization = require(ReplicatedStorage.Shared.Config.Monetization)
local Registry = require(script.Parent.Parent.Registry)

local EconomyService = {}

local passOwnership: { [Player]: { [string]: boolean } } = {}
local lastEmote: { [Player]: number } = {}

local function passConfigured(key: string): boolean
	local id = GameConfig.GamePasses[key]
	return type(id) == "number" and id > 0
end

local function premiumConfigured(key: string): boolean
	return Monetization.configured(Monetization.get(key))
end

local function refreshPasses(player: Player)
	local owned = {}
	for key, id in GameConfig.GamePasses do
		if type(id) == "number" and id > 0 then
			local ok, has = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, id)
			end)
			owned[key] = ok and has == true
		end
	end
	passOwnership[player] = owned
	player:SetAttribute("VIP", owned.VIP == true)
end

-- Asks Roblox again which passes this player owns (after a purchase prompt:
-- the prompt's own "purchased" flag is never trusted on its own).
function EconomyService:RefreshPasses(player: Player)
	refreshPasses(player)
	self:ApplyCosmetics(player)
	Registry.ProgressionService:Push(player)
end

function EconomyService:OwnsPass(player: Player, key: string): boolean
	return (passOwnership[player] or {})[key] == true
end

function EconomyService:PassList(player: Player)
	local list = {}
	for key in GameConfig.GamePasses do
		if passConfigured(key) then
			list[key] = (passOwnership[player] or {})[key] == true
		end
	end
	return list
end

function EconomyService:IsOwned(player: Player, id: string): boolean
	local item = Cosmetics.get(id)
	if not item then
		return false
	end
	if item.default then
		return true
	end
	local data = Registry.DataService:Get(player)
	if not data then
		return false
	end
	if data.owned[id] then
		return true
	end
	if item.level and Progression.fromTotal(data.xp) >= item.level then
		return true
	end
	if item.achievement and data.achievements[item.achievement] then
		return true
	end
	if item.pass and (passOwnership[player] or {})[item.pass] then
		return true
	end
	return false
end

function EconomyService:OwnedList(player: Player)
	local list = {}
	for _, item in Cosmetics.List do
		if self:IsOwned(player, item.id) then
			list[item.id] = true
		end
	end
	return list
end

-- Shop catalog with per-player state. Pass items whose pass isn't configured are hidden.
function EconomyService:GetShop(player: Player)
	local data = Registry.DataService:Get(player)
	local items = {}
	for _, item in Cosmetics.List do
		if (not item.pass or passConfigured(item.pass)) and (not item.premium or premiumConfigured(item.premium)) then
			local owned = self:IsOwned(player, item.id)
			local lock = nil
			if not owned then
				if item.level then
					lock = "LEVEL " .. item.level
				elseif item.achievement then
					lock = "ACHIEVEMENT"
				elseif item.pass then
					lock = "PASS"
				elseif item.premium then
					lock = "PASS"
				end
			end
			table.insert(items, {
				id = item.id,
				category = item.category,
				name = item.name,
				price = item.price,
				owned = owned,
				equipped = data and data.equipped[item.category] == item.id,
				lock = lock,
				pass = item.pass,
			})
		end
	end
	return { items = items, echoes = data and data.echoes or 0 }
end

-- Publishes cosmetic choices as attributes so every client can render them.
function EconomyService:ApplyCosmetics(player: Player)
	local data = Registry.DataService:Get(player)
	if not data then
		return
	end
	local fl = Cosmetics.get(data.equipped.FLASHLIGHT)
	local beam = Cosmetics.get(data.equipped.BEAM)
	local trail = Cosmetics.get(data.equipped.TRAIL)
	local ui = Cosmetics.get(data.equipped.UI)
	local title = Cosmetics.get(data.equipped.TITLE)
	local gloves = Cosmetics.get(data.equipped.GLOVES)
	local badge = Cosmetics.get(data.equipped.BADGE)
	player:SetAttribute("GloveColor", gloves and gloves.color or nil)
	player:SetAttribute("Badge", badge and badge.glyph or "")
	player:SetAttribute("FlashlightColor", fl and fl.light or Color3.new(1, 1, 1))
	player:SetAttribute("FlashlightBody", fl and fl.body or Color3.new(0.1, 0.1, 0.1))
	player:SetAttribute("BeamEffect", beam and beam.effect or "clean")
	player:SetAttribute("TrailEffect", trail and trail.effect or "none")
	player:SetAttribute("TrailColor", trail and trail.color or Color3.new(1, 1, 1))
	player:SetAttribute("UIAccent", ui and ui.accent or Color3.fromRGB(232, 228, 220))
	player:SetAttribute("Title", title and title.name or "Visitor")
	if player.Character then
		player.Character:SetAttribute("Title", player:GetAttribute("Title"))
		player.Character:SetAttribute("Badge", player:GetAttribute("Badge"))
	end
end

-- Every shop request gets one answer (the client's buttons wait for it).
local function answer(player: Player, action: string, id: string, ok: boolean, reason: string?)
	Net.fire(player, "ShopResult", { action = action, id = id, ok = ok, reason = reason })
	if not ok then
		Registry.AudioService:Play2D({ player }, "UIError")
	end
end

local function onShop(player: Player, action: any, id: any)
	if type(action) ~= "string" or type(id) ~= "string" or #id > 64 then
		return
	end
	if action == "buy" then
		local item = Cosmetics.get(id)
		if not item or not item.price then
			answer(player, action, id, false, "This can't be bought with Echoes.")
			return
		end
		if EconomyService:IsOwned(player, id) then
			answer(player, action, id, false, "You already own this.")
			return
		end
		-- the check and the charge happen together, inside one update: two
		-- requests in a row can never buy twice or spend what is not there
		local result = "missing"
		Registry.DataService:Update(player, function(d)
			if d.owned[id] then
				result = "owned"
			elseif d.echoes < item.price then
				result = "poor"
			else
				d.echoes -= item.price
				d.owned[id] = true
				result = "bought"
			end
		end)
		if result ~= "bought" then
			answer(player, action, id, false, if result == "poor" then "Not enough Echoes." elseif result == "owned" then "You already own this." else "Your record isn't ready yet. Try again in a moment.")
			return
		end
		Registry.AudioService:Play2D({ player }, "UIPurchase")
		Registry.AnalyticsService:Event(player, "CosmeticPurchased", item.price, { id = id })
		answer(player, action, id, true)
	elseif action == "equip" then
		local item = Cosmetics.get(id)
		if not item or item.category == "EMOTE" or not EconomyService:IsOwned(player, id) then
			answer(player, action, id, false, "You don't own this yet.")
			return
		end
		Registry.DataService:Update(player, function(d)
			d.equipped[item.category] = id
		end)
		EconomyService:ApplyCosmetics(player)
		Registry.AudioService:Play2D({ player }, "UIEquip")
		answer(player, action, id, true)
	elseif action == "pass" then
		-- game passes go through the premium store (MonetizationService)
		local monetization = Registry.MonetizationService
		if monetization then
			monetization:Prompt(player, "pass", id)
		end
		return
	else
		return
	end
	Registry.ProgressionService:Push(player)
end

local function onEmote(player: Player, id: any)
	if type(id) ~= "string" then
		return
	end
	local item = Cosmetics.get(id)
	if not item or item.category ~= "EMOTE" or not EconomyService:IsOwned(player, id) then
		return
	end
	local status = Registry.PlayerService:GetStatus(player)
	if status ~= Enums.PlayerStatus.Lobby and status ~= Enums.PlayerStatus.Alive then
		return
	end
	local now = os.clock()
	if lastEmote[player] and now - lastEmote[player] < 2.5 then
		return
	end
	lastEmote[player] = now
	local character = player.Character
	if character then
		character:SetAttribute("Emote", item.emote)
		character:SetAttribute("EmoteAt", workspace:GetServerTimeNow())
	end
end

function EconomyService:Init()
	Net.on("Shop", onShop)
	Net.on("Emote", onEmote)
	Net.handle("GetShop", function(player)
		return EconomyService:GetShop(player)
	end)
end

function EconomyService:Start()
	Registry.DataService.Loaded:Connect(function(player)
		refreshPasses(player)
		EconomyService:ApplyCosmetics(player)
		Registry.ProgressionService:Push(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		passOwnership[player] = nil
		lastEmote[player] = nil
	end)
end

return EconomyService
