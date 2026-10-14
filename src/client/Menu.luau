--!strict

-- The menu. Two cards share one screen-wide overlay: the PLAY card (fight a bot at a level, train, queue for a 1v1, or
-- open the garage), which shows when the player asks for it in the hall, and the result card, which shows to the players
-- in a ring when their match ends. Mouse, touch, keyboard and gamepad all work. It only asks the server for things; the
-- rings react through the attributes the server sets (see Rings on the server).

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BotBrain = require(Shared:WaitForChild("BotBrain"))
local FightConfig = require(Shared:WaitForChild("FightConfig"))
local MatchFlow = require(Shared:WaitForChild("MatchFlow"))
local MatchView = require(script.Parent:WaitForChild("MatchView"))

export type Info = {
	-- The local player's fighter slot, and whether they hold it (they are in a ring).
	slot: number,
	seated: boolean,
	versus: boolean,
	-- Whether the server would take a rematch now, and who is next in line for the player's ring ("" for nobody).
	rematchOpen: boolean,
	nextUp: string,
	-- Whether the player is in line, which shows the LEAVE THE LINE entry.
	queued: boolean,
}

export type Menu = {
	-- Call every frame with the match state and the player's place in the hall.
	update: (view: MatchView.View, info: Info) -> (),
	-- Opens the PLAY card, with the entry for a section ("Bot", "Training" or "Versus") picked. Closes it again.
	open: (section: string?) -> (),
	close: () -> (),
	isOpen: () -> boolean,
	-- Phone-sized screens get shorter rows and no blurbs, so the card fits.
	setCompact: (compact: boolean) -> (),
	-- The line under GARAGE on the PLAY card: the build the player has chosen.
	setGarageBlurb: (text: string) -> (),
}

type Entry = {
	button: TextButton,
	name: TextLabel,
	blurb: TextLabel?,
	accent: Frame,
	-- The outline on the entry Enter or the gamepad would pick.
	focus: UIStroke,
	activate: () -> (),
	-- A tile sits beside others in a row and shows only its name; its `about` line shows under the row when it is picked.
	tile: boolean,
	about: string,
}

type Card = {
	frame: Frame,
	padding: UIPadding,
	layout: UIListLayout,
	entries: { Entry },
	headers: { TextLabel },
	rows: { Frame },
	title: TextLabel,
	subtitle: TextLabel,
	score: TextLabel,
	hint: TextLabel?,
	caption: TextLabel?,
	-- Shrinks the card when the window is too short for it (see FIT_MARGIN).
	fit: UIScale,
}

local Menu = {}

local PANEL = Color3.fromRGB(8, 10, 18)
local ROW = Color3.fromRGB(18, 23, 38)
local ROW_HOT = Color3.fromRGB(30, 40, 66)
local TEAL = Color3.fromRGB(64, 214, 232)
local AMBER = Color3.fromRGB(255, 200, 90)
local MUTED = Color3.fromRGB(140, 154, 184)
local TITLE = "THE FOUNDRY"
local VERSUS_COLOR = Color3.fromRGB(255, 96, 84)
-- How long after a match ends the result card waits, so the knockout can be seen first.
local RESULT_DELAY_FRAMES = 45
-- On a wide enough view the result card rests to the right of the winner, under a lighter shade (see FightConfig's
-- ResultMinWidth). It keeps a margin to the right edge on views that are only just wide enough.
local RESULT_WIDTH = 380
local RESULT_X = 0.74
local RESULT_MARGIN = 24
local SHADE_MENU = 0.45
local SHADE_RESULT = 0.8
-- A card taller than the window, less this margin, is scaled down to fit, however small the window is (a short desktop
-- window as well as a phone), but never below FIT_MIN.
local FIT_MARGIN = 16
local FIT_MIN = 0.5

local LEVEL_STYLES = {
	{ color = Color3.fromRGB(90, 214, 130), blurb = "Learn the controls. It makes mistakes." },
	{ color = Color3.fromRGB(255, 190, 70), blurb = "A fair fight. It blocks and punishes." },
	{ color = Color3.fromRGB(255, 84, 84), blurb = "Reads you and punishes every mistake." },
}

