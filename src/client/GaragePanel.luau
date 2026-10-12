--!strict

-- The garage screen. A panel beside the robot (along the bottom of a tall, narrow view) with three pages: BUILD (a chassis
-- and a module each for arms, core and legs, every part saying what it gives and what it costs, over bars that rate the
-- whole build), PRESETS (ready-made builds, one tap each) and PAINT (armor, accent, finish and crest).
--
-- The robot in the arena wears every change at once (see `preview`); the choices go to the server (Garage on the server),
-- which checks them and keeps them. The panel keeps asking until the server's own copy, which it publishes on the player
-- as GarageLoadout and GarageLook, matches what the screen shows.
--
-- The panel never looks at the game: whoever builds it hands it a place to draw, the player to read the server's codes from,
-- a way to send, and a way to play a sound. Call `step` every frame.

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Loadout = require(Shared:WaitForChild("Loadout"))
local Looks = require(Shared:WaitForChild("Looks"))
local Widgets = require(script.Parent:WaitForChild("GarageWidgets"))

export type Options = {
	-- Where the panel goes: the HUD's ScreenGui.
	gui: GuiBase2d,
	-- Carries the codes the server confirmed, as the attributes GarageLoadout and GarageLook: the local Player.
	owner: Instance,
	-- Sends the player's choices (the keys of a garage profile) to the server.
	send: (choices: { [string]: number }) -> (),
	play: (name: string, gain: number?, pitch: number?) -> (),
}

export type Panel = {
	open: () -> (),
	close: () -> (),
	isOpen: () -> boolean,
	-- What every button does, so a check can press them without a mouse.
	actions: Actions,
	-- Call every frame with the time: it sends what changed and follows what the server says.
	step: (now: number) -> (),
	-- The loadout and look codes the player has picked that the server has not confirmed yet, so the robot can wear them at
	-- once; nil when nothing is waiting.
	preview: () -> (number?, number?),
	-- The loadout and look codes the player has chosen, confirmed or not.
	current: () -> (number, number),
	-- How much of a view of this size the panel covers, for the camera: a fraction of half the view's width (a panel at the
	-- side) and of half its height (a panel at the bottom).
	room: (viewport: Vector2) -> (number, number),
	setCompact: (compact: boolean) -> (),
	destroy: () -> (),
}

type SlotUi = {
	head: TextLabel,
	chips: { Widgets.Option },
	detail: Widgets.Detail,
}

type PresetUi = {
	option: Widgets.Option,
	tag: TextLabel,
}

type TabUi = {
	button: TextButton,
	line: Frame,
}

type Ui = {
	mode: string,
	metrics: Widgets.Metrics,
	panel: Frame,
	-- Where the panel rests, and where it waits off screen.
	rest: UDim2,
	hidden: UDim2,
	name: TextLabel,
	tabs: { TabUi },
	pages: { ScrollingFrame },
	stats: { Widgets.StatCard },
	chassis: SlotUi,
	modules: { [string]: SlotUi },
	presets: { PresetUi },
	armorHead: TextLabel,
	armor: { Widgets.Option },
	accentHead: TextLabel,
	accent: { Widgets.Option },
	finishHead: TextLabel,
	finish: { Widgets.Option },
	crestHead: TextLabel,
	crest: { Widgets.Option },
}

export type Actions = {
	chassis: (index: number) -> (),
	module: (slot: string, index: number) -> (),
	preset: (index: number) -> (),
	armor: (index: number) -> (),
	accent: (index: number) -> (),
	finish: (index: number) -> (),
	crest: (index: number) -> (),
	tab: (index: number) -> (),
	done: () -> (),
}

local GaragePanel = {}

local Color = Widgets.Color
local TAB_NAMES = { "BUILD", "PRESETS", "PAINT" }
-- A view narrower than this (width over height) puts the panel along the bottom instead of the side.
local SHEET_ASPECT = 1.2
local SHEET_HEIGHT = 0.56
-- The panel sends at most this often, keeps asking until the server agrees, and gives up after a while.
local SEND_INTERVAL = 0.2
local GIVE_UP_SECONDS = 4
-- The robot keeps the panel's choices a moment after the server agrees, until the fighter's own copy has arrived.
local HOLD_SECONDS = 0.5
-- The panel ignores its own closing keys for this long after it opens, so the key that opened it does not close it.
local KEY_GUARD = 0.25
local CHASSIS_COLORS = {
	Color3.fromRGB(118, 150, 214),
	Color3.fromRGB(96, 204, 142),
	Color3.fromRGB(255, 196, 84),
	Color3.fromRGB(255, 108, 132),
	Color3.fromRGB(255, 142, 66),
}

