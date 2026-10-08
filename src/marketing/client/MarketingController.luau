--[[
	MarketingController
	Plays, pauses and cleans up Marketing Studio scenes.

	  MarketingController.PlayScene(name)     MarketingController.StopScene()
	  MarketingController.PauseScene()        MarketingController.ResumeScene()
	  MarketingController.RestartScene()      MarketingController.ListScenes()
	  MarketingController.CleanupMarketingScene()

	A scene is a ModuleScript in Scenes/ returning
	  { Name, Description, Duration, Format?, Build = function(L) return events end }
	where L is Utilities/Locations and events are Actions (see Actions.luau).

	While a scene plays (all local to this screen):
	  * one render step, after the game's camera, drives the timeline and the
	    camera; the game's camera keeps reporting the player's real view
	  * the game's interface, your character and (optionally) the game's audio
	    are hidden; your character is held still
	When it stops, CleanupMarketingScene() restores every one of those.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Marketing"):WaitForChild("MarketingConfig"))
local Signal = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Util"):WaitForChild("Signal"))
local Runtime = require(script.Parent.Runtime)
local Timeline = require(script.Parent.Timeline)
local Actions = require(script.Parent.Actions)
local CameraRig = require(script.Parent.Cameras.CameraRig)
local Screen = require(script.Parent.Effects.Screen)
local LightFX = require(script.Parent.Effects.LightFX)
local Doors = require(script.Parent.Effects.Doors)
local Eye = require(script.Parent.Effects.Eye)
local Figures = require(script.Parent.Effects.Figures)
local Audio = require(script.Parent.Audio.MarketingAudio)
local Titles = require(script.Parent.Text.Titles)
local Locations = require(script.Parent.Utilities.Locations)

local MarketingController = {}

local RENDER_NAME = "MarketingStudio"
local player = Players.LocalPlayer

local current: any = nil -- the running timeline
local currentName: string? = nil
local finishedAt: number? = nil
local bound = false
local options = table.clone(Config.Defaults)
local formatName = Config.DefaultFormat
local cameraStyle = Config.DefaultCamera

MarketingController.Changed = Signal.new() -- (state)

local function fire()
	MarketingController.Changed:Fire(MarketingController.GetState())
end

------------------------------------------------------------------------------------
-- Scenes
------------------------------------------------------------------------------------

local function scenesFolder(): Instance
	return script.Parent:WaitForChild("Scenes")
end

function MarketingController.ListScenes(): { string }
	local list = {}
	for _, m in scenesFolder():GetChildren() do
		if m:IsA("ModuleScript") then
			table.insert(list, m.Name)
		end
	end
	table.sort(list)
	return list
end

function MarketingController.GetScene(name: string): any
	local m = scenesFolder():FindFirstChild(name)
	if not m or not m:IsA("ModuleScript") then
		return nil
	end
	local ok, def = pcall(require, m)
	if not ok then
		warn("[Marketing] scene " .. name .. " failed to load: " .. tostring(def))
		return nil
	end
	return def
end

------------------------------------------------------------------------------------
-- Options
------------------------------------------------------------------------------------

function MarketingController.SetOption(key: string, value: any)
	options[key] = value
	if key == "TimeScale" and current then
		current.speed = value
		Audio.setSpeedScale(value)
	end
	fire()
end

function MarketingController.GetOption(key: string): any
	return options[key]
end

function MarketingController.SetFormat(name: string)
	formatName = name
	Screen.setFormat(name)
	fire()
end

function MarketingController.GetFormat(): string
	return formatName
end

function MarketingController.SetCameraStyle(name: string)
	cameraStyle = name
	CameraRig.force(if name == "AUTO" then nil else name)
	fire()
end

function MarketingController.GetCameraStyle(): string
	return cameraStyle
end

------------------------------------------------------------------------------------
-- Hiding the game while recording (all restorable)
------------------------------------------------------------------------------------

local function hideHUD()
	local playerGui = player:FindFirstChild("PlayerGui")
	if playerGui then
		for _, g in playerGui:GetChildren() do
			if g:IsA("ScreenGui") and g.Name ~= "MarketingRuntimeGui" and g.Name ~= "MarketingStudioPanel" and g.Enabled then
				Runtime.setProp(g, "Enabled", false)
			end
		end
	end
	-- core UI (chat, player list...): remember each one and give it back
	local saved = {}
	for _, t in { Enum.CoreGuiType.PlayerList, Enum.CoreGuiType.Chat, Enum.CoreGuiType.Health, Enum.CoreGuiType.Backpack, Enum.CoreGuiType.EmotesMenu } do
		local ok, on = pcall(function()
			return StarterGui:GetCoreGuiEnabled(t)
		end)
		if ok and on then
			table.insert(saved, t)
			pcall(function()
				StarterGui:SetCoreGuiEnabled(t, false)
			end)
		end
	end
	Runtime.onCleanup(function()
		for _, t in saved do
			pcall(function()
				StarterGui:SetCoreGuiEnabled(t, true)
			end)
		end
	end)
end

local function characterParts(): { BasePart }
	local list = {}
	local character = player.Character
	if character then
		for _, d in character:GetDescendants() do
			if d:IsA("BasePart") or d:IsA("Decal") then
				table.insert(list, d :: any)
			end
		end
	end
	return list
end

local function freezeCharacter()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") and not root.Anchored then
		Runtime.setProp(root, "Anchored", true)
	end
end

------------------------------------------------------------------------------------
-- The loop
------------------------------------------------------------------------------------

local FRAME_JOBS = {
	{ "camera", function(_tl, dt)
		CameraRig.update(dt)
	end },
	{ "eye", function(tl, dt)
		Eye.update(dt, tl.clock)
	end },
	{ "titles", function(tl, dt)
		Titles.update(dt, tl.clock)
		Titles.updateImages()
	end },
	{ "grain", function()
		Screen.updateGrain()
	end },
	{ "cctv", function(tl)
		if tl.data.cctvClock then
			local secs = tl.data.cctvStart + (tl.clock - tl.data.cctvClock)
			local stamp = string.format("%s  %02d:%02d:%02d", tl.data.cctvDate, math.floor(secs / 3600) % 24, math.floor(secs / 60) % 60, math.floor(secs) % 60)
			Screen.updateCCTV(tl.clock, stamp)
		end
	end },
}

local function step(dt: number)
	local tl = current
	if not tl then
		return
	end
	tl:step(dt)
	if not tl.paused then
		local scaled = dt * tl.speed
		-- each per-frame layer is isolated: one failing never stops the others
		for _, job in FRAME_JOBS do
			local ok, err = pcall(job[2], tl, scaled)
			if not ok and not tl.data["warned_" .. job[1]] then
				tl.data["warned_" .. job[1]] = true
				tl.failed += 1
				warn(string.format("[Marketing] %s failed every frame: %s", job[1], tostring(err)))
			end
		end
	end
	Screen.layout()
	CameraRig.apply()
	LightFX.updateFill(game:GetService("Workspace").CurrentCamera.CFrame)
	-- Roblox resets local transparency each frame for first-person characters
	if options.HideCharacter then
		for _, p in characterParts() do
			(p :: any).LocalTransparencyModifier = 1
		end
	end
	if tl:isFinished() and not tl.paused then
		local since: number = finishedAt or os.clock()
		finishedAt = since
		if os.clock() - since >= (options.HoldAtEnd or 0) then
			if options.Loop and currentName then
				MarketingController.RestartScene()
			else
				MarketingController.StopScene()
			end
		end
	end
end

local function bind()
	if bound then
		return
	end
	bound = true
	RunService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Last.Value, step)
end

local function unbind()
	if not bound then
		return
	end
	bound = false
	pcall(function()
		RunService:UnbindFromRenderStep(RENDER_NAME)
	end)
end

------------------------------------------------------------------------------------
-- API
------------------------------------------------------------------------------------

-- Undo everything a scene did. Safe to call at any time, any number of times.
function MarketingController.CleanupMarketingScene()
	unbind()
	current = nil
	finishedAt = nil
	Runtime.cleanup()
	-- module state that pointed at destroyed instances
	Eye.reset()
	Figures.reset()
	Titles.reset()
	require(script.Parent.Text.Scratch).reset()
	LightFX.reset()
	Doors.reset()
	Audio.reset()
	Locations.reset()
	CameraRig.force(if cameraStyle == "AUTO" then nil else cameraStyle)
	-- character transparency comes back by itself next frame (first person);
	-- outside first person, put it back explicitly
	for _, p in characterParts() do
		(p :: any).LocalTransparencyModifier = 0
	end
end

function MarketingController.PlayScene(name: string): (boolean, string?)
	local def = MarketingController.GetScene(name)
	if not def then
		return false, "unknown scene " .. tostring(name)
	end
	MarketingController.CleanupMarketingScene()
	Locations.reset()
	-- build the scene against the current world
	local ok, events = pcall(def.Build, Locations, Config)
	if not ok or type(events) ~= "table" then
		warn("[Marketing] scene " .. name .. " could not be built: " .. tostring(events))
		MarketingController.CleanupMarketingScene()
		return false, tostring(events)
	end
	-- format: the scene's own unless the panel chose one
	Screen.begin()
	Screen.setFormat(formatName)
	CameraRig.begin()
	CameraRig.force(if cameraStyle == "AUTO" then nil else cameraStyle)
	if options.HideHUD then
		hideHUD()
	end
	-- sets built far from the map: the player's flashlight and the game's eye
	-- adaptation light follow the camera, keep them out of the shot
	if def.Isolated then
		local Workspace = game:GetService("Workspace")
		for _, child in Workspace:GetChildren() do
			if child:IsA("BasePart") and (child.Name == "LocalFlashlight" or child.Name == "DarkAdaptation" or string.sub(child.Name, 1, 11) == "Flashlight_") then
				Runtime.setProp(child, "Parent", nil)
				local holder = child
				Runtime.onCleanup(function()
					if holder.Parent == nil then
						pcall(function()
							holder.Parent = Workspace
						end)
					end
				end)
			end
		end
	end
	-- fill light (scenes on a black card set Light = false)
	if def.Light ~= false then
		LightFX.fill(options.Light or 3)
	end
	if options.FreezeCharacter then
		freezeCharacter()
	end
	-- make sure the campaign images are loaded (and say so in the Output)
	local extra = {}
	if type(Config.TitleImage) == "number" and Config.TitleImage > 0 then
		table.insert(extra, "rbxassetid://" .. string.format("%d", Config.TitleImage))
	end
	Eye.preload(extra)
	local tl = Timeline.new(events, def.Duration or 10, Actions.run)
	tl.speed = options.TimeScale or 1
	Audio.setSpeedScale(tl.speed)
	if options.MuteGameAudio then
		Audio.muteGame(tl, 0)
	end
	current = tl
	currentName = name
	finishedAt = nil
	bind()
	print(string.format("[Marketing] ▶ %s (%d events, %.1f s)%s", name, #events, def.Duration or 10, if Eye.photographic() then "" else " · eye images not set: drawn eye"))
	fire()
	return true, nil
end

local function report(reason: string)
	local tl = current
	if tl and currentName then
		print(string.format("[Marketing] %s %s: %d/%d events ran, %d failed%s", currentName, reason, tl.ran, #tl.events, tl.failed, if tl.failed > 0 then " (see the warnings above)" else ""))
	end
end

function MarketingController.StopScene()
	report(if current and current:isFinished() then "finished" else "stopped")
	MarketingController.CleanupMarketingScene()
	fire()
end

function MarketingController.PauseScene()
	if current and not current.paused then
		current.paused = true
		Audio.pauseAll()
		fire()
	end
end

function MarketingController.ResumeScene()
	if current and current.paused then
		current.paused = false
		Audio.resumeAll()
		fire()
	end
end

function MarketingController.RestartScene()
	local name = currentName
	if name then
		return MarketingController.PlayScene(name)
	end
	return false, "nothing to restart"
end

function MarketingController.IsPlaying(): boolean
	return current ~= nil
end

function MarketingController.GetState()
	return {
		scene = currentName,
		playing = current ~= nil,
		paused = current ~= nil and current.paused,
		clock = if current then current.clock else 0,
		duration = if current then current.duration else 0,
		format = formatName,
		camera = cameraStyle,
		options = table.clone(options),
		building = Locations.hasBuilding(),
	}
end

-- Step the active scene manually (tests and frame-by-frame preview).
function MarketingController._step(dt: number)
	step(dt)
end

-- Character reset mid-scene: never leave a mess behind.
local removing = (player :: any).CharacterRemoving
if removing then
	removing:Connect(function()
		if current then
			MarketingController.StopScene()
		end
	end)
end

return MarketingController
