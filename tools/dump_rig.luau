--[[ Prints every Observer rig part's CFrame (for previews of the generated meshes).
	lune run tools/dump_rig.luau build/test.rbxlx ]]
local env = require("./lib/env")
local game = env.game
local Shared = game:GetService("ReplicatedStorage"):FindFirstChild("Shared")
local ObserverRig = env.requireModule(Shared.ObserverRig)
local model = ObserverRig.build(nil, { localCopy = true })
for _, p in model:GetChildren() do
	if p:IsA("BasePart") then
		local c = { p.CFrame:GetComponents() }
		local parts = {}
		for _, v in c do
			table.insert(parts, string.format("%.5f", v))
		end
		print(p.Name, table.concat(parts, " "), string.format("%.4f %.4f %.4f", p.Size.X, p.Size.Y, p.Size.Z))
	end
end
