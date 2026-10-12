--[[
	Monetization
	The premium store's catalogue: what can be bought with Robux, and the ids
	that connect it to Roblox. Nothing in here helps anyone survive: every
	item is cosmetic (the look of your light, a title, a badge, emotes) or a
	thank-you. Equipment, Echoes and upgrades are never sold for Robux.
	No random rewards: every product says exactly what it gives.

	THE IDS ARE NOT SET. Each `id = 0` is waiting for the real id from the
	Creator Dashboard (docs/TIENDA_PREMIUM.md explains every step). While an
	id is 0 the item shows "PENDING SETUP" in the store and no purchase can
	be started: nothing is ever simulated.

	Prices are not here on purpose: Roblox owns the price. The store reads it
	from MarketplaceService:GetProductInfo, so what the player sees is what
	the prompt will charge.

	GamePasses: bought once, owned forever (UserOwnsGamePassAsync).
	  grants  cosmetic ids (Catalog/Cosmetics, `pass = key`)
	Products (Developer Products): every purchase goes through ProcessReceipt.
	  grants  cosmetic ids given on purchase
	  once    true: buying is refused once every grant is owned (no buying the
	          same skin twice)
	  repeatable  true: can be bought again (a thank-you); `grants` are then
	          given the first time only
]]

local Monetization = {}

Monetization.GamePasses = {
	{
		key = "VIP",
		id = 0,
		name = "Patron",
		description = "The Patron title, the Silver Lantern flashlight, the Void lobby trail and the Frost interface.",
		grants = { "TI_VIP", "FL_SILVER", "TR_VOID", "UI_FROST" },
	},
	{
		key = "FlashlightCollection",
		id = 0,
		name = "Flashlight Collection",
		description = "Two flashlight finishes: Noir and Faded Rose. Same light as every other.",
		grants = { "FL_NOIR", "FL_ROSE" },
	},
	{
		key = "EmotePack",
		id = 0,
		name = "Quiet Gestures",
		description = "Two emotes: Hush and Bow.",
		grants = { "EM_HUSH", "EM_BOW" },
	},
}

Monetization.Products = {
	{
		key = "SKIN_CANDLE",
		id = 0,
		name = "Candlelight Finish",
		description = "A flashlight finish with a warm, low amber tint. Cosmetic only.",
		grants = { "FL_CANDLE" },
		once = true,
	},
	{
		key = "SKIN_ASHEN",
		id = 0,
		name = "Ashen Finish",
		description = "A flashlight finish in burnt grey with a cold white tint. Cosmetic only.",
		grants = { "FL_ASHEN" },
		once = true,
	},
	{
		key = "SUPPORT",
		id = 0,
		name = "Leave a Light On",
		description = "A thank-you to the people who make the game. The first one adds the Supporter title and badge.",
		grants = { "TI_SUPPORTER", "BD_SUPPORTER" },
		repeatable = true,
	},
}

Monetization.ByKey = {}
for _, p in Monetization.GamePasses do
	p.kind = "pass"
	Monetization.ByKey[p.key] = p
end
for _, p in Monetization.Products do
	p.kind = "product"
	Monetization.ByKey[p.key] = p
end

function Monetization.get(key: string)
	return Monetization.ByKey[key]
end

function Monetization.configured(entry: any): boolean
	return entry ~= nil and type(entry.id) == "number" and entry.id > 0
end

-- The product with this Roblox id (ProcessReceipt), if it is configured.
function Monetization.productById(id: number)
	for _, p in Monetization.Products do
		if Monetization.configured(p) and p.id == id then
			return p
		end
	end
	return nil
end

return Monetization
