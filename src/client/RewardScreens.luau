--!strict

-- Client: the reward screens. CASES shows a case, how many the player has, what opening one costs and every item's odds
-- before anything is opened or bought (see Cases: the same numbers decide the draw), the pity counter and what a
-- duplicate turns into; opening one plays a reel that comes to rest on what the server drew. REWARDS shows the seven-day
-- daily reward and the day's contracts. Both only ask the server (see Rewards on the server) and show what it sends back.

local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cases = require(Shared:WaitForChild("Cases"))
local Contracts = require(Shared:WaitForChild("Contracts"))
local DailyRewards = require(Shared:WaitForChild("DailyRewards"))
local Looks = require(Shared:WaitForChild("Looks"))
local Shop = require(Shared:WaitForChild("Shop"))

export type CaseState = { id: string, count: number, pity: number }

export type State = {
	ready: boolean,
	packs: boolean,
	today: number,
	coins: number?,
	cases: { CaseState }?,
	daily: { ready: boolean, streak: number, cycleDay: number, broken: boolean }?,
	contracts: {
		list: { { id: string, text: string, goal: number, progress: number, coins: number } },
		bonus: boolean,
		bonusCoins: number,
	}?,
}

export type Opened = {
	case: string,
	item: string,
	rarity: number,
	name: string,
	kind: string,
	duplicate: boolean,
	refund: number,
	pity: boolean,
}

export type Options = {
	gui: ScreenGui,
	-- Asks the server: "daily", "open" (case id, "coins" or "case"), "buy" (case id, pack index), "sync".
	send: (action: string, first: any?, second: any?) -> (),
	-- Puts an item on the player's robot (through the garage).
	equip: (item: string) -> (),
	play: (name: string, gain: number?, pitch: number?) -> (),
	-- The items the player owns.
	owned: () -> { [string]: boolean },
}

export type Screens = {
	open: (name: string) -> (),
	-- Closes the screens; a reel that is still running keeps them open unless `force` (a fight starting) cuts it short.
	close: (force: boolean?) -> (),
	isOpen: () -> boolean,
	setState: (state: State) -> (),
	reveal: (opened: Opened) -> (),
	-- For the hall's buttons: whether the daily reward waits, and how many unopened cases the player has.
	dailyReady: () -> boolean,
	casesWaiting: () -> number,
}

local RewardScreens = {}

local PANEL = Color3.fromRGB(8, 10, 18)
local ROW = Color3.fromRGB(18, 23, 38)
local ROW_HOT = Color3.fromRGB(30, 40, 66)
-- A progress bar's empty track, which has to read against both the panel and a row.
local TRACK = Color3.fromRGB(38, 46, 70)
local TEAL = Color3.fromRGB(64, 214, 232)
local AMBER = Color3.fromRGB(255, 200, 90)
local GREEN = Color3.fromRGB(86, 200, 120)
local MUTED = Color3.fromRGB(140, 154, 184)
local DARK = Color3.fromRGB(10, 14, 24)
local WHITE = Color3.new(1, 1, 1)

local CASES_SIZE = Vector2.new(820, 548)
local REWARDS_SIZE = Vector2.new(760, 520)
local CARD_WIDTH = 140
local CARD_GAP = 8
local REEL_CARDS = 46
local REEL_WINNER = 39
local REEL_SECONDS = 4.8

local function rgb(color: Looks.Rgb): Color3
	return Color3.fromRGB(color[1], color[2], color[3])
end

