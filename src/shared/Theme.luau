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
	Warning = Color3.fromRGB(214, 190, 140), -- a caution, not yet danger
	Lost = Color3.fromRGB(196, 170, 166), -- the title of an ending nobody walked away from
	-- paper in the world's hands: notes, documents, the archive
	Paper = Color3.fromRGB(214, 206, 184),
	PaperShade = Color3.fromRGB(205, 196, 176),
	Ink = Color3.fromRGB(34, 30, 26),
	InkFaint = Color3.fromRGB(90, 84, 76),
	Archive = Color3.fromRGB(196, 178, 140),
	-- devices: the keypad and the readouts of the field tools
	Device = Color3.fromRGB(34, 36, 38),
	DeviceEdge = Color3.fromRGB(70, 72, 74),
	Key = Color3.fromRGB(176, 176, 170),
	KeyOk = Color3.fromRGB(170, 196, 170),
	KeyClear = Color3.fromRGB(196, 170, 160),
	KeyInk = Color3.fromRGB(20, 20, 20),
	LcdBack = Color3.fromRGB(20, 32, 26),
	Lcd = Color3.fromRGB(150, 230, 170),
}

-- an LCD's "wrong" is the danger red, lit
Theme.Colors.LcdError = Theme.Colors.Danger:Lerp(Color3.new(1, 1, 1), 0.4)

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