local function toColor(rgb: Looks.Rgb): Color3
	return Color3.fromRGB(math.floor(rgb[1] + 0.5), math.floor(rgb[2] + 0.5), math.floor(rgb[3] + 0.5))
end

local function richName(heading: string, value: string): string
	return `{heading}  <font color="rgb(64,214,232)">{value}</font>`
end

-- A row of buttons that split the width evenly, with a name on each and an optional color bar under it.
local function chipRow(
	parent: Instance,
	order: number,
	metrics: Widgets.Metrics,
	names: { string },
	colors: { Color3 }?,
	columns: number,
	onPick: (index: number) -> ()
): { Widgets.Option }
	local box = Widgets.grid(parent, order, Vector2.new(0, metrics.chip), metrics.cellGap, columns)
	local chips: { Widgets.Option } = {}
	for index, name in names do
		local option = Widgets.option(box, false, function()
			onPick(index)
		end)
		option.button.LayoutOrder = index
		local label = Widgets.text(option.button, name, Enum.Font.GothamBold, metrics.chipText, Color.Text)
		label.Position = UDim2.fromOffset(4, 0)
		label.Size = UDim2.new(1, -8, 1, if colors ~= nil then -5 else 0)
		label.TextXAlignment = Enum.TextXAlignment.Center
		label.TextWrapped = true
		if colors ~= nil then
			local bar = Instance.new("Frame")
			bar.AnchorPoint = Vector2.new(0.5, 1)
			bar.BackgroundColor3 = colors[index]
			bar.BorderSizePixel = 0
			bar.Position = UDim2.new(0.5, 0, 1, -5)
			bar.Size = UDim2.new(1, -18, 0, 3)
			bar.Parent = option.button
			Widgets.round(bar, 2)
		end
		chips[index] = option
	end
	return chips
end

