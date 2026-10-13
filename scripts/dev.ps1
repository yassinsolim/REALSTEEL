param(
    [ValidateSet('format', 'format-check', 'lint', 'sourcemap', 'typecheck', 'build', 'test-build', 'validate', 'serve')]
    [string]$Task = 'validate'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-ProjectTool {
    param([string]$Name, [string[]]$Arguments)

    & $Name @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Name failed with exit code $LASTEXITCODE."
    }
}

function Invoke-Sourcemap {
    Invoke-ProjectTool rojo @('sourcemap', '--include-non-scripts', 'default.project.json', '--output', 'sourcemap.json')
}

function Invoke-Typecheck {
    Invoke-Sourcemap
    $version = (& luau-lsp --version).Trim()
    if ($LASTEXITCODE -ne 0 -or $version -notmatch '^\d+\.\d+\.\d+$') {
        throw 'Could not determine the installed stable Luau Language Server version.'
    }

    $definitionsPath = ".luau/$version-globalTypes.d.luau"
    if (-not (Test-Path $definitionsPath)) {
        New-Item -ItemType Directory -Path '.luau' -Force | Out-Null
        $downloadPath = "$definitionsPath.download"
        try {
            Invoke-WebRequest -UseBasicParsing -Uri "https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/$version/scripts/globalTypes.d.luau" -OutFile $downloadPath
            Move-Item -Path $downloadPath -Destination $definitionsPath
        }
        finally {
            if (Test-Path $downloadPath) {
                Remove-Item $downloadPath
            }
        }
    }

    Invoke-ProjectTool luau-lsp @('analyze', '--platform=roblox', '--sourcemap=sourcemap.json', "--definitions=$definitionsPath", 'src', 'tests/FightSimSpec.luau', 'tests/RobotSpec.luau', 'tests/BotSpec.luau', 'tests/LoadoutSpec.luau', 'tests/GarageSpec.luau', 'tests/GarageServerSpec.luau', 'tests/QueueSpec.luau', 'tests/LayoutSpec.luau', 'tests/PadSpec.luau', 'tests/StandingsSpec.luau', 'tests/HoistSpec.luau', 'tests/RecordsSpec.luau')
}

function Invoke-Build {
    New-Item -ItemType Directory -Path 'build' -Force | Out-Null
    Invoke-ProjectTool rojo @('build', 'default.project.json', '--output', 'build/REALSTEEL.rbxlx')
}

# The checks place adds the automated multiplayer scripts from tests/ on top of the game; it is never published.
function Invoke-TestBuild {
    Invoke-Typecheck
    New-Item -ItemType Directory -Path 'build' -Force | Out-Null
    Invoke-ProjectTool rojo @('sourcemap', 'tests/playtest.project.json', '--include-non-scripts', '--output', 'build/test-sourcemap.json')
    $version = (& luau-lsp --version).Trim()
    # Sourcemap paths are relative to the project file, so analyze from the tests folder.
    Push-Location 'tests'
    try {
        Invoke-ProjectTool luau-lsp @('analyze', '--platform=roblox', '--sourcemap=../build/test-sourcemap.json', "--definitions=../.luau/$version-globalTypes.d.luau", '../src', 'StudioChecks.server.luau', 'StudioChecks.client.luau')
    }
    finally {
        Pop-Location
    }
    Invoke-ProjectTool rojo @('build', 'tests/playtest.project.json', '--output', 'build/REALSTEEL-checks.rbxlx')
}

$originalPath = $env:Path
Push-Location (Split-Path -Parent $PSScriptRoot)
try {
    $rokitBin = Join-Path $HOME '.rokit/bin'
    if (Test-Path $rokitBin) {
        $env:Path = "$rokitBin;$env:Path"
    }

    switch ($Task) {
        'format' { Invoke-ProjectTool stylua @('src', 'tests') }
        'format-check' { Invoke-ProjectTool stylua @('--check', 'src', 'tests') }
        'lint' { Invoke-ProjectTool selene @('src', 'tests') }
        'sourcemap' { Invoke-Sourcemap }
        'typecheck' { Invoke-Typecheck }
        'build' { Invoke-Build }
        'test-build' { Invoke-TestBuild }
        'validate' {
            Invoke-ProjectTool stylua @('--check', 'src', 'tests')
            Invoke-ProjectTool selene @('src', 'tests')
            Invoke-TestBuild
            Invoke-Build
        }
        'serve' { Invoke-ProjectTool rojo @('serve', 'default.project.json', '--address', '127.0.0.1') }
    }

    Write-Output "PASS: $Task"
}
finally {
    $env:Path = $originalPath
    Pop-Location
}
