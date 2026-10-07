--[[
	Lobby
	"The Waiting Room": a small, dim room where players gather before a round.
	Built once at server start, far away from the building.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Layout = require(script.Parent.Layout)
local Build = require(script.Parent.Build)
local Props = require(script.Parent.Props)
local SeededRandom = require(ReplicatedStorage.Shared.Util.SeededRandom)

local M = Enum.Material

local Lobby = {}

function Lobby.build(parent: Instance)
	local rng = SeededRandom.new(1994, "lobby")
	local O = Layout.Origin + Layout.LobbyOrigin
	local folder = Instance.new("Folder")
	folder.Name = "Lobby"
	local W, D, H = 44, 32, 12
	local floorCol = Color3.fromRGB(60, 50, 42)
	local wallCol = Color3.fromRGB(92, 84, 72)
	Build.part(folder, "Floor", Vector3.new(W, 1, D), CFrame.new(O + Vector3.new(0, -0.5, 0)), floorCol, M.WoodPlanks)
	Build.part(folder, "Ceiling", Vector3.new(W, 1, D), CFrame.new(O + Vector3.new(0, H + 0.5, 0)), Color3.fromRGB(70, 66, 60), M.Plaster)
	local function wall(name, size, pos)
		Build.part(folder, name, size, CFrame.new(O + pos), wallCol, M.Plaster)
	end
	wall("WallN", Vector3.new(W + 2, H, 1), Vector3.new(0, H / 2, -D / 2 - 0.5))
	wall("WallS", Vector3.new(W + 2, H, 1), Vector3.new(0, H / 2, D / 2 + 0.5))
	wall("WallW", Vector3.new(1, H, D), Vector3.new(-W / 2 - 0.5, H / 2, 0))
	wall("WallE", Vector3.new(1, H, D), Vector3.new(W / 2 + 0.5, H / 2, 0))
	-- wainscot
	for _, side in { { Vector3.new(0, 2, -D / 2 + 0.1), Vector3.new(W, 4, 0.2) }, { Vector3.new(0, 2, D / 2 - 0.1), Vector3.new(W, 4, 0.2) }, { Vector3.new(-W / 2 + 0.1, 2, 0), Vector3.new(0.2, 4, D) }, { Vector3.new(W / 2 - 0.1, 2, 0), Vector3.new(0.2, 4, D) } } do
		Build.part(folder, "Wainscot", side[2], CFrame.new(O + side[1]), Color3.fromRGB(56, 42, 32), M.Wood)
	end
	-- the door into the building (north wall)
	local doorPos = O + Vector3.new(0, 0, -D / 2 + 0.25)
	local doorCF = CFrame.lookAt(doorPos, doorPos + Vector3.new(0, 0, 1))
	Build.part(folder, "BuildingDoor", Vector3.new(5, 10, 0.4), doorCF * CFrame.new(0, 5, 0), Color3.fromRGB(40, 32, 26), M.Wood)
	Build.part(folder, "DoorFrame", Vector3.new(6, 10.8, 0.3), doorCF * CFrame.new(0, 5.4, 0.15), Color3.fromRGB(30, 24, 20), M.Wood)
	local lampPart = Build.part(folder, "DoorLamp", Vector3.new(1, 0.4, 0.6), doorCF * CFrame.new(0, 11, -0.4), Color3.fromRGB(255, 220, 170), M.Neon, { CanCollide = false })
	Build.light(lampPart, "SpotLight", { Brightness = 1.6, Range = 18, Angle = 70, Face = Enum.NormalId.Bottom, Color = Color3.fromRGB(255, 210, 160), Shadows = true })
	Props.sign(folder, doorCF * CFrame.new(0, 8.6, -0.25), "THE ASHGROVE BUILDING", 6, 0.9, "brass")
	-- central lamp
	local bulb = Build.ball(folder, "Bulb", 0.7, CFrame.new(O + Vector3.new(0, H - 2.2, 2)), Color3.fromRGB(255, 214, 160), M.Neon, { CanCollide = false })
	Build.detail(folder, "Cord", Vector3.new(0.06, 1.8, 0.06), CFrame.new(O + Vector3.new(0, H - 0.9, 2)), Color3.new(), M.Rubber)
	local mainLight = Build.light(bulb, "PointLight", { Brightness = 1.4, Range = 30, Color = Color3.fromRGB(255, 200, 150), Shadows = true })
	mainLight:AddTag("LobbyLamp")
	-- furniture
	for i = -1, 1 do
		Props.waitingChairs(folder, CFrame.lookAt(O + Vector3.new(i * 9, 0, 10), O + Vector3.new(i * 9, 0, 0)), rng, 3)
	end
	Props.sofa(folder, CFrame.lookAt(O + Vector3.new(-18, 0, -2), O + Vector3.new(0, 0, -2)), rng)
	Props.plant(folder, CFrame.new(O + Vector3.new(19, 0, -13)), rng, true)
	Props.plant(folder, CFrame.new(O + Vector3.new(-19, 0, -13)), rng, true)
	Props.clock(folder, CFrame.lookAt(O + Vector3.new(10, 8.5, -D / 2 + 0.05), O + Vector3.new(10, 8.5, 0)), rng)
	Props.painting(folder, CFrame.lookAt(O + Vector3.new(-W / 2 + 0.05, 6.5, -4), O + Vector3.new(0, 6.5, -4)), rng, 5, 3.5, "sea")
	-- TV with static on a table
	local tv = Props.table(folder, CFrame.new(O + Vector3.new(16, 0, 8)), rng, 4, 2.4)
	local crt = Props.crt(tv, CFrame.new(O + Vector3.new(16, 3.12, 8)) * CFrame.Angles(0, math.rad(-120), 0), rng)
	local screen = crt:FindFirstChild("Screen") :: BasePart
	screen.Material = M.Neon
	screen.Color = Color3.fromRGB(70, 74, 78)
	screen:AddTag("StaticScreen")
	-- kiosks: journal and shop
	local function kiosk(name, label, kind, pos, look)
		local cf = CFrame.lookAt(O + pos, O + pos + look)
		local m = Build.model(folder, name, cf)
		Build.part(m, "Stand", Vector3.new(3, 4, 1.6), cf * CFrame.new(0, 2, 0), Color3.fromRGB(40, 38, 36), M.Wood)
		local top = Build.part(m, "Screen", Vector3.new(2.6, 1.8, 0.2), cf * CFrame.new(0, 5, -0.2) * CFrame.Angles(math.rad(-15), 0, 0), Color3.fromRGB(26, 28, 28), M.SmoothPlastic)
		local gui = Build.surfaceGui(top, Enum.NormalId.Front, 60)
		gui.LightInfluence = 0.3
		Build.text(gui, { Size = UDim2.fromScale(0.9, 0.6), Position = UDim2.fromScale(0.05, 0.2), Text = label, Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(220, 214, 200) })
		top:AddTag("Interactable")
		top:SetAttribute("InteractKind", "Kiosk")
		top:SetAttribute("Kiosk", kind)
		top:SetAttribute("Prompt", "Open " .. string.lower(label))
		return m
	end
	kiosk("JournalKiosk", "JOURNAL", "JOURNAL", Vector3.new(-W / 2 + 2, 0, 8), Vector3.new(1, 0, 0))
	kiosk("ShopKiosk", "SHOP", "SHOP", Vector3.new(W / 2 - 2, 0, -6), Vector3.new(-1, 0, 0))
	-- rain-streaked windows on the south wall
	for i = -1, 1 do
		local wp = O + Vector3.new(i * 12, 6.5, D / 2)
		Build.part(folder, "Window", Vector3.new(5, 4, 0.2), CFrame.new(wp + Vector3.new(0, 0, -0.1)), Color3.fromRGB(30, 38, 46), M.Glass, { Transparency = 0.2, Reflectance = 0.15 })
		Build.detail(folder, "WindowFrame", Vector3.new(5.6, 4.6, 0.3), CFrame.new(wp + Vector3.new(0, 0, 0.05)), Color3.fromRGB(40, 32, 26), M.Wood)
		local flash = Build.part(folder, "Lightning", Vector3.new(0.2, 0.2, 0.2), CFrame.new(wp + Vector3.new(0, 4, 6)), Color3.new(), M.SmoothPlastic, { Transparency = 1, CanCollide = false, CanQuery = false })
		local l = Build.light(flash, "PointLight", { Brightness = 0, Range = 24, Color = Color3.fromRGB(200, 214, 255), Shadows = false })
		l:AddTag("Lightning")
	end
	-- spawn points
	local spawns = {}
	for i = 1, 4 do
		local p = O + Vector3.new(-6 + (i - 1) * 4, 3, 2)
		table.insert(spawns, CFrame.lookAt(p, O + Vector3.new(0, 3, -D / 2)))
	end
	-- a camera shot used behind lobby UI
	local camera = CFrame.lookAt(O + Vector3.new(14, 7, 12), O + Vector3.new(-2, 4, -10))
	folder.Parent = parent
	return {
		Root = folder,
		Spawns = spawns,
		Camera = camera,
		Center = O,
		Size = Vector3.new(W, H, D),
	}
end

return Lobby
