--[[
	Format
	Social aspect ratios. Roblox cannot change the window size, so the scene is
	framed inside a centred "safe frame" with black bars around it: record the
	window (or crop OBS to the safe frame) and the clip is already composed.
	The vertical camera field of view is kept, so a 9:16 crop of a 16:9 window
	frames exactly what the shot was designed for.
]]

local Format = {}

Format.Presets = {
	SOCIAL_VERTICAL = { label = "9:16", aspect = 9 / 16, note = "TikTok · Shorts · Reels (1080x1920)" },
	SOCIAL_HORIZONTAL = { label = "16:9", aspect = 16 / 9, note = "YouTube · trailers (1920x1080)" },
	SQUARE = { label = "1:1", aspect = 1, note = "feed posts (1080x1080)" },
}
Format.Order = { "SOCIAL_VERTICAL", "SOCIAL_HORIZONTAL", "SQUARE" }

-- Safe frame (position, size) in pixels for a viewport.
function Format.safeRect(name: string, viewport: Vector2): (Vector2, Vector2)
	local preset = Format.Presets[name] or Format.Presets.SOCIAL_VERTICAL
	local vw, vh = math.max(viewport.X, 1), math.max(viewport.Y, 1)
	local w, h
	if vw / vh > preset.aspect then
		h = vh
		w = vh * preset.aspect
	else
		w = vw
		h = vw / preset.aspect
	end
	return Vector2.new((vw - w) / 2, (vh - h) / 2), Vector2.new(w, h)
end

return Format
