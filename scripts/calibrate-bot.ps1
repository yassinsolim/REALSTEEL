param(
    [int]$Rounds = 100,
    [string]$Luau = ''
)

# Calibrates the bot levels without Studio. It bundles the pure shared modules (FightConfig, FightSim, MatchFlow, BotBrain)
# with scripts/calibrate-bot.luau into one file under build/ and runs it with the standalone Luau interpreter, which is
# not part of rokit.toml: download luau-windows.zip from https://github.com/luau-lang/luau/releases, unzip it, and pass
# the path to luau.exe with -Luau (or put it on PATH).
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
[void]$builder.AppendLine("ROUNDS = $Rounds")
[void]$builder.AppendLine('local __modules = {}')
[void]$builder.AppendLine('local __loaded = {}')
[void]$builder.AppendLine('local function load(name) if __loaded[name] == nil then __loaded[name] = __modules[name]() end return __loaded[name] end')
foreach ($name in 'FightConfig', 'FightSim', 'MatchFlow', 'BotBrain') {
    $source = [System.IO.File]::ReadAllText((Join-Path $root "src\shared\$name.luau"))
    # The modules require each other through script.Parent, and export their types; neither exists outside Roblox.
    $source = $source -replace 'require\(script\.Parent\.(\w+)\)', 'load("$1")'
    $source = $source -replace '(?m)^export type', 'type'
    [void]$builder.AppendLine("__modules.$name = function()")
    [void]$builder.AppendLine($source)
    [void]$builder.AppendLine('end')
}
[void]$builder.AppendLine([System.IO.File]::ReadAllText((Join-Path $PSScriptRoot 'calibrate-bot.luau')))

New-Item -ItemType Directory -Path (Join-Path $root 'build') -Force | Out-Null
$bundle = Join-Path $root 'build\calibrate-bot.bundle.luau'
# The interpreter rejects a byte order mark, so write without one.
[System.IO.File]::WriteAllText($bundle, $builder.ToString(), (New-Object System.Text.UTF8Encoding($false)))
& $Luau $bundle
if ($LASTEXITCODE -ne 0) {
    throw "The Luau interpreter failed with exit code $LASTEXITCODE."
}