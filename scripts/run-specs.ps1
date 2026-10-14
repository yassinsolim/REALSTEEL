param(
    [string]$Luau = '',
    [string[]]$Specs = @('FightSimSpec', 'BotSpec', 'LoadoutSpec', 'QueueSpec', 'LayoutSpec', 'PadSpec', 'StandingsSpec', 'HoistSpec', 'CasesSpec', 'RewardsSpec')
)

# Runs the pure specs (the ones that need no Roblox types) without Studio. It bundles the shared modules that have no
# Roblox dependencies together with the specs into one file under build/ and runs it with the standalone Luau
# interpreter, which is not part of rokit.toml: download luau-windows.zip from https://github.com/luau-lang/luau/releases,
# unzip it, and pass the path to luau.exe with -Luau (or put it on PATH). The bundle stands in just enough of Vector3 and
# CFrame for FoundryLayout and LayoutSpec; RobotSpec needs the real ones, so it only runs in Studio.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
if (-not $Luau) {
    $found = Get-Command luau -ErrorAction SilentlyContinue
    if ($null -eq $found) {
        throw 'The Luau interpreter was not found. Pass -Luau <path to luau.exe> (see the comment at the top of this script).'
    }
    $Luau = $found.Source
}

$builder = New-Object System.Text.StringBuilder
[void]$builder.AppendLine('local __modules = {}')
[void]$builder.AppendLine('local __loaded = {}')
[void]$builder.AppendLine('local function load(name) if __loaded[name] == nil then __loaded[name] = __modules[name]() end return __loaded[name] end')
[void]$builder.AppendLine('local game = { GetService = function() return {} end }')
# Just enough of Vector3, CFrame and Vector2 for FoundryLayout and LayoutSpec: positions, sums, scaling, length, direction, dot
# products, and frames that only know where they are and which way they look.
[void]$builder.AppendLine(@'
local Vector3, CFrame
do
	local V3 = {}
	local function new(x, y, z)
		return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V3)
	end
	V3.__index = function(self, key)
		local length = math.sqrt(rawget(self, "X") ^ 2 + rawget(self, "Y") ^ 2 + rawget(self, "Z") ^ 2)
		if key == "Magnitude" then
			return length
		elseif key == "Unit" then
			return new(rawget(self, "X") / length, rawget(self, "Y") / length, rawget(self, "Z") / length)
		elseif key == "Dot" then
			return function(a, b)
				return a.X * b.X + a.Y * b.Y + a.Z * b.Z
			end
		end
		return nil
	end
	V3.__add = function(a, b) return new(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
	V3.__sub = function(a, b) return new(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
	V3.__unm = function(a) return new(-a.X, -a.Y, -a.Z) end
	V3.__mul = function(a, b)
		if type(a) == "number" then return new(a * b.X, a * b.Y, a * b.Z) end
		if type(b) == "number" then return new(a.X * b, a.Y * b, a.Z * b) end
		return new(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
	end
	V3.__div = function(a, b) return new(a.X / b, a.Y / b, a.Z / b) end
	V3.__eq = function(a, b) return a.X == b.X and a.Y == b.Y and a.Z == b.Z end
	Vector3 = {
		new = new,
		zero = new(0, 0, 0),
		one = new(1, 1, 1),
		xAxis = new(1, 0, 0),
		yAxis = new(0, 1, 0),
		zAxis = new(0, 0, 1),
	}

	local CF = {}
	CF.__index = function(self, key)
		local position = rawget(self, "Position")
		if key == "X" then return position.X elseif key == "Y" then return position.Y elseif key == "Z" then return position.Z end
		return nil
	end
	local function frame(position, look)
		return setmetatable({ Position = position, LookVector = look }, CF)
	end
	CF.__add = function(a, b) return frame(a.Position + b, a.LookVector) end
	CFrame = {
		new = function(x, y, z)
			return frame(if type(x) == "table" then x else new(x or 0, y or 0, z or 0), new(0, 0, -1))
		end,
		lookAt = function(at, target)
			return frame(at, (target - at).Unit)
		end,
	}
	CFrame.identity = CFrame.new()
end
local Vector2 = {
	new = function(x, y)
		return { X = x or 0, Y = y or 0 }
	end,
}
'@)
foreach ($name in 'FightConfig', 'FightSim', 'MatchFlow', 'Loadout', 'Looks', 'Shop', 'BotBrain', 'FrameData', 'RingQueue', 'FoundryLayout', 'PadRules', 'Standings', 'Hoist', 'Cases', 'DailyRewards', 'Contracts') {
    $source = [System.IO.File]::ReadAllText((Join-Path $root "src\shared\$name.luau"))
    # The modules require each other through script.Parent, and export their types; neither exists outside Roblox.
    $source = $source -replace 'require\(script\.Parent\.(\w+)\)', 'load("$1")'
    $source = $source -replace '(?m)^export type', 'type'
    [void]$builder.AppendLine("__modules.$name = function()")
    [void]$builder.AppendLine($source)
    [void]$builder.AppendLine('end')
}
[void]$builder.AppendLine('local __specs = {}')
foreach ($name in $Specs) {
    $source = [System.IO.File]::ReadAllText((Join-Path $root "tests\$name.luau"))
    $source = $source -replace 'require\(ReplicatedStorage\.Shared\.(\w+)\)', 'load("$1")'
    [void]$builder.AppendLine("__specs.$name = function()")
    [void]$builder.AppendLine($source)
    [void]$builder.AppendLine('end')
}
[void]$builder.AppendLine(@'
local totalFailures = 0
local names = {
'@)
foreach ($name in $Specs) {
    [void]$builder.AppendLine("`t`"$name`",")
}
[void]$builder.AppendLine(@'
}
for _, name in names do
	local run = __specs[name]()
	local passed, failures = run()
	print(string.format("%-14s %3d passed, %d failed", name, passed, #failures))
	for _, failure in failures do
		print("  FAIL " .. failure)
	end
	totalFailures += #failures
end
if totalFailures > 0 then
	error(totalFailures .. " checks failed")
end
'@)

New-Item -ItemType Directory -Path (Join-Path $root 'build') -Force | Out-Null
$bundle = Join-Path $root 'build\run-specs.bundle.luau'
# The interpreter rejects a byte order mark, so write without one.
[System.IO.File]::WriteAllText($bundle, $builder.ToString(), (New-Object System.Text.UTF8Encoding($false)))
& $Luau $bundle
if ($LASTEXITCODE -ne 0) {
    throw "The specs failed (exit code $LASTEXITCODE)."
}
Write-Output 'PASS: specs'
