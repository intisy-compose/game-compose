#Requires -Version 5.1
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Targets)

Set-StrictMode -Version Latest

$dataDir = "$PSScriptRoot\mc_data"
$games   = @("minecraft", "hytale", "ark-ase", "ark-asa")

function Assert-Admin([string]$ArgLine) {
    $principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" $ArgLine" -Verb RunAs
        exit
    }
}
function Write-Step([string]$msg) { Write-Host $msg -ForegroundColor Cyan }
function Write-OK([string]$msg)   { Write-Host "  $msg" -ForegroundColor Green }
function Show-Usage {
    Write-Host "Usage: .\docker-compose.ps1 [<game>...|down|logs]"
    Write-Host "  Games (none run by default): $($games -join ', ')"
    Write-Host "  e.g. .\docker-compose.ps1 minecraft       run one server"
    Write-Host "       .\docker-compose.ps1 minecraft hytale  run several"
    Write-Host "       .\docker-compose.ps1 down              stop everything"
}

# Paper writes configs atomically (temp -> chmod -> rename). Docker Desktop's
# Windows bind mounts report files as root-owned, so non-root servers can't chmod
# and crash-loop. Probe as uid 1000: if it fails, use the volume + sync override.
function Test-ChmodSupported {
    docker run --rm -u 1000:1000 -v "${dataDir}:/probe" alpine `
        sh -c 'touch /probe/.chmodprobe && chmod 600 /probe/.chmodprobe; r=$?; rm -f /probe/.chmodprobe; exit $r' 2>$null | Out-Null
    return ($LASTEXITCODE -eq 0)
}

Set-Location $PSScriptRoot
if (-not (Test-Path $dataDir)) { New-Item -ItemType Directory -Force $dataDir | Out-Null }

$composeFiles = @("-f", "$PSScriptRoot\docker-compose.yml")
if (-not (Test-ChmodSupported)) {
    Write-Step "Data partition can't chmod; using volumes + sync mirror."
    $composeFiles += @("-f", "$PSScriptRoot\docker-compose.sync.yml")
}

$action = if ($Targets) { $Targets[0].ToLower() } else { "" }

switch ($action) {
    ""     { Show-Usage }
    "down" { Write-Step "Stopping everything..."; docker compose $composeFiles --profile "*" down }
    "logs" { docker compose $composeFiles --profile "*" logs -f }
    default {
        $selected = $Targets | ForEach-Object { $_.ToLower() }
        $unknown  = $selected | Where-Object { $_ -notin $games }
        if ($unknown) { Write-Host "Unknown server(s): $($unknown -join ', ')" -ForegroundColor Red; Show-Usage; exit 1 }

        Assert-Admin -ArgLine ($selected -join ' ')

        Write-Step "Reserving ports from Hyper-V..."
        net stop winnat  | Out-Null
        netsh int ipv4 add excludedportrange protocol=tcp startport=25565 numberofports=1 | Out-Null
        net start winnat | Out-Null

        $profileArgs = @()
        foreach ($g in $selected) { $profileArgs += @("--profile", $g) }
        Write-Step "Starting: $($selected -join ', ')"
        docker compose $composeFiles $profileArgs up -d
        Write-OK "Running. Stop with: .\docker-compose.ps1 down"
        Write-Host "`nPress Enter to exit..."
        $null = Read-Host
    }
}
