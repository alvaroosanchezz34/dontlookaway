--[[
	NametagController
	Small, depth-tested name tags (walls hide them) so teammates can identify each
	other without voice chat. Mimics wear the same tag, but it glitches now and
	then: a careful player can tell. The YOUR_NAME anomaly overrides names locally.
]]

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Kit = require(script.Parent.Parent.UI.Kit)

local NametagController = {}

local player = Players.LocalPlayer
local tags: { [Model]: { gui: BillboardGui, name: TextLabel, title: TextLabel, nextGlitch: number } } = {}
local random = Random.new()
local GLYPHS = { "#", "%", "&", "0", "_", "/", "?" }

local function create(model: Model)
	if tags[model] or model == player.Character then
		return
	end
	local head = model:WaitForChild("Head", 5) :: BasePart?
	if not head or tags[model] then
		return
	end
	local gui = Kit.new("BillboardGui", {
		Name = "DLA_Tag",
		Size = UDim2.fromOffset(200, 44),
		StudsOffsetWorldSpace = Vector3.new(0, 2.1, 0),
		MaxDistance = 48,
		AlwaysOnTop = false,
		LightInfluence = 0,
		ResetOnSpawn = false,
		Adornee = head,
		Parent = player:WaitForChild("PlayerGui"),
	})
	local name = Kit.text({ Size = UDim2.new(1, 0, 0, 22), TextXAlignment = Enum.TextXAlignment.Center, FontFace = Kit.F.Heading, TextSize = 18, TextStrokeTransparency = 0.6, Parent = gui })
	local title = Kit.text({ Size = UDim2.new(1, 0, 0, 16), Position = UDim2.fromOffset(0, 22), TextXAlignment = Enum.TextXAlignment.Center, FontFace = Kit.F.Light, TextSize = 13, TextColor3 = Kit.C.TextDim, TextStrokeTransparency = 0.8, Parent = gui })
	tags[model] = { gui = gui, name = name, title = title, nextGlitch = os.clock() + random:NextNumber(2, 4) }
end

local function remove(model: Model)
	local t = tags[model]
	if t then
		t.gui:Destroy()
		tags[model] = nil
	end
end

local function nameFor(model: Model): (string, string)
	local owner = Players:GetPlayerFromCharacter(model)
	local display = model:GetAttribute("PlayerName") or (owner and owner.DisplayName) or model.Name
	local title = model:GetAttribute("Title") or (owner and owner:GetAttribute("Title")) or ""
	local override = model:GetAttribute("NameOverride")
	if type(override) == "string" then
		display = override
	end
	-- the badge glyph is never copied onto a mimic: one more tell
	local badge = model:GetAttribute("Badge") or (owner and owner:GetAttribute("Badge"))
	if type(badge) == "string" and badge ~= "" and not model:GetAttribute("Mimic") then
		display = badge .. "  " .. display
	end
	return display, title
end

function NametagController:Start()
	local function onCharacter(character: Model)
		task.defer(create, character)
	end
	for _, p in Players:GetPlayers() do
		if p ~= player then
			if p.Character then
				onCharacter(p.Character)
			end
			p.CharacterAdded:Connect(onCharacter)
		end
	end
	Players.PlayerAdded:Connect(function(p)
		p.CharacterAdded:Connect(onCharacter)
	end)
	for _, m in CollectionService:GetTagged("NameTagged") do
		task.defer(create, m)
	end
	CollectionService:GetInstanceAddedSignal("NameTagged"):Connect(function(m)
		task.defer(create, m)
	end)
	RunService.RenderStepped:Connect(function()
		local now = os.clock()
		for model, t in tags do
			if not model.Parent or not model:IsDescendantOf(Workspace) then
				remove(model)
			else
				local display, title = nameFor(model)
				if model:GetAttribute("Mimic") then
					-- the tell: letters slip for a moment, the title is gone
					if now > t.nextGlitch then
						t.nextGlitch = now + random:NextNumber(1.8, 3.6)
						local i = random:NextInteger(1, math.max(1, #display))
						t.name.Text = display:sub(1, i - 1) .. GLYPHS[random:NextInteger(1, #GLYPHS)] .. display:sub(i + 1)
						task.delay(0.16, function()
							if t.name.Parent then
								t.name.Text = display
							end
						end)
					elseif t.name.Text ~= display and now > t.nextGlitch - 1.5 then
						t.name.Text = display
					end
					t.title.Text = ""
				else
					t.name.Text = display
					t.title.Text = title
				end
			end
		end
	end)
end

return NametagController
