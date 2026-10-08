--[[
	PSYCHOLOGICAL anomalies: sounds, voices, shadows and reflections.
	DANGEROUS anomalies: each has a rule. Break it and The Observer comes.
	LEGENDARY anomalies: extremely rare events.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Util = require(ReplicatedStorage.Shared.Util.Util)
local Net = require(ReplicatedStorage.Shared.Net)
local SoundFactory = require(ReplicatedStorage.Shared.SoundFactory)
local Registry = require(script.Parent.Parent.Registry)

local G, P, T = "GLOBAL", "PLAYER", "TEAM"
local FOCUS, INTERACT, ENDURE = "FOCUS", "INTERACT", "ENDURE"

local emitterCount = 0

-- An invisible part carrying a sound that starts when the part is cloned in.
local function emitter(key: string, volume: number?)
	emitterCount += 1
	local part = Instance.new("Part")
	part.Size = Vector3.new(0.4, 0.4, 0.4)
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CastShadow = false
	local s = SoundFactory.create(key, part, { volume = volume })
	if s then
		s:SetAttribute("AutoPlay", true)
	end
	return Registry.RealityService:AddTemplate("Emitter_" .. key .. "_" .. emitterCount, part, true)
end

local function playCreatedSounds(created)
	for _, inst in created do
		for _, d in inst:GetDescendants() do
			if d:IsA("Sound") and d:GetAttribute("AutoPlay") then
				d:Play()
			end
		end
	end
end

local function otherName(players: { Player }, target: Player): string
	local others = {}
	for _, p in Players:GetPlayers() do
		if p ~= target and Registry.PlayerService:IsAlive(p) then
			table.insert(others, p)
		end
	end
	if #others == 0 then
		return target.DisplayName
	end
	return others[math.random(1, #others)].DisplayName
end

local function farSpots(ctx, minD: number, maxD: number, filter)
	local list = {}
	for _, room in ctx.map.Rooms do
		if not room.secret and room.kind ~= "stairs" and (not filter or filter(room)) then
			for _, spot in room.floorSpots do
				local d = ctx:nearest(spot)
				if d >= minD and d <= maxD then
					table.insert(list, { pos = spot, room = room })
				end
			end
		end
	end
	return list
end

local function caption(players: { Player }, text: string, duration: number?)
	Net.fireList(players, "Caption", { text = text, duration = duration or 3.5, speaker = "world" })
end

local function stareLimit(): number
	local d = Registry.RoundService:GetDifficulty()
	return if d == "NIGHTMARE" then 2.8 elseif d == "HARD" then 3.4 else 5
end

return {
	------------------------------------------------------------------ PSYCHOLOGICAL
	{
		id = "PHONE_RING",
		difficulty = 1,
		scopes = { G, P },
		detection = INTERACT,
		candidates = function(ctx)
			return ctx:tagged("Phone")
		end,
		create = function(ctx, phone)
			local base = phone:FindFirstChild("Base")
			if not base then
				return nil
			end
			return {
				claim = phone,
				ops = {
					{ t = "Clone", template = emitter("PhoneRing"), parent = phone, cframe = base.CFrame },
					{ t = "Attr", target = base, name = "InteractKind", value = "Anomaly" },
					{ t = "Attr", target = base, name = "Prompt", value = "Answer" },
					{ t = "Tag", target = base, tag = "Interactable" },
				},
				anchors = { { pos = base.Position, radius = 1.8 } },
				interactTarget = base,
				lifetime = 70,
				onApplied = function(_, created)
					playCreatedSounds(created)
				end,
				onInteract = function(inst, player)
					Registry.AudioService:PlayAtFor({ player }, "Static", base.Position, { volume = 0.8 })
					caption({ player }, "[the line crackles]  ...you looked away...", 3.5)
					inst.data.resolver = player
					return "resolve"
				end,
			}
		end,
	},
	{
		id = "TEAMMATE_VOICE",
		difficulty = 2,
		scopes = { P },
		detection = FOCUS,
		candidates = function(ctx)
			local list = {}
			for _, rec in ctx.map.Doors do
				if rec.model and rec.model:HasTag("Door") then
					local d = ctx:nearest(rec.center)
					if d > 22 and d < 70 then
						table.insert(list, rec)
					end
				end
			end
			return list
		end,
		create = function(ctx, rec)
			local target = ctx.players[1]
			local name = otherName(ctx.players, target)
			local line = ctx.rng:Pick({ "over here", "come look at this", "i found it", "hey. in here", "help me" })
			local part = Instance.new("Part")
			part.Size = Vector3.new(0.4, 0.4, 0.4)
			part.Transparency = 1
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			local bb = Instance.new("BillboardGui")
			bb.Name = "Bubble"
			bb.Size = UDim2.fromOffset(240, 46)
			bb.StudsOffset = Vector3.new(0, 1.5, 0)
			bb.MaxDistance = 140
			bb.LightInfluence = 0
			bb.AlwaysOnTop = false
			bb.Parent = part
			local frame = Instance.new("Frame")
			frame.Size = UDim2.fromScale(1, 1)
			frame.BackgroundColor3 = Color3.fromRGB(14, 14, 16)
			frame.BackgroundTransparency = 0.25
			frame.Parent = bb
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, 8)
			corner.Parent = frame
			local label = Instance.new("TextLabel")
			label.Size = UDim2.new(1, -16, 1, -8)
			label.Position = UDim2.fromOffset(8, 4)
			label.BackgroundTransparency = 1
			label.TextColor3 = Color3.fromRGB(226, 222, 212)
			label.TextScaled = true
			label.Font = Enum.Font.GothamMedium
			label.Text = name .. ": " .. line
			label.Parent = frame
			local s = SoundFactory.create("Whisper", part, { volume = 0.7 })
			if s then
				s:SetAttribute("AutoPlay", true)
			end
			local template = Registry.RealityService:AddTemplate("Voice_" .. rec.id, part, true)
			local pos = rec.center + Vector3.new(0, 5.5, 0)
			return {
				ops = { { t = "Clone", template = template, parent = ctx.map.Root, cframe = CFrame.new(pos), name = "Voice" } },
				anchors = { { pos = pos, radius = 3.5 } },
				lifetime = 40,
				cue = false,
			}
		end,
	},
	{
		id = "FOOTSTEPS_BEHIND",
		difficulty = 2,
		scopes = { P },
		detection = FOCUS,
		candidates = function(ctx)
			local target = ctx.players[1]
			local h = ctx:history(target)
			if #h < 10 then
				return {}
			end
			local path = {}
			for i = #h - 8, #h - 3 do
				table.insert(path, h[i].pos)
			end
			local length = 0
			for i = 2, #path do
				length += (path[i] - path[i - 1]).Magnitude
			end
			if length < 8 then
				return {}
			end
			return { path }
		end,
		create = function(ctx, path)
			local target = ctx.players[1]
			local ops, anchors = {}, {}
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { target.Character :: Instance }
			local template = ctx:template("Footprint")
			local side = 1
			for i = 1, #path - 1 do
				local a, b = path[i], path[i + 1]
				local dir = Util.flat(b - a)
				if dir.Magnitude > 0.5 then
					dir = dir.Unit
					local steps = math.max(1, math.floor((b - a).Magnitude / 2.6))
					for s = 0, steps - 1 do
						local p = a:Lerp(b, s / steps) + Vector3.new(dir.Z, 0, -dir.X) * 0.45 * side
						side = -side
						local ground = workspace:Raycast(p + Vector3.new(0, 1, 0), Vector3.new(0, -8, 0), params)
						if ground then
							local cf = CFrame.lookAt(ground.Position, ground.Position + dir)
							table.insert(ops, { t = "Clone", template = template, parent = ctx.map.Root, cframe = cf * CFrame.new(0, 0.02, 0), name = "Footprint" })
							table.insert(anchors, { pos = ground.Position + Vector3.new(0, 0.3, 0), radius = 1.6 })
						end
					end
				end
			end
			if #ops < 3 then
				return nil
			end
			local last = anchors[#anchors].pos
			table.insert(ops, { t = "Clone", template = emitter("FootstepsBehind"), parent = ctx.map.Root, cframe = CFrame.new(last + Vector3.new(0, 1, 0)) })
			return {
				ops = ops,
				anchors = anchors,
				checkPoints = { anchors[1].pos, last },
				lifetime = 70,
				cue = false,
			}
		end,
	},
	{
		id = "BREATHING",
		difficulty = 2,
		scopes = { G, P },
		detection = FOCUS,
		candidates = function(ctx)
			return ctx:tagged("Locker")
		end,
		create = function(ctx, locker)
			local c = ctx:center(locker)
			return {
				claim = locker,
				ops = { { t = "Clone", template = emitter("BreathingCloset"), parent = locker, cframe = CFrame.new(c) } },
				anchors = { ctx:anchor(locker, 0.4) },
				onApplied = function(_, created)
					playCreatedSounds(created)
				end,
			}
		end,
	},
	{
		id = "DOOR_KNOCK",
		difficulty = 1,
		scopes = { G, P },
		detection = FOCUS,
		candidates = function(ctx)
			local list = {}
			for _, rec in ctx.map.Doors do
				if rec.model and rec.model:HasTag("Door") and not rec.model:GetAttribute("Open") then
					local d = ctx:nearest(rec.center)
					if d > 12 and d < 55 then
						table.insert(list, rec)
					end
				end
			end
			return list
		end,
		create = function(ctx, rec)
			local timer = 3
			local connection = nil
			return {
				claim = rec.model,
				ops = {},
				anchors = { { pos = rec.center + Vector3.new(0, 5, 0), radius = 3.2 } },
				lifetime = 80,
				cue = false,
				onApplied = function(inst)
					connection = Registry.DoorService.DoorToggled:Connect(function(door, open, player)
						if door == rec.model and open and player then
							Registry.AudioService:PlayAtFor({ player }, "Wind", rec.center, { volume = 0.8 })
							inst.data.resolver = player
							inst.data.openedBy = player
						end
					end)
				end,
				update = function(inst, dt)
					if inst.data.openedBy then
						return "resolve"
					end
					timer += dt
					if timer >= 7 then
						timer = 0
						task.spawn(function()
							for _ = 1, 3 do
								Registry.AudioService:PlayAtFor(inst.players, "KnockDoor", rec.center + Vector3.new(0, 5, 0))
								task.wait(0.45)
							end
						end)
					end
					return nil
				end,
				cleanup = function()
					if connection then
						connection:Disconnect()
					end
				end,
			}
		end,
	},
	{
		id = "WRONG_SHADOW",
		difficulty = 3,
		scopes = { G, P },
		detection = FOCUS,
		candidates = function(ctx)
			local list = {}
			for _, room in ctx.map.Rooms do
				if not room.secret and room.wallSpots then
					for _, spot in room.wallSpots do
						table.insert(list, { pos = spot.cframe.Position, cf = spot.cframe, room = room })
					end
				end
			end
			return list
		end,
		create = function(ctx, c)
			return {
				ops = { { t = "Clone", template = ctx:template("Shadow"), parent = c.room.folder, cframe = c.cf * CFrame.new(0, 0, -0.04), name = "Shadow" } },
				anchors = { { pos = (c.cf * CFrame.new(0, 4.4, 0)).Position, radius = 3.4 } },
			}
		end,
	},
	{
		id = "WRONG_REFLECTION",
		difficulty = 3,
		scopes = { P, G },
		detection = FOCUS,
		candidates = function(ctx)
			return ctx:tagged("Mirror")
		end,
		create = function(ctx, mirror)
			local glass = mirror:FindFirstChild("Glass")
			local overlay = glass and glass:FindFirstChild("Overlay")
			local figure = overlay and overlay:FindFirstChild("Figure")
			if not figure then
				return nil
			end
			return {
				claim = mirror,
				ops = { { t = "Prop", target = figure, prop = "Visible", value = true } },
				anchors = { ctx:anchor(glass, 0.3) },
			}
		end,
	},
	{
		id = "FIGURE_DISTANT",
		difficulty = 2,
		scopes = { P },
		detection = FOCUS,
		candidates = function(ctx)
			local target = ctx.players[1]
			local room = ctx:playerRoom(target)
			if not room or room.kind ~= "corridor" then
				return {}
			end
			local list = {}
			for _, spot in room.floorSpots do
				local d = ctx:nearest(spot)
				if d > 42 and d < 110 then
					table.insert(list, { pos = spot, room = room })
				end
			end
			return list
		end,
		create = function(ctx, c)
			local target = ctx.players[1]
			local root = Util.getRoot(target)
			if not root then
				return nil
			end
			local look = Util.flat(root.Position - c.pos)
			if look.Magnitude < 0.1 then
				return nil
			end
			local seen = 0
			local head = c.pos + Vector3.new(0, 8.5, 0)
			return {
				ops = { { t = "Clone", template = ctx:template("Figure"), parent = c.room.folder, cframe = CFrame.lookAt(c.pos, c.pos + look.Unit), name = "Figure" } },
				anchors = { { pos = c.pos + Vector3.new(0, 5, 0), radius = 4.2 } },
				checkPoints = { head, c.pos + Vector3.new(0, 3, 0) },
				lifetime = 32,
				update = function(inst, dt)
					local r = Util.getRoot(inst.players[1])
					if r and (r.Position - c.pos).Magnitude < 16 then
						return "expire"
					end
					if Registry.PlayerService:IsLookingAt(inst.players[1], head, 25, 140) then
						seen += dt
						if seen > 3 then
							return "expire"
						end
					end
					return nil
				end,
			}
		end,
	},
	------------------------------------------------------------------ DANGEROUS
	{
		id = "STARE_ENTITY",
		difficulty = 2,
		scopes = { G, P },
		detection = FOCUS,
		candidates = function(ctx)
			local list = {}
			for _, rec in ctx.map.Doors do
				if rec.model and rec.model:HasTag("Door") and rec.model:GetAttribute("Kind") == "normal" then
					local a, b = ctx.map.Rooms[rec.roomA or ""], ctx.map.Rooms[rec.roomB or ""]
					if a and b and (a.kind == "corridor" or b.kind == "corridor") then
						local d = ctx:nearest(rec.center)
						if d > 16 and d < 70 then
							table.insert(list, rec)
						end
					end
				end
			end
			return list
		end,
		create = function(ctx, rec)
			local a = ctx.map.Rooms[rec.roomA or ""]
			-- stand just inside the room, facing out into the corridor
			local intoRoom = if a and a.kind == "corridor" then rec.passageDir else -rec.passageDir
			local pos = rec.center + intoRoom * 3.2
			local cf = CFrame.lookAt(pos, pos - intoRoom)
			local head = pos + Vector3.new(0, 7, 0)
			local stare: { [Player]: number } = {}
			return {
				ops = { { t = "Clone", template = ctx:template("PaleFigure"), parent = ctx.map.Root, cframe = cf, name = "PaleFigure" } },
				anchors = { { pos = pos + Vector3.new(0, 4, 0), radius = 3.6 } },
				checkPoints = { head, pos + Vector3.new(0, 3, 0) },
				lifetime = 75,
				onApplied = function()
					-- the door it stands behind creaks open on its own
					if not rec.model:GetAttribute("Open") then
						Registry.DoorService:SetOpen(rec.model, true)
					end
				end,
				update = function(inst, dt)
					local limit = stareLimit()
					for _, p in inst.players do
						if Registry.PlayerService:IsLookingAt(p, head, 18, 90) then
							stare[p] = (stare[p] or 0) + dt
							if stare[p] >= limit then
								inst.data.victim = p
								return "fail"
							end
						else
							stare[p] = math.max(0, (stare[p] or 0) - dt * 0.5)
						end
					end
					return nil
				end,
				onFail = function(_, player)
					Registry.AudioService:PlayAt("ObserverScreech", head)
					if player then
						Registry.ObserverService:StartHunt(player, { near = pos, reason = "stare" })
					end
				end,
			}
		end,
	},
	{
		id = "WRONG_OBJECT",
		difficulty = 3,
		scopes = { G },
		detection = FOCUS,
		requires = function()
			local state = Registry.ObjectiveService:GetState()
			return state ~= nil and state.fuses < 3
		end,
		candidates = function(ctx)
			local list = {}
			for _, room in ctx.map.Rooms do
				if not room.lockKey and not room.keypad and not room.secret and room.kind ~= "stairs" then
					for _, cf in room.itemSpots or {} do
						local d = ctx:nearest(cf.Position)
						if d > 20 and d < 90 then
							table.insert(list, { pos = cf.Position, cf = cf, room = room })
						end
					end
				end
			end
			return list
		end,
		create = function(ctx, c)
			return {
				ops = {},
				anchors = { { pos = c.pos + Vector3.new(0, 0.5, 0), radius = 1.6 } },
				lifetime = 130,
				cue = false,
				onApplied = function(inst)
					inst.data.pickup = Registry.InventoryService:SpawnPickup("FALSE_FUSE", CFrame.new(c.pos) * CFrame.Angles(0, math.rad(ctx.rng:Number(0, 360)), 0), { falseItem = true, color = Color3.fromRGB(214, 160, 112) })
				end,
				cleanup = function(inst)
					if inst.data.pickup and inst.data.pickup.Parent then
						inst.data.pickup:Destroy()
					end
				end,
				onFail = function(_, player)
					if player then
						Net.fire(player, "Effect", { name = "Glitch", strength = 1 })
						Net.fire(player, "Notify", { kind = "danger", text = "It was never a fuse." })
						Registry.ObserverService:StartHunt(player, { reason = "duplicate" })
					end
				end,
			}
		end,
	},
	{
		id = "LIGHTS_OUT",
		difficulty = 3,
		scopes = { G },
		detection = ENDURE,
		maxUses = 1,
		candidates = function(ctx)
			local list = {}
			for _, p in ctx.players do
				local room = ctx:playerRoom(p)
				if room and #room.fixtures > 0 and room.kind ~= "stairs" and not table.find(list, room) then
					table.insert(list, room)
				end
			end
			return list
		end,
		create = function(ctx, room)
			local ops = {}
			for _, f in room.fixtures do
				table.insert(ops, { t = "Attr", target = f, name = "Override", value = "off" })
			end
			local center = room.center + Vector3.new(0, 4, 0)
			local inside = {}
			for _, p in ctx.players do
				if ctx:playerRoom(p) == room then
					table.insert(inside, p)
				end
			end
			if #inside == 0 then
				return nil
			end
			local elapsed = 0
			local DURATION = 28
			local GRACE = 4
			local function bound(player: Player): boolean
				local root = Util.getRoot(player)
				return root ~= nil and (root.Position - center).Magnitude < 45 and table.find(inside, player) ~= nil
			end
			return {
				ops = ops,
				anchors = { { pos = center, radius = 6 } },
				checkPoints = {},
				lifetime = DURATION + 10,
				cue = false,
				onApplied = function()
					Registry.AudioService:PlayAtFor(inside, "BulbPop", center)
					task.delay(1.2, function()
						Registry.AudioService:PlayAtFor(inside, "Whisper", center, { volume = 1.2 })
						caption(inside, "...keep... the light... on...", 4)
					end)
				end,
				update = function(inst, dt)
					elapsed += dt
					if elapsed > GRACE then
						for _, p in inside do
							if bound(p) and Registry.PlayerService:IsAlive(p) and not Registry.InventoryService:IsLightOn(p) and Registry.InventoryService:GetBattery(p) > 0 then
								inst.data.victim = p
								return "fail"
							end
						end
					end
					if elapsed >= DURATION then
						inst.data.resolver = inside[1]
						return "resolve"
					end
					return nil
				end,
				onFlashlight = function(_, player, on)
					if not on and elapsed > GRACE and bound(player) and Registry.InventoryService:GetBattery(player) > 0 then
						return "fail"
					end
					return nil
				end,
				onFail = function(_, player)
					if player then
						Registry.ObserverService:StartHunt(player, { reason = "dark" })
					end
				end,
			}
		end,
	},
	{
		id = "LOOK_BACK",
		difficulty = 4,
		scopes = { P },
		detection = ENDURE,
		maxUses = 1,
		candidates = function(ctx)
			local target = ctx.players[1]
			return if Util.getRoot(target) then { target } else {}
		end,
		create = function(ctx, target: Player)
			local elapsed, stepTimer = 0, 0
			local looks, looking = 0, false
			local DURATION = 22
			local function follower(): Vector3?
				local h = ctx:history(target)
				local root = Util.getRoot(target)
				if not root then
					return nil
				end
				local entry = h[#h - 2]
				local pos = if entry and (entry.pos - root.Position).Magnitude > 3 then entry.pos else root.Position - Util.flat(root.CFrame.LookVector) * 5
				return pos
			end
			return {
				ops = {},
				anchors = {},
				checkPoints = {},
				lifetime = DURATION + 8,
				cue = false,
				onApplied = function(inst)
					caption(inst.players, "[footsteps behind you]", 3)
				end,
				update = function(inst, dt)
					elapsed += dt
					stepTimer += dt
					local pos = follower()
					if not pos then
						return nil
					end
					if stepTimer > 0.6 then
						stepTimer = 0
						Registry.AudioService:PlayAtFor({ target }, "FootstepsBehind", pos)
					end
					local isLooking = Registry.PlayerService:IsLookingAt(target, pos + Vector3.new(0, 2, 0), 50, 40)
					if isLooking and not looking then
						looks += 1
						inst.data.looks = looks
						Registry.AudioService:PlayAtFor({ target }, "ObserverTwitch", pos)
						if looks >= 3 then
							inst.data.victim = target
							return "fail"
						end
					end
					looking = isLooking
					if elapsed >= DURATION then
						inst.data.resolver = target
						return "resolve"
					end
					return nil
				end,
				onResolve = function(inst, player)
					if player and (inst.data.looks or 0) == 0 then
						Registry.ProgressionService:Award(player, "NEVER_LOOK_BACK")
					end
				end,
				onFail = function(_, player)
					if player then
						Registry.ObserverService:StartHunt(player, { behind = true, reason = "lookback" })
					end
				end,
			}
		end,
	},
	{
		id = "WRONG_ROOM",
		difficulty = 2,
		scopes = { G },
		detection = FOCUS,
		candidates = function(ctx)
			local list = {}
			for _, room in ctx.map.Rooms do
				if room.kind == "corridor" and room.wallSpots then
					for _, spot in room.wallSpots do
						local d = ctx:nearest(spot.cframe.Position)
						if d > 18 and d < 90 then
							table.insert(list, { pos = spot.cframe.Position, cf = spot.cframe, room = room })
						end
					end
				end
			end
			return list
		end,
		create = function(ctx, c)
			local cf = c.cf * CFrame.new(0, 0, -0.25)
			local spec
			spec = {
				ops = { { t = "Clone", template = ctx:template("B13Door"), parent = c.room.folder, cframe = cf, name = "B-13" } },
				anchors = { { pos = (cf * CFrame.new(0, 5, 0)).Position, radius = 3.4 } },
				lifetime = 110,
				onApplied = function(_, created)
					local door = created[1]
					local panel = door and door:FindFirstChild("Panel")
					if panel then
						panel:AddTag("Interactable")
						panel:SetAttribute("InteractKind", "Anomaly")
						panel:SetAttribute("Prompt", "Open B-13")
						spec.interactTarget = panel
					end
				end,
				onInteract = function(inst, player)
					inst.data.victim = player
					return "fail"
				end,
				onFail = function(_, player)
					if not player then
						return
					end
					-- the room behind B-13 is somewhere else entirely
					local options = {}
					for _, id in { "B_h", "B_w", "B_f", "U_x" } do
						local room = ctx.map.Rooms[id]
						if room and #room.floorSpots > 0 then
							table.insert(options, room)
						end
					end
					local room = options[math.random(1, math.max(1, #options))]
					if room then
						local spot = room.floorSpots[math.random(1, #room.floorSpots)]
						Net.fire(player, "Effect", { name = "WrongRoom" })
						task.delay(0.6, function()
							Registry.PlayerService:Teleport(player, CFrame.new(spot + Vector3.new(0, 3, 0)))
							Registry.ObserverService:StartHunt(player, { reason = "b13" })
						end)
					end
				end,
			}
			return spec
		end,
	},
	{
		id = "FALSE_PING",
		difficulty = 2,
		scopes = { P, T },
		detection = FOCUS,
		candidates = function(ctx)
			return farSpots(ctx, 38, 95)
		end,
		create = function(ctx, c)
			local target = ctx.players[1]
			local name = otherName(ctx.players, target)
			local pingId = "false_" .. tostring(math.random(1, 1e8))
			local pos = c.pos + Vector3.new(0, 2.5, 0)
			return {
				ops = {},
				anchors = { { pos = pos, radius = 3 } },
				lifetime = 45,
				cue = false,
				onApplied = function(inst)
					Net.fireList(inst.players, "PingShow", { id = pingId, kind = "COME_HERE", position = pos, from = name, fake = true, duration = 45 })
				end,
				update = function(inst)
					for _, p in inst.players do
						local root = Util.getRoot(p)
						if root and (root.Position - c.pos).Magnitude < 7 then
							inst.data.victim = p
							return "fail"
						end
					end
					return nil
				end,
				cleanup = function(inst)
					Net.fireList(inst.players, "PingShow", { id = pingId, remove = true })
				end,
				onFail = function(_, player)
					if player then
						Registry.ObserverService:StartHunt(player, { near = c.pos, reason = "ping" })
					end
				end,
			}
		end,
	},
	------------------------------------------------------------------ LEGENDARY
	{
		id = "ROOM_ZERO",
		difficulty = 5,
		scopes = { G },
		detection = FOCUS,
		candidates = function(ctx)
			local list = {}
			local room = ctx.map.Rooms.U_c
			if room and room.wallSpots then
				for _, spot in room.wallSpots do
					table.insert(list, { pos = spot.cframe.Position, cf = spot.cframe, room = room })
				end
			end
			return list
		end,
		create = function(ctx, c)
			local cf = c.cf * CFrame.new(0, 0, -0.25)
			local spec
			spec = {
				ops = { { t = "Clone", template = ctx:template("ZeroDoor"), parent = c.room.folder, cframe = cf, name = "Room0" } },
				anchors = { { pos = (cf * CFrame.new(0, 5, 0)).Position, radius = 3.4 } },
				lifetime = 120,
				onApplied = function(_, created)
					local door = created[1]
					local panel = door and door:FindFirstChild("Panel")
					if panel then
						panel:AddTag("Interactable")
						panel:SetAttribute("InteractKind", "Anomaly")
						panel:SetAttribute("Prompt", "Open 0")
						spec.interactTarget = panel
					end
				end,
				onInteract = function(inst, player)
					local secret = ctx.map.Rooms.B_z
					if secret then
						Net.fire(player, "Effect", { name = "PortalGlitch" })
						Registry.PlayerService:Teleport(player, CFrame.new(secret.center + Vector3.new(0, 3, 2)))
					end
					inst.data.resolver = player
					return "resolve"
				end,
			}
			return spec
		end,
	},
	{
		id = "YOUR_NAME",
		difficulty = 3,
		scopes = { P },
		detection = FOCUS,
		minPlayers = 2,
		candidates = function(ctx)
			return { ctx.players[1] }
		end,
		create = function(ctx, target: Player)
			local ops, anchors = {}, {}
			for _, p in Registry.PlayerService:GetAlive() do
				if p ~= target and p.Character then
					table.insert(ops, { t = "Attr", target = p.Character, name = "NameOverride", value = target.DisplayName })
					local head = p.Character:FindFirstChild("Head")
					if head then
						table.insert(anchors, { pos = head, radius = 2.6 })
					end
				end
			end
			if #anchors == 0 then
				return nil
			end
			return { ops = ops, anchors = anchors, checkPoints = {}, lifetime = 45, cue = false }
		end,
	},
}
