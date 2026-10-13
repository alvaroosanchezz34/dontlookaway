--[[
	Inserts the Creator Store candidates of docs/CREATOR_STORE_AUDIT.md so you
	can look at them and listen to them. Paste it in View -> Command Bar.

	USE AN EMPTY PLACE (File -> New), never the game's place.

	  * Models go to Workspace.StoreCandidates, side by side, each with a label.
	    EVERY script inside them is deleted before anything can run (they
	    only run on Play; this runs in edit mode). The output lists what was
	    removed: anything there is a reason to read the audit report.
	  * Sounds go to Workspace.StoreCandidates.Sounds, one per candidate.
	    Select one and press "Preview" in Properties (or set Playing = true
	    from the Command Bar) to hear it.

	When you have chosen, save a model with right-click -> Save to File... and
	run tools/audit_asset.luau on it before it goes anywhere near the game.
]]

local InsertService = game:GetService("InsertService")

local MODELS = {
	{ id = 10840642581, name = "House Props Pack - Duvall Drive (@Roblox)" },
	{ id = 10847897579, name = "House Furniture Pack - Duvall Drive (@Roblox)" },
	{ id = 10904527778, name = "Old CRT TV Mesh PBR" },
	{ id = 4750431468, name = "Hospital bed" },
}

local SOUNDS = {
	{ id = 619993906, name = "Buzzing Fluorescent Light" },
	{ id = 9112775175, name = "Eerie Ambience 1 (SFX)" },
	{ id = 9039981149, name = "Horror (APM)" },
	{ id = 1847064374, name = "Scary Atmosphere (APM)" },
	{ id = 9119630175, name = "Steel Door 4 (SFX)" },
	{ id = 9114145200, name = "Door Long Squeaks 18 (SFX)" },
	{ id = 9116554136, name = "Metal Creak Twisting Apart 5 (SFX)" },
	{ id = 9114247505, name = "Electricity Static 22 (SFX)" },
	{ id = 9119588836, name = "Static Rough 3 (SFX)" },
	{ id = 9120099286, name = "Toggle Switch Metal Industrial 76 (SFX)" },
	{ id = 9112839293, name = "Oil Refinery Ambience 2 (SFX)" },
}

local old = workspace:FindFirstChild("StoreCandidates")
if old then
	old:Destroy()
end
local root = Instance.new("Folder")
root.Name = "StoreCandidates"
root.Parent = workspace

local function label(model: Model, text: string)
	local ok, cf, size = pcall(function()
		return model:GetBoundingBox()
	end)
	if not ok then
		return
	end
	local anchor = Instance.new("Part")
	anchor.Name = "Label"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.CFrame = CFrame.new(cf.Position + Vector3.new(0, size.Y / 2 + 3, 0))
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(360, 40)
	gui.AlwaysOnTop = true
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 0.3
	t.BackgroundColor3 = Color3.new(0, 0, 0)
	t.TextColor3 = Color3.new(1, 1, 1)
	t.TextScaled = true
	t.Text = text
	t.Parent = gui
	gui.Parent = anchor
	anchor.Parent = model
end

local x = 0
for _, entry in MODELS do
	local ok, asset = pcall(function()
		return InsertService:LoadAsset(entry.id)
	end)
	if not ok then
		warn(string.format("[Store] %d %s: could not insert (%s)", entry.id, entry.name, tostring(asset)))
		continue
	end
	-- no script ever gets the chance to run
	local removed = {}
	for _, d in asset:GetDescendants() do
		if d:IsA("LuaSourceContainer") then
			table.insert(removed, d:GetFullName())
		end
	end
	for _, d in asset:GetDescendants() do
		if d:IsA("LuaSourceContainer") then
			d:Destroy()
		end
	end
	local holder = Instance.new("Model")
	holder.Name = string.format("%d %s", entry.id, entry.name)
	for _, child in asset:GetChildren() do
		child.Parent = holder
	end
	asset:Destroy()
	holder.Parent = root
	local okBox, cf, size = pcall(function()
		return holder:GetBoundingBox()
	end)
	if okBox then
		holder:PivotTo(holder:GetPivot() * CFrame.new(x - cf.Position.X + size.X / 2, -(cf.Position.Y - size.Y / 2), -cf.Position.Z))
		x += size.X + 12
	end
	label(holder, entry.name)
	print(string.format("[Store] %d %s: inserted; %d script(s) removed", entry.id, entry.name, #removed))
	for _, n in removed do
		print("    removed " .. n)
	end
end

local sounds = Instance.new("Folder")
sounds.Name = "Sounds"
sounds.Parent = root
for _, entry in SOUNDS do
	local s = Instance.new("Sound")
	s.Name = string.format("%d %s", entry.id, entry.name)
	s.SoundId = "rbxassetid://" .. entry.id
	s.Volume = 0.8
	s.Parent = sounds
end
print(string.format("[Store] %d sounds in Workspace.StoreCandidates.Sounds: select one, Properties -> Preview", #SOUNDS))
