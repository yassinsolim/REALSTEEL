--!strict

-- Studio-only checks of the server's garage (src/server/Garage.luau): what it does with what a client sends, how it
-- keeps and loads a profile, and that it publishes and reports changes. It runs against a stand-in DataStore and stand-in
-- players, so it needs no game. From the command bar in Edit mode:
--   require(game.ReplicatedStorage.Tests.GarageServerSpec:Clone())()
-- (clone it so an edit is not hidden by a cached result).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

-- A request is accepted at most this often per player (REQUEST_COOLDOWN in the module), so checks wait a little longer.
local COOLDOWN = 0.12

local function newPlayer(userId: number): any
	local attributes: { [string]: any } = {}
	local player: any = { UserId = userId, attributes = attributes }
	function player:SetAttribute(name: string, value: any)
		attributes[name] = value
	end
	function player:GetAttribute(name: string): any
		return attributes[name]
	end
	return player
end

-- Anything with GetAsync and SetAsync. `delay` makes a read slow; `failWrites` makes a write throw.
local function newStore(): any
	local store: any = { data = {}, reads = 0, writes = 0, delay = 0, failWrites = false }
	function store:GetAsync(key: string): any
		store.reads += 1
		if store.delay > 0 then
			task.wait(store.delay)
		end
		return store.data[key]
	end
	function store:SetAsync(key: string, value: any)
		store.writes += 1
		if store.failWrites then
			error("the store is down")
		end
		store.data[key] = value
	end
	return store
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

	-- A fresh copy of the module and of what it needs, so nothing cached from an earlier run is used.
	local temp = Instance.new("Folder")
	temp.Name = "__GarageServerSpecTemp"
	ReplicatedStorage:WaitForChild("Shared"):Clone().Parent = temp
	local copy = ServerScriptService:WaitForChild("Garage"):Clone() :: any
	copy.Source = string.gsub(copy.Source, "ReplicatedStorage%.Shared", "script.Parent.Shared")
	copy.Parent = temp
	temp.Parent = ServerStorage
	local garages: { any } = {}
	local remotes: { RemoteEvent } = {}

	-- The modules are found at run time, so `require` is called through a loose type.
	local load: (module: any) -> any = require :: any
	local Loadout: any = load((temp :: any).Shared.Loadout)
	local Looks: any = load((temp :: any).Shared.Looks)
	local Garage: any = load(copy)

	-- A garage on a stand-in store, and a log of who it reported as changed.
	local function newGarage(store: any): (any, { any })
		local changed: { any } = {}
		local remote = Instance.new("RemoteEvent")
		table.insert(remotes, remote)
		local garage = Garage.new(function(player: any)
			table.insert(changed, player)
		end, { store = store, remote = remote })
		table.insert(garages, garage)
		return garage, changed
	end

	local ok, err = pcall(function()
		-- A new player starts as the stock ANVIL in team colors, and the screen can read that.
		do
			local store = newStore()
			local garage, changed = newGarage(store)
			local player = newPlayer(1)
			garage.add(player)
			task.wait(0.05)
			local loadoutCode, lookCode = garage.codes(player)
			check(
				"a new player is the stock ANVIL in team colors",
				loadoutCode == Loadout.DefaultCode and lookCode == 1
			)
			check(
				"the codes are published on the player",
				player:GetAttribute("GarageLoadout") == loadoutCode and player:GetAttribute("GarageLook") == lookCode
			)
			check(
				"a player nobody added reads as the stock ANVIL",
				select(1, garage.codes(newPlayer(99))) == Loadout.DefaultCode
			)
			check(
				"the end of loading is reported, with nothing saved",
				#changed == 1 and changed[1] == player and store.reads == 1
			)

			-- A client sets its garage.
			local want = { chassis = 3, arms = 2, core = 3, legs = 1, armor = 7, accent = 5, finish = 3, crest = 4 }
			garage.handle(player, "set", want)
			local chosen = Loadout.decode((garage.codes(player)))
			local _, lookChosen = garage.codes(player)
			local look = Looks.decode(lookChosen)
			check(
				"a request sets the build and the look",
				chosen.chassis == 3
					and chosen.arms == 2
					and chosen.core == 3
					and chosen.legs == 1
					and look.armor == 7
					and look.accent == 5
					and look.finish == 3
					and look.crest == 4
			)
			check(
				"the new codes are published",
				player:GetAttribute("GarageLoadout") == Loadout.encode(chosen)
					and player:GetAttribute("GarageLook") == lookChosen
			)
			check("a change is reported", #changed == 2 and changed[2] == player, #changed)

			-- The server accepts one request in a short while.
			garage.handle(player, "set", { chassis = 5 })
			check(
				"a second request straight after is ignored",
				Loadout.decode((garage.codes(player))).chassis == 3 and #changed == 2
			)
			task.wait(COOLDOWN)
			garage.handle(player, "set", { chassis = 5 })
			local after = Loadout.decode((garage.codes(player)))
			check("a request after the wait is taken", after.chassis == 5 and #changed == 3)
			check(
				"fields a request leaves out keep their value",
				after.arms == 2 and after.core == 3 and Looks.decode(select(2, garage.codes(player))).armor == 7
			)

			-- Whatever a client sends is cleaned before it is kept. (The player owns everything here, so the clamped picks are
			-- worn as they are: the last armor is a case item.)
			garage.setOwnership(function(): boolean
				return true
			end)
			task.wait(COOLDOWN)
			garage.handle(player, "set", {
				chassis = 99,
				arms = -4,
				core = 2.9,
				legs = 0 / 0,
				armor = math.huge,
				accent = -math.huge,
				finish = 1e300,
				crest = "four",
			})
			local cleaned = Loadout.decode((garage.codes(player)))
			local cleanedLook = Looks.decode(select(2, garage.codes(player)))
			check(
				"numbers out of range are clamped",
				cleaned.chassis == 5 and cleaned.arms == 1 and cleaned.core == 2 and cleaned.legs == 1,
				`{cleaned.chassis},{cleaned.arms},{cleaned.core},{cleaned.legs}`
			)
			check(
				"nonsense paint is clamped, and a word leaves the old crest",
				cleanedLook.armor == #Looks.Armor
					and cleanedLook.accent == 1
					and cleanedLook.finish == #Looks.Finishes
					and cleanedLook.crest == 4,
				`{cleanedLook.armor},{cleanedLook.accent},{cleanedLook.finish},{cleanedLook.crest}`
			)
			check(
				"whatever was kept is a real code",
				Loadout.isValidCode(player:GetAttribute("GarageLoadout"))
					and Looks.isValidCode(player:GetAttribute("GarageLook"))
			)

			local seen = #changed
			local junkValues: { any } = { 5, true, "x", {}, "SET", "set " }
			for _, junk in junkValues do
				task.wait(COOLDOWN)
				garage.handle(player, "reset", junk)
				garage.handle(player, junk, { chassis = 2 })
			end
			task.wait(COOLDOWN)
			garage.handle(player, "set", "not a table")
			garage.handle(player, "set", nil)
			check(
				"other actions and payloads that are not tables do nothing",
				#changed == seen and Loadout.decode((garage.codes(player))).chassis == 5
			)
			garage.handle(newPlayer(500), "set", { chassis = 2 })
			check("a player nobody added cannot set anything", #changed == seen)
		end

		-- Saving and loading.
		do
			local store = newStore()
			local garage = newGarage(store)
			local player = newPlayer(42)
			garage.add(player)
			task.wait(0.05)
			garage.handle(
				player,
				"set",
				{ chassis = 4, arms = 3, core = 1, legs = 2, armor = 6, accent = 2, finish = 2, crest = 5 }
			)
			check("nothing is written for every pick", store.writes == 0, store.writes)
			garage.saveAll()
			local saved = store.data.u42
			check(
				"saving writes the whole garage under the player's id",
				saved ~= nil
					and saved.chassis == 4
					and saved.arms == 3
					and saved.legs == 2
					and saved.armor == 6
					and saved.crest == 5
					and saved.v == 1
			)
			garage.saveAll()
			check("an unchanged garage is not written again", store.writes == 1, store.writes)

			-- A new session for the same player reads it back.
			local second, secondChanged = newGarage(store)
			local again = newPlayer(42)
			second.add(again)
			task.wait(0.05)
			check(
				"a saved garage is loaded when the player joins",
				select(1, second.codes(again)) == Loadout.encode({ chassis = 4, arms = 3, core = 1, legs = 2 })
			)
			check(
				"and published, and reported",
				again:GetAttribute("GarageLoadout") == select(1, second.codes(again)) and #secondChanged >= 1
			)

			-- Leaving saves what changed.
			second.handle(again, "set", { chassis = 2 })
			second.remove(again)
			check("leaving saves a change", store.data.u42 ~= nil and store.data.u42.chassis == 2)
			check("a player who left is forgotten", select(1, second.codes(again)) == Loadout.DefaultCode)

			-- A store that is down: nothing throws and the change is kept for the next try.
			local down = newStore()
			local third = newGarage(down)
			local p3 = newPlayer(7)
			third.add(p3)
			task.wait(0.05)
			third.handle(p3, "set", { chassis = 5 })
			down.failWrites = true
			third.saveAll()
			check("a failed write is survived", down.writes == 1 and down.data.u7 == nil)
			down.failWrites = false
			third.saveAll()
			check(
				"and tried again",
				down.writes == 2 and down.data.u7 ~= nil and down.data.u7.chassis == 5,
				down.writes
			)

			-- Saved data from somewhere else is cleaned like a request.
			local odd = newStore()
			odd.data.u9 =
				{ chassis = 99, arms = "x", core = 2, legs = -1, armor = 4, accent = 0, finish = 99, crest = 2 }
			local fourth = newGarage(odd)
			local p4 = newPlayer(9)
			fourth.add(p4)
			task.wait(0.05)
			local odd1 = Loadout.decode((fourth.codes(p4)))
			check(
				"a damaged save loads as the nearest real garage",
				odd1.chassis == 5 and odd1.arms == 1 and odd1.core == 2 and odd1.legs == 1
			)
			local garbage = newStore()
			garbage.data.u10 = "not a table"
			local fifth = newGarage(garbage)
			local p5 = newPlayer(10)
			fifth.add(p5)
			task.wait(0.05)
			check("a save that is not a table is ignored", select(1, fifth.codes(p5)) == Loadout.DefaultCode)

			-- A pick made while the saved garage is still being read wins over it.
			local slow = newStore()
			slow.data.u11 = { chassis = 2, arms = 1, core = 1, legs = 1 }
			slow.delay = 0.3
			local sixth, sixthChanged = newGarage(slow)
			local p6 = newPlayer(11)
			sixth.add(p6)
			task.wait(0.05)
			sixth.handle(p6, "set", { chassis = 5, arms = 3, core = 3, legs = 3 })
			task.wait(0.5)
			check("a pick made before the load finished is kept", Loadout.decode((sixth.codes(p6))).chassis == 5)
			check("and the end of the load is still reported", #sixthChanged >= 2, #sixthChanged)
		end

		-- Two players do not share anything.
		do
			local garage = newGarage(newStore())
			local a, b = newPlayer(21), newPlayer(22)
			garage.add(a)
			garage.add(b)
			task.wait(0.05)
			garage.handle(a, "set", { chassis = 2 })
			garage.handle(b, "set", { chassis = 4 })
			check(
				"each player keeps their own garage",
				Loadout.decode((garage.codes(a))).chassis == 2 and Loadout.decode((garage.codes(b))).chassis == 4
			)
		end

		-- Shop items: a player wears only what they own, keeps the pick for when they own it, and saves it.
		do
			local store = newStore()
			local garage, changed = newGarage(store)
			local ownedBy: { [number]: { [string]: boolean } } = {}
			garage.setOwnership(function(player: any, item: string): boolean
				local owned = ownedBy[player.UserId]
				return owned ~= nil and owned[item] == true
			end)
			local buyer = newPlayer(31)
			garage.add(buyer)
			task.wait(0.05)
			local monarch = Looks.bodyFor("body.monarch")
			local crown = Looks.crestFor("crest.crown")
			garage.handle(buyer, "set", { chassis = 5, body = monarch, crest = crown, armor = 4 })
			local worn = Looks.decode(select(2, garage.codes(buyer)))
			check(
				"a body or a crest the player does not own is not worn, and the paint is",
				worn.body == 1 and worn.crest == 1 and worn.armor == 4,
				`{worn.body},{worn.crest},{worn.armor}`
			)
			check(
				"nor published",
				Looks.decode(buyer:GetAttribute("GarageLook")).body == 1
					and Looks.decode(buyer:GetAttribute("GarageLook")).crest == 1
			)
			local before = #changed
			ownedBy[31] = { ["body.monarch"] = true }
			garage.refresh(buyer)
			local afterBuy = Looks.decode(select(2, garage.codes(buyer)))
			check(
				"once bought, the kept pick is worn at once, and only what is owned",
				afterBuy.body == monarch
					and afterBuy.crest == 1
					and Looks.decode(buyer:GetAttribute("GarageLook")).body == monarch
			)
			check("and the change is reported", #changed == before + 1, #changed - before)
			ownedBy[31]["crest.crown"] = true
			garage.refresh(buyer)
			check("a crest bought later goes on too", Looks.decode(select(2, garage.codes(buyer))).crest == crown)
			garage.saveAll()
			check(
				"the body is saved with the garage",
				store.data.u31 ~= nil and store.data.u31.body == monarch and store.data.u31.crest == crown
			)
			local other = newPlayer(32)
			garage.add(other)
			task.wait(0.05)
			task.wait(COOLDOWN)
			garage.handle(other, "set", { chassis = 5, body = monarch })
			check("one player's purchase is not another's", Looks.decode(select(2, garage.codes(other))).body == 1)
			local reported = #changed
			garage.refresh(newPlayer(99))
			check("refreshing a player nobody added does nothing", #changed == reported)
		end
	end)
	if not ok then
		table.insert(failures, "the spec itself failed: " .. tostring(err))
	end

	for _, garage in garages do
		garage.destroy()
	end
	for _, remote in remotes do
		remote:Destroy()
	end
	temp:Destroy()
	return passed, failures
end
