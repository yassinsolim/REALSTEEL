--!strict

-- Reads the round and match state the simulation keeps on the match core, in one typed table for the HUD, the menu and
-- the camera. Client-only; nothing here writes anything.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MatchFlow = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MatchFlow"))

export type View = {
	-- Commands from the server.
	lobby: boolean,
	training: boolean,
	botLevel: number,
	-- Written by the simulation.
	phase: number,
	phaseFrame: number,
	round: number,
	winsA: number,
	winsB: number,
	timer: number,
	result: number,
	reason: number,
}

local MatchView = {}

function MatchView.new(): View
	return {
		lobby = true,
		training = true,
		botLevel = 0,
		phase = MatchFlow.Phase.Lobby,
		phaseFrame = 0,
		round = 1,
		winsA = 0,
		winsB = 0,
		timer = 0,
		result = 0,
		reason = 0,
	}
end

local function number(core: Instance, name: string, fallback: number): number
	local value = core:GetAttribute(name)
	return if type(value) == "number" then value else fallback
end

function MatchView.read(core: Instance, into: View)
	into.lobby = core:GetAttribute("Lobby") == true
	into.training = core:GetAttribute("TrainingMode") == true
	into.botLevel = number(core, "BotLevel", 0)
	into.phase = number(core, "Phase", MatchFlow.Phase.Lobby)
	into.phaseFrame = number(core, "PhaseFrame", 0)
	into.round = number(core, "Round", 1)
	into.winsA = number(core, "WinsA", 0)
	into.winsB = number(core, "WinsB", 0)
	into.timer = number(core, "Timer", 0)
	into.result = number(core, "Result", 0)
	into.reason = number(core, "Reason", 0)
end

return MatchView