-- A part's section: its heading, the choices, and the box that says what the chosen one gives and costs.
local function newSlot(
	parent: Instance,
	order: number,
	metrics: Widgets.Metrics,
	names: { string },
	colors: { Color3 }?,
	onPick: (index: number) -> ()
): SlotUi
	local frame, head = Widgets.section(parent, order, metrics)
	local chips = chipRow(frame, 2, metrics, names, colors, #names, onPick)
	local detail = Widgets.detail(frame, 3, metrics)
	return { head = head, chips = chips, detail = detail }
end

local function newPreset(
	parent: Instance,
	order: number,
	metrics: Widgets.Metrics,
	preset: Loadout.Preset,
	onPick: () -> ()
): PresetUi
	local option = Widgets.option(parent, false, onPick)
	local button = option.button
	button.LayoutOrder = order
	button.Size = UDim2.new(1, 0, 0, metrics.card)
	local color = CHASSIS_COLORS[preset.chassis]

	local bar = Instance.new("Frame")
	bar.BackgroundColor3 = color
	bar.BorderSizePixel = 0
	bar.Position = UDim2.fromOffset(10, 10)
	bar.Size = UDim2.new(0, 4, 1, -20)
	bar.Parent = button
	Widgets.round(bar, 2)

	local nameHeight = metrics.body + 6
	local blurbHeight = metrics.small + 5
	local partsHeight = if metrics.cardParts then metrics.small + 3 else 0
	local top = math.floor((metrics.card - (nameHeight + blurbHeight + partsHeight)) / 2)
	local name = Widgets.text(button, preset.name, Enum.Font.GothamBold, metrics.body + 3, Color.Text)
	name.Position = UDim2.fromOffset(24, top)
	name.Size = UDim2.new(1, -(24 + 90), 0, nameHeight)
	local tag = Widgets.text(button, "EQUIPPED", Enum.Font.GothamBold, metrics.small - 1, Color.Amber)
	tag.AnchorPoint = Vector2.new(1, 0)
	tag.Position = UDim2.new(1, -12, 0, top + 2)
	tag.Size = UDim2.fromOffset(78, nameHeight - 2)
	tag.TextXAlignment = Enum.TextXAlignment.Right
	tag.Visible = false
	local blurb = Widgets.text(button, preset.blurb, Enum.Font.GothamMedium, metrics.small + 1, Color.Muted)
	blurb.Position = UDim2.fromOffset(24, top + nameHeight)
	blurb.Size = UDim2.new(1, -36, 0, blurbHeight)
	blurb.TextTruncate = Enum.TextTruncate.AtEnd
	if metrics.cardParts then
		local parts = Widgets.text(button, Loadout.summary(preset), Enum.Font.GothamMedium, metrics.small - 1, color)
		parts.Position = UDim2.fromOffset(24, top + nameHeight + blurbHeight)
		parts.Size = UDim2.new(1, -36, 0, partsHeight)
		parts.TextTruncate = Enum.TextTruncate.AtEnd
	end
	return { option = option, tag = tag }
end

-- A grid of paint swatches. The first swatch of every list means the side's team color.
local function newSwatches(
	parent: Instance,
	order: number,
	metrics: Widgets.Metrics,
	swatches: { Looks.Swatch },
	teamColor: Looks.Rgb,
	onPick: (index: number) -> ()
): { Widgets.Option }
	local box = Widgets.grid(parent, order, Vector2.new(metrics.cell, metrics.cell), metrics.cellGap, nil)
	local options: { Widgets.Option } = {}
	for index, swatch in swatches do
		local color = toColor(swatch.color or teamColor)
		local option = Widgets.option(box, true, function()
			onPick(index)
		end)
		option.button.LayoutOrder = index
		option.button.BackgroundColor3 = color
		if swatch.color == nil then
			local luma = 0.299 * color.R + 0.587 * color.G + 0.114 * color.B
			option.button.Text = "TEAM"
			option.button.Font = Enum.Font.GothamBold
			option.button.TextSize = metrics.small - 2
			option.button.TextColor3 = if luma > 0.55 then Color.Dark else Color3.new(1, 1, 1)
		end
		options[index] = option
	end
	return options
end

local function nameOf(item: { name: string }): string
	return item.name
end

local function namesOf<T>(list: { T }, read: (item: T) -> string): { string }
	local names: { string } = {}
	for _, entry in list do
		table.insert(names, read(entry))
	end
	return names
end

local function buildUi(gui: GuiBase2d, mode: string, actions: Actions): Ui
	local metrics = if mode == "side" then Widgets.Regular else Widgets.Compact
	local pad = metrics.pad

	local panel = Instance.new("Frame")
	panel.Name = "Garage"
	panel.BackgroundColor3 = Color.Panel
	panel.BackgroundTransparency = 0.06
	panel.BorderSizePixel = 0
	panel.Active = true
	panel.Visible = false
	panel.ZIndex = 30
	panel.Parent = gui
	Widgets.round(panel, 12)
	Widgets.stroke(panel, Color.Teal, 1.5, 0.45)

	local rest: UDim2
	local hidden: UDim2
	if mode == "sheet" then
		panel.AnchorPoint = Vector2.new(0.5, 1)
		panel.Size = UDim2.new(1, -2 * metrics.margin, SHEET_HEIGHT, 0)
		rest = UDim2.new(0.5, 0, 1, -metrics.margin)
		hidden = UDim2.fromScale(0.5, 1.7)
	else
		panel.AnchorPoint = Vector2.new(0, 0.5)
		panel.Size = UDim2.new(0, metrics.width, 1, -2 * metrics.margin)
		rest = UDim2.new(0, metrics.margin, 0.5, 0)
		hidden = UDim2.new(0, -(metrics.width + 40), 0.5, 0)
	end
	panel.Position = rest

	-- The header: the title and the name of the build, with DONE at the right.
	local headerWidth = UDim2.new(1, -(pad * 2 + metrics.done.X + 8), 0, 0)
	local title = Widgets.text(panel, "GARAGE", Enum.Font.Michroma, metrics.title, Color3.new(1, 1, 1))
	title.Position = UDim2.fromOffset(pad, pad)
	title.Size = headerWidth + UDim2.fromOffset(0, metrics.title + 4)
	local name = Widgets.text(panel, "", Enum.Font.GothamBold, metrics.name, Color.Teal)
	name.Position = UDim2.fromOffset(pad, pad + metrics.title + 6)
	name.Size = headerWidth + UDim2.fromOffset(0, metrics.name + 4)
	name.TextTruncate = Enum.TextTruncate.AtEnd
	local done = Instance.new("TextButton")
	done.Name = "Done"
	done.AnchorPoint = Vector2.new(1, 0)
	done.Position = UDim2.new(1, -pad, 0, pad)
	done.Size = UDim2.fromOffset(metrics.done.X, metrics.done.Y)
	done.BackgroundColor3 = Color.Amber
	done.BorderSizePixel = 0
	done.Text = "DONE"
	done.Font = Enum.Font.GothamBlack
	done.TextSize = metrics.tabText + 1
	done.TextColor3 = Color.Dark
	done.Parent = panel
	Widgets.round(done, 8)
	done.Activated:Connect(actions.done)

	-- The tabs.
	local tabsTop = pad + metrics.title + metrics.name + metrics.gap + 8
	local tabBar = Widgets.grid(panel, 0, Vector2.new(0, metrics.tab), 4, #TAB_NAMES)
	tabBar.Name = "Tabs"
	tabBar.Position = UDim2.fromOffset(pad, tabsTop)
	tabBar.Size = UDim2.new(1, -2 * pad, 0, metrics.tab)
	local tabs: { TabUi } = {}
	for index, tabName in TAB_NAMES do
		local button = Instance.new("TextButton")
		button.Name = tabName
		button.LayoutOrder = index
		button.AutoButtonColor = false
		button.BackgroundColor3 = Color.Row
		button.BorderSizePixel = 0
		button.Text = tabName
		button.Font = Enum.Font.GothamBold
		button.TextSize = metrics.tabText
		button.TextColor3 = Color.Muted
		button.Parent = tabBar
		Widgets.round(button, 8)
		local line = Instance.new("Frame")
		line.AnchorPoint = Vector2.new(0.5, 1)
		line.BackgroundColor3 = Color.Teal
		line.BorderSizePixel = 0
		line.Position = UDim2.new(0.5, 0, 1, -3)
		line.Size = UDim2.new(1, -24, 0, 2)
		line.Visible = false
		line.Parent = button
		Widgets.round(line, 1)
		button.Activated:Connect(function()
			actions.tab(index)
		end)
		tabs[index] = { button = button, line = line }
	end

	-- One scrolling page for each tab.
	local bodyTop = tabsTop + metrics.tab + metrics.gap
	local pages: { ScrollingFrame } = {}
	for index = 1, #TAB_NAMES do
		local page = Instance.new("ScrollingFrame")
		page.Name = TAB_NAMES[index]
		page.BackgroundTransparency = 1
		page.BorderSizePixel = 0
		page.Position = UDim2.fromOffset(pad, bodyTop)
		page.Size = UDim2.new(1, -2 * pad, 1, -(bodyTop + pad))
		page.CanvasSize = UDim2.new()
		page.AutomaticCanvasSize = Enum.AutomaticSize.Y
		page.ScrollingDirection = Enum.ScrollingDirection.Y
		page.ScrollBarThickness = 4
		page.ScrollBarImageColor3 = Color.Teal
		page.ScrollBarImageTransparency = 0.5
		page.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
		page.Visible = index == 1
		page.Parent = panel
		Widgets.list(page, metrics.gap)
		Widgets.padding(page, 0, 10, 8, 0)
		pages[index] = page
	end

	-- BUILD.
	local stats = { Widgets.stats(pages[1], 1, metrics), Widgets.stats(pages[2], 1, metrics) }
	local chassisNames = namesOf(Loadout.Chassis, nameOf)
	local chassis = newSlot(pages[1], 2, metrics, chassisNames, CHASSIS_COLORS, actions.chassis)
	local modules: { [string]: SlotUi } = {}
	for order, slot in Loadout.Slots do
		modules[slot] = newSlot(
			pages[1],
			2 + order,
			metrics,
			namesOf(Loadout.Modules[slot], nameOf),
			nil,
			function(index: number)
				actions.module(slot, index)
			end
		)
	end

	-- PRESETS.
	local presets: { PresetUi } = {}
	for index, preset in Loadout.Presets do
		presets[index] = newPreset(pages[2], 1 + index, metrics, preset, function()
			actions.preset(index)
		end)
	end

	-- PAINT.
	local armorBox, armorHead = Widgets.section(pages[3], 1, metrics)
	local armor = newSwatches(armorBox, 2, metrics, Looks.Armor, Looks.Team.me.armor, actions.armor)
	local accentBox, accentHead = Widgets.section(pages[3], 2, metrics)
	local accent = newSwatches(accentBox, 2, metrics, Looks.Accents, Looks.Team.me.accent, actions.accent)
	local finishBox, finishHead = Widgets.section(pages[3], 3, metrics)
	local finish = chipRow(finishBox, 2, metrics, namesOf(Looks.Finishes, nameOf), nil, 4, actions.finish)
	local crestBox, crestHead = Widgets.section(pages[3], 4, metrics)
	local crestColumns = if mode == "side" then #Looks.Crests else 3
	local crest = chipRow(crestBox, 2, metrics, Looks.Crests, nil, crestColumns, actions.crest)

	return {
		mode = mode,
		metrics = metrics,
		panel = panel,
		rest = rest,
		hidden = hidden,
		name = name,
		tabs = tabs,
		pages = pages,
		stats = stats,
		chassis = chassis,
		modules = modules,
		presets = presets,
		armorHead = armorHead,
		armor = armor,
		accentHead = accentHead,
		accent = accent,
		finishHead = finishHead,
		finish = finish,
		crestHead = crestHead,
		crest = crest,
	}
end

local function sameChoice(a: Loadout.Choice, b: Loadout.Choice): boolean
	return a.chassis == b.chassis and a.arms == b.arms and a.core == b.core and a.legs == b.legs
end

function GaragePanel.new(options: Options): Panel
	local gui = options.gui
	local owner = options.owner

	local choice: Loadout.Choice = Loadout.decode(owner:GetAttribute("GarageLoadout"))
	local look: Looks.Look = Looks.decode(owner:GetAttribute("GarageLook"))
	local ui: Ui? = nil
	local opened = false
	local tab = 1
	local compact = false
	-- Picks the server has not confirmed yet, since when, and until when the robot keeps wearing them after it has.
	local dirty = false
	local dirtySince = 0
	local holdUntil = 0
	local lastSend = -math.huge
	local lastNow = os.clock()
	local openedAt = -math.huge
	local lastSize = Vector2.zero

	local function moduleIndex(slot: string): number
		return if slot == "ARMS" then choice.arms elseif slot == "CORE" then choice.core else choice.legs
	end

	-- Draws the picks: bars, names, which chips are chosen and what they say.
	local function refresh()
		local current = ui
		if current == nil then
			return
		end
		local ratings = Loadout.ratings(Loadout.stats(Loadout.encode(choice)))
		local values = { ratings.health, ratings.mobility, ratings.damage, ratings.speed, ratings.reach }
		for _, card in current.stats do
			card.set(values)
		end
		current.name.Text = Loadout.buildName(choice)

		local chassis = Loadout.Chassis[choice.chassis]
		current.chassis.head.Text = richName("CHASSIS", chassis.name)
		for index, chip in current.chassis.chips do
			Widgets.setSelected(chip, index == choice.chassis)
		end
		current.chassis.detail.set(chassis.role, chassis.blurb, Loadout.describe(chassis.mods))
		for _, slot in Loadout.Slots do
			local slotUi = current.modules[slot]
			local picked = moduleIndex(slot)
			local module = Loadout.Modules[slot][picked]
			slotUi.head.Text = richName(slot, module.name)
			for index, chip in slotUi.chips do
				Widgets.setSelected(chip, index == picked)
			end
			slotUi.detail.set(nil, module.blurb, Loadout.describe(module.mods))
		end

		local equipped = Loadout.presetIndex(choice)
		for index, entry in current.presets do
			Widgets.setSelected(entry.option, index == equipped)
			entry.tag.Visible = index == equipped
		end

		current.armorHead.Text = richName("ARMOR", Looks.Armor[look.armor].name)
		current.accentHead.Text = richName("ACCENT", Looks.Accents[look.accent].name)
		current.finishHead.Text = richName("FINISH", Looks.Finishes[look.finish].name)
		current.crestHead.Text = richName("CREST", Looks.Crests[look.crest])
		for index, option in current.armor do
			Widgets.setSelected(option, index == look.armor)
		end
		for index, option in current.accent do
			Widgets.setSelected(option, index == look.accent)
		end
		for index, option in current.finish do
			Widgets.setSelected(option, index == look.finish)
		end
		for index, option in current.crest do
			Widgets.setSelected(option, index == look.crest)
		end
	end

	local function applyTab()
		local current = ui
		if current == nil then
			return
		end
		for index, page in current.pages do
			page.Visible = index == tab
		end
		for index, entry in current.tabs do
			local active = index == tab
			entry.button.BackgroundColor3 = if active then Color.Hot else Color.Row
			entry.button.TextColor3 = if active then Color.Text else Color.Muted
			entry.line.Visible = active
		end
	end

	local function commit(nextChoice: Loadout.Choice?, nextLook: Looks.Look?)
		if nextChoice ~= nil then
			choice = nextChoice
		end
		if nextLook ~= nil then
			look = nextLook
		end
		dirty = true
		dirtySince = lastNow
		holdUntil = 0
		options.play("clank", 0.16, 1.9)
		refresh()
	end

	local function withLook(armor: number?, accent: number?, finish: number?, crest: number?): Looks.Look
		return {
			armor = armor or look.armor,
			accent = accent or look.accent,
			finish = finish or look.finish,
			crest = crest or look.crest,
		}
	end

	local function setTab(index: number)
		local wrapped = ((index - 1) % #TAB_NAMES) + 1
		local current = ui
		if wrapped ~= tab and current ~= nil then
			tab = wrapped
			current.pages[tab].CanvasPosition = Vector2.zero
			options.play("clank", 0.1, 2.3)
			applyTab()
		end
	end

	local close: () -> ()
	local actions: Actions = {
		chassis = function(index: number)
			if index ~= choice.chassis then
				commit({ chassis = index, arms = choice.arms, core = choice.core, legs = choice.legs }, nil)
			end
		end,
		module = function(slot: string, index: number)
			if index ~= moduleIndex(slot) then
				commit({
					chassis = choice.chassis,
					arms = if slot == "ARMS" then index else choice.arms,
					core = if slot == "CORE" then index else choice.core,
					legs = if slot == "LEGS" then index else choice.legs,
				}, nil)
			end
		end,
		preset = function(index: number)
			local preset = Loadout.Presets[index]
			local next: Loadout.Choice = {
				chassis = preset.chassis,
				arms = preset.arms,
				core = preset.core,
				legs = preset.legs,
			}
			if not sameChoice(next, choice) then
				commit(next, nil)
			end
		end,
		armor = function(index: number)
			if index ~= look.armor then
				commit(nil, withLook(index, nil, nil, nil))
			end
		end,
		accent = function(index: number)
			if index ~= look.accent then
				commit(nil, withLook(nil, index, nil, nil))
			end
		end,
		finish = function(index: number)
			if index ~= look.finish then
				commit(nil, withLook(nil, nil, index, nil))
			end
		end,
		crest = function(index: number)
			if index ~= look.crest then
				commit(nil, withLook(nil, nil, nil, index))
			end
		end,
		tab = setTab,
		done = function()
			close()
		end,
	}

	local function modeFor(size: Vector2): string
		if size.X / math.max(size.Y, 1) < SHEET_ASPECT then
			return "sheet"
		end
		return if compact then "compact" else "side"
	end

	-- Builds the panel for the view's size, or builds it again when the size or the input changed what suits it.
	local function ensureUi()
		local size = gui.AbsoluteSize
		if size.X <= 0 or size.Y <= 0 then
			return
		end
		local mode = modeFor(size)
		local current = ui
		if current ~= nil and current.mode == mode then
			return
		end
		if current ~= nil then
			current.panel:Destroy()
		end
		local built = buildUi(gui, mode, actions)
		ui = built
		built.panel.Visible = opened
		refresh()
		applyTab()
	end

	local function adopt(loadoutCode: number, lookCode: number)
		choice = Loadout.decode(loadoutCode)
		look = Looks.decode(lookCode)
		refresh()
	end

	-- The codes the server has published for the player. Anything that is not a real code is ignored.
	local function serverCodes(): (number?, number?)
		local loadoutCode = owner:GetAttribute("GarageLoadout")
		local lookCode = owner:GetAttribute("GarageLook")
		if not Loadout.isValidCode(loadoutCode) or not Looks.isValidCode(lookCode) then
			return nil, nil
		end
		return loadoutCode :: number, lookCode :: number
	end

	local function slide(target: UDim2, style: Enum.EasingStyle, direction: Enum.EasingDirection, seconds: number)
		local current = ui
		if current ~= nil then
			TweenService:Create(current.panel, TweenInfo.new(seconds, style, direction), { Position = target }):Play()
		end
	end

	local function open()
		if opened then
			return
		end
		opened = true
		openedAt = lastNow
		local loadoutCode, lookCode = serverCodes()
		if not dirty and loadoutCode ~= nil and lookCode ~= nil then
			adopt(loadoutCode, lookCode)
		end
		ensureUi()
		local current = ui
		if current ~= nil then
			current.panel.Visible = true
			current.panel.Position = current.hidden
			slide(current.rest, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0.32)
			if UserInputService.PreferredInput == Enum.PreferredInput.Gamepad then
				GuiService.SelectedObject = current.chassis.chips[choice.chassis].button
			end
		end
		options.play("whoosh", 0.25, 1.5)
	end

	close = function()
		if not opened then
			return
		end
		opened = false
		local current = ui
		if current ~= nil then
			slide(current.hidden, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0.2)
			task.delay(0.22, function()
				if not opened and ui == current then
					current.panel.Visible = false
				end
			end)
			if GuiService.SelectedObject ~= nil and GuiService.SelectedObject:IsDescendantOf(current.panel) then
				GuiService.SelectedObject = nil
			end
		end
	end

	local function step(now: number)
		lastNow = now
		local loadoutCode, lookCode = serverCodes()
		if dirty then
			if loadoutCode == Loadout.encode(choice) and lookCode == Looks.encode(look) then
				dirty = false
				holdUntil = now + HOLD_SECONDS
			elseif now - dirtySince > GIVE_UP_SECONDS then
				-- The server never took the picks, so show what it has.
				dirty = false
				if loadoutCode ~= nil and lookCode ~= nil then
					adopt(loadoutCode, lookCode)
				end
			elseif now - lastSend >= SEND_INTERVAL then
				lastSend = now
				options.send({
					chassis = choice.chassis,
					arms = choice.arms,
					core = choice.core,
					legs = choice.legs,
					armor = look.armor,
					accent = look.accent,
					finish = look.finish,
					crest = look.crest,
				})
			end
		elseif now >= holdUntil and loadoutCode ~= nil and lookCode ~= nil then
			-- Nothing of ours is waiting, so follow the server (a saved garage arriving late, for one).
			if loadoutCode ~= Loadout.encode(choice) or lookCode ~= Looks.encode(look) then
				adopt(loadoutCode, lookCode)
			end
		end

		local size = gui.AbsoluteSize
		if size ~= lastSize then
			lastSize = size
			if ui ~= nil or opened then
				ensureUi()
			end
		elseif opened and ui == nil then
			ensureUi()
		end
	end

	local keys = UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if not opened then
			return
		end
		local key = input.KeyCode
		local settled = lastNow - openedAt > KEY_GUARD
		if
			key == Enum.KeyCode.ButtonB or (not processed and (key == Enum.KeyCode.Backspace or key == Enum.KeyCode.G))
		then
			if settled then
				close()
			end
		elseif key == Enum.KeyCode.ButtonL1 or (not processed and key == Enum.KeyCode.Q) then
			setTab(tab - 1)
		elseif key == Enum.KeyCode.ButtonR1 or (not processed and key == Enum.KeyCode.E) then
			setTab(tab + 1)
		end
	end)

	return {
		open = open,
		close = close,
		isOpen = function()
			return opened
		end,
		actions = actions,
		step = step,
		preview = function(): (number?, number?)
			if dirty or lastNow < holdUntil then
				return Loadout.encode(choice), Looks.encode(look)
			end
			return nil, nil
		end,
		current = function(): (number, number)
			return Loadout.encode(choice), Looks.encode(look)
		end,
		room = function(viewport: Vector2): (number, number)
			local current = ui
			if current == nil then
				return 0, 0
			end
			local origin = gui.AbsolutePosition
			local size = gui.AbsoluteSize
			if current.mode == "sheet" then
				local top = origin.Y + size.Y - current.metrics.margin - size.Y * SHEET_HEIGHT
				return 0, math.clamp((viewport.Y - top) / math.max(viewport.Y, 1), 0, 0.9)
			end
			local right = origin.X + current.metrics.margin + current.metrics.width + 8
			return math.clamp(right / math.max(viewport.X, 1), 0, 0.85), 0
		end,
		setCompact = function(value: boolean)
			if value ~= compact then
				compact = value
				if ui ~= nil then
					ensureUi()
				end
			end
		end,
		destroy = function()
			keys:Disconnect()
			local current = ui
			if current ~= nil then
				current.panel:Destroy()
			end
			ui = nil
			opened = false
		end,
	}
end

return GaragePanel
