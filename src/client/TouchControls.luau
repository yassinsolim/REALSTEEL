--!strict

-- On-screen controls for touch: a movement stick, four action buttons, and small training buttons. They drive the same
-- actions as every other device through the Scriptable bindings, so prediction and replication need no special case.

local UserInputService = game:GetService("UserInputService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InputSetup = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("InputSetup"))

export type TouchControls = {
	setVisible: (visible: boolean) -> (),
	-- DUMMY and RESET only make sense in training.
	setTrainingVisible: (visible: boolean) -> (),
	-- MENU opens the menu, so it stays available while you are the only human playing.
	setModeVisible: (visible: boolean) -> (),
}

type ButtonSpec = {
	name: string,
	text: string,
	color: Color3,
	position: UDim2,
	size: number,
	binding: InputBinding,
}

local TouchControls = {}

-- Drag distance in pixels for full stick deflection, and the fraction of it ignored as a dead zone.
local STICK_AREA_WIDTH = 240
local STICK_RADIUS = 60
local DEAD_ZONE = 0.2
local BUTTON_SIZE = 68
local SMALL_SIZE = 56
local BUTTON_GAP = 10
local MARGIN = 16

-- Screen width taken by the stick on the left and the attack cluster with its guard and dash buttons on the right.
-- Overlays that live between them, like the training panel, fit into what is left.
TouchControls.reservedWidth = (MARGIN + STICK_AREA_WIDTH)
	+ (MARGIN + BUTTON_SIZE * 2 + BUTTON_GAP + BUTTON_GAP + SMALL_SIZE)
	+ 8

local function isPointer(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1
end

-- Touches are matched by object, mouse buttons by type.
local function sameInput(a: InputObject, b: InputObject): boolean
	if a.UserInputType == Enum.UserInputType.Touch then
		return a == b
	end
	return a.UserInputType == b.UserInputType
end

local function round(instance: GuiObject)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = instance
end

local function createStick(parent: Instance, binding: InputBinding): (Frame, () -> ())
	local area = Instance.new("Frame")
	area.Name = "Stick"
	area.Size = UDim2.fromOffset(STICK_AREA_WIDTH, 230)
	area.AnchorPoint = Vector2.new(0, 1)
	area.Position = UDim2.new(0, MARGIN, 1, -MARGIN)
	area.BackgroundTransparency = 1
	area.Active = true
	area.Parent = parent

	local base = Instance.new("Frame")
	base.Name = "Base"
	base.Size = UDim2.fromOffset(130, 130)
	base.AnchorPoint = Vector2.new(0.5, 0.5)
	base.Position = UDim2.fromOffset(120, 140)
	base.BackgroundColor3 = Color3.new(1, 1, 1)
	base.BackgroundTransparency = 0.82
	base.BorderSizePixel = 0
	base.Parent = area
	round(base)

	local knob = Instance.new("Frame")
	knob.Name = "Knob"
	knob.Size = UDim2.fromOffset(58, 58)
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Position = UDim2.fromScale(0.5, 0.5)
	knob.BackgroundColor3 = Color3.new(1, 1, 1)
	knob.BackgroundTransparency = 0.35
	knob.BorderSizePixel = 0
	knob.Parent = base
	round(knob)

	local active: InputObject? = nil
	local origin = Vector2.zero

	local function apply(position: Vector3)
		local delta = (Vector2.new(position.X, position.Y) - origin) / STICK_RADIUS
		if delta.Magnitude > 1 then
			delta = delta.Unit
		end
		-- Screen y grows downward; forward is up.
		local output = if delta.Magnitude < DEAD_ZONE then Vector2.zero else Vector2.new(delta.X, -delta.Y)
		binding:Fire(output)
		knob.Position = UDim2.new(0.5, delta.X * 45, 0.5, delta.Y * 45)
	end

	local function release()
		active = nil
		binding:Fire(Vector2.zero)
		knob.Position = UDim2.fromScale(0.5, 0.5)
	end

	area.InputBegan:Connect(function(input: InputObject)
		if active ~= nil or not isPointer(input) then
			return
		end
		active = input
		origin = Vector2.new(input.Position.X, input.Position.Y)
		apply(input.Position)
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject)
		local current = active
		if current == nil then
			return
		end
		local moved = input.UserInputType == Enum.UserInputType.Touch and input == current
			or input.UserInputType == Enum.UserInputType.MouseMovement
				and current.UserInputType == Enum.UserInputType.MouseButton1
		if moved then
			apply(input.Position)
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		local current = active
		if current ~= nil and sameInput(input, current) then
			release()
		end
	end)

	return area, release
end

local function createButton(
	parent: Instance,
	name: string,
	text: string,
	color: Color3,
	position: UDim2,
	size: number,
	binding: InputBinding
): (TextButton, () -> ())
	local button = Instance.new("TextButton")
	button.Name = name
	button.Size = UDim2.fromOffset(size, size)
	button.Position = position
	button.AutoButtonColor = false
	button.BackgroundColor3 = color
	button.BackgroundTransparency = 0.45
	button.BorderSizePixel = 0
	button.Text = text
	button.TextColor3 = Color3.new(1, 1, 1)
	button.Font = Enum.Font.GothamBold
	button.TextSize = 11
	button.TextWrapped = true
	button.Parent = parent
	round(button)

	local pressed: InputObject? = nil
	local function release()
		pressed = nil
		binding:Fire(false)
		button.BackgroundTransparency = 0.45
	end

	button.InputBegan:Connect(function(input: InputObject)
		if pressed ~= nil or not isPointer(input) then
			return
		end
		pressed = input
		binding:Fire(true)
		button.BackgroundTransparency = 0.1
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		local current = pressed
		if current ~= nil and sameInput(input, current) then
			release()
		end
	end)
	return button, release
end

-- Training actions only need a short press; the server reads their state on its next frames.
local function createTapButton(
	parent: Instance,
	name: string,
	text: string,
	order: number,
	binding: InputBinding
): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Size = UDim2.fromOffset(52, 24)
	button.Position = UDim2.fromOffset(0, (order - 1) * 28)
	button.AutoButtonColor = true
	button.BackgroundColor3 = Color3.fromRGB(30, 34, 44)
	button.BackgroundTransparency = 0.2
	button.BorderSizePixel = 0
	button.Text = text
	button.TextColor3 = Color3.new(1, 1, 1)
	button.Font = Enum.Font.GothamBold
	button.TextSize = 11
	button.Parent = parent
	button.Activated:Connect(function()
		binding:Fire(true)
		task.wait(0.15)
		binding:Fire(false)
	end)
	return button
end

function TouchControls.new(gui: ScreenGui, scripted: InputSetup.Scripted): TouchControls
	local root = Instance.new("Frame")
	root.Name = "TouchControls"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.Visible = false
	root.Parent = gui

	local _, releaseStick = createStick(root, scripted.move)

	local cluster = Instance.new("Frame")
	cluster.Name = "Buttons"
	local clusterSize = BUTTON_SIZE * 2 + BUTTON_GAP
	cluster.Size = UDim2.fromOffset(clusterSize, clusterSize)
	cluster.AnchorPoint = Vector2.new(1, 1)
	cluster.Position = UDim2.new(1, -MARGIN, 1, -MARGIN)
	cluster.BackgroundTransparency = 1
	cluster.Parent = root

	-- The four limbs sit where they are on the body: punches on top, kicks below, left limbs on the left. Guard and
	-- dash are smaller buttons beside the cluster, in easy reach of the same thumb.
	local far = BUTTON_SIZE + BUTTON_GAP
	local sideX = -(SMALL_SIZE + BUTTON_GAP)
	local sideY = clusterSize - SMALL_SIZE
	local releases: { () -> () } = { releaseStick }
	local specs: { ButtonSpec } = {
		{
			name = "Jab",
			text = "JAB",
			color = Color3.fromRGB(70, 140, 255),
			position = UDim2.fromOffset(0, 0),
			size = BUTTON_SIZE,
			binding = scripted.jab,
		},
		{
			name = "Straight",
			text = "STRAIGHT",
			color = Color3.fromRGB(255, 84, 70),
			position = UDim2.fromOffset(far, 0),
			size = BUTTON_SIZE,
			binding = scripted.straight,
		},
		{
			name = "SnapKick",
			text = "SNAP\nKICK",
			color = Color3.fromRGB(40, 175, 150),
			position = UDim2.fromOffset(0, far),
			size = BUTTON_SIZE,
			binding = scripted.leftKick,
		},
		{
			name = "PowerKick",
			text = "POWER\nKICK",
			color = Color3.fromRGB(240, 150, 40),
			position = UDim2.fromOffset(far, far),
			size = BUTTON_SIZE,
			binding = scripted.rightKick,
		},
		{
			name = "Guard",
			text = "GUARD",
			color = Color3.fromRGB(205, 205, 220),
			position = UDim2.fromOffset(sideX, sideY),
			size = SMALL_SIZE,
			binding = scripted.guard,
		},
		{
			name = "Dash",
			text = "DASH",
			color = Color3.fromRGB(170, 110, 230),
			position = UDim2.fromOffset(sideX, sideY - SMALL_SIZE - BUTTON_GAP),
			size = SMALL_SIZE,
			binding = scripted.dash,
		},
	}
	for _, spec in specs do
		local _, release =
			createButton(cluster, spec.name, spec.text, spec.color, spec.position, spec.size, spec.binding)
		table.insert(releases, release)
	end

	-- A column at the left edge, under the health bar and clear of the fighters and the stick.
	local training = Instance.new("Frame")
	training.Name = "Training"
	training.Size = UDim2.fromOffset(52, 80)
	training.Position = UDim2.fromOffset(MARGIN, 88)
	training.BackgroundTransparency = 1
	training.Parent = root
	local modeButton = createTapButton(training, "Toggle", "MENU", 1, scripted.toggle)
	local nextButton = createTapButton(training, "Next", "DUMMY", 2, scripted.next)
	local resetButton = createTapButton(training, "Reset", "RESET", 3, scripted.reset)
	nextButton.Visible = false
	resetButton.Visible = false
	modeButton.Visible = false

	return {
		setVisible = function(visible: boolean)
			root.Visible = visible
			if not visible then
				for _, release in releases do
					release()
				end
			end
		end,
		setTrainingVisible = function(visible: boolean)
			nextButton.Visible = visible
			resetButton.Visible = visible
		end,
		setModeVisible = function(visible: boolean)
			modeButton.Visible = visible
		end,
	}
end

return TouchControls
