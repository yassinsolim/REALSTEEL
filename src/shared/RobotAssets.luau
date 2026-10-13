--!strict

export type Entry = { Id: number }

-- Roblox asset IDs of the uploaded robot models, one for each frame in RobotRigs (the free frames and the premium bodies).
-- scripts/upload-robot.ps1 writes them. An ID of 0 means the model is not uploaded yet, and the game draws a blockout robot
-- from the rig's part sizes instead.
local assets: { [string]: Entry } = {
	Anvil = { Id = 129839614787002 },
	Bulwark = { Id = 137479817799167 },
	Lance = { Id = 108908538179424 },
	Razor = { Id = 130853626050404 },
	Maul = { Id = 125438959191514 },
	Monarch = { Id = 137648048729760 },
}

return assets
