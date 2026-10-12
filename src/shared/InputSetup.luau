--!strict

-- Builds the per-player input contexts. Created at runtime on the server so they replicate under the Player, which is
-- what the server authority system needs to attribute and replay inputs.
--
-- Every action also gets a Scriptable binding named "Scripted". Touch controls and automated tests drive actions
-- through it with InputBinding:Fire, which the engine treats like hardware input (InputAction:Fire is deprecated).

export type Actions = {
	move: InputAction,
	jab: InputAction,
	straight: InputAction,
	leftKick: InputAction,
	rightKick: InputAction,
	guard: InputAction,
	dash: InputAction,
}

export type TrainingActions = {
	next: InputAction,
	reset: InputAction,
	toggle: InputAction,
}

export type Scripted = {
	move: InputBinding,
	jab: InputBinding,
	straight: InputBinding,
	leftKick: InputBinding,
	rightKick: InputBinding,
	guard: InputBinding,
	dash: InputBinding,
	next: InputBinding,
	reset: InputBinding,
	toggle: InputBinding,
}

local InputSetup = {}

local function addAction(context: InputContext, name: string, actionType: Enum.InputActionType): InputAction
	local action = Instance.new("InputAction")
	action.Name = name
	action.Type = actionType
	action.Parent = context

	local scripted = Instance.new("InputBinding")
	scripted.Name = "Scripted"
	scripted.Type = Enum.InputBindingType.Scriptable
	scripted.Parent = action
	return action
end

local function addBinding(action: InputAction, name: string, key: Enum.KeyCode)
	local binding = Instance.new("InputBinding")
	binding.Name = name
	binding.KeyCode = key
	binding.Parent = action
end

function InputSetup.build(player: Player)
	local fight = Instance.new("InputContext")
	fight.Name = "FightInputs"

	-- Reads as a screen-style vector (x right, y up). FightSim.moveFromStick turns it into walking and sidestepping.
	local move = addAction(fight, "Move", Enum.InputActionType.Direction2D)
	local keyboard = Instance.new("InputBinding")
	keyboard.Name = "Keyboard"
	keyboard.Up = Enum.KeyCode.W
	keyboard.Down = Enum.KeyCode.S
	keyboard.Left = Enum.KeyCode.A
	keyboard.Right = Enum.KeyCode.D
	keyboard.Parent = move
	addBinding(move, "Gamepad", Enum.KeyCode.Thumbstick1)

	local jab = addAction(fight, "Jab", Enum.InputActionType.Bool)
	addBinding(jab, "Mouse", Enum.KeyCode.MouseLeftButton)
	addBinding(jab, "Keyboard", Enum.KeyCode.J)
	addBinding(jab, "Gamepad", Enum.KeyCode.ButtonX)

	local straight = addAction(fight, "Straight", Enum.InputActionType.Bool)
	addBinding(straight, "Mouse", Enum.KeyCode.MouseRightButton)
	addBinding(straight, "Keyboard", Enum.KeyCode.K)
	addBinding(straight, "Gamepad", Enum.KeyCode.ButtonY)

	-- Left punch, right punch, left kick, right kick: the four limbs sit on the left and right of both the mouse and
	-- the J K / U I keys, and on the gamepad's X Y / A B face buttons.
	local leftKick = addAction(fight, "LeftKick", Enum.InputActionType.Bool)
	addBinding(leftKick, "Keyboard", Enum.KeyCode.Q)
	addBinding(leftKick, "KeyboardRight", Enum.KeyCode.U)
	addBinding(leftKick, "Gamepad", Enum.KeyCode.ButtonA)

	local rightKick = addAction(fight, "RightKick", Enum.InputActionType.Bool)
	addBinding(rightKick, "Keyboard", Enum.KeyCode.E)
	addBinding(rightKick, "KeyboardRight", Enum.KeyCode.I)
	addBinding(rightKick, "Gamepad", Enum.KeyCode.ButtonB)

	local guard = addAction(fight, "Guard", Enum.InputActionType.Bool)
	addBinding(guard, "Keyboard", Enum.KeyCode.LeftShift)
	addBinding(guard, "GamepadBumper", Enum.KeyCode.ButtonL1)
	addBinding(guard, "GamepadTrigger", Enum.KeyCode.ButtonL2)

	local dash = addAction(fight, "Dash", Enum.InputActionType.Bool)
	addBinding(dash, "Keyboard", Enum.KeyCode.Space)
	addBinding(dash, "GamepadBumper", Enum.KeyCode.ButtonR1)
	addBinding(dash, "GamepadTrigger", Enum.KeyCode.ButtonR2)

	fight.Parent = player

	local training = Instance.new("InputContext")
	training.Name = "TrainingInputs"
	addBinding(addAction(training, "Next", Enum.InputActionType.Bool), "Keyboard", Enum.KeyCode.T)
	addBinding(addAction(training, "Reset", Enum.InputActionType.Bool), "Keyboard", Enum.KeyCode.R)
	-- Toggle opens the menu.
	local toggle = addAction(training, "Toggle", Enum.InputActionType.Bool)
	addBinding(toggle, "Keyboard", Enum.KeyCode.M)
	addBinding(toggle, "Gamepad", Enum.KeyCode.ButtonSelect)
	training.Parent = player
