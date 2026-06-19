#Requires -Version 5.1
param([string]$Command = "")

Set-StrictMode -Version Latest

$dataDir = "$PSScriptRoot\mc_data"

function Assert-Admin([string]$ScriptPath, [string]$Command = "") {
    $principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`" $Command" -Verb RunAs
        exit
    }
}
function Write-Step([string]$msg) { Write-Host $msg -ForegroundColor Cyan }
function Write-OK([string]$msg)   { Write-Host "  $msg" -ForegroundColor Green }

# Paper writes configs atomically (temp -> chmod -> rename). Docker Desktop's
# Windows bind mounts report every file as root-owned, so the server's uid 1000
# can't chmod and crash-loops. Probe as that same uid: if chmod fails we run on
# a volume and mirror to the folder (sync override).
function Test-ChmodSupported {
    docker run --rm -u 1000:1000 -v "${dataDir}:/probe" alpine `
        sh -c 'touch /probe/.chmodprobe && chmod 600 /probe/.chmodprobe; r=$?; rm -f /probe/.chmodprobe; exit $r' 2>$null | Out-Null
    return ($LASTEXITCODE -eq 0)
}

Assert-Admin -ScriptPath $PSCommandPath -Command $Command
Set-Location $PSScriptRoot

if (-not (Test-Path $dataDir)) { New-Item -ItemType Directory -Force $dataDir | Out-Null }

$composeFiles = @("-f", "$PSScriptRoot\docker-compose.yml")
if (-not (Test-ChmodSupported)) {
    Write-Step "Data folder can't chmod; enabling volume + sync mirror."
    $composeFiles += @("-f", "$PSScriptRoot\docker-compose.sync.yml")
}

switch ($Command.ToLower()) {
    "down" { Write-Step "Stopping..."; docker compose $composeFiles down }
    "logs" { docker compose $composeFiles logs -f }
    default {
        Write-Step "Reserving ports from Hyper-V..."
        net stop winnat  | Out-Null
        netsh int ipv4 add excludedportrange protocol=tcp startport=25565 numberofports=1 | Out-Null
        net start winnat | Out-Null
        Write-Step "Starting game servers..."
        docker compose $composeFiles up -d
        Write-OK "Stack is up."
        Write-Host "`nPress Enter to exit..."
        $null = Read-Host
    }
}
