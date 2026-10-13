--!strict

-- Studio-only checks of the garage screen (GaragePanel): what its buttons do, what it sends and how it follows the server,
-- and that the layout holds on a desktop view, a phone and a tall narrow window. It lays real GUI out under StarterGui, so
-- it runs in Edit mode from the command bar:
--   require(game.ReplicatedStorage.Tests.GarageSpec:Clone())()
-- (clone it so an edit is not hidden by a cached result). It builds its own copies of the shared modules and of the two
-- client modules it tests, and removes everything it made when it is done.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local StarterGui = game:GetService("StarterGui")
local StarterPlayer = game:GetService("StarterPlayer")
local TextService = game:GetService("TextService")

local FRAME = 1 / 30

type Scene = {
	container: Frame,
	owner: Folder,
	panel: any,
	sent: { { [string]: number } },
	sounds: { count: number },
	bought: { string },
}

-- Whether a label can be seen: it and everything above it, up to `root`, is visible.
local function shown(item: Instance, root: Instance): boolean
	local current: Instance? = item
	while current ~= nil and current ~= root do
		if current:IsA("GuiObject") and not current.Visible then
			return false
		end
		current = current.Parent
	end
	return true
end

-- Whether every label under `root` can show its text: a one-line label is wide enough, a wrapping one tall enough.
local function textProblems(root: Instance): { string }
	local problems: { string } = {}
	for _, item in root:GetDescendants() do
		if
			(item:IsA("TextLabel") or item:IsA("TextButton"))
			and item.Text ~= ""
			and not item.RichText
			and shown(item, root)
		then
			local width = item.AbsoluteSize.X
			if item.TextWrapped then
				local needed = TextService:GetTextSize(item.Text, item.TextSize, item.Font, Vector2.new(width, 100000))
				if needed.Y > item.AbsoluteSize.Y + 1 then
					table.insert(
						problems,
						`'{string.sub(item.Text, 1, 24)}' needs {needed.Y} high, has {item.AbsoluteSize.Y}`
					)
				end
			else
				local needed = TextService:GetTextSize(item.Text, item.TextSize, item.Font, Vector2.new(100000, 100000))
				if needed.X > width + 0.5 then
					table.insert(problems, `'{string.sub(item.Text, 1, 24)}' needs {needed.X} wide, has {width}`)
				end
			end
		end
	end
	return problems
end

-- How many rows of cells a grid frame lays out, and how many cells it has.
local function gridShape(frame: Instance): (number, number)
	local rows: { [number]: boolean } = {}
	local cells = 0
	for _, child in frame:GetChildren() do
		if child:IsA("GuiObject") then
			cells += 1
			rows[math.floor(child.AbsolutePosition.Y + 0.5)] = true
		end
	end
	local count = 0
	for _ in rows do
		count += 1
	end
	return count, cells
end

local function grids(page: Instance): { Instance }
	local found: { Instance } = {}
	for _, item in page:GetDescendants() do
		if item:IsA("UIGridLayout") and item.Parent ~= nil then
			table.insert(found, item.Parent)
		end
	end
	return found
end

local function visibleText(root: Instance, text: string): boolean
	for _, item in root:GetDescendants() do
		if item:IsA("TextLabel") and item.Text == text and shown(item, root) then
			return true
		end
	end
	return false
end

local function countVisibleText(root: Instance, text: string): number
	local count = 0
	for _, item in root:GetDescendants() do
		if item:IsA("TextLabel") and item.Text == text and shown(item, root) then
			count += 1
		end
	end
	return count
end

