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
    Write-Host "  (no args)  create all containers (stopped) for Docker Desktop"
    Write-Host "  <game>...  run server(s) now: $($games -join ', ')"
    Write-Host "  down       stop and remove everything"
    Write-Host "  logs       follow logs"
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
    "down" { Write-Step "Stopping everything..."; docker compose $composeFiles --profile "*" down; break }
    "logs" { docker compose $composeFiles --profile "*" logs -f; break }
    default {
        $selected = @()
        if ($action -ne "") {
            $selected = $Targets | ForEach-Object { $_.ToLower() }
            $unknown  = $selected | Where-Object { $_ -notin $games }
            if ($unknown) { Write-Host "Unknown server(s): $($unknown -join ', ')" -ForegroundColor Red; Show-Usage; exit 1 }
        }

        Assert-Admin -ArgLine ($selected -join ' ')

        Write-Step "Reserving ports from Hyper-V..."
        net stop winnat  | Out-Null
        netsh int ipv4 add excludedportrange protocol=tcp startport=25565 numberofports=1 | Out-Null
        net start winnat | Out-Null

        Write-Step "Creating game containers (stopped) and starting playit + sync..."
        docker compose $composeFiles --profile "*" create
        docker compose $composeFiles up -d

        if ($selected) {
            $profileArgs = @()
            foreach ($g in $selected) { $profileArgs += @("--profile", $g) }
            Write-Step "Starting: $($selected -join ', ')"
            docker compose $composeFiles $profileArgs up -d
        }

        Write-OK "playit + sync running; games are in Docker Desktop ready to start."
        Write-Host "`nPress Enter to exit..."
        $null = Read-Host
    }
}
