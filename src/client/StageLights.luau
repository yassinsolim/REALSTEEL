--!strict

-- Client-only lights that follow the fight. Future lighting is physically based, so a few lights close to the action do
-- more than a rig of fixed ones: a key light above the pair that casts the shadows, a rim light behind each fighter in
-- its team color, and a soft fill at the camera so the side the player sees is never black.
--
-- Strength is easy to get wrong: a light's reach falls off with the square of the distance, and a mid-gray robot goes
-- from black to white over about a factor of four. Devices that cannot run Future lighting fall back to ShadowMap, which
-- needs about 1.5 where Future wants about 4 for the same look, and a script cannot tell which one is running. The
-- numbers below are a compromise: a little dark in Future, a little bright in the fallback, good enough in both.

local Workspace = game:GetService("Workspace")

export type StageLights = {
	folder: Folder,
	key: Part,
	rims: { Part },
	fill: Part,
}

local StageLights = {}

local KEY_COLOR = Color3.fromRGB(255, 242, 228)
local KEY_HEIGHT = 17
local KEY_BRIGHTNESS = 2.6
local KEY_ANGLE = 70
local RIM_BACK = 5.5
local RIM_HEIGHT = 8.5
local RIM_AIM_HEIGHT = 3.4
local RIM_BRIGHTNESS = 3
local FILL_COLOR = Color3.fromRGB(190, 205, 255)
local FILL_BRIGHTNESS = 1.1

local function lightPart(parent: Instance, name: string, light: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.one * 0.2
	part.Parent = parent
	light.Parent = part
	return part
end

local function spot(color: Color3, angle: number, brightness: number, range: number, shadows: boolean): SpotLight
	local light = Instance.new("SpotLight")
	light.Face = Enum.NormalId.Front
	light.Color = color
	light.Angle = angle
	light.Brightness = brightness
	light.Range = range
	light.Shadows = shadows
	return light
end

-- `accents` are the fighters' team colors, in slot order.
function StageLights.new(accents: { Color3 }): StageLights
	local folder = Instance.new("Folder")
	folder.Name = "StageLights"
	folder.Parent = Workspace

	local key = lightPart(folder, "Key", spot(KEY_COLOR, KEY_ANGLE, KEY_BRIGHTNESS, 36, true))
	local rims: { Part } = {}
	for index, accent in accents do
		local color = accent:Lerp(Color3.new(1, 1, 1), 0.12)
		rims[index] = lightPart(folder, "Rim" .. index, spot(color, 55, RIM_BRIGHTNESS, 24, false))
	end

	local fillLight = Instance.new("PointLight")
	fillLight.Color = FILL_COLOR
	fillLight.Brightness = FILL_BRIGHTNESS
	fillLight.Range = 32
	fillLight.Shadows = false
	local fill = lightPart(folder, "Fill", fillLight)

	return { folder = folder, key = key, rims = rims, fill = fill }
end

-- Recolors a fighter's rim light, for when the team colors change sides.
function StageLights.setAccent(self: StageLights, slot: number, accent: Color3)
	local rim: Part? = self.rims[slot]
	if rim ~= nil then
		local light = rim:FindFirstChildOfClass("SpotLight")
		if light ~= nil then
			light.Color = accent:Lerp(Color3.new(1, 1, 1), 0.12)
		end
	end
end

-- `positions` are where the fighters are drawn (on the canvas), in slot order.
function StageLights.update(self: StageLights, positions: { Vector3 }, cameraPosition: Vector3)
	local middle = (positions[1] + positions[2]) / 2
	-- Straight down, so the "up" of the light is chosen sideways.
	self.key.CFrame = CFrame.lookAt(middle + Vector3.new(0, KEY_HEIGHT, 0), middle, Vector3.xAxis)

	for index, rim in self.rims do
		local me = positions[index]
		local foe = positions[3 - index]
		local away = Vector3.new(me.X - foe.X, 0, me.Z - foe.Z)
		if away.Magnitude > 1e-3 then
			away = away.Unit
		else
			away = Vector3.xAxis * (if index == 1 then -1 else 1)
		end
		local at = me + away * RIM_BACK + Vector3.new(0, RIM_HEIGHT, 0)
		rim.CFrame = CFrame.lookAt(at, me + Vector3.new(0, RIM_AIM_HEIGHT, 0))
	end

	self.fill.Position = cameraPosition + Vector3.new(0, 1, 0)
end

return StageLights
