--[[
	AccessibilityController
	Applies the presentation settings that are not owned by a single system:
	  brightness    a gentle user grade (never enough to erase the darkness, never
	                enough to make it pitch black)
	  colorMode     colour-blind friendly remaps of the UI danger / good colours and
	                a high-contrast grade
	  graphics      AUTO / LOW / MEDIUM / HIGH: shadow-casting fixtures and particle
	                density (Quality() is read by other controllers)
	Other settings (reduce motion, subtitle size, audio indicators, flashlight
	effects) are read directly by the systems they affect.
]]

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MaterialLibrary = require(ReplicatedStorage.Shared.MaterialLibrary)
local State = require(script.Parent.Parent.State)
local Kit = require(script.Parent.Parent.UI.Kit)

local AccessibilityController = {}

local userGrade: ColorCorrectionEffect
local lastGraphics: string? = nil

-- Original palette, so modes can be switched back.
local BASE = {
	Danger = Kit.C.Danger,
	DangerDim = Kit.C.DangerDim,
	Good = Kit.C.Good,
	Accent = Kit.C.Accent,
}

-- Danger must stay readable without red/green discrimination.
local PALETTES = {
	NORMAL = BASE,
	DEUTERANOPIA = { Danger = Color3.fromRGB(214, 120, 30), DangerDim = Color3.fromRGB(110, 62, 18), Good = Color3.fromRGB(120, 170, 230), Accent = Color3.fromRGB(120, 170, 230) },
	PROTANOPIA = { Danger = Color3.fromRGB(226, 170, 40), DangerDim = Color3.fromRGB(116, 88, 22), Good = Color3.fromRGB(110, 160, 230), Accent = Color3.fromRGB(110, 160, 230) },
	TRITANOPIA = { Danger = Color3.fromRGB(214, 60, 90), DangerDim = Color3.fromRGB(110, 30, 46), Good = Color3.fromRGB(120, 210, 200), Accent = Color3.fromRGB(120, 210, 200) },
	HIGH_CONTRAST = { Danger = Color3.fromRGB(255, 60, 60), DangerDim = Color3.fromRGB(140, 20, 20), Good = Color3.fromRGB(230, 255, 230), Accent = Color3.fromRGB(170, 220, 255) },
}

-- 1 = low, 2 = medium, 3 = high.
function AccessibilityController:Quality(): number
	local g = State.settings.graphics
	if g == "LOW" then
		return 1
	elseif g == "MEDIUM" then
		return 2
	elseif g == "HIGH" then
		return 3
	end
	-- AUTO follows the Roblox graphics slider when it is readable
	local ok, level = pcall(function()
		return UserSettings():GetService("UserGameSettings").SavedQualityLevel.Value
	end)
	if ok and type(level) == "number" and level > 0 then
		return if level <= 3 then 1 elseif level <= 7 then 2 else 3
	end
	return 2
end

local function applyShadows()
	local shadows = AccessibilityController:Quality() >= 2
	for _, m in CollectionService:GetTagged("Fixture") do
		if m:IsDescendantOf(Workspace) then
			for _, d in m:GetDescendants() do
				if d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight") then
					if d:GetAttribute("BaseShadows") == nil then
						d:SetAttribute("BaseShadows", d.Shadows)
					end
					d.Shadows = shadows and d:GetAttribute("BaseShadows") == true
				end
			end
		end
	end
end

local function apply()
	local s = State.settings
	-- brightness 0..1, 0.5 neutral
	local b = math.clamp(tonumber(s.brightness) or 0.5, 0, 1) - 0.5
	local mode = PALETTES[s.colorMode] and s.colorMode or "NORMAL"
	userGrade.Brightness = b * 0.14
	userGrade.Contrast = if mode == "HIGH_CONTRAST" then 0.22 else 0
	userGrade.Saturation = if mode == "HIGH_CONTRAST" then 0.1 else 0
	local palette = PALETTES[mode]
	for key, color in palette do
		Kit.C[key] = color
	end
	if s.graphics ~= lastGraphics then
		lastGraphics = s.graphics
		applyShadows()
	end
end

function AccessibilityController:Init()
	-- custom surface textures (base-material overrides are applied per side)
	MaterialLibrary.apply()
	userGrade = Instance.new("ColorCorrectionEffect")
	userGrade.Name = "UserSettingsGrade"
	userGrade.Parent = Lighting
end

function AccessibilityController:Start()
	apply()
	State.SettingsChanged:Connect(apply)
	Workspace:GetAttributeChangedSignal("MapReady"):Connect(function()
		task.delay(1, applyShadows)
	end)
end

return AccessibilityController