local function round(instance: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = instance
end

local function outline(instance: Instance, color: Color3, transparency: number, thickness: number): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = color
	stroke.Transparency = transparency
	stroke.Thickness = thickness
	stroke.Parent = instance
	return stroke
end

local function text(
	parent: Instance,
	content: string,
	font: Enum.Font,
	size: number,
	color: Color3,
	position: UDim2,
	extent: UDim2,
	alignX: Enum.TextXAlignment?
): TextLabel
	local item = Instance.new("TextLabel")
	item.BackgroundTransparency = 1
	item.Text = content
	item.Font = font
	item.TextSize = size
	item.TextColor3 = color
	item.TextXAlignment = alignX or Enum.TextXAlignment.Left
	item.TextYAlignment = Enum.TextYAlignment.Center
	item.Position = position
	item.Size = extent
	item.TextWrapped = true
	item.Parent = parent
	return item
end

local function button(parent: Instance, content: string, color: Color3, position: UDim2, extent: UDim2): TextButton
	local item = Instance.new("TextButton")
	item.BackgroundColor3 = color
	item.BorderSizePixel = 0
	item.AutoButtonColor = true
	item.Text = content
	item.Font = Enum.Font.GothamBlack
	item.TextSize = 15
	item.TextColor3 = DARK
	item.Position = position
	item.Size = extent
	item.Parent = parent
	round(item, 8)
	return item
end

-- A panel in the middle of the screen, scaled down to fit a small one.
local function panel(parent: Instance, name: string, size: Vector2): (Frame, UIScale)
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromOffset(size.X, size.Y)
	frame.BackgroundColor3 = PANEL
	frame.BackgroundTransparency = 0.04
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.Parent = parent
	round(frame, 14)
	outline(frame, TEAL, 0.45, 1.5)
	local scale = Instance.new("UIScale")
	scale.Parent = frame
	return frame, scale
end

local function closeButton(parent: Instance, onClose: () -> ()): TextButton
	local close = button(parent, "CLOSE", ROW, UDim2.new(1, -112, 0, 18), UDim2.fromOffset(92, 34))
	close.Name = "Close"
	close.TextColor3 = MUTED
	close.TextSize = 13
	close.Activated:Connect(onClose)
	return close
end

-- A progress bar: a track and a fill that is `fraction` of it.
local function bar(parent: Instance, position: UDim2, extent: UDim2, color: Color3): Frame
	local track = Instance.new("Frame")
	track.BackgroundColor3 = TRACK
	track.BorderSizePixel = 0
	track.Position = position
	track.Size = extent
	track.Parent = parent
	round(track, 4)
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = color
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(0, 1)
	fill.Parent = track
	round(fill, 4)
	return track
end

local function setBar(track: Frame, fraction: number)
	local fill = track:FindFirstChild("Fill")
	if fill ~= nil and fill:IsA("Frame") then
		fill.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
	end
end

-- An item as a card in the reel, centered on `center`: its name and kind over a bar in its rarity's color.
local function itemCard(parent: Instance, item: string, rarity: number, center: UDim2): Frame
	local color = rgb(Cases.Rarities[rarity].color)
	local card = Instance.new("Frame")
	card.BackgroundColor3 = Color3.fromRGB(22, 27, 40)
	card.BorderSizePixel = 0
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = center
	card.Size = UDim2.fromOffset(CARD_WIDTH, 150)
	card.Parent = parent
	round(card, 10)
	outline(card, color, 0.35, 2)
	local glow = Instance.new("Frame")
	glow.BackgroundColor3 = color
	glow.BackgroundTransparency = 0.78
	glow.BorderSizePixel = 0
	glow.Size = UDim2.new(1, 0, 0, 64)
	glow.Parent = card
	round(glow, 10)
	local described = Looks.describe(item)
	text(
		card,
		if described ~= nil then described.name else item,
		Enum.Font.GothamBlack,
		15,
		WHITE,
		UDim2.fromOffset(10, 18),
		UDim2.new(1, -20, 0, 44),
		Enum.TextXAlignment.Center
	)
	text(
		card,
		if described ~= nil then described.kind else "",
		Enum.Font.GothamMedium,
		11,
		MUTED,
		UDim2.fromOffset(10, 76),
		UDim2.new(1, -20, 0, 30),
		Enum.TextXAlignment.Center
	)
	local strip = Instance.new("Frame")
	strip.BackgroundColor3 = color
	strip.BorderSizePixel = 0
	strip.AnchorPoint = Vector2.new(0, 1)
	strip.Position = UDim2.fromScale(0, 1)
	strip.Size = UDim2.new(1, 0, 0, 26)
	strip.Parent = card
	round(strip, 10)
	text(
		strip,
		Cases.Rarities[rarity].name,
		Enum.Font.GothamBlack,
		12,
		DARK,
		UDim2.fromScale(0, 0),
		UDim2.fromScale(1, 1),
		Enum.TextXAlignment.Center
	)
	return card
end

function RewardScreens.new(options: Options): Screens
	local root = Instance.new("Frame")
	root.Name = "RewardScreens"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.Visible = false
	root.ZIndex = 30
	root.Parent = options.gui
	local shade = Instance.new("TextButton")
	shade.Name = "Shade"
	shade.Size = UDim2.fromScale(1, 1)
	shade.BackgroundColor3 = Color3.fromRGB(2, 4, 12)
	shade.BackgroundTransparency = 0.35
	shade.BorderSizePixel = 0
	shade.AutoButtonColor = false
	shade.Text = ""
	shade.Selectable = false
	shade.Parent = root

	local state: State = { ready = false, packs = false, today = 0 }
	local current = ""
	local revealing = false
	local caseId = Cases.List[1].id

	-- With a gamepad, the selection goes straight to the button that matters.
	local function focus(target: GuiObject?)
		if UserInputService.PreferredInput == Enum.PreferredInput.Gamepad then
			GuiService.SelectedObject = target
		end
	end

	local function caseState(id: string): CaseState
		local held: { CaseState } = state.cases or {}
		for _, entry in held do
			if entry.id == id then
				return entry
			end
		end
		return { id = id, count = 0, pity = 0 }
	end

	-- CASES ---------------------------------------------------------------------------------------------------------------
	local cases, casesScale = panel(root, "Cases", CASES_SIZE)
	local case = Cases.get(caseId) :: Cases.Case
	text(cases, case.name, Enum.Font.Michroma, 26, WHITE, UDim2.fromOffset(24, 16), UDim2.fromOffset(500, 36))
	text(
		cases,
		string.upper(case.blurb),
		Enum.Font.GothamMedium,
		12,
		MUTED,
		UDim2.fromOffset(24, 50),
		UDim2.fromOffset(560, 18)
	)

	-- The case itself: a crate with a band of every rarity's color.
	local art = Instance.new("Frame")
	art.BackgroundColor3 = Color3.fromRGB(34, 38, 52)
	art.BorderSizePixel = 0
	art.Position = UDim2.fromOffset(24, 84)
	art.Size = UDim2.fromOffset(340, 140)
	art.Parent = cases
	round(art, 12)
	outline(art, AMBER, 0.4, 2)
	local band = Instance.new("Frame")
	band.BackgroundTransparency = 1
	band.Position = UDim2.new(0, 14, 1, -26)
	band.Size = UDim2.new(1, -28, 0, 10)
	band.Parent = art
	local bandLayout = Instance.new("UIListLayout")
	bandLayout.FillDirection = Enum.FillDirection.Horizontal
	bandLayout.Padding = UDim.new(0, 4)
	bandLayout.Parent = band
	for _, rarity in Cases.Rarities do
		local segment = Instance.new("Frame")
		segment.BackgroundColor3 = rgb(rarity.color)
		segment.BorderSizePixel = 0
		segment.Size = UDim2.new(0.2, -4, 1, 0)
		segment.Parent = band
		round(segment, 3)
	end
	text(
		art,
		"?",
		Enum.Font.Michroma,
		64,
		AMBER,
		UDim2.fromOffset(0, 8),
		UDim2.new(1, 0, 0, 80),
		Enum.TextXAlignment.Center
	)

	local countLine =
		text(cases, "", Enum.Font.GothamBold, 14, WHITE, UDim2.fromOffset(24, 232), UDim2.fromOffset(340, 22))
	local openOwned = button(cases, "OPEN ONE", AMBER, UDim2.fromOffset(24, 260), UDim2.fromOffset(340, 42))
	openOwned.Name = "OpenOne"
	local openCoins = button(cases, "", TEAL, UDim2.fromOffset(24, 308), UDim2.fromOffset(340, 42))
	openCoins.Name = "OpenCoins"
	local packButtons: { TextButton } = {}
	for index, pack in case.packs do
		local width = (340 - 8 * (#case.packs - 1)) / #case.packs
		local item = button(
			cases,
			`{pack.count} {if pack.count == 1 then "CASE" else "CASES"}  ·  R$ {pack.robux}`,
			GREEN,
			UDim2.fromOffset(24 + (index - 1) * (width + 8), 356),
			UDim2.fromOffset(width, 42)
		)
		item.TextSize = 14
		item.Activated:Connect(function()
			options.send("buy", caseId, index)
		end)
		packButtons[index] = item
		item.Name = `Pack{index}`
	end
	local regionNote = text(
		cases,
		"Cases for Robux aren't offered where you play. Earn them with coins and daily rewards.",
		Enum.Font.GothamMedium,
		12,
		MUTED,
		UDim2.fromOffset(24, 356),
		UDim2.fromOffset(340, 42)
	)
	local pityLine =
		text(cases, "", Enum.Font.GothamBold, 12, AMBER, UDim2.fromOffset(24, 410), UDim2.fromOffset(340, 34))
	local pityBar = bar(cases, UDim2.fromOffset(24, 448), UDim2.fromOffset(340, 8), AMBER)
	local refunds = {}
	for _, rarity in Cases.Rarities do
		table.insert(refunds, `{rarity.name} {Shop.formatCoins(rarity.refund)}`)
	end
	text(
		cases,
		"An item you already own turns into coins: " .. table.concat(refunds, "  ·  "),
		Enum.Font.GothamMedium,
		11,
		MUTED,
		UDim2.fromOffset(24, 466),
		UDim2.fromOffset(340, 60)
	)
	openOwned.Activated:Connect(function()
		if not revealing then
			options.send("open", caseId, "case")
		end
	end)
	openCoins.Activated:Connect(function()
		if not revealing then
			options.send("open", caseId, "coins")
		end
	end)

	-- Every item's odds, by rarity, as they stand for the next open.
	local odds = Instance.new("ScrollingFrame")
	odds.Name = "Odds"
	odds.BackgroundColor3 = Color3.fromRGB(12, 15, 26)
	odds.BorderSizePixel = 0
	odds.Position = UDim2.fromOffset(388, 84)
	odds.Size = UDim2.fromOffset(408, 440)
	odds.CanvasSize = UDim2.new()
	odds.AutomaticCanvasSize = Enum.AutomaticSize.Y
	odds.ScrollBarThickness = 4
	odds.ScrollBarImageColor3 = TEAL
	odds.Parent = cases
	round(odds, 10)
	local oddsLayout = Instance.new("UIListLayout")
	oddsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	oddsLayout.Padding = UDim.new(0, 2)
	oddsLayout.Parent = odds
	local oddsPadding = Instance.new("UIPadding")
	oddsPadding.PaddingLeft = UDim.new(0, 14)
	oddsPadding.PaddingRight = UDim.new(0, 14)
	oddsPadding.PaddingTop = UDim.new(0, 10)
	oddsPadding.PaddingBottom = UDim.new(0, 12)
	oddsPadding.Parent = odds

	local function oddsRow(order: number, height: number): Frame
		local row = Instance.new("Frame")
		row.BackgroundTransparency = 1
		row.LayoutOrder = order
		row.Size = UDim2.new(1, 0, 0, height)
		row.Parent = odds
		return row
	end

	local function drawOdds()
		for _, child in odds:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end
		local mine = caseState(caseId)
		local due = Cases.pityDue(mine.pity)
		local rarityOdds = Cases.rarityOdds(mine.pity)
		local owned = options.owned()
		local order = 0
		local function nextOrder(): number
			order += 1
			return order
		end
		local head = oddsRow(nextOrder(), 44)
		text(head, "ODDS", Enum.Font.GothamBlack, 15, WHITE, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 22))
		text(
			head,
			if due
				then "This open is guaranteed: only LEGENDARY and MYTHIC can come."
				else "For the next open. Every item of a rarity is equally likely.",
			Enum.Font.GothamMedium,
			11,
			if due then AMBER else MUTED,
			UDim2.fromOffset(0, 22),
			UDim2.new(1, 0, 0, 20)
		)
		for rarity, items in case.items do
			local info = Cases.Rarities[rarity]
			local color = rgb(info.color)
			local title = oddsRow(nextOrder(), 26)
			local chip = Instance.new("Frame")
			chip.BackgroundColor3 = color
			chip.BorderSizePixel = 0
			chip.Position = UDim2.fromOffset(0, 8)
			chip.Size = UDim2.fromOffset(10, 10)
			chip.Parent = title
			round(chip, 3)
			text(title, info.name, Enum.Font.GothamBlack, 13, color, UDim2.fromOffset(18, 0), UDim2.new(1, -90, 1, 0))
			text(
				title,
				Cases.formatChance(rarityOdds[rarity]),
				Enum.Font.GothamBlack,
				13,
				color,
				UDim2.new(1, -80, 0, 0),
				UDim2.fromOffset(80, 26),
				Enum.TextXAlignment.Right
			)
			local each = oddsRow(nextOrder(), 16)
			text(
				each,
				`Each item below: {Cases.formatChance(rarityOdds[rarity] / #items)}`,
				Enum.Font.GothamMedium,
				11,
				MUTED,
				UDim2.fromOffset(18, 0),
				UDim2.new(1, -18, 1, 0)
			)
			for _, item in items do
				local line = oddsRow(nextOrder(), 18)
				local described = Looks.describe(item)
				text(
					line,
					if described ~= nil then `{described.name}  ·  {described.kind}` else item,
					Enum.Font.GothamMedium,
					12,
					Color3.fromRGB(206, 214, 230),
					UDim2.fromOffset(18, 0),
					UDim2.new(1, -90, 1, 0)
				)
				if owned[item] then
					text(
						line,
						"OWNED",
						Enum.Font.GothamBold,
						10,
						TEAL,
						UDim2.new(1, -80, 0, 0),
						UDim2.fromOffset(80, 18),
						Enum.TextXAlignment.Right
					)
				end
			end
		end
		local note = oddsRow(nextOrder(), 48)
		text(
			note,
			`LEGENDARY or better within {Cases.PityLimit} opens: when {Cases.PityLimit - 1} opens in a row have not given one, the next draws only LEGENDARY and MYTHIC, in proportion to their odds.`,
			Enum.Font.GothamMedium,
			11,
			MUTED,
			UDim2.fromOffset(0, 6),
			UDim2.new(1, 0, 1, -6)
		)
	end

	local function drawCases()
		local mine = caseState(caseId)
		local coins = state.coins or 0
		countLine.Text = if mine.count > 0 then `YOU HAVE {mine.count} UNOPENED` else "NO UNOPENED CASES"
		openOwned.Visible = mine.count > 0
		openCoins.Position = UDim2.fromOffset(24, if mine.count > 0 then 308 else 260)
		openCoins.Text = if coins >= case.coins
			then `OPEN  ·  {Shop.formatCoins(case.coins)} COINS`
			else `NEED {Shop.formatCoins(case.coins)} COINS (YOU HAVE {Shop.formatCoins(coins)})`
		openCoins.BackgroundColor3 = if coins >= case.coins then TEAL else ROW
		openCoins.TextColor3 = if coins >= case.coins then DARK else MUTED
		openCoins.AutoButtonColor = coins >= case.coins
		local packY = if mine.count > 0 then 356 else 308
		local forSale = false
		for index, pack in case.packs do
			local shown = state.packs and Cases.forSale(pack)
			packButtons[index].Visible = shown
			packButtons[index].Position = UDim2.fromOffset(packButtons[index].Position.X.Offset, packY)
			forSale = forSale or Cases.forSale(pack)
		end
		regionNote.Visible = forSale and not state.packs and state.ready
		regionNote.Position = UDim2.fromOffset(24, packY)
		local due = Cases.pityDue(mine.pity)
		local left = Cases.PityLimit - mine.pity
		pityLine.Text = if due
			then "YOUR NEXT OPEN IS A GUARANTEED LEGENDARY OR MYTHIC"
			else `LEGENDARY OR BETTER GUARANTEED WITHIN {left} OPENS`
		setBar(pityBar, mine.pity / (Cases.PityLimit - 1))
		drawOdds()
	end

	-- The reel ---------------------------------------------------------------------------------------------------------
	local reveal = Instance.new("Frame")
	reveal.Name = "Reveal"
	reveal.Size = UDim2.fromScale(1, 1)
	reveal.BackgroundColor3 = Color3.fromRGB(2, 4, 12)
	reveal.BackgroundTransparency = 0.2
	reveal.BorderSizePixel = 0
	reveal.Visible = false
	reveal.ZIndex = 5
	reveal.Parent = root
	local strip = Instance.new("Frame")
	strip.Name = "Strip"
	strip.AnchorPoint = Vector2.new(0.5, 0.5)
	strip.Position = UDim2.fromScale(0.5, 0.42)
	strip.Size = UDim2.new(1, 0, 0, 170)
	strip.BackgroundColor3 = Color3.fromRGB(10, 13, 22)
	strip.BackgroundTransparency = 0.1
	strip.BorderSizePixel = 0
	strip.ClipsDescendants = true
	strip.Parent = reveal
	local reel = Instance.new("Frame")
	reel.BackgroundTransparency = 1
	reel.Size = UDim2.fromOffset(REEL_CARDS * (CARD_WIDTH + CARD_GAP), 150)
	reel.Parent = strip
	local marker = Instance.new("Frame")
	marker.AnchorPoint = Vector2.new(0.5, 0.5)
	marker.Position = UDim2.fromScale(0.5, 0.5)
	marker.Size = UDim2.new(0, 2, 1, 0)
	marker.BackgroundColor3 = AMBER
	marker.BackgroundTransparency = 0.55
	marker.BorderSizePixel = 0
	marker.ZIndex = 3
	marker.Parent = strip
	-- Solid notches above and below the cards, so the line itself can stay faint over the card it points at.
	for _, edge in { 0, 1 } do
		local notch = Instance.new("Frame")
		notch.AnchorPoint = Vector2.new(0.5, edge)
		notch.Position = UDim2.fromScale(0.5, edge)
		notch.Size = UDim2.fromOffset(14, 9)
		notch.BackgroundColor3 = AMBER
		notch.BorderSizePixel = 0
		notch.ZIndex = 3
		notch.Parent = strip
	end

	local result = Instance.new("Frame")
	result.Name = "Result"
	result.AnchorPoint = Vector2.new(0.5, 0)
	result.Position = UDim2.new(0.5, 0, 0.42, 100)
	result.Size = UDim2.fromOffset(460, 190)
	result.BackgroundColor3 = PANEL
	result.BorderSizePixel = 0
	result.Visible = false
	result.Parent = reveal
	round(result, 14)
	local resultStroke = outline(result, AMBER, 0.1, 2.5)
	local resultRarity = text(
		result,
		"",
		Enum.Font.GothamBlack,
		14,
		AMBER,
		UDim2.fromOffset(0, 14),
		UDim2.new(1, 0, 0, 20),
		Enum.TextXAlignment.Center
	)
	local resultName = text(
		result,
		"",
		Enum.Font.Michroma,
		26,
		WHITE,
		UDim2.fromOffset(10, 36),
		UDim2.new(1, -20, 0, 36),
		Enum.TextXAlignment.Center
	)
	local resultLine = text(
		result,
		"",
		Enum.Font.GothamBold,
		13,
		TEAL,
		UDim2.fromOffset(10, 76),
		UDim2.new(1, -20, 0, 36),
		Enum.TextXAlignment.Center
	)
	local equip = button(result, "EQUIP", AMBER, UDim2.fromOffset(20, 126), UDim2.fromOffset(130, 44))
	equip.Name = "Equip"
	local again = button(result, "OPEN ANOTHER", TEAL, UDim2.fromOffset(165, 126), UDim2.fromOffset(150, 44))
	again.Name = "OpenAnother"
	again.TextSize = 13
	local done = button(result, "DONE", ROW, UDim2.fromOffset(330, 126), UDim2.fromOffset(110, 44))
	done.Name = "Done"
	done.TextColor3 = MUTED
	local shown: Opened? = nil
	local spin: Tween? = nil
	local ticking: RBXScriptConnection? = nil

	-- Stops the reel where it is, without the result's sounds (`shown` is cleared first, so its end is ignored).
	local function stopReveal()
		shown = nil
		local running = spin
		spin = nil
		if running ~= nil then
			running:Cancel()
		end
		local connection = ticking
		ticking = nil
		if connection ~= nil then
			connection:Disconnect()
		end
		revealing = false
		reveal.Visible = false
		result.Visible = false
	end

	local function finishReveal()
		stopReveal()
		drawCases()
		focus(if openOwned.Visible then openOwned else openCoins)
	end
	equip.Activated:Connect(function()
		local opened = shown
		if opened ~= nil then
			options.equip(opened.item)
			options.play("clank", 0.6, 1.6)
			equip.Text = "EQUIPPED"
		end
	end)
	again.Activated:Connect(function()
		local mine = caseState(caseId)
		finishReveal()
		if mine.count > 0 then
			options.send("open", caseId, "case")
		elseif (state.coins or 0) >= case.coins then
			options.send("open", caseId, "coins")
		end
	end)
	done.Activated:Connect(finishReveal)

	local function playReveal(opened: Opened)
		stopReveal()
		revealing = true
		shown = opened
		for _, child in reel:GetChildren() do
			child:Destroy()
		end
		-- The cards the reel runs past are drawn by the case's own odds, so it looks the way opening one goes; the server
		-- already decided where it stops.
		local random = Random.new()
		local winnerCard: Frame? = nil
		for index = 1, REEL_CARDS do
			local item, rarity = opened.item, opened.rarity
			if index ~= REEL_WINNER then
				local draw = Cases.draw(case, 0, random:NextNumber(), random:NextNumber())
				item, rarity = draw.item, draw.rarity
			end
			local card = itemCard(
				reel,
				item,
				rarity,
				UDim2.fromOffset((index - 1) * (CARD_WIDTH + CARD_GAP) + CARD_WIDTH / 2, 85)
			)
			if index == REEL_WINNER then
				winnerCard = card
			end
		end
		local step = CARD_WIDTH + CARD_GAP
		result.Visible = false
		reveal.Visible = true
		equip.Text = "EQUIP"
		local width = strip.AbsoluteSize.X
		-- Where the winning card's middle meets the marker, give or take a little so it never stops dead center.
		local finalX = width / 2
			- ((REEL_WINNER - 1) * step + CARD_WIDTH / 2)
			+ random:NextNumber(-CARD_WIDTH * 0.35, CARD_WIDTH * 0.35)
		local startX = width / 2 - (2 * step + CARD_WIDTH / 2)
		reel.Position = UDim2.fromOffset(startX, 0)
		local lastTick = 0
		ticking = RunService.RenderStepped:Connect(function()
			local passed = math.floor((startX - reel.Position.X.Offset) / step)
			if passed ~= lastTick then
				lastTick = passed
				options.play("clank", 0.14, 2.6)
			end
		end)
		local tween = TweenService:Create(
			reel,
			TweenInfo.new(REEL_SECONDS, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
			{ Position = UDim2.fromOffset(finalX, 0) }
		)
		spin = tween
		tween.Completed:Connect(function()
			if shown ~= opened then
				return
			end
			spin = nil
			local connection = ticking
			ticking = nil
			if connection ~= nil then
				connection:Disconnect()
			end
			local info = Cases.Rarities[opened.rarity]
			local color = rgb(info.color)
			-- The card it stopped on steps forward.
			local winner = winnerCard
			if winner ~= nil then
				winner.ZIndex = 2
				local edge = winner:FindFirstChildOfClass("UIStroke")
				if edge ~= nil then
					edge.Thickness = 3
					edge.Transparency = 0
				end
				local grow = Instance.new("UIScale")
				grow.Parent = winner
				TweenService
					:Create(
						grow,
						TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
						{ Scale = 1.08 }
					)
					:Play()
			end
			resultStroke.Color = color
			resultRarity.Text = if opened.pity then `{info.name}  ·  GUARANTEED` else info.name
			resultRarity.TextColor3 = color
			resultName.Text = opened.name
			resultLine.Text = if opened.duplicate
				then `{opened.kind}  ·  ALREADY YOURS: +{Shop.formatCoins(opened.refund)} COINS`
				else `{opened.kind}  ·  NEW!`
			resultLine.TextColor3 = if opened.duplicate then AMBER else TEAL
			equip.Visible = Looks.slotOf(opened.item) ~= nil
			local mine = caseState(caseId)
			again.Visible = mine.count > 0 or (state.coins or 0) >= case.coins
			result.Visible = true
			focus(if equip.Visible then equip else done)
			if opened.rarity >= 3 then
				options.play("boom", 0.6, 1.2)
			end
			options.play("bell", 0.7, 1.3 + opened.rarity * 0.1)
		end)
		tween:Play()
	end

	-- REWARDS -----------------------------------------------------------------------------------------------------------
	local rewards, rewardsScale = panel(root, "Rewards", REWARDS_SIZE)
	text(rewards, "REWARDS", Enum.Font.Michroma, 26, WHITE, UDim2.fromOffset(24, 16), UDim2.fromOffset(400, 36))
	text(
		rewards,
		"A new daily reward and new contracts every day at 00:00 UTC.",
		Enum.Font.GothamMedium,
		12,
		MUTED,
		UDim2.fromOffset(24, 50),
		UDim2.fromOffset(520, 18)
	)
	text(rewards, "DAILY REWARD", Enum.Font.GothamBlack, 13, MUTED, UDim2.fromOffset(24, 80), UDim2.fromOffset(300, 20))
	local streakLine = text(
		rewards,
		"",
		Enum.Font.GothamBold,
		12,
		AMBER,
		UDim2.fromOffset(336, 80),
		UDim2.fromOffset(400, 20),
		Enum.TextXAlignment.Right
	)
	local dayTiles: { { frame: Frame, stroke: UIStroke, label: TextLabel, amount: TextLabel, mark: TextLabel } } = {}
	local tileWidth = (712 - 6 * 8) / #DailyRewards.Cycle
	for index, reward in DailyRewards.Cycle do
		local tile = Instance.new("Frame")
		tile.BackgroundColor3 = ROW
		tile.BorderSizePixel = 0
		tile.Position = UDim2.fromOffset(24 + (index - 1) * (tileWidth + 8), 106)
		tile.Size = UDim2.fromOffset(tileWidth, 104)
		tile.Parent = rewards
		round(tile, 10)
		local stroke = outline(tile, AMBER, 1, 2)
		local label = text(
			tile,
			`DAY {index}`,
			Enum.Font.GothamBlack,
			12,
			MUTED,
			UDim2.fromOffset(0, 8),
			UDim2.new(1, 0, 0, 18),
			Enum.TextXAlignment.Center
		)
		local amount = text(
			tile,
			if reward.cases ~= nil then "CASE" else Shop.formatCoins(reward.coins),
			Enum.Font.GothamBlack,
			20,
			if reward.cases ~= nil then AMBER else WHITE,
			UDim2.fromOffset(0, 30),
			UDim2.new(1, 0, 0, 44),
			Enum.TextXAlignment.Center
		)
		local mark = text(
			tile,
			"COINS",
			Enum.Font.GothamBold,
			11,
			MUTED,
			UDim2.fromOffset(0, 76),
			UDim2.new(1, 0, 0, 18),
			Enum.TextXAlignment.Center
		)
		dayTiles[index] = { frame = tile, stroke = stroke, label = label, amount = amount, mark = mark }
	end
	local claim = button(rewards, "", AMBER, UDim2.fromOffset(24, 222), UDim2.fromOffset(320, 44))
	claim.Name = "Claim"
	claim.Activated:Connect(function()
		options.send("daily")
	end)

	text(
		rewards,
		"TODAY'S CONTRACTS",
		Enum.Font.GothamBlack,
		13,
		MUTED,
		UDim2.fromOffset(24, 284),
		UDim2.fromOffset(300, 20)
	)
	local contractRows: { { frame: Frame, label: TextLabel, count: TextLabel, reward: TextLabel, bar: Frame } } = {}
	for index = 1, Contracts.PerDay do
		local row = Instance.new("Frame")
		row.BackgroundColor3 = ROW
		row.BorderSizePixel = 0
		row.Position = UDim2.fromOffset(24, 308 + (index - 1) * 52)
		row.Size = UDim2.fromOffset(712, 44)
		row.Parent = rewards
		round(row, 8)
		local label = text(row, "", Enum.Font.GothamBold, 14, WHITE, UDim2.fromOffset(16, 0), UDim2.fromOffset(330, 44))
		local track = bar(row, UDim2.fromOffset(360, 18), UDim2.fromOffset(200, 8), TEAL)
		local count = text(
			row,
			"",
			Enum.Font.GothamBold,
			13,
			MUTED,
			UDim2.fromOffset(566, 0),
			UDim2.fromOffset(50, 44),
			Enum.TextXAlignment.Center
		)
		local reward = text(
			row,
			"",
			Enum.Font.GothamBlack,
			13,
			AMBER,
			UDim2.fromOffset(616, 0),
			UDim2.fromOffset(84, 44),
			Enum.TextXAlignment.Right
		)
		contractRows[index] = { frame = row, label = label, count = count, reward = reward, bar = track }
	end
	local bonusLine = text(
		rewards,
		"",
		Enum.Font.GothamBold,
		13,
		MUTED,
		UDim2.fromOffset(24, 466),
		UDim2.fromOffset(712, 30),
		Enum.TextXAlignment.Center
	)

	local function drawRewards()
		local daily = state.daily
		if daily ~= nil then
			local claimedThrough = if daily.ready then daily.cycleDay - 1 else daily.cycleDay
			for index, tile in dayTiles do
				local isNext = daily.ready and index == daily.cycleDay
				local claimed = index <= claimedThrough
				tile.frame.BackgroundColor3 = if isNext
					then ROW_HOT
					elseif claimed then Color3.fromRGB(14, 18, 30)
					else ROW
				tile.stroke.Transparency = if isNext then 0 else 1
				tile.label.TextColor3 = if isNext then AMBER else MUTED
				tile.amount.TextColor3 = if claimed
					then MUTED
					elseif DailyRewards.Cycle[index].cases ~= nil then AMBER
					else WHITE
				tile.mark.Text = if claimed
					then "CLAIMED"
					elseif DailyRewards.Cycle[index].cases ~= nil then `+{DailyRewards.Cycle[index].coins} COINS`
					else "COINS"
				tile.mark.TextColor3 = if claimed then TEAL else MUTED
			end
			local reward = DailyRewards.Cycle[daily.cycleDay]
			claim.Text = if daily.ready
				then `CLAIM DAY {daily.cycleDay}  ·  {if reward.cases ~= nil then "A CASE + " else ""}{Shop.formatCoins(
					reward.coins
				)} COINS`
				else "CLAIMED TODAY  ·  COME BACK TOMORROW"
			claim.BackgroundColor3 = if daily.ready then AMBER else ROW
			claim.TextColor3 = if daily.ready then DARK else MUTED
			claim.AutoButtonColor = daily.ready
			claim.TextSize = 13
			streakLine.Text = if daily.broken
				then "YOU MISSED A DAY, SO THE STREAK STARTS AGAIN"
				elseif daily.ready and daily.streak > 1 then `STREAK  ·  DAY {daily.streak} IN A ROW`
				elseif not daily.ready and daily.streak > 0 then `STREAK  ·  {daily.streak} {if daily.streak
						== 1
					then "DAY"
					else "DAYS"} IN A ROW`
				else ""
		end
		local contracts = state.contracts
		if contracts ~= nil then
			for index, row in contractRows do
				local entry = contracts.list[index]
				row.frame.Visible = entry ~= nil
				if entry ~= nil then
					local finished = entry.progress >= entry.goal
					row.label.Text = string.upper(entry.text)
					row.label.TextColor3 = if finished then MUTED else WHITE
					row.count.Text = if finished then "DONE" else `{entry.progress}/{entry.goal}`
					row.count.TextColor3 = if finished then TEAL else MUTED
					row.reward.Text = `+{Shop.formatCoins(entry.coins)}`
					setBar(row.bar, entry.progress / entry.goal)
				end
			end
			bonusLine.Text = if contracts.bonus
				then `ALL THREE DONE  ·  +{contracts.bonusCoins} COINS PAID`
				else `FINISH ALL THREE  ·  +{contracts.bonusCoins} COINS MORE`
			bonusLine.TextColor3 = if contracts.bonus then TEAL else MUTED
		end
	end

	local function closeScreens(force: boolean?)
		if revealing and not force then
			return
		end
		stopReveal()
		current = ""
		root.Visible = false
		local selected = GuiService.SelectedObject
		if selected ~= nil and selected:IsDescendantOf(root) then
			GuiService.SelectedObject = nil
		end
	end
	closeButton(cases, function()
		closeScreens(false)
	end)
	closeButton(rewards, function()
		closeScreens(false)
	end)

	-- Fits the panels to the window.
	local function fit()
		local camera = Workspace.CurrentCamera
		if camera == nil then
			return
		end
		local size = camera.ViewportSize
		casesScale.Scale = math.min(1, (size.X - 24) / CASES_SIZE.X, (size.Y - 24) / CASES_SIZE.Y)
		rewardsScale.Scale = math.min(1, (size.X - 24) / REWARDS_SIZE.X, (size.Y - 24) / REWARDS_SIZE.Y)
	end

	local function show(name: string)
		current = name
		fit()
		cases.Visible = name == "cases"
		rewards.Visible = name == "rewards"
		root.Visible = true
		if name == "cases" then
			drawCases()
			focus(if openOwned.Visible then openOwned else openCoins)
		elseif name == "rewards" then
			drawRewards()
			focus(claim)
		end
		options.send("sync")
	end

	-- Esc or B steps back: from a result to the case, and from a panel to the hall. (Like the PLAY card, these count even
	-- when Roblox has seen the key first.)
	UserInputService.InputBegan:Connect(function(input: InputObject)
		local key = input.KeyCode
		if not root.Visible or (key ~= Enum.KeyCode.Escape and key ~= Enum.KeyCode.ButtonB) then
			return
		end
		if revealing then
			if result.Visible then
				finishReveal()
			end
		else
			closeScreens(false)
		end
	end)

	return {
		open = function(name: string)
			show(name)
		end,
		close = closeScreens,
		isOpen = function(): boolean
			return root.Visible
		end,
		setState = function(next: State)
			state = next
			if current == "cases" and not revealing then
				drawCases()
			elseif current == "rewards" then
				drawRewards()
			end
		end,
		reveal = function(opened: Opened)
			if current ~= "cases" then
				show("cases")
			end
			playReveal(opened)
		end,
		dailyReady = function(): boolean
			local daily = state.daily
			return daily ~= nil and daily.ready
		end,
		casesWaiting = function(): number
			local total = 0
			local held: { CaseState } = state.cases or {}
			for _, entry in held do
				total += entry.count
			end
			return total
		end,
	}
end

return RewardScreens
