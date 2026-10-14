--!strict

-- Server: every player's garage. A profile is the loadout and the look a player has chosen. It is kept in memory, saved to
-- a DataStore when Studio or the game allows it, and handed to the fighters when a match starts (see Main.server). The
-- client only ever asks: whatever it sends is sanitized here before it is stored or replicated, and the numbers the match
-- uses are the ones on the fighter cores, not anything a client says about itself. A look may pick shop items (a premium
-- body, a crest); the profile keeps the pick, but only what the player owns is published and worn (Looks.strip).

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Loadout = require(ReplicatedStorage.Shared.Loadout)
local Looks = require(ReplicatedStorage.Shared.Looks)

local STORE_NAME = "RealSteelGarage1"
local SAVE_VERSION = 1
-- A client may change its garage this often. Saves are batched so a player clicking through swatches costs one write.
local REQUEST_COOLDOWN = 0.1
local SAVE_DELAY = 15
local LOAD_ATTEMPTS = 3

type Profile = {
	choice: Loadout.Choice,
	look: Looks.Look,
	-- Changed since the last save, and when it was last written.
	dirty: boolean,
	lastSave: number,
	-- False until the stored profile has been read (or given up on), so a player's early choices are not overwritten.
	loaded: boolean,
}

export type Garage = {
	-- The loadout and look codes a player's fighter takes into a match (the look without anything they do not own).
	codes: (player: Player) -> (number, number),
	add: (player: Player) -> (),
	remove: (player: Player) -> (),
	-- Saves every profile that changed; the server calls it as it shuts down.
	saveAll: () -> (),
	-- What the remote does with a request. The remote calls it; checks can too.
	handle: (player: Player, action: unknown, payload: unknown) -> (),
	-- Who owns which shop item (see Wallet). Until it is set nobody owns anything.
	setOwnership: (owns: (player: Player, item: string) -> boolean) -> (),
	-- Publishes a player's garage again after what they own changed, so an item they just got shows (or one they no longer
	-- have comes off).
	refresh: (player: Player) -> (),
	-- Stops the background saving. The server never needs it; checks do.
	destroy: () -> (),
}

-- For checks: a stand-in for the DataStore (anything with GetAsync and SetAsync) and a remote that is not in the game. With
-- them the module touches nothing outside itself.
export type Options = {
	store: any?,
	remote: RemoteEvent?,
}

local Garage = {}

local warned = false
local function warnOnce(message: string)
	if not warned then
		warned = true
		warn("[REALSTEEL] Garage saves are off: " .. message)
	end
end

local function toSaved(profile: Profile): { [string]: number }
	return {
		v = SAVE_VERSION,
		chassis = profile.choice.chassis,
		arms = profile.choice.arms,
		core = profile.choice.core,
		legs = profile.choice.legs,
		armor = profile.look.armor,
		accent = profile.look.accent,
		finish = profile.look.finish,
		crest = profile.look.crest,
		body = profile.look.body,
		glow = profile.look.glow,
		trail = profile.look.trail,
		impact = profile.look.impact,
		title = profile.look.title,
	}
end

