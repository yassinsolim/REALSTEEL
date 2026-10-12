--!strict

-- Training overlay: frame data for the last move, the measured result of the last exchange, and a frame meter.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FightSim = require(Shared:WaitForChild("FightSim"))
local FrameData = require(Shared:WaitForChild("FrameData"))
local TouchControls = require(script.Parent:WaitForChild("TouchControls"))

export type Args = {
	history: FrameData.History,
	mySlot: number,
	training: boolean,
	compact: boolean,
	dummyMode: number,
	me: FightSim.Fighter,
	foe: FightSim.Fighter,
	debugLine: string,
}

export type TrainingHud = {
	update: (args: Args) -> (),
	-- The frame data and meter are tucked away until asked for; the status line under the VS plate is always there.
	setDetail: (visible: boolean) -> (),
}

local TrainingHud = {}

local CELLS = 60
local CELL_GAP = 1
local ROW_HEIGHT = 12
local PANEL_COLOR = Color3.fromRGB(8, 10, 18)
local ACCENT = Color3.fromRGB(64, 214, 232)

local COLORS: { [string]: Color3 } = {
	idle = Color3.fromRGB(58, 60, 68),
	guard = Color3.fromRGB(232, 232, 240),
	blockstun = Color3.fromRGB(255, 150, 40),
	hitstun = Color3.fromRGB(255, 220, 60),
	startup = Color3.fromRGB(90, 200, 110),
	active = Color3.fromRGB(235, 70, 70),
	recovery = Color3.fromRGB(80, 130, 235),
	dash = Color3.fromRGB(170, 110, 230),
	ko = Color3.fromRGB(10, 10, 10),
}

local LEGEND_ORDER = { "idle", "guard", "startup", "active", "recovery", "dash", "hitstun", "blockstun" }

local DUMMY_NAMES = { "Idle", "Guard", "Jab loop", "Straight loop", "Mixed", "Snap kick loop", "Power kick loop" }

local function signed(value: number): string
	return if value > 0 then "+" .. value else tostring(value)
end

local function legendText(): string
	local parts = {}
	for _, kind in LEGEND_ORDER do
		table.insert(parts, `<font color="#{COLORS[kind]:ToHex()}">{kind}</font>`)
	end
	return table.concat(parts, "  ")
end

