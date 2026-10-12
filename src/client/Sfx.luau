--!strict

-- Sound effects. Every sound is a free Creator Store asset (see the audio credits in the README), chosen by measuring
-- each one's loudness over time with an AudioAnalyzer: a hit has to start within a frame or two, or the sound lags the
-- picture. A kind can have several variations, and each play picks one at random and shifts its pitch a little, so a
-- run of punches never sounds like a machine gun of one sample.
--
-- Everything is client-side and flat (not positional): the camera is fixed to the fight, so panning adds nothing.
-- A sound that fails to load is skipped, so a removed asset costs a sound, never an error.

local ContentProvider = game:GetService("ContentProvider")
local Debris = game:GetService("Debris")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

export type Sfx = {
	folder: Folder,
	templates: { [string]: { Sound } },
	random: Random,
	-- Master volume, 0 to 1.
	volume: number,
	ambience: Sound?,
	crowdLevel: number,
	lastCrowd: number,
}

type Kind = {
	ids: { number },
	volume: number,
	-- Where in the file the sound starts, for assets with a gap before the hit.
	from: number?,
	-- Cut the sound off after this many seconds, with a short fade.
	limit: number?,
}

local Sfx = {}

local KINDS: { [string]: Kind } = {
	-- Punch Impact 1, 2, 3 by NickySergal.
	punch = { ids = { 132504023010884, 126895218143022, 96439476779754 }, volume = 0.9 },
	-- Heavy_punch_impact_#3 by MegaBloxxy.
	heavy = { ids = { 82235785832022 }, volume = 1 },
	-- Metal Drops Clanking Impacts On Concrete 11, Pro Sound Effects. The hit starts 0.17 s in.
	clank = { ids = { 9116617045 }, volume = 1.7, from = 0.17, limit = 0.7 },
	-- Electric Whoosh Bys Singles Low End Synth Buzz 1, Pro Sound Effects. Swells for 0.18 s, like a strike.
	whoosh = { ids = { 9125517884 }, volume = 0.9, limit = 0.6 },
	-- Deep Hits Big Reverberant Booms Rumbling Tail 1, Pro Sound Effects.
	boom = { ids = { 9125484526 }, volume = 1, limit = 2.8 },
	-- Boxing Bell by scorp_ius.
	bell = { ids = { 135309651997361 }, volume = 0.8, limit = 2.4 },
	-- Wrestling Crowd 3, Pro Sound Effects.
	surge = { ids = { 9120974378 }, volume = 0.55, limit = 4 },
}

-- Large Arena Crowd Ambience by Extreme Action Wrestling, a long loop under everything.
local AMBIENCE_ID = 6145229185
local AMBIENCE_BASE = 0.1
local AMBIENCE_EXCITED = 0.26
local SURGE_COOLDOWN = 3.5

local function newSound(id: number, parent: Instance): Sound
	local sound = Instance.new("Sound")
	sound.Name = tostring(id)
	sound.SoundId = "rbxassetid://" .. id
	sound.Parent = parent
	return sound
end

function Sfx.new(): Sfx
	local folder = Instance.new("Folder")
	folder.Name = "Sfx"
	folder.Parent = SoundService

	local templates: { [string]: { Sound } } = {}
	local toLoad: { Instance } = {}
	for name, kind in KINDS do
		local list: { Sound } = {}
		for _, id in kind.ids do
			local sound = newSound(id, folder)
			table.insert(list, sound)
			table.insert(toLoad, sound)
		end
		templates[name] = list
	end

	local ambience = newSound(AMBIENCE_ID, folder)
	ambience.Name = "Ambience"
	ambience.Looped = true
	ambience.Volume = 0
	table.insert(toLoad, ambience)

	-- Load in the background; playing a sound that has not loaded yet simply waits for it.
	task.spawn(function()
		pcall(function()
			ContentProvider:PreloadAsync(toLoad)
		end)
	end)

	return {
		folder = folder,
		templates = templates,
		random = Random.new(),
		volume = 1,
		ambience = ambience,
		crowdLevel = 0,
		lastCrowd = -100,
	}
end

-- Plays one sound of `name`. `gain` scales its volume and `pitch` its speed, on top of a small random shift, and `from`
-- overrides where in the file it starts.
function Sfx.play(self: Sfx, name: string, gain: number?, pitch: number?, from: number?)
	local kind = KINDS[name]
	local list = self.templates[name]
	if kind == nil or list == nil or #list == 0 or self.volume <= 0 then
		return
	end
	local sound = list[self.random:NextInteger(1, #list)]:Clone()
	sound.Volume = kind.volume * (gain or 1) * self.volume
	sound.PlaybackSpeed = (pitch or 1) * self.random:NextNumber(0.94, 1.06)
	sound.TimePosition = from or kind.from or 0
	sound.Parent = self.folder
	sound:Play()

	local limit = kind.limit
	if limit ~= nil then
		-- Fade out over the last 0.15 s of the allowed time instead of cutting off.
		local fade = math.min(0.15, limit / 2)
		task.delay((limit - fade) / math.max(sound.PlaybackSpeed, 0.1), function()
			if sound.Parent ~= nil then
				TweenService:Create(sound, TweenInfo.new(fade), { Volume = 0 }):Play()
			end
		end)
		Debris:AddItem(sound, limit / math.max(sound.PlaybackSpeed, 0.1) + 0.1)
	else
		Debris:AddItem(sound, sound.TimeLength / math.max(sound.PlaybackSpeed, 0.1) + 0.5)
	end
end

-- A swell of cheering, at most once in a while.
function Sfx.surge(self: Sfx, now: number, gain: number?)
	if now - self.lastCrowd < SURGE_COOLDOWN then
		return
	end
	self.lastCrowd = now
	Sfx.play(self, "surge", gain, 1)
end

-- The crowd bed gets louder with excitement (0 to 1) and quieter while a menu is up.
function Sfx.setCrowd(self: Sfx, excitement: number, menuOpen: boolean)
	local ambience = self.ambience
	if ambience == nil then
		return
	end
	local target = (AMBIENCE_BASE + (AMBIENCE_EXCITED - AMBIENCE_BASE) * math.clamp(excitement, 0, 1))
		* (if menuOpen then 0.6 else 1)
		* self.volume
	self.crowdLevel += (target - self.crowdLevel) * 0.08
	ambience.Volume = self.crowdLevel
	if not ambience.IsPlaying and self.volume > 0 then
		ambience:Play()
	end
end

return Sfx