local function label(parent: Instance, text: string, font: Enum.Font, size: number, color: Color3): TextLabel
	local item = Instance.new("TextLabel")
	item.BackgroundTransparency = 1
	item.Text = text
	item.Font = font
	item.TextSize = size
	item.TextColor3 = color
	item.TextXAlignment = Enum.TextXAlignment.Center
	item.Size = UDim2.new(1, 0, 0, size + 6)
	item.Parent = parent
	return item
end

local function round(instance: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = instance
end

local function focusStroke(button: TextButton, color: Color3): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Name = "Focus"
	-- Contextual would outline the button's text.
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = color
	stroke.Thickness = 1.5
	stroke.Transparency = 1
	stroke.Parent = button
	return stroke
end

local function newCard(parent: Instance, name: string, width: number): Card
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.new(1, -24, 0, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.BackgroundColor3 = PANEL
	frame.BackgroundTransparency = 0.08
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.Parent = parent
	round(frame, 12)
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(width, math.huge)
	limit.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = TEAL
	stroke.Thickness = 1.5
	stroke.Transparency = 0.45
	stroke.Parent = frame
	local padding = Instance.new("UIPadding")
	padding.Parent = frame
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = frame
	local fit = Instance.new("UIScale")
	fit.Parent = frame

	local title = label(frame, "", Enum.Font.Michroma, 30, Color3.new(1, 1, 1))
	title.LayoutOrder = 1
	local subtitle = label(frame, "", Enum.Font.GothamMedium, 13, MUTED)
	subtitle.LayoutOrder = 2
	local score = label(frame, "", Enum.Font.Michroma, 22, AMBER)
	score.LayoutOrder = 3
	score.Visible = false
	return {
		frame = frame,
		padding = padding,
		layout = layout,
		entries = {},
		headers = {},
		rows = {},
		title = title,
		subtitle = subtitle,
		score = score,
		hint = nil,
		caption = nil,
		fit = fit,
	}
end

local function header(card: Card, order: number, text: string)
	local item = label(card.frame, text, Enum.Font.GothamBold, 12, MUTED)
	item.LayoutOrder = order
	item.TextXAlignment = Enum.TextXAlignment.Left
	item.Size = UDim2.new(1, 0, 0, 22)
	table.insert(card.headers, item)
end

local function addEntry(
	card: Card,
	order: number,
	text: string,
	blurb: string,
	color: Color3,
	activate: () -> ()
): Entry
	local button = Instance.new("TextButton")
	button.Name = text
	button.LayoutOrder = order
	button.BackgroundColor3 = ROW
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Text = ""
	button.Selectable = true
	button.Parent = card.frame
	round(button, 8)

	local accent = Instance.new("Frame")
	accent.Name = "Accent"
	accent.BackgroundColor3 = color
	accent.BorderSizePixel = 0
	accent.Parent = button
	round(accent, 3)

	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Text = text
	name.Font = Enum.Font.GothamBold
	name.TextColor3 = Color3.new(1, 1, 1)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.Parent = button

	local sub: TextLabel? = nil
	if blurb ~= "" then
		local item = Instance.new("TextLabel")
		item.BackgroundTransparency = 1
		item.Text = blurb
		item.Font = Enum.Font.GothamMedium
		item.TextColor3 = MUTED
		item.TextXAlignment = Enum.TextXAlignment.Left
		item.Parent = button
		sub = item
	end

	local entry: Entry = {
		button = button,
		name = name,
		blurb = sub,
		accent = accent,
		focus = focusStroke(button, color),
		activate = activate,
		tile = false,
		about = blurb,
	}
	table.insert(card.entries, entry)
	button.Activated:Connect(activate)
	return entry
end

-- A row of tiles across the card.
local function addRow(card: Card, order: number): Frame
	local row = Instance.new("Frame")
	row.Name = "Row"
	row.BackgroundTransparency = 1
	row.LayoutOrder = order
	row.Parent = card.frame
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row
	table.insert(card.rows, row)
	return row
end

-- A tile in a row: a name over a short bar in its color.
local function addTile(
	card: Card,
	row: Frame,
	order: number,
	text: string,
	about: string,
	color: Color3,
	activate: () -> ()
): Entry
	local button = Instance.new("TextButton")
	button.Name = text
	button.LayoutOrder = order
	button.BackgroundColor3 = ROW
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Text = ""
	button.Selectable = true
	button.Parent = row
	round(button, 8)

	local accent = Instance.new("Frame")
	accent.Name = "Accent"
	accent.AnchorPoint = Vector2.new(0.5, 1)
	accent.BackgroundColor3 = color
	accent.BorderSizePixel = 0
	accent.Parent = button
	round(accent, 2)

	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Text = text
	name.Font = Enum.Font.GothamBold
	name.TextColor3 = Color3.new(1, 1, 1)
	name.TextXAlignment = Enum.TextXAlignment.Center
	name.Parent = button

	local entry: Entry = {
		button = button,
		name = name,
		blurb = nil,
		accent = accent,
		focus = focusStroke(button, color),
		activate = activate,
		tile = true,
		about = about,
	}
	table.insert(card.entries, entry)
	button.Activated:Connect(activate)
	return entry
end

-- Sizes everything on a card for a roomy desktop window or a small phone screen.
local function sizeCard(card: Card, compact: boolean)
	local pad = if compact then 10 else 22
	card.padding.PaddingTop = UDim.new(0, pad)
	card.padding.PaddingBottom = UDim.new(0, pad - 2)
	card.padding.PaddingLeft = UDim.new(0, pad)
	card.padding.PaddingRight = UDim.new(0, pad)
	card.layout.Padding = UDim.new(0, if compact then 4 else 8)

	local titleSize = if compact then 20 else 30
	card.title.TextSize = titleSize
	card.title.Size = UDim2.new(1, 0, 0, titleSize + 6)
	card.subtitle.TextSize = if compact then 11 else 13
	card.subtitle.Size = UDim2.new(1, 0, 0, if compact then 15 else 19)
	card.score.TextSize = if compact then 17 else 22
	card.score.Size = UDim2.new(1, 0, 0, if compact then 24 else 28)
	for _, item in card.headers do
		item.Size = UDim2.new(1, 0, 0, if compact then 16 else 22)
		item.TextSize = if compact then 10 else 12
	end
	if card.hint ~= nil then
		card.hint.Visible = not compact
	end
	local caption = card.caption
	if caption ~= nil then
		caption.Visible = not compact
		caption.TextSize = 12
		caption.Size = UDim2.new(1, 0, 0, 18)
	end

	local gap = if compact then 6 else 8
	local tileHeight = if compact then 36 else 48
	for _, row in card.rows do
		row.Size = UDim2.new(1, 0, 0, tileHeight)
		local layout = row:FindFirstChildOfClass("UIListLayout")
		if layout ~= nil then
			layout.Padding = UDim.new(0, gap)
		end
	end

	for _, entry in card.entries do
		if entry.tile then
			local parent = entry.button.Parent
			local count = 0
			if parent ~= nil then
				for _, sibling in parent:GetChildren() do
					if sibling:IsA("TextButton") then
						count += 1
					end
				end
			end
			count = math.max(count, 1)
			entry.button.Size = UDim2.new(1 / count, -math.ceil(gap * (count - 1) / count), 1, 0)
			entry.accent.Size = UDim2.new(1, -28, 0, 3)
			entry.accent.Position = UDim2.new(0.5, 0, 1, if compact then -5 else -7)
			entry.name.TextSize = if compact then 14 else 16
			entry.name.Position = UDim2.fromOffset(4, 0)
			entry.name.Size = UDim2.new(1, -8, 1, -4)
			continue
		end
		local roomy = entry.blurb ~= nil and not compact
		local height = if compact then 36 else (if roomy then 58 else 48)
		entry.button.Size = UDim2.new(1, 0, 0, height)
		entry.accent.Size = UDim2.new(0, 5, 1, -(if compact then 12 else 16))
		entry.accent.Position = UDim2.fromOffset(10, if compact then 6 else 8)
		entry.name.TextSize = if compact then 15 else 18
		entry.name.Position = UDim2.fromOffset(28, if roomy then 8 else 0)
		entry.name.Size = UDim2.new(1, -40, 0, if roomy then 24 else height)
		local blurb = entry.blurb
		if blurb ~= nil then
			blurb.Visible = roomy
			blurb.TextSize = 12
			blurb.Position = UDim2.fromOffset(28, 31)
			blurb.Size = UDim2.new(1, -40, 0, 18)
		end
	end
end

function Menu.new(
	gui: ScreenGui,
	send: (action: string, level: number?) -> (),
	openGarage: () -> (),
	openScreen: (name: string) -> ()
): Menu
	-- A plain frame, not a CanvasGroup: a CanvasGroup draws its contents into a texture whose quality follows the
	-- player's graphics setting, which left the whole card blurry on lower settings. The shade fades instead, and the card
	-- slides in.
	local root = Instance.new("Frame")
	root.Name = "Menu"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.Visible = false
	root.ZIndex = 20
	root.Parent = gui

	-- A click on the shade around the PLAY card closes it.
	local shade = Instance.new("TextButton")
	shade.Name = "Shade"
	shade.Size = UDim2.fromScale(1, 1)
	shade.BackgroundColor3 = Color3.fromRGB(2, 4, 12)
	shade.BackgroundTransparency = 1
	shade.BorderSizePixel = 0
	shade.AutoButtonColor = false
	shade.Text = ""
	shade.Selectable = false
	shade.Parent = root

	-- Asked for by the PLAY button or P; every choice closes it again.
	local wantMain = false
	local wantSection: string? = nil
	local function closeMain()
		wantMain = false
	end
	local function pick(action: string, level: number?): () -> ()
		return function()
			closeMain()
			send(action, level)
		end
	end

	-- The PLAY card.
	local main = newCard(root, "Main", 420)
	main.title.Text = TITLE
	main.subtitle.Text = "ROBOT FIGHT CLUB"
	header(main, 4, "FIGHT A BOT")
	local levelRow = addRow(main, 5)
	local levelEntries: { Entry } = {}
	for level = 1, BotBrain.LevelCount do
		local style = LEVEL_STYLES[level]
		local entry =
			addTile(main, levelRow, level, BotBrain.Levels[level].name, style.blurb, style.color, pick("bot", level))
		entry.button.Name = "Level" .. level
		levelEntries[level] = entry
	end
	header(main, 6, "PRACTICE OR TAKE ON A PLAYER")
	local modeRow = addRow(main, 7)
	local trainingEntry =
		addTile(main, modeRow, 1, "TRAINING", "A dummy to hit, with frame data.", TEAL, pick("training", nil))
	local versusEntry = addTile(
		main,
		modeRow,
		2,
		"1V1",
		"The next player in line. Or meet on the 1V1 pads.",
		VERSUS_COLOR,
		pick("versus", nil)
	)
	local caption = label(main.frame, "", Enum.Font.GothamMedium, 12, MUTED)
	caption.LayoutOrder = 8
	main.caption = caption
	header(main, 10, "YOUR ROBOT")
	local garageEntry = addEntry(main, 11, "GARAGE", "Pick a build and paint it.", AMBER, function()
		closeMain()
		openGarage()
	end)
	local extrasRow = addRow(main, 12)
	addTile(main, extrasRow, 1, "REWARDS", "The daily reward and today's contracts.", AMBER, function()
		closeMain()
		openScreen("rewards")
	end)
	addTile(main, extrasRow, 2, "CASES", "Core glows, strike trails, impact effects and titles.", TEAL, function()
		closeMain()
		openScreen("cases")
	end)
	local leaveEntry = addEntry(main, 13, "LEAVE THE LINE", "", MUTED, pick("leave", nil))
	leaveEntry.button.Visible = false
	local hint = label(
		main.frame,
		"Arrows or W S to choose, Enter to pick. G opens the garage; P or Esc closes this.",
		Enum.Font.GothamMedium,
		11,
		MUTED
	)
	hint.LayoutOrder = 14
	hint.TextWrapped = true
	hint.Size = UDim2.new(1, 0, 0, 30)
	main.hint = hint

	-- The result card.
	local result = newCard(root, "Result", RESULT_WIDTH)
	result.score.Visible = true
	local rematchEntry = addEntry(result, 4, "REMATCH", "", AMBER, function()
		send("rematch", nil)
	end)
	addEntry(result, 5, "LEAVE THE RING", "", TEAL, function()
		send("leave", nil)
	end)

	local cards = { main, result }
	local compactLayout = false
	for _, card in cards do
		sizeCard(card, false)
	end

	-- AbsoluteSize includes the scale, so the card's own height is read back without it; setting the same scale again
	-- changes nothing, which keeps the size signal from feeding itself.
	local function fitCard(card: Card)
		local natural = card.frame.AbsoluteSize.Y / card.fit.Scale
		local room = gui.AbsoluteSize.Y - FIT_MARGIN
		if natural <= 0 or room <= 0 then
			return
		end
		local wanted = math.clamp(room / natural, FIT_MIN, 1)
		if math.abs(wanted - card.fit.Scale) > 0.005 then
			card.fit.Scale = wanted
		end
	end
	for _, card in cards do
		card.frame:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			fitCard(card)
		end)
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		for _, card in cards do
			fitCard(card)
		end
	end)

	local shown: Card? = nil
	local selected = 1
	-- What the result card was last set up with, so it is only rebuilt when that changes.
	local resultKey = ""

	local function paint()
		local card = shown
		if card == nil then
			return
		end
		for index, entry in card.entries do
			local hot = index == selected
			TweenService:Create(entry.button, TweenInfo.new(0.1), { BackgroundColor3 = if hot then ROW_HOT else ROW })
				:Play()
			TweenService:Create(entry.focus, TweenInfo.new(0.1), { Transparency = if hot then 0.15 else 1 }):Play()
		end
		-- Tiles have no room for a line of their own, so the picked one's line shows under the rows.
		local line = card.caption
		if line ~= nil then
			local entry = card.entries[selected]
			line.Text = if entry ~= nil and entry.tile then entry.about else "Pick a fight, or open the garage."
		end
	end

	local function choose(index: number)
		local card = shown
		if card == nil then
			return
		end
		selected = ((index - 1) % #card.entries) + 1
		paint()
		if UserInputService.PreferredInput == Enum.PreferredInput.Gamepad then
			GuiService.SelectedObject = card.entries[selected].button
		end
	end

	-- Steps to the next entry that is showing.
	local function move(delta: number)
		local card = shown
		if card == nil then
			return
		end
		local count = #card.entries
		local index = selected
		for _ = 1, count do
			index = ((index - 1 + delta) % count) + 1
			if card.entries[index].button.Visible then
				break
			end
		end
		choose(index)
	end

	-- Picks `entry` when it is on the card and showing, or else the first entry that is.
	local function chooseEntry(entry: Entry?)
		local card = shown
		if card == nil then
			return
		end
		for index, candidate in card.entries do
			if candidate == entry and candidate.button.Visible then
				choose(index)
				return
			end
		end
		selected = 0
		move(1)
	end

	for _, card in cards do
		for index, entry in card.entries do
			entry.button.MouseEnter:Connect(function()
				if shown == card then
					selected = index
					paint()
				end
			end)
		end
	end
	shade.Activated:Connect(function()
		if shown == main then
			closeMain()
		end
	end)

	-- The result card rests beside the winner when the view is wide enough, phones in landscape included; the PLAY card,
	-- and a narrow view, stays centered.
	local function restX(card: Card): number
		local size = gui.AbsoluteSize
		local wideEnough = size.X >= FightConfig.ResultMinWidth
			and size.X / math.max(size.Y, 1) >= FightConfig.ResultMinAspect
		if card ~= result or not wideEnough then
			return 0.5
		end
		return math.min(RESULT_X, (size.X - RESULT_MARGIN - RESULT_WIDTH / 2) / size.X)
	end

	local function show(card: Card?)
		if shown == card then
			return
		end
		shown = card
		for _, other in cards do
			other.frame.Visible = other == card
		end
		if card == nil then
			TweenService:Create(shade, TweenInfo.new(0.18), { BackgroundTransparency = 1 }):Play()
			task.delay(0.2, function()
				if shown == nil then
					root.Visible = false
				end
			end)
			GuiService.SelectedObject = nil
			return
		end
		root.Visible = true
		fitCard(card)
		local x = restX(card)
		card.frame.Position = UDim2.fromScale(x, 0.56)
		TweenService
			:Create(
				shade,
				TweenInfo.new(0.3),
				{ BackgroundTransparency = if x ~= 0.5 then SHADE_RESULT else SHADE_MENU }
			)
			:Play()
		TweenService:Create(
			card.frame,
			TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Position = UDim2.fromScale(x, 0.5) }
		):Play()
		if card == main then
			local section = wantSection
			wantSection = nil
			chooseEntry(
				if section == "Bot"
					then levelEntries[2]
					elseif section == "Training" then trainingEntry
					elseif section == "Versus" then versusEntry
					else nil
			)
		else
			chooseEntry(nil)
		end
	end

	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		local card = shown
		if card == nil then
			return
		end
		local key = input.KeyCode
		if key == Enum.KeyCode.Up or key == Enum.KeyCode.W or key == Enum.KeyCode.DPadUp then
			move(-1)
		elseif key == Enum.KeyCode.Down or key == Enum.KeyCode.S or key == Enum.KeyCode.DPadDown then
			move(1)
		elseif not processed and (key == Enum.KeyCode.Return or key == Enum.KeyCode.KeypadEnter) then
			local entry = card.entries[selected]
			if entry ~= nil and entry.button.Visible then
				entry.activate()
			end
		elseif card == main and (key == Enum.KeyCode.Escape or key == Enum.KeyCode.ButtonB) then
			closeMain()
		elseif card == main and not processed and key == Enum.KeyCode.G then
			closeMain()
			openGarage()
		end
	end)

	return {
		open = function(section: string?)
			wantMain = true
			wantSection = section
			if shown == main and section ~= nil then
				wantSection = nil
				chooseEntry(
					if section == "Bot"
						then levelEntries[2]
						elseif section == "Training" then trainingEntry
						elseif section == "Versus" then versusEntry
						else nil
				)
			end
		end,
		close = closeMain,
		isOpen = function()
			return wantMain
		end,
		setGarageBlurb = function(text: string)
			local blurb = garageEntry.blurb
			if blurb ~= nil then
				blurb.Text = text
			end
		end,
		setCompact = function(compact: boolean)
			if compact ~= compactLayout then
				compactLayout = compact
				for _, card in cards do
					sizeCard(card, compact)
				end
			end
		end,
		update = function(view: MatchView.View, info: Info)
			if info.seated then
				wantMain = false
				if view.phase == MatchFlow.Phase.MatchEnd and view.phaseFrame >= RESULT_DELAY_FRAMES then
					local mine = if info.slot == 1 then view.winsA else view.winsB
					local theirs = if info.slot == 1 then view.winsB else view.winsA
					local key = `{mine}:{theirs}:{info.versus}:{view.botLevel}:{info.rematchOpen}:{info.nextUp}`
					if shown ~= result or resultKey ~= key then
						resultKey = key
						result.title.Text = if mine > theirs
							then "YOU WIN"
							elseif mine < theirs then "YOU LOSE"
							else "DRAW"
						result.title.TextColor3 = if mine > theirs
							then AMBER
							elseif mine < theirs then Color3.fromRGB(255, 96, 84)
							else Color3.new(1, 1, 1)
						result.score.Text = `{mine}  -  {theirs}`
						local against = if info.versus
							then "VERSUS"
							else `VS BOT  ·  {BotBrain.Levels[math.clamp(view.botLevel, 1, BotBrain.LevelCount)].name}`
						result.subtitle.Text = if info.nextUp ~= "" and not info.rematchOpen
							then `{against}  ·  NEXT UP {info.nextUp}`
							else against
						rematchEntry.button.Visible = info.rematchOpen
						-- The entries changed, so restart the transition.
						shown = nil
						show(result)
					end
				else
					show(nil)
				end
				return
			end
			if wantMain then
				leaveEntry.button.Visible = info.queued
				show(main)
			else
				show(nil)
			end
		end,
	}
end

return Menu