function TrainingHud.new(parent: ScreenGui, onToggleDetail: () -> ()): TrainingHud
	-- A status line under the VS plate. Tapping or clicking it opens the frame data, which works on touch too.
	local pill = Instance.new("TextButton")
	pill.Name = "TrainingPill"
	pill.AnchorPoint = Vector2.new(0.5, 0)
	pill.Position = UDim2.new(0.5, 0, 0, 58)
	pill.Size = UDim2.fromOffset(0, 22)
	pill.AutomaticSize = Enum.AutomaticSize.X
	pill.BackgroundColor3 = PANEL_COLOR
	pill.BackgroundTransparency = 0.15
	pill.BorderSizePixel = 0
	pill.AutoButtonColor = false
	pill.TextColor3 = Color3.fromRGB(205, 214, 230)
	pill.Font = Enum.Font.GothamMedium
	pill.TextSize = 12
	pill.RichText = true
	pill.Parent = parent
	local pillCorner = Instance.new("UICorner")
	pillCorner.CornerRadius = UDim.new(0, 11)
	pillCorner.Parent = pill
	local pillStroke = Instance.new("UIStroke")
	pillStroke.Color = ACCENT
	pillStroke.Thickness = 1
	pillStroke.Transparency = 0.55
	pillStroke.Parent = pill
	local pillPadding = Instance.new("UIPadding")
	pillPadding.PaddingLeft = UDim.new(0, 12)
	pillPadding.PaddingRight = UDim.new(0, 12)
	pillPadding.Parent = pill
	pill.Activated:Connect(onToggleDetail)

	-- Both live along the bottom edge, below the fighters' feet.
	local panel = Instance.new("TextLabel")
	panel.Name = "TrainingPanel"
	panel.AnchorPoint = Vector2.new(0.5, 1)
	panel.BackgroundColor3 = PANEL_COLOR
	panel.BackgroundTransparency = 0.2
	panel.BorderSizePixel = 0
	panel.TextColor3 = Color3.fromRGB(214, 222, 236)
	panel.Font = Enum.Font.Code
	panel.TextXAlignment = Enum.TextXAlignment.Left
	panel.TextYAlignment = Enum.TextYAlignment.Top
	panel.RichText = true
	panel.Parent = parent
	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 6)
	panelCorner.Parent = panel
	local panelPadding = Instance.new("UIPadding")
	panelPadding.PaddingLeft = UDim.new(0, 8)
	panelPadding.PaddingTop = UDim.new(0, 5)
	panelPadding.Parent = panel
	local detail = false

	local meter = Instance.new("Frame")
	meter.Name = "FrameMeter"
	meter.AnchorPoint = Vector2.new(0.5, 1)
	meter.BackgroundTransparency = 1
	meter.Parent = parent

	local labels: { TextLabel } = {}
	local cells: { { Frame } } = {}
	local shown: { { string } } = {}
	for row = 1, 2 do
		local name = Instance.new("TextLabel")
		name.Name = "RowLabel" .. row
		name.BackgroundTransparency = 1
		name.Text = if row == 1 then "YOU" else "OPP"
		name.TextColor3 = Color3.new(1, 1, 1)
		name.Font = Enum.Font.Code
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.Parent = meter
		labels[row] = name

		cells[row] = {}
		shown[row] = {}
		for index = 1, CELLS do
			local cell = Instance.new("Frame")
			cell.Name = "Cell" .. index
			cell.BackgroundColor3 = COLORS.idle
			cell.BorderSizePixel = 0
			cell.Parent = meter
			cells[row][index] = cell
			shown[row][index] = "idle"
		end
	end

	local legend = Instance.new("TextLabel")
	legend.Name = "Legend"
	legend.BackgroundTransparency = 1
	legend.Font = Enum.Font.Code
	legend.TextColor3 = Color3.new(1, 1, 1)
	legend.RichText = true
	legend.TextWrapped = true
	legend.TextYAlignment = Enum.TextYAlignment.Top
	legend.Text = legendText()
	legend.Parent = meter

	-- Touch layouts are narrower so the meter fits between the stick and the buttons.
	local layoutCompact: boolean? = nil
	local layoutWidth = 0
	local function layout(compact: boolean)
		layoutCompact = compact
		layoutWidth = parent.AbsoluteSize.X
		local labelWidth = if compact then 30 else 36
		-- On touch the panel and meter take whatever room is left between the stick and the buttons.
		local free = math.max(layoutWidth - TouchControls.reservedWidth, 180)
		local cellWidth = if compact then math.clamp(math.floor((free - labelWidth) / CELLS) - CELL_GAP, 1, 5) else 7
		local meterWidth = labelWidth + CELLS * (cellWidth + CELL_GAP)
		-- The legend wraps onto a second line when the meter is narrow.
		local meterHeight = ROW_HEIGHT * 2 + (if compact then 32 else 24)

		panel.Size = UDim2.fromOffset(if compact then free else meterWidth, if compact then 46 else 56)
		panel.Position = UDim2.new(0.5, 0, 1, -(12 + meterHeight + 6))
		panel.TextSize = if compact then 9 else 12

		meter.Size = UDim2.fromOffset(meterWidth, meterHeight)
		meter.Position = UDim2.new(0.5, 0, 1, -12)
		legend.Size = UDim2.new(1, 0, 0, if compact then 22 else 14)
		legend.Position = UDim2.fromOffset(0, ROW_HEIGHT * 2 + 6)
		legend.TextSize = if compact then 9 else 11

		for row = 1, 2 do
			local y = (row - 1) * (ROW_HEIGHT + 2)
			labels[row].Size = UDim2.fromOffset(labelWidth, ROW_HEIGHT)
			labels[row].Position = UDim2.fromOffset(0, y)
			labels[row].TextSize = if compact then 9 else 11
			for index = 1, CELLS do
				local cell = cells[row][index]
				cell.Size = UDim2.fromOffset(cellWidth, ROW_HEIGHT)
				cell.Position = UDim2.fromOffset(labelWidth + (index - 1) * (cellWidth + CELL_GAP), y)
			end
		end
	end
	layout(false)

	local lastMoveId = 0
	local exchange: FrameData.Exchange? = nil
	local lastExchangeCheck = 0

	return {
		setDetail = function(visible: boolean)
			detail = visible
		end,
		update = function(args: Args)
			pill.Visible = args.training
			panel.Visible = args.training and detail
			meter.Visible = args.training and detail
			if not args.training then
				return
			end
			local dummy = DUMMY_NAMES[args.dummyMode + 1] or "?"
			pill.Text = if args.compact
				then `<b>TRAINING</b>  ·  {string.upper(dummy)}`
				else `<b>TRAINING</b>  ·  DUMMY: {string.upper(dummy)}   ·   T next   R reset   M menu   H data`
			if not detail then
				return
			end
			if layoutCompact ~= args.compact or layoutWidth ~= parent.AbsoluteSize.X then
				layout(args.compact)
			end

			local now = os.clock()
			if args.me.moveId ~= 0 then
				lastMoveId = args.me.moveId
			end
			if now - lastExchangeCheck > 0.1 then
				lastExchangeCheck = now
				exchange = FrameData.lastExchange(args.history)
			end

			local lines: { string } = {}
			-- Touch layouts have room for about 30 characters per line, so they get the short forms.
			if lastMoveId ~= 0 then
				local data = FrameData.forMove(lastMoveId, args.me.stats, args.foe.stats)
				if args.compact then
					table.insert(
						lines,
						`<b>{data.name}</b> {data.startup}/{data.active}/{data.recovery}  {signed(data.onHit)}/{signed(
							data.onBlock
						)}  dmg {data.damage}`
					)
				else
					table.insert(
						lines,
						`LAST MOVE <b>{data.name}</b>  startup {data.startup} active {data.active} recovery {data.recovery}  on hit {signed(
							data.onHit
						)}  on block {signed(data.onBlock)}  dmg {data.damage}`
					)
				end
			else
				table.insert(lines, if args.compact then "(throw an attack)" else "LAST MOVE  (throw any attack)")
			end

			local result = exchange
			if result ~= nil then
				local mine = result.attacker == args.mySlot
				local data = FrameData.forMove(
					result.moveId,
					if mine then args.me.stats else args.foe.stats,
					if mine then args.foe.stats else args.me.stats
				)
				local expected = if result.blocked then data.onBlock else data.onHit
				local matches = result.advantage == expected
				local who = if mine then "you" else "dummy"
				if args.compact then
					local verdict = if matches
						then '<font color="#6fe38a">ok</font>'
						else '<font color="#ff6b6b">MISMATCH</font>'
					table.insert(
						lines,
						`{who} {data.name} {if result.blocked then "BLOCK" else "HIT"} {signed(result.advantage)} {verdict}`
					)
				else
					local verdict = if matches
						then '<font color="#6fe38a">matches data</font>'
						else '<font color="#ff6b6b">MISMATCH</font>'
					table.insert(
						lines,
						`LAST EXCHANGE  {who} {data.name} {if result.blocked then "BLOCKED" else "HIT"}  measured {signed(
							result.advantage
						)}  ({signed(expected)} in data) {verdict}`
					)
				end
			else
				table.insert(lines, if args.compact then "(no exchange yet)" else "LAST EXCHANGE  (none yet)")
			end
			table.insert(lines, `<font color="#9aa6a0">{args.debugLine}</font>`)
			panel.Text = table.concat(lines, "\n")

			local history = args.history
			local meSideA = args.mySlot == 1
			for row = 1, 2 do
				local useA = (row == 1) == meSideA
				local states = if useA then history.stateA else history.stateB
				local moves = if useA then history.moveA else history.moveB
				local stateFrames = if useA then history.stateFrameA else history.stateFrameB
				-- The top row is always the player, whichever slot that is.
				local rowMoves = (if row == 1 then args.me else args.foe).stats.moves
				for index = 1, CELLS do
					local frame = history.latest - (CELLS - index)
					local entry = FrameData.indexOf(history, frame)
					local kind = "idle"
					if entry ~= nil then
						kind = FrameData.cellKind(states[entry], moves[entry], stateFrames[entry], rowMoves)
					end
					if shown[row][index] ~= kind then
						shown[row][index] = kind
						cells[row][index].BackgroundColor3 = COLORS[kind]
					end
				end
			end
		end,
	}
end

return TrainingHud
