--!strict

-- Loads the uploaded robot models once at server start and shares them with clients as ReplicatedStorage.Robots. The
-- folder is created even when nothing loads, so clients know when to stop waiting and fall back to blockout robots.

local AssetService = game:GetService("AssetService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RobotAssets = require(ReplicatedStorage.Shared.RobotAssets)

local RobotLibrary = {}

local function load(name: string, id: number): Folder?
	local loaded, model = pcall(function()
		return AssetService:LoadAssetAsync(id)
	end)
	if not loaded or typeof(model) ~= "Instance" then
		warn(
			string.format(
				"[REALSTEEL] Robot %s (asset %d) did not load, using a blockout: %s",
				name,
				id,
				tostring(model)
			)
		)
		return nil
	end

	local template = Instance.new("Folder")
	template.Name = name
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("MeshPart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant:ClearAllChildren()
			descendant.Parent = template
		end
	end
	model:Destroy()
	if #template:GetChildren() == 0 then
		warn(string.format("[REALSTEEL] Robot %s (asset %d) has no meshes, using a blockout", name, id))
		template:Destroy()
		return nil
	end
	return template
end

-- Yields while the models download.
function RobotLibrary.preload()
	local folder = Instance.new("Folder")
	folder.Name = "Robots"
	for name, entry in RobotAssets do
		if entry.Id > 0 then
			local template = load(name, entry.Id)
			if template ~= nil then
				template.Parent = folder
			end
		end
	end
	folder.Parent = ReplicatedStorage
end

return RobotLibrary
