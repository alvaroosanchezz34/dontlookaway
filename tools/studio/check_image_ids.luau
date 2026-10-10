--[[
	Paste into Studio's Command Bar (View -> Command Bar) with the place synced
	by Rojo, press Enter, then copy the line that starts with DLA_FIX.

	Why: Roblox gives two ids for an uploaded picture, a Decal and the Image
	inside it. SurfaceAppearance, MaterialVariant, Decal.Texture and
	ImageLabel need the Image id; a Decal id fails with "Asset type does not
	match requested type". This checks every picture id the game uses and, for
	each Decal id, reads the Image id inside it (InsertService.LoadAsset works
	in Studio on your own assets). It changes nothing in the place.

	Then: python3 tools/apply_image_fix.py "DLA_FIX ..." rewrites the ids.
]]
local RS = game:GetService("ReplicatedStorage")
local MPS = game:GetService("MarketplaceService")
local IS = game:GetService("InsertService")
local AssetIds = require(RS.Shared.Config.AssetIds)
local Marketing = RS:FindFirstChild("Marketing")
local MC = Marketing and Marketing:FindFirstChild("MarketingConfig") and require(Marketing.MarketingConfig)

local ids, seen = {}, {}
local function add(id)
	if type(id) == "number" and id > 0 and not seen[id] then
		seen[id] = true
		table.insert(ids, id)
	end
end
for _, e in AssetIds.Materials or {} do
	for _, v in e do add(v) end
end
for _, v in AssetIds.Decals or {} do add(v) end
for _, e in AssetIds.PropMeshes or {} do
	for k, v in e do
		if k ~= "model" and k ~= "mesh" then add(v) end
	end
end
if AssetIds.Observer and type(AssetIds.Observer.skin) == "table" then
	for _, v in AssetIds.Observer.skin do add(v) end
end
if MC then
	for _, v in MC.EyeImages or {} do add(v) end
	add(MC.TitleImage)
end

print(string.format("[DLA] checking %d ids (about 1 s each, wait for the DLA_FIX line)...", #ids))
local fixes, images, decals, failed = {}, 0, 0, 0
for i, id in ids do
	if i % 10 == 0 then
		print(string.format("[DLA] %d / %d", i, #ids))
	end
	local ok, info = pcall(function()
		return MPS:GetProductInfo(id, Enum.InfoType.Asset)
	end)
	local kind = ok and info and info.AssetTypeId
	if kind == 1 then
		images += 1
	elseif kind == 13 then
		decals += 1
		local okLoad, model = pcall(function()
			return IS:LoadAsset(id)
		end)
		local decal = okLoad and model and model:FindFirstChildWhichIsA("Decal", true)
		local image = decal and tonumber(string.match(decal.Texture, "(%d+)%D*$"))
		if model and okLoad then model:Destroy() end
		if image then
			table.insert(fixes, string.format("%d:%d", id, image))
		else
			failed += 1
			warn("[DLA] decal " .. id .. ": could not read its image")
		end
	else
		failed += 1
		warn(string.format("[DLA] %d: %s", id, if ok then "asset type " .. tostring(kind) else tostring(info)))
	end
end
print(string.format("[DLA] %d ids: %d images ok, %d decals to fix, %d problems", #ids, images, decals, failed))
print("DLA_FIX " .. table.concat(fixes, ","))
