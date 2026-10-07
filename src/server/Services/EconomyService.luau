--[[
	EconomyService
	Echoes (soft currency), the cosmetic shop, equipping, emotes and game passes.
	Nothing sold or earned here affects survival: flashlights share identical stats,
	trails only show in the lobby, emotes are purely visual.

	Game passes are configured in GameConfig.GamePasses. An id of 0 means the pass
	is not set up yet; its items are hidden from the shop and no prompt is shown.
	There are no randomized purchases.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

local Net = require(ReplicatedStorage.Shared.Net)
local Enums = require(ReplicatedStorage.Shared.Enums)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Cosmetics = require(ReplicatedStorage.Shared.Catalog.Cosmetics)
local Progression = require(ReplicatedStorage.Shared.Progression)
local Registry = require(script.Parent.Parent.Registry)

local EconomyService = {}

local passOwnership: { [Player]: { [string]: boolean } } = {}
local lastEmote: { [Player]: number } = {}

local function passConfigured(key: string): boolean
	local id = GameConfig.GamePasses[key]
	return type(id) == "number" and id > 0
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
		if not item.pass or passConfigured(item.pass) then
			local owned = self:IsOwned(player, item.id)
			local lock = nil
			if not owned then
				if item.level then
					lock = "LEVEL " .. item.level
				elseif item.achievement then
					lock = "ACHIEVEMENT"
				elseif item.pass then
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

local function onShop(player: Player, action: any, id: any)
	if type(action) ~= "string" or type(id) ~= "string" then
		return
	end
	if action == "buy" then
		local item = Cosmetics.get(id)
		if not item or not item.price or EconomyService:IsOwned(player, id) then
			return
		end
		local data = Registry.DataService:Get(player)
		if not data or data.echoes < item.price then
			Net.fire(player, "Notify", { kind = "info", text = "Not enough Echoes." })
			Registry.AudioService:Play2D({ player }, "UIError")
			return
		end
		Registry.DataService:Update(player, function(d)
			d.echoes -= item.price
			d.owned[id] = true
		end)
		Registry.AudioService:Play2D({ player }, "UIPurchase")
		Registry.AnalyticsService:Event(player, "CosmeticPurchased", item.price, { id = id })
	elseif action == "equip" then
		local item = Cosmetics.get(id)
		if not item or item.category == "EMOTE" or not EconomyService:IsOwned(player, id) then
			return
		end
		Registry.DataService:Update(player, function(d)
			d.equipped[item.category] = id
		end)
		EconomyService:ApplyCosmetics(player)
	elseif action == "pass" then
		local passId = GameConfig.GamePasses[id]
		if type(passId) == "number" and passId > 0 then
			pcall(function()
				MarketplaceService:PromptGamePassPurchase(player, passId)
			end)
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
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, _passId, purchased)
		if purchased then
			refreshPasses(player)
			EconomyService:ApplyCosmetics(player)
			Registry.ProgressionService:Push(player)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		passOwnership[player] = nil
		lastEmote[player] = nil
	end)
end

return EconomyService