end

local function findAction(context: Instance, name: string): InputAction?
	local child = context:FindFirstChild(name)
	if child ~= nil and child:IsA("InputAction") then
		return child
	end
	return nil
end

local function findScriptedBinding(context: Instance, name: string): InputBinding?
	local action = findAction(context, name)
	if action == nil then
		return nil
	end
	local child = action:FindFirstChild("Scripted")
	if child ~= nil and child:IsA("InputBinding") then
		return child
	end
	return nil
end

-- Looks up a player's fight actions; both sides use this so they read the same instances.
function InputSetup.find(player: Player): Actions?
	local context = player:FindFirstChild("FightInputs")
	if context == nil then
		return nil
	end
	local move = findAction(context, "Move")
	local jab = findAction(context, "Jab")
	local straight = findAction(context, "Straight")
	local leftKick = findAction(context, "LeftKick")
	local rightKick = findAction(context, "RightKick")
	local guard = findAction(context, "Guard")
	local dash = findAction(context, "Dash")
	if
		move == nil
		or jab == nil
		or straight == nil
		or leftKick == nil
		or rightKick == nil
		or guard == nil
		or dash == nil
	then
		return nil
	end
	return {
		move = move,
		jab = jab,
		straight = straight,
		leftKick = leftKick,
		rightKick = rightKick,
		guard = guard,
		dash = dash,
	}
end

function InputSetup.findTraining(player: Player): TrainingActions?
	local context = player:FindFirstChild("TrainingInputs")
	if context == nil then
		return nil
	end
	local next = findAction(context, "Next")
	local reset = findAction(context, "Reset")
	local toggle = findAction(context, "Toggle")
	if next == nil or reset == nil or toggle == nil then
		return nil
	end
	return { next = next, reset = reset, toggle = toggle }
end

-- The Scriptable bindings used to drive the local player's actions from UI or tests.
function InputSetup.findScripted(player: Player): Scripted?
	local fight = player:FindFirstChild("FightInputs")
	local training = player:FindFirstChild("TrainingInputs")
	if fight == nil or training == nil then
		return nil
	end
	local move = findScriptedBinding(fight, "Move")
	local jab = findScriptedBinding(fight, "Jab")
	local straight = findScriptedBinding(fight, "Straight")
	local leftKick = findScriptedBinding(fight, "LeftKick")
	local rightKick = findScriptedBinding(fight, "RightKick")
	local guard = findScriptedBinding(fight, "Guard")
	local dash = findScriptedBinding(fight, "Dash")
	local next = findScriptedBinding(training, "Next")
	local reset = findScriptedBinding(training, "Reset")
	local toggle = findScriptedBinding(training, "Toggle")
	if
		move == nil
		or jab == nil
		or straight == nil
		or leftKick == nil
		or rightKick == nil
		or guard == nil
		or dash == nil
		or next == nil
		or reset == nil
		or toggle == nil
	then
		return nil
	end
	return {
		move = move,
		jab = jab,
		straight = straight,
		leftKick = leftKick,
		rightKick = rightKick,
		guard = guard,
		dash = dash,
		next = next,
		reset = reset,
		toggle = toggle,
	}
end

return InputSetup
