--!strict

-- The building blocks of the garage screen (see GaragePanel): chips and swatches that can be selected, the box that says
-- what a part gives and what it costs, and the bars that rate a build. Plain Roblox UI that only draws what it is told.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Loadout = require(Shared:WaitForChild("Loadout"))

-- Sizes for the roomy desktop panel and the tighter phone one.
export type Metrics = {
	-- The panel's width beside the robot, its margin to the edge of the view, and the padding inside it.
	width: number,
	margin: number,
	pad: number,
	-- The space between neighbors in a list, and between the cells of a grid.
	gap: number,
	cellGap: number,
	title: number,
	name: number,
	tab: number,
	tabText: number,
	chip: number,
	chipText: number,
	body: number,
	small: number,
	-- A row of text, a ready-made build's card (and whether it has room to list the build's parts), a paint swatch, and the
	-- width of a rating bar's label.
	row: number,
	card: number,
	cardParts: boolean,
	cell: number,
	label: number,
	done: Vector2,
}

export type Option = {
	button: TextButton,
	edge: UIStroke,
	selected: boolean,
	hot: boolean,
	-- A swatch keeps its own color and only draws a ring when it is picked.
	colored: boolean,
}

type DetailRow = {
	row: Frame,
	dot: Frame,
	ring: UIStroke,
	label: TextLabel,
}

export type Detail = {
	frame: Frame,
	-- Shows a part: an optional tag line, what it is, and what it gives and costs (good lines first in the order given).
	set: (tag: string?, blurb: string, lines: { Loadout.Line }) -> (),
}

export type StatCard = {
	frame: Frame,
	-- Takes the five ratings of a build, in the order of Widgets.StatLabels.
	set: (values: { number }) -> (),
}

local Widgets = {}

Widgets.Color = {
	Panel = Color3.fromRGB(8, 10, 18),
	Inset = Color3.fromRGB(13, 17, 30),
	Track = Color3.fromRGB(28, 34, 54),
	Row = Color3.fromRGB(18, 23, 38),
	Hover = Color3.fromRGB(24, 31, 52),
	Hot = Color3.fromRGB(30, 40, 66),
	Teal = Color3.fromRGB(64, 214, 232),
	Amber = Color3.fromRGB(255, 200, 90),
	Muted = Color3.fromRGB(140, 154, 184),
	Text = Color3.fromRGB(222, 228, 240),
	Good = Color3.fromRGB(110, 226, 140),
	Bad = Color3.fromRGB(255, 110, 100),
	Dark = Color3.fromRGB(10, 14, 24),
}

Widgets.Regular = {
	width = 400,
	margin = 14,
	pad = 16,
	gap = 10,
	cellGap = 6,
	title = 22,
	name = 13,
	tab = 34,
	tabText = 13,
	chip = 42,
	chipText = 12,
	body = 12,
	small = 11,
	row = 18,
	card = 68,
	cardParts = true,
	cell = 38,
	label = 98,
	done = Vector2.new(88, 32),
} :: Metrics

Widgets.Compact = {
	width = 320,
	margin = 8,
	pad = 10,
	gap = 7,
	cellGap = 4,
	title = 15,
	name = 11,
	tab = 28,
	tabText = 11,
	chip = 34,
	chipText = 10,
	body = 11,
	small = 10,
	row = 15,
	card = 46,
	cardParts = false,
	cell = 32,
	label = 80,
	done = Vector2.new(66, 26),
} :: Metrics

-- The five bars, in the order of the ratings Loadout.ratings gives.
Widgets.StatLabels = { "HEALTH", "MOBILITY", "DAMAGE", "ATTACK SPEED", "REACH" }

local Color = Widgets.Color
local FAST = TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local BAR = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
-- The most lines a part can have to say; the biggest chassis has six.
local MAX_LINES = 7
local STAT_PAD = 10

function Widgets.text(parent: Instance, content: string, font: Enum.Font, size: number, color: Color3): TextLabel
	local item = Instance.new("TextLabel")
	item.BackgroundTransparency = 1
	item.Text = content
	item.Font = font
	item.TextSize = size
	item.TextColor3 = color
	item.TextXAlignment = Enum.TextXAlignment.Left
	item.Parent = parent
	return item
end

function Widgets.round(instance: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = instance
end

-- A border drawn around a frame or a button (not around its text).
function Widgets.stroke(instance: Instance, color: Color3, thickness: number, transparency: number): UIStroke
	local item = Instance.new("UIStroke")
	item.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	item.Color = color
	item.Thickness = thickness
	item.Transparency = transparency
	item.Parent = instance
	return item
end

function Widgets.padding(instance: Instance, top: number, right: number, bottom: number, left: number)
	local item = Instance.new("UIPadding")
	item.PaddingTop = UDim.new(0, top)
	item.PaddingRight = UDim.new(0, right)
	item.PaddingBottom = UDim.new(0, bottom)
	item.PaddingLeft = UDim.new(0, left)
	item.Parent = instance
end

function Widgets.list(parent: Instance, gap: number): UIListLayout
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, gap)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = parent
	return layout
