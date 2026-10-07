--[[
	Theme
	UI visual identity: black, dark grey, bone white, and a very restrained red that
	is reserved exclusively for danger, plus a single cold blue accent for
	selection and progress.
]]

local Theme = {}

Theme.Colors = {
	Black = Color3.fromRGB(6, 6, 7),
	Panel = Color3.fromRGB(14, 14, 16),
	PanelLight = Color3.fromRGB(24, 24, 27),
	Line = Color3.fromRGB(58, 58, 62),
	Muted = Color3.fromRGB(120, 120, 124),
	Text = Color3.fromRGB(232, 228, 220),
	TextDim = Color3.fromRGB(168, 165, 158),
	Danger = Color3.fromRGB(168, 38, 38),
	DangerDim = Color3.fromRGB(96, 24, 24),
	Good = Color3.fromRGB(190, 206, 190),
	Stamina = Color3.fromRGB(200, 198, 190),
	Battery = Color3.fromRGB(226, 220, 196),
	Accent = Color3.fromRGB(140, 186, 214), -- the one cold accent: selection, owned, progress
}

Theme.Fonts = {
	Title = Font.fromEnum(Enum.Font.GothamBlack),
	Heading = Font.fromEnum(Enum.Font.GothamBold),
	Body = Font.fromEnum(Enum.Font.GothamMedium),
	Light = Font.fromEnum(Enum.Font.Gotham),
	Mono = Font.fromEnum(Enum.Font.Code),
	Type = Font.fromEnum(Enum.Font.SpecialElite),
	Hand = Font.fromEnum(Enum.Font.IndieFlower),
}

Theme.Tween = {
	Fast = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Normal = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
	Slow = TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
	Cinematic = TweenInfo.new(2.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
}

return Theme
