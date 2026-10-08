--[[
	Scene07_FinalWarning  (≈9.6 s)
	Black. 3 DAYS.  YOU SHOULD NOT BE HERE.  DON'T LOOK AWAY.
	(Edit MarketingConfig.Text.Countdown for each day of the campaign.)
]]

return {
	Name = "Scene07_FinalWarning",
	Description = "Countdown card",
	Duration = 9.6,
	Build = function(_L, Config)
		return {
			{ at = 0, action = "Backdrop", on = true },
			{ at = 0, action = "PlayAmbience", sound = "AmbientDrone", volume = 0.5, fadeIn = 1 },
			{ at = 0.8, action = "ShowText", id = "count", text = Config.Text.Countdown, style = "title", size = 0.06, fadeIn = 0.25, duration = 2.1 },
			{ at = 0.8, action = "PlaySound", sound = "TitleHit", volume = 0.8 },
			{ at = 3.6, action = "ShowText", id = "warn", text = "YOU SHOULD NOT BE HERE.", style = "whisper", size = 0.03, fadeIn = 0.6, duration = 2.3, glitch = 0.03 },
			{ at = 3.6, action = "PlaySound", sound = "Whisper", volume = 0.25 },
			{ at = 6.2, action = "Glitch", duration = 0.22, intensity = 0.6 },
			{ at = 6.6, action = "ShowText", id = "title", text = Config.Text.Title, style = "title", size = 0.05, fadeIn = 0.7, duration = 2.5, tracking = { from = 2, to = 16 } },
			{ at = 6.6, action = "PlaySound", sound = "TitleHit", volume = 0.6, speed = 0.8 },
		}
	end,
}
