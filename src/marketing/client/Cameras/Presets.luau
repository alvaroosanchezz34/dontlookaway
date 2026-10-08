--[[
	Camera presets: the "lens and operator" of a shot. A shot picks one; the
	panel can force one on every shot (Camera: AUTO uses each shot's own).

	fov        vertical field of view
	handheld   operator sway: position (studs) and rotation (degrees)
	freq       sway speed
	breathe    a slow drift even on a tripod (studs)
	overlay    "cctv" draws the security-camera overlay and grade
	fps        stepped motion (security cameras record at a low frame rate)
]]

return {
	CCTV = { fov = 78, handheld = 0, rot = 0, freq = 0, breathe = 0, overlay = "cctv", fps = 12 },
	STATIC = { fov = 60, handheld = 0, rot = 0, freq = 0, breathe = 0 },
	HANDHELD = { fov = 68, handheld = 0.05, rot = 0.7, freq = 0.9, breathe = 0.02 },
	FIRST_PERSON = { fov = 70, handheld = 0.03, rot = 0.45, freq = 1.4, breathe = 0.015, bob = true },
	CINEMATIC = { fov = 50, handheld = 0.008, rot = 0.12, freq = 0.35, breathe = 0.01 },
	CLOSE_UP = { fov = 32, handheld = 0.006, rot = 0.15, freq = 0.4, breathe = 0.006 },
	EYE_CLOSEUP = { fov = 20, handheld = 0.004, rot = 0.1, freq = 0.3, breathe = 0.004 },
	DOOR_SHOT = { fov = 55, handheld = 0.003, rot = 0.05, freq = 0.25, breathe = 0.006 },
	HALLWAY = { fov = 64, handheld = 0.012, rot = 0.2, freq = 0.5, breathe = 0.01 },
}