end

-- A frame that is as tall as what it holds and as wide as its parent.
function Widgets.stack(parent: Instance, order: number): Frame
	local frame = Instance.new("Frame")
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel = 0
	frame.Size = UDim2.fromScale(1, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.LayoutOrder = order
	frame.Parent = parent
	return frame
end

-- A titled block of a page: the frame to fill, and the heading (rich text, so the choice can be set off in color).
function Widgets.section(parent: Instance, order: number, metrics: Metrics): (Frame, TextLabel)
	local frame = Widgets.stack(parent, order)
	Widgets.list(frame, metrics.cellGap + 2)
	local head = Widgets.text(frame, "", Enum.Font.GothamBold, metrics.small, Color.Muted)
	head.RichText = true
	head.Size = UDim2.new(1, 0, 0, metrics.small + 6)
	head.LayoutOrder = 1
	return frame, head
end

-- Cells laid out in rows. `columns` splits the width evenly; without it the cells keep a fixed size and wrap.
function Widgets.grid(parent: Instance, order: number, cell: Vector2, gap: number, columns: number?): Frame
	local frame = Widgets.stack(parent, order)
	local layout = Instance.new("UIGridLayout")
	layout.CellPadding = UDim2.fromOffset(gap, gap)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	if columns ~= nil then
		-- A pixel is taken off every cell so rounding can never push the last one onto a new row.
		local share = math.ceil(gap * (columns - 1) / columns) + 1
		layout.CellSize = UDim2.new(1 / columns, -share, 0, cell.Y)
		layout.FillDirectionMaxCells = columns
	else
		layout.CellSize = UDim2.fromOffset(cell.X, cell.Y)
		layout.FillDirectionMaxCells = 8
	end
	layout.Parent = frame
	return frame
end

local function paint(option: Option)
	if option.colored then
		local ring = if option.selected then 0 elseif option.hot then 0.6 else 1
		TweenService:Create(option.edge, FAST, { Transparency = ring }):Play()
		return
	end
	local fill = if option.selected then Color.Hot elseif option.hot then Color.Hover else Color.Row
	TweenService:Create(option.button, FAST, { BackgroundColor3 = fill }):Play()
	TweenService:Create(option.edge, FAST, { Transparency = if option.selected then 0.05 else 1 }):Play()
end

-- A button that can show itself as picked. A colored one is a paint swatch: it keeps its color, and a white ring marks it.
function Widgets.option(parent: Instance, colored: boolean, onActivate: () -> ()): Option
	local button = Instance.new("TextButton")
	button.AutoButtonColor = false
	button.Text = ""
	button.BorderSizePixel = 0
	button.BackgroundColor3 = Color.Row
	button.Parent = parent
	Widgets.round(button, if colored then 6 else 8)
	local edge =
		Widgets.stroke(button, if colored then Color3.new(1, 1, 1) else Color.Teal, if colored then 2.5 else 1.5, 1)
	local option: Option = { button = button, edge = edge, selected = false, hot = false, colored = colored }
	button.MouseEnter:Connect(function()
		option.hot = true
		paint(option)
	end)
	button.MouseLeave:Connect(function()
		option.hot = false
		paint(option)
	end)
	button.Activated:Connect(onActivate)
	return option
end

function Widgets.setSelected(option: Option, selected: boolean)
	if option.selected ~= selected then
		option.selected = selected
		paint(option)
	end
end

-- The box that says what a part is, what it gives and what it costs: a dot per line, solid green for a gain and a red ring
-- for a cost, so the two read apart without relying on color alone.
function Widgets.detail(parent: Instance, order: number, metrics: Metrics): Detail
	local frame = Instance.new("Frame")
	frame.BackgroundColor3 = Color.Inset
	frame.BorderSizePixel = 0
	frame.Size = UDim2.fromScale(1, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.LayoutOrder = order
	frame.Parent = parent
	Widgets.round(frame, 8)
	Widgets.padding(frame, 8, 10, 8, 10)
	Widgets.list(frame, 3)

	local tag = Widgets.text(frame, "", Enum.Font.GothamBold, metrics.small, Color.Amber)
	tag.Size = UDim2.new(1, 0, 0, metrics.small + 4)
	tag.LayoutOrder = 1
	local blurb = Widgets.text(frame, "", Enum.Font.GothamMedium, metrics.body, Color.Muted)
	blurb.TextWrapped = true
	blurb.TextYAlignment = Enum.TextYAlignment.Top
	blurb.AutomaticSize = Enum.AutomaticSize.Y
	blurb.Size = UDim2.fromScale(1, 0)
	blurb.LayoutOrder = 2

	local rows: { DetailRow } = {}
	for index = 1, MAX_LINES do
		local row = Instance.new("Frame")
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, metrics.row)
		row.LayoutOrder = 2 + index
		row.Visible = false
		row.Parent = frame
		local dot = Instance.new("Frame")
		dot.AnchorPoint = Vector2.new(0, 0.5)
		dot.Position = UDim2.new(0, 3, 0.5, 0)
		dot.Size = UDim2.fromOffset(7, 7)
		dot.BorderSizePixel = 0
		dot.Parent = row
		Widgets.round(dot, 4)
		local ring = Widgets.stroke(dot, Color.Bad, 1.5, 1)
		local label = Widgets.text(row, "", Enum.Font.GothamMedium, metrics.body, Color.Text)
		label.Position = UDim2.fromOffset(18, 0)
		label.Size = UDim2.new(1, -18, 1, 0)
		label.TextTruncate = Enum.TextTruncate.AtEnd
		rows[index] = { row = row, dot = dot, ring = ring, label = label }
	end

	return {
		frame = frame,
		set = function(tagText: string?, text: string, lines: { Loadout.Line })
			tag.Visible = tagText ~= nil
			tag.Text = tagText or ""
			blurb.Text = text
			for index, entry in rows do
				local line = lines[index]
				entry.row.Visible = line ~= nil
				if line ~= nil then
					entry.label.Text = line.text
					entry.dot.BackgroundColor3 = Color.Good
					entry.dot.BackgroundTransparency = if line.good then 0 else 1
					entry.ring.Transparency = if line.good then 1 else 0
				end
			end
		end,
	}
end

-- A rating as the number it is shown as: whole when it is whole, one decimal otherwise.
function Widgets.formatRating(value: number): string
	if value % 1 == 0 then
		return tostring(value)
	end
	return string.format("%.1f", value)
end

-- The five rating bars: a track for 1 to 10, a tick where the stock robot sits (5), and the value on the right.
function Widgets.stats(parent: Instance, order: number, metrics: Metrics): StatCard
	local frame = Instance.new("Frame")
	frame.BackgroundColor3 = Color.Inset
	frame.BorderSizePixel = 0
	frame.Size = UDim2.new(1, 0, 0, STAT_PAD * 2 + #Widgets.StatLabels * metrics.row)
	frame.LayoutOrder = order
	frame.Parent = parent
	Widgets.round(frame, 8)

	local fills: { Frame } = {}
	local values: { TextLabel } = {}
	local valueWidth = 28
	for index, name in Widgets.StatLabels do
		local y = STAT_PAD + (index - 1) * metrics.row
		local label = Widgets.text(frame, name, Enum.Font.GothamBold, metrics.small, Color.Muted)
		label.Position = UDim2.fromOffset(STAT_PAD, y)
		label.Size = UDim2.fromOffset(metrics.label, metrics.row)

		local track = Instance.new("Frame")
		track.BackgroundColor3 = Color.Track
		track.BorderSizePixel = 0
		track.Position = UDim2.fromOffset(STAT_PAD + metrics.label + 6, y + math.floor((metrics.row - 6) / 2))
		track.Size = UDim2.new(1, -(STAT_PAD * 2 + metrics.label + 6 + valueWidth + 6), 0, 6)
		track.Parent = frame
		Widgets.round(track, 3)

		local fill = Instance.new("Frame")
		fill.BackgroundColor3 = Color.Teal
		fill.BorderSizePixel = 0
		fill.Size = UDim2.fromScale(0.5, 1)
		fill.Parent = track
		Widgets.round(fill, 3)

		local tick = Instance.new("Frame")
		tick.AnchorPoint = Vector2.new(0.5, 0.5)
		tick.BackgroundColor3 = Color3.new(1, 1, 1)
		tick.BackgroundTransparency = 0.5
		tick.BorderSizePixel = 0
		tick.Position = UDim2.fromScale(0.5, 0.5)
		tick.Size = UDim2.fromOffset(2, 12)
		tick.ZIndex = 2
		tick.Parent = track

		local value = Widgets.text(frame, "5", Enum.Font.GothamBold, metrics.small + 1, Color.Text)
		value.AnchorPoint = Vector2.new(1, 0)
		value.Position = UDim2.new(1, -STAT_PAD, 0, y)
		value.Size = UDim2.fromOffset(valueWidth, metrics.row)
		value.TextXAlignment = Enum.TextXAlignment.Right
		fills[index] = fill
		values[index] = value
	end

	return {
		frame = frame,
		set = function(ratings: { number })
			for index, fill in fills do
				local rating = ratings[index]
				fill.BackgroundColor3 = if rating >= 5 then Color.Teal else Color.Amber
				TweenService:Create(fill, BAR, { Size = UDim2.fromScale(math.clamp(rating / 10, 0, 1), 1) }):Play()
				local value = values[index]
				value.Text = Widgets.formatRating(rating)
				value.TextColor3 = if rating > 5 then Color.Good elseif rating < 5 then Color.Bad else Color.Text
			end
		end,
	}
end

return Widgets
