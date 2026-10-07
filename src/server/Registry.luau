--[[
	Registry
	Late-bound service table. Services reference each other through it inside
	functions (never at require time), which avoids circular requires.
]]

return {}
