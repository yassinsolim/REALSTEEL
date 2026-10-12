param(
    [switch]$Set
)

# Keeps the Open Cloud API key outside the repository, encrypted for the current Windows user (DPAPI).
# Run `./scripts/api-key.ps1 -Set` to store or replace it; other scripts dot-source this file and call Get-RobloxApiKey.
$script:RobloxApiKeyFile = Join-Path $env:LOCALAPPDATA 'REALSTEEL\roblox-api-key.txt'

function Get-RobloxApiKey {
    if ($env:ROBLOX_API_KEY) {
        return $env:ROBLOX_API_KEY
    }
    if (-not (Test-Path $script:RobloxApiKeyFile)) {
        throw 'No Open Cloud API key stored. Run ./scripts/api-key.ps1 -Set and paste the key.'
    }
    $secure = Get-Content $script:RobloxApiKeyFile | ConvertTo-SecureString
    return (New-Object System.Management.Automation.PSCredential('key', $secure)).GetNetworkCredential().Password
}

if ($Set) {
    $secure = Read-Host -AsSecureString 'Paste the Open Cloud API key (input is hidden)'
    if ($secure.Length -eq 0) {
        throw 'No key entered; nothing stored.'
    }
    New-Item -ItemType Directory -Force -Path (Split-Path $script:RobloxApiKeyFile) | Out-Null
    $secure | ConvertFrom-SecureString | Set-Content -Path $script:RobloxApiKeyFile
    Write-Output "Stored the key encrypted for $env:USERNAME in $script:RobloxApiKeyFile"
}
