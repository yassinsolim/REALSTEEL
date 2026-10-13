param(
    [ValidateSet('none', 'rest', 'poses', 'all', 'kits', 'frames', 'worn')]
    [string]$Previews = 'none',
    [ValidateSet('WORKBENCH', 'EEVEE')]
    [string]$Engine = 'WORKBENCH',
    [string]$Sheets = '',
    [string]$Frames = '',
    [string]$Blender = ''
)

# Rebuilds the robot art with Blender running headless: for every frame (one robot per chassis) its worn-metal textures
# in art/build/textures, art/build/<Name>.fbx and rig data (not tracked), plus the generated Luau modules
# src/shared/RobotRigs.luau, RobotClips.luau and RobotKits.luau (tracked, formatted with stylua). -Frames 'BULWARK,LANCE'
# limits the textures and FBX to those frames. Previews render instead of exporting: -Previews poses renders contact
# sheets of the key poses into art/build, kits the crests and some paint jobs, frames lineups and a hero shot of every
# frame, and worn bakes the textures and renders every frame wearing them (use -Engine EEVEE, which gives lit renders).
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$originalPath = $env:Path
Push-Location (Split-Path -Parent $PSScriptRoot)
try {
    $rokitBin = Join-Path $HOME '.rokit/bin'
    if (Test-Path $rokitBin) {
        $env:Path = "$rokitBin;$env:Path"
    }
    if (-not $Blender) {
        $found = @(Get-ChildItem 'C:\Program Files\Blender Foundation' -Recurse -Filter blender.exe -ErrorAction SilentlyContinue |
                Sort-Object FullName -Descending | Select-Object -ExpandProperty FullName)
        if ($found.Count -eq 0) {
            throw 'Blender was not found. Pass -Blender <path to blender.exe>.'
        }
        $Blender = $found[0]
    }
    $arguments = @('--background', '--factory-startup', '--python', 'art/build_robot.py', '--', '--out', 'art/build',
        '--luau', 'src/shared', '--previews', $Previews, '--engine', $Engine)
    if ($Sheets) {
        $arguments += @('--sheets', $Sheets)
    }
    if ($Frames) {
        $arguments += @('--frames', $Frames)
    }
    & $Blender @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Blender failed with exit code $LASTEXITCODE."
    }
    & stylua src/shared/RobotRigs.luau src/shared/RobotClips.luau src/shared/RobotKits.luau
    if ($LASTEXITCODE -ne 0) {
        throw "stylua failed with exit code $LASTEXITCODE."
    }
    Write-Output 'PASS: art'
}
finally {
    $env:Path = $originalPath
    Pop-Location
}
