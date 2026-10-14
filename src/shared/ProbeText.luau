--!strict

-- Text for the owner's connection probe (see NetProbe on the client and on the server): one player's input contexts
-- with every action's state, and one character's physics and humanoid state, as either side sees them.

local RunService = game:GetService("RunService")

local ProbeText = {}

function ProbeText.value(value: unknown): string
	if typeof(value) == "Vector3" then
		local vector = value :: Vector3
		return string.format("(%.2f,%.2f,%.2f)", vector.X, vector.Y, vector.Z)
	elseif typeof(value) == "Vector2" then
		local vector = value :: Vector2
		return string.format("(%.2f,%.2f)", vector.X, vector.Y)
	elseif type(value) == "number" then
		return string.format("%.2f", value)
	end
	return tostring(value)
end

-- Every input context under the player: on or OFF, its priority, whether it sinks, and each action's state.
function ProbeText.inputs(player: Player): string
	local out = {}
	for _, item in player:GetDescendants() do
		if item:IsA("InputContext") then
			local context = item :: any
			local actions = {}
			for _, child in item:GetChildren() do
				if child:IsA("InputAction") then
					local action = child :: any
					local ok, state = pcall(function()
						return action:GetState()
					end)
					table.insert(
						actions,
						string.format(
							"%s%s=%s",
							child.Name,
							if action.Enabled then "" else "(off)",
							if ok then ProbeText.value(state) else "?"
						)
					)
				end
			end
			table.insert(
				out,
				string.format(
					"%s[%s p%s%s]{%s}",
					item.Name,
					if context.Enabled then "on" else "OFF",
					tostring(context.Priority),
					if context.Sink then " sink" else "",
					table.concat(actions, " ")
				)
			)
		end
	end
	return if #out > 0 then table.concat(out, " ") else "no input contexts"
end

-- The character's root and humanoid: where it is, whether anything holds it, and what the humanoid is doing.
function ProbeText.character(character: Model?): string
	if character == nil then
		return "no character"
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if root == nil or not root:IsA("BasePart") or humanoid == nil then
		return "character without root or humanoid"
	end
	local predicted = "?"
	pcall(function()
		predicted = (RunService :: any):GetPredictionStatus(root).Name
	end)
	return string.format(
		"root %s anchored %s velocity %s prediction %s | %s walk %.1f move %s floor %s platform %s sit %s health %.0f",
		ProbeText.value(root.Position),
		tostring(root.Anchored),
		ProbeText.value(root.AssemblyLinearVelocity),
		predicted,
		humanoid:GetState().Name,
		humanoid.WalkSpeed,
		ProbeText.value(humanoid.MoveDirection),
		humanoid.FloorMaterial.Name,
		tostring(humanoid.PlatformStand),
		tostring(humanoid.Sit),
		humanoid.Health
	)
end

return ProbeText