-- Creates the Garage remote and the bookkeeping. `onChange` runs after a player's garage changed, whether by the player
-- or by their saved profile arriving, so the server can put the new loadout on the fighters when that is allowed.
function Garage.new(onChange: (player: Player) -> (), options: Options?): Garage
	local testing = options ~= nil
	local remote: RemoteEvent
	if options ~= nil and options.remote ~= nil then
		remote = options.remote
	else
		remote = Instance.new("RemoteEvent")
		remote.Name = "Garage"
		remote.Parent = ReplicatedStorage
	end

	local profiles: { [Player]: Profile } = {}
	local lastRequest: { [Player]: number } = {}
	local running = true
	local ownership: (player: Player, item: string) -> boolean = function(_player: Player, _item: string): boolean
		return false
	end

	local store: any = nil
	if options ~= nil and options.store ~= nil then
		store = options.store
	else
		local opened, result = pcall(function()
			return DataStoreService:GetDataStore(STORE_NAME)
		end)
		if opened then
			store = result
		else
			warnOnce(tostring(result))
		end
	end

	-- The look a player may wear: their pick, without the shop items they do not own.
	local function wornLook(player: Player, profile: Profile): Looks.Look
		return Looks.strip(profile.look, function(item: string): boolean
			return ownership(player, item)
		end)
	end

	-- What the client's garage screen reads. The numbers are the same codes the fighters use.
	local function publish(player: Player, profile: Profile)
		player:SetAttribute("GarageLoadout", Loadout.encode(profile.choice))
		player:SetAttribute("GarageLook", Looks.encode(wornLook(player, profile)))
	end

	local function save(player: Player, profile: Profile)
		local current = store
		if current == nil or not profile.loaded or not profile.dirty then
			return
		end
		profile.dirty = false
		profile.lastSave = os.clock()
		local saved = toSaved(profile)
		local ok, err = pcall(function()
			current:SetAsync("u" .. player.UserId, saved)
		end)
		if not ok then
			profile.dirty = true
			warnOnce(tostring(err))
		end
	end

	local function loadProfile(player: Player, profile: Profile)
		local current = store
		if current ~= nil then
			for attempt = 1, LOAD_ATTEMPTS do
				local ok, data = pcall(function()
					return current:GetAsync("u" .. player.UserId)
				end)
				if ok then
					if type(data) == "table" and profiles[player] == profile and not profile.dirty then
						-- Whatever the player picked before the save arrived wins; otherwise the saved profile does.
						profile.choice = Loadout.sanitize(data)
						profile.look = Looks.sanitize(data)
						publish(player, profile)
					end
					break
				end
				warnOnce(tostring(data))
				if attempt < LOAD_ATTEMPTS then
					task.wait(2 * attempt)
				end
			end
		end
		profile.loaded = true
		if profiles[player] == profile then
			onChange(player)
		end
	end

	local function numberField(source: { [string]: unknown }, key: string): number?
		local value = source[key]
		return if type(value) == "number" then value else nil
	end

	local function handle(player: Player, action: unknown, payload: unknown)
		local profile = profiles[player]
		if profile == nil or action ~= "set" or type(payload) ~= "table" then
			return
		end
		local now = os.clock()
		if now - (lastRequest[player] or 0) < REQUEST_COOLDOWN then
			return
		end
		lastRequest[player] = now

		-- Fields the client leaves out keep what the profile has.
		local source = payload :: { [string]: unknown }
		local merged: { [string]: unknown } = table.clone(toSaved(profile) :: any)
		for _, key in
			{
				"chassis",
				"arms",
				"core",
				"legs",
				"armor",
				"accent",
				"finish",
				"crest",
				"body",
				"glow",
				"trail",
				"impact",
				"title",
			}
		do
			local value = numberField(source, key)
			if value ~= nil then
				merged[key] = value
			end
		end
		profile.choice = Loadout.sanitize(merged)
		profile.look = Looks.sanitize(merged)
		profile.dirty = true
		publish(player, profile)
		onChange(player)
	end
	local connection = remote.OnServerEvent:Connect(handle)

	-- Written in the background so a busy store never holds up a match.
	task.spawn(function()
		while running do
			task.wait(5)
			local now = os.clock()
			for player, profile in profiles do
				if profile.dirty and now - profile.lastSave >= SAVE_DELAY then
					save(player, profile)
				end
			end
		end
	end)

	local self: Garage = {
		codes = function(player: Player): (number, number)
			local profile = profiles[player]
			if profile == nil then
				return Loadout.DefaultCode, 1
			end
			return Loadout.encode(profile.choice), Looks.encode(wornLook(player, profile))
		end,
		add = function(player: Player)
			local profile: Profile = {
				choice = Loadout.sanitize(nil),
				look = Looks.default(),
				dirty = false,
				lastSave = 0,
				loaded = false,
			}
			profiles[player] = profile
			publish(player, profile)
			task.spawn(loadProfile, player, profile)
		end,
		remove = function(player: Player)
			local profile = profiles[player]
			if profile ~= nil then
				save(player, profile)
			end
			profiles[player] = nil
			lastRequest[player] = nil
		end,
		saveAll = function()
			for player, profile in profiles do
				save(player, profile)
			end
		end,
		handle = handle,
		setOwnership = function(owns: (player: Player, item: string) -> boolean)
			ownership = owns
		end,
		refresh = function(player: Player)
			local profile = profiles[player]
			if profile ~= nil then
				publish(player, profile)
				onChange(player)
			end
		end,
		destroy = function()
			running = false
			connection:Disconnect()
		end,
	}

	if not testing then
		-- With options (checks) the module leaves the game alone, so no shutdown hook either.
		game:BindToClose(function()
			self.saveAll()
		end)
	end
	return self
end

return Garage