return function(): (number, { string })
	local passed = 0
	local failures: { string } = {}

	local function check(name: string, condition: boolean, detail: any?)
		if condition then
			passed += 1
		else
			table.insert(failures, if detail ~= nil then `{name} ({detail})` else name)
		end
	end

	-- Fresh copies of everything under test, so nothing cached from an earlier run (or an older edit) is used.
	local temp = Instance.new("Folder")
	temp.Name = "__GarageSpecTemp"
	ReplicatedStorage:WaitForChild("Shared"):Clone().Parent = temp
	local scripts = StarterPlayer:WaitForChild("StarterPlayerScripts")
	for _, name in { "GaragePanel", "GarageWidgets" } do
		local copy = scripts:WaitForChild(name):Clone() :: any
		copy.Source = string.gsub(
			copy.Source,
			'ReplicatedStorage:WaitForChild%("Shared"%)',
			'script.Parent:WaitForChild("Shared")'
		)
		copy.Parent = temp
	end
	temp.Parent = ServerStorage
	local gui = Instance.new("ScreenGui")
	gui.Name = "__GarageSpecGui"
	-- Like the game's HUD (see Hud), which the panel lives in.
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = StarterGui
	local scenes: { Scene } = {}

	-- The modules are found at run time, so `require` is called through a loose type.
	local load: (module: any) -> any = require :: any
	local Loadout: any = load((temp :: any).Shared.Loadout)
	local Looks: any = load((temp :: any).Shared.Looks)
	local Shop: any = load((temp :: any).Shared.Shop)
	local GaragePanel: any = load((temp :: any).GaragePanel)

	local function newScene(width: number, height: number, compact: boolean): Scene
		local container = Instance.new("Frame")
		container.BackgroundTransparency = 1
		container.Size = UDim2.fromOffset(width, height)
		container.Parent = gui
		local owner = Instance.new("Folder")
		owner:SetAttribute("GarageLoadout", Loadout.DefaultCode)
		owner:SetAttribute("GarageLook", 1)
		local sent: { { [string]: number } } = {}
		local sounds = { count = 0 }
		local bought: { string } = {}
		local panel = GaragePanel.new({
			gui = container,
			owner = owner,
			send = function(choices: { [string]: number })
				table.insert(sent, choices)
			end,
			play = function()
				sounds.count += 1
			end,
			buy = function(item: any)
				table.insert(bought, item.id)
			end,
		})
		panel.setCompact(compact)
		local scene: Scene =
			{ container = container, owner = owner, panel = panel, sent = sent, sounds = sounds, bought = bought }
		table.insert(scenes, scene)
		return scene
	end

	local ok, err = pcall(function()
		-- What the buttons do, and how the panel talks to the server.
		do
			local scene = newScene(1280, 720, false)
			local panel, owner, sent = scene.panel, scene.owner, scene.sent
			local clock = 1000
			panel.step(clock)
			panel.open()
			task.wait(0.7)
			check("the panel opens", panel.isOpen())

			local loadoutCode, lookCode = panel.current()
			check(
				"a new garage is the stock ANVIL in team colors",
				loadoutCode == Loadout.DefaultCode and lookCode == 1
			)
			check("nothing waits at first", panel.preview() == nil)
			check("nothing is sent before a pick", #sent == 0)

			panel.actions.module("ARMS", 2)
			local expected = Loadout.encode({ chassis = 1, arms = 2, core = 1, legs = 1 })
			local previewLoadout, previewLook = panel.preview()
			check("a pick is worn at once", previewLoadout == expected and previewLook == 1, previewLoadout)
			check("a pick is the current choice", (panel.current()) == expected)
			clock += FRAME
			panel.step(clock)
			check("the first pick is sent in the next frame", #sent == 1)
			local first = sent[1]
			check(
				"the whole garage is sent, not a part",
				first ~= nil
					and first.chassis == 1
					and first.arms == 2
					and first.core == 1
					and first.legs == 1
					and first.armor == 1
					and first.accent == 1
					and first.finish == 1
					and first.crest == 1
					and first.body == 1
			)
			clock += 0.1
			panel.step(clock)
			check("it is not sent again straight away", #sent == 1, #sent)
			clock += 0.15
			panel.step(clock)
			check("it is sent again while the server has not agreed", #sent == 2, #sent)

			owner:SetAttribute("GarageLoadout", expected)
			clock += FRAME
			panel.step(clock)
			clock += 0.3
			panel.step(clock)
			check("nothing more is sent once the server agrees", #sent == 2, #sent)
			check("the pick is still worn for a moment", panel.preview() ~= nil)
			clock += 0.5
			panel.step(clock)
			check("then the fighter's own copy takes over", panel.preview() == nil)

			-- Picks that come close together are sent as one: the last.
			local before = #sent
			panel.actions.chassis(2)
			panel.actions.chassis(3)
			panel.actions.chassis(4)
			clock += FRAME
			panel.step(clock)
			local last = sent[#sent]
			check(
				"quick picks are sent together",
				#sent == before + 1 and last ~= nil and last.chassis == 4,
				#sent - before
			)
			check("the chassis pick kept the module", last ~= nil and last.arms == 2)

			-- Choosing what is already chosen does nothing.
			owner:SetAttribute("GarageLoadout", (panel.current()))
			clock += FRAME
			panel.step(clock)
			clock += 1
			panel.step(clock)
			local settled = #sent
			local soundsBefore = scene.sounds.count
			panel.actions.chassis(4)
			panel.actions.module("ARMS", 2)
			panel.actions.armor(1)
			clock += 0.5
			panel.step(clock)
			check("choosing what is chosen sounds nothing", scene.sounds.count == soundsBefore)
			check("and sends nothing", #sent == settled, #sent - settled)

			-- A preset fills every slot at once.
			panel.actions.preset(4)
			local preset = Loadout.Presets[4]
			local choice = Loadout.decode((panel.current()))
			check(
				"a preset sets every part",
				choice.chassis == preset.chassis
					and choice.arms == preset.arms
					and choice.core == preset.core
					and choice.legs == preset.legs
			)

			-- Paint.
			panel.actions.armor(5)
			panel.actions.accent(7)
			panel.actions.finish(3)
			panel.actions.crest(4)
			local _, paintCode = panel.current()
			local paint = Looks.decode(paintCode)
			check(
				"paint is picked part by part",
				paint.armor == 5 and paint.accent == 7 and paint.finish == 3 and paint.crest == 4
			)
			check("paint leaves the build alone", Loadout.presetIndex(Loadout.decode((panel.current()))) == 4)

			-- A server that never answers: the screen gives in and shows what the server has.
			clock += 0.3
			panel.step(clock)
			local serverLoadout = owner:GetAttribute("GarageLoadout")
			clock += 4.5
			panel.step(clock)
			check("an unanswered pick is given up", (panel.current()) == serverLoadout and panel.preview() == nil)

			-- A saved garage that arrives late is followed, and nonsense is not.
			local saved = Loadout.encode({ chassis = 5, arms = 3, core = 3, legs = 1 })
			owner:SetAttribute("GarageLoadout", saved)
			owner:SetAttribute("GarageLook", Looks.encode({ armor = 9, accent = 4, finish = 2, crest = 2, body = 1 }))
			clock += FRAME
			panel.step(clock)
			local followed, followedLook = panel.current()
			check("a late saved garage is followed", followed == saved and Looks.decode(followedLook).armor == 9)
			owner:SetAttribute("GarageLoadout", 99999)
			clock += FRAME
			panel.step(clock)
			check("an invalid code from the server is ignored", (panel.current()) == saved)

			-- It can be closed and opened again.
			panel.close()
			task.wait(0.4)
			local frame = scene.container:FindFirstChild("Garage") :: Frame?
			check("a closed panel is hidden", not panel.isOpen() and frame ~= nil and not frame.Visible)
			panel.open()
			task.wait(0.5)
			check("and it opens again", panel.isOpen() and frame ~= nil and frame.Visible)
		end

		-- The shop: trying on, buying with coins and with Robux, equipping, and crests that are not owned yet.
		do
			local scene = newScene(1280, 720, false)
			local panel, owner, sent, bought = scene.panel, scene.owner, scene.sent, scene.bought
			local monarch, crown, mohawk = 0, 0, 0
			for index, item in Shop.Items do
				if item.id == "body.monarch" then
					monarch = index
				elseif item.id == "crest.crown" then
					crown = index
				elseif item.id == "crest.mohawk" then
					mohawk = index
				end
			end
			check("the shop sells MONARCH, CROWN and MOHAWK", monarch > 0 and crown > 0 and mohawk > 0)
			local crownCrest = Looks.crestFor("crest.crown")
			local mohawkCrest = Looks.crestFor("crest.mohawk")
			local monarchBody = Looks.bodyFor("body.monarch")
			local clock = 3000
			owner:SetAttribute("Coins", 1250)
			owner:SetAttribute("Owned", "")
			panel.step(clock)
			panel.open()
			task.wait(0.6)
			local frame = scene.container:FindFirstChild("Garage") :: Frame?
			local shopPage = if frame ~= nil then frame:FindFirstChild("SHOP") else nil
			panel.actions.tab(4)
			task.wait(0.05)
			check("the SHOP page shows", shopPage ~= nil and (shopPage :: ScrollingFrame).Visible)
			local coinsShown = false
			if shopPage ~= nil then
				for _, item in shopPage:GetDescendants() do
					if item:IsA("TextLabel") and string.find(item.Text, "1,250", 1, true) ~= nil then
						coinsShown = true
					end
				end
			end
			check("the shop shows the coins", coinsShown)

			-- Trying MONARCH on draws it on MAUL without asking the server for anything.
			panel.actions.item(monarch)
			local tryLoadout, tryLook = panel.preview()
			check(
				"tapping a body tries it on, on its own chassis",
				tryLoadout ~= nil
					and Loadout.decode(tryLoadout).chassis == 5
					and tryLook ~= nil
					and Looks.decode(tryLook).body == monarchBody
			)
			clock += 0.5
			panel.step(clock)
			check("trying on sends nothing", #sent == 0, #sent)
			check("trying on leaves the garage as it was", (panel.current()) == Loadout.DefaultCode)

			-- MONARCH has no developer product yet: its button does nothing.
			local productBefore = Shop.Items[monarch].product
			Shop.Items[monarch].product = 0
			panel.actions.itemAction(monarch)
			check("an item without a product cannot be bought", #bought == 0, #bought)
			-- Until the server has read the wallet nothing is sold: the player might own it already.
			Shop.Items[monarch].product = 123456
			panel.actions.itemAction(monarch)
			check("nothing is sold before the wallet is known", #bought == 0, #bought)
			owner:SetAttribute("WalletReady", true)
			clock += FRAME
			panel.step(clock)
			-- With a product, its button prompts the purchase, and not again straight away.
			panel.actions.itemAction(monarch)
			check("a Robux item's button buys it", bought[#bought] == "body.monarch", bought[#bought])
			panel.actions.itemAction(monarch)
			check("a second tap straight after prompts nothing", #bought == 1, #bought)
			-- A prompt closed without buying can be opened again at once.
			panel.purchaseFinished("body.monarch", false)
			panel.actions.itemAction(monarch)
			check("after a prompt closed without buying, it prompts again", #bought == 2, #bought)
			-- Bought: it shows as on its way and is not offered again until the server grants it.
			panel.purchaseFinished("body.monarch", true)
			clock += 3
			panel.step(clock)
			panel.actions.itemAction(monarch)
			local pendingShown = false
			if shopPage ~= nil then
				for _, item in shopPage:GetDescendants() do
					if item:IsA("TextButton") and item.Text == "PENDING" then
						pendingShown = true
					end
				end
			end
			check("a paid item is shown as on its way and not sold again", pendingShown and #bought == 2, #bought)
			-- The purchase lands: it goes on at once, with its chassis.
			owner:SetAttribute("Owned", "body.monarch")
			clock += FRAME
			panel.step(clock)
			local afterLoadout, afterLook = panel.current()
			check(
				"a bought body is put on, with its chassis",
				Loadout.decode(afterLoadout).chassis == 5 and Looks.decode(afterLook).body == monarchBody
			)
			clock += FRAME
			panel.step(clock)
			local wanted = sent[#sent]
			check(
				"and the server is asked for it",
				wanted ~= nil and wanted.chassis == 5 and wanted.body == monarchBody,
				if wanted ~= nil then `{wanted.chassis},{wanted.body}` else "nothing sent"
			)
			-- Its button now takes it off.
			panel.actions.itemAction(monarch)
			check("an equipped body's button takes it off", Looks.decode(select(2, panel.current())).body == 1)
			panel.actions.itemAction(monarch)
			check("and puts it back on", Looks.decode(select(2, panel.current())).body == monarchBody)
			Shop.Items[monarch].product = productBefore

			-- Coins: too few buys nothing; enough buys it, and it goes on when the server says it is owned.
			owner:SetAttribute("Coins", 100)
			clock += FRAME
			panel.step(clock)
			local boughtBefore = #bought
			panel.actions.itemAction(crown)
			check("too few coins buy nothing", #bought == boughtBefore)
			owner:SetAttribute("Coins", 1250)
			clock += FRAME
			panel.step(clock)
			panel.actions.itemAction(crown)
			check("enough coins buy a crest", bought[#bought] == "crest.crown", bought[#bought])
			owner:SetAttribute("Owned", "body.monarch,crest.crown")
			owner:SetAttribute("Coins", 650)
			clock += FRAME
			panel.step(clock)
			check("a bought crest is put on", Looks.decode(select(2, panel.current())).crest == crownCrest)

			-- A crest that is not owned yet, picked on the PAINT page, is tried on in the shop instead.
			panel.actions.tab(3)
			task.wait(0.05)
			local paintPage = if frame ~= nil then frame:FindFirstChild("PAINT") else nil
			local marks = 0
			if paintPage ~= nil then
				for _, item in paintPage:GetDescendants() do
					if item.Name == "Locked" and item:IsA("GuiObject") and item.Visible then
						marks += 1
					end
				end
			end
			check("only the crests not owned yet are marked", marks == 1, marks)
			panel.actions.crest(mohawkCrest)
			local _, mohawkLook = panel.preview()
			check(
				"picking a crest that is not owned opens the shop wearing it",
				shopPage ~= nil
					and (shopPage :: ScrollingFrame).Visible
					and mohawkLook ~= nil
					and Looks.decode(mohawkLook).crest == mohawkCrest
					and Looks.decode(select(2, panel.current())).crest == crownCrest
			)
			panel.actions.tab(1)
			owner:SetAttribute("GarageLoadout", (panel.current()))
			owner:SetAttribute("GarageLook", select(2, panel.current()))
			clock += FRAME
			panel.step(clock)
			clock += 1
			panel.step(clock)
			check("leaving the shop stops trying things on", panel.preview() == nil)
		end

		-- The layout, on a desktop view, a phone and a tall narrow window.
		local views = {
			{ name = "desktop", width = 1280, height = 720, compact = false, mode = "side" },
			{ name = "phone", width = 844, height = 390, compact = true, mode = "side" },
			{ name = "narrow", width = 600, height = 900, compact = false, mode = "sheet" },
		}
		for _, view in views do
			local scene = newScene(view.width, view.height, view.compact)
			local panel = scene.panel
			panel.step(2000)
			panel.open()
			task.wait(0.7)
			local frame = scene.container:FindFirstChild("Garage") :: Frame?
			check(`{view.name}: the panel exists`, frame ~= nil)
			if frame == nil then
				continue
			end
			local position, size = frame.AbsolutePosition, frame.AbsoluteSize
			check(
				`{view.name}: the panel is inside the view`,
				position.X >= -0.5
					and position.Y >= -0.5
					and position.X + size.X <= view.width + 0.5
					and position.Y + size.Y <= view.height + 0.5,
				`{position} {size}`
			)
			local shiftX, shiftY = panel.room(Vector2.new(view.width, view.height))
			if view.mode == "side" then
				check(
					`{view.name}: the panel is a column at the side`,
					size.Y > size.X and size.X <= view.width * 0.5,
					tostring(size)
				)
				check(
					`{view.name}: the camera makes room at the side`,
					shiftX > 0.15 and shiftX < 0.6 and shiftY == 0,
					shiftX
				)
			else
				check(
					`{view.name}: the panel lies along the bottom`,
					size.X > size.Y and position.Y > view.height * 0.3,
					`{position} {size}`
				)
				check(`{view.name}: the camera makes room below`, shiftY > 0.3 and shiftY < 0.8 and shiftX == 0, shiftY)
			end

			local tabs = frame:FindFirstChild("Tabs")
			local tabButtons = {}
			if tabs ~= nil then
				for _, child in tabs:GetChildren() do
					if child:IsA("TextButton") then
						table.insert(tabButtons, child)
					end
				end
			end
			check(`{view.name}: four tabs`, #tabButtons == 4, #tabButtons)
			local tabRows = if tabs ~= nil then gridShape(tabs) else 0
			check(`{view.name}: the tabs share a row`, tabRows == 1, tabRows)

			local pagesSeen = 0
			for index, pageName in { "BUILD", "PRESETS", "PAINT", "SHOP" } do
				scene.panel.actions.tab(index)
				task.wait(0.05)
				local page = frame:FindFirstChild(pageName) :: ScrollingFrame?
				if page == nil then
					check(`{view.name}: the {pageName} page exists`, false)
					continue
				end
				pagesSeen += 1
				check(`{view.name}: {pageName} is the page showing`, page.Visible)
				check(
					`{view.name}: {pageName} does not scroll sideways`,
					page.AbsoluteCanvasSize.X <= page.AbsoluteSize.X + 1,
					`{page.AbsoluteCanvasSize} in {page.AbsoluteSize}`
				)
				check(
					`{view.name}: {pageName} text fits`,
					#textProblems(page) == 0,
					table.concat(textProblems(page), "; ")
				)
				for _, item in page:GetDescendants() do
					if item:IsA("TextButton") and item.Visible then
						if item.AbsoluteSize.X < 28 or item.AbsoluteSize.Y < 24 then
							check(
								`{view.name}: {pageName} buttons are big enough to press`,
								false,
								`{item.Name} {item.AbsoluteSize}`
							)
						end
					end
				end
			end
			check(`{view.name}: all four pages exist`, pagesSeen == 4)

			-- The rows of chips and swatches.
			scene.panel.actions.tab(1)
			task.wait(0.05)
			local build = frame:FindFirstChild("BUILD")
			if build ~= nil then
				local shapes = {}
				for _, grid in grids(build) do
					local rows, cells = gridShape(grid)
					table.insert(shapes, `{cells}x{rows}`)
				end
				check(
					`{view.name}: chassis and module chips each fit one row`,
					table.concat(shapes, ",") == "5x1,3x1,3x1,3x1",
					table.concat(shapes, ",")
				)
			end
			scene.panel.actions.tab(3)
			task.wait(0.05)
			local paintPage = frame:FindFirstChild("PAINT")
			if paintPage ~= nil then
				local shapes = {}
				for _, grid in grids(paintPage) do
					local rows, cells = gridShape(grid)
					table.insert(shapes, `{cells}x{rows}`)
				end
				check(
					`{view.name}: swatches make two rows of eight; finishes fit a row and crests two`,
					table.concat(shapes, ",") == "16x2,16x2,4x1,7x2",
					table.concat(shapes, ",")
				)
			end

			-- A build with the most to say still fits, and says all of it.
			scene.panel.actions.tab(1)
			scene.panel.actions.chassis(5)
			scene.panel.actions.module("ARMS", 3)
			scene.panel.actions.module("CORE", 2)
			scene.panel.actions.module("LEGS", 3)
			task.wait(0.3)
			if build ~= nil then
				local all = true
				local chassis = Loadout.Chassis[5]
				for _, line in Loadout.describe(chassis.mods) do
					all = all and visibleText(build, line.text)
				end
				for slot, index in { ARMS = 3, CORE = 2, LEGS = 3 } do
					for _, line in Loadout.describe(Loadout.Modules[slot][index].mods) do
						all = all and visibleText(build, line.text)
					end
				end
				check(`{view.name}: every gain and cost of the chosen parts is listed`, all)
				check(
					`{view.name}: a wordy build's text fits`,
					#textProblems(build) == 0,
					table.concat(textProblems(build), "; ")
				)
				check(`{view.name}: the chosen chassis is named in its role line`, visibleText(build, chassis.role))
			end

			-- Presets: the one that is equipped says so.
			scene.panel.actions.preset(7)
			scene.panel.actions.tab(2)
			task.wait(0.1)
			local presetPage = frame:FindFirstChild("PRESETS")
			if presetPage ~= nil then
				local tags = countVisibleText(presetPage, "EQUIPPED")
				check(`{view.name}: one preset is marked equipped`, tags == 1, tags)
				scene.panel.actions.module("LEGS", 1)
				task.wait(0.05)
				tags = countVisibleText(presetPage, "EQUIPPED")
				check(`{view.name}: changing a part takes the mark off`, tags == 0, tags)
			end
		end
	end)
	if not ok then
		table.insert(failures, "the spec itself failed: " .. tostring(err))
	end

	for _, scene in scenes do
		scene.panel.destroy()
	end
	gui:Destroy()
	temp:Destroy()
	return passed, failures
end
