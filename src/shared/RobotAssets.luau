--!strict

export type Entry = { Id: number }

-- Roblox asset IDs of the uploaded robot models. scripts/upload-robot.ps1 writes them. An ID of 0 means the model is not
-- uploaded yet, and the game draws a blockout robot from the rig's part sizes instead.
local assets: { [string]: Entry } = {
	Anvil = { Id = 129839614787002 },
}

return assets
