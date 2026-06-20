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
function Import-Config([string]$Path) {
    if (-not (Test-Path $Path)) { return }
    Get-Content $Path | Where-Object { $_ -notmatch '^\s*#' -and $_ -match '=' } | ForEach-Object {
        $k, $v = $_ -split '=', 2
        Set-Item "env:$($k.Trim())" $v.Trim()
    }
}
function Show-Usage {
    Write-Host "Usage: .\docker-compose.ps1 [<game>...|down|logs]"
    Write-Host "  (no args)  create all containers (stopped) for Docker Desktop"
    Write-Host "  <game>...  run server(s) now: $($games -join ', ')"
    Write-Host "  down       stop and remove everything"
    Write-Host "  logs       follow logs"
    Write-Host "  vps        set up / verify the frp server on the VPS (TUNNEL=frp)"
}

# Paper writes configs atomically (temp -> chmod -> rename). Docker Desktop's
# Windows bind mounts report files as root-owned, so non-root servers can't chmod
# and crash-loop. Probe as uid 1000: if it fails, use the volume + sync override.
function Test-ChmodSupported {
    docker run --rm -u 1000:1000 -v "${dataDir}:/probe" alpine `
        sh -c 'touch /probe/.chmodprobe && chmod 600 /probe/.chmodprobe; r=$?; rm -f /probe/.chmodprobe; exit $r' 2>$null | Out-Null
    return ($LASTEXITCODE -eq 0)
}

# Provisions frps on the VPS over SSH if it isn't already running: installs
# Docker, opens the firewall, writes the token config, and starts the container.
# Idempotent — safe to call on every frp start.
function Ensure-Frps {
    if (-not $frpServer) { Write-Host "FRP_SERVER_ADDR not set in config.env" -ForegroundColor Red; exit 1 }
    if (-not (Test-Path $sshKey)) { Write-Host "SSH key not found: $sshKey" -ForegroundColor Red; exit 1 }
    # Git's ssh tolerates the key's file permissions; Windows' ssh.exe rejects
    # them on this drive. Prefer Git's, fall back to whatever ssh is on PATH.
    $sshExe = "ssh"
    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($git) { $c = Join-Path (Split-Path (Split-Path $git.Source)) "usr\bin\ssh.exe"; if (Test-Path $c) { $sshExe = $c } }
    $sshArgs = @("-i", $sshKey, "-o", "StrictHostKeyChecking=accept-new", "-o", "ConnectTimeout=20", "$sshUser@$frpServer")

    Write-Step "Checking frps on $frpServer ..."
    if ((& $sshExe @sshArgs "sudo docker ps --filter name=frps --format '{{.Names}}'" 2>$null) -match "frps") {
        Write-OK "frps already running."; return
    }

    Write-Step "  Installing Docker if missing..."
    & $sshExe @sshArgs "command -v docker >/dev/null 2>&1 || (curl -fsSL https://get.docker.com | sudo sh)" 2>&1 | Out-Null

    Write-Step "  Opening firewall ports..."
    & $sshExe @sshArgs 'for r in "tcp 7000" "tcp 25565" "udp 5520" "udp 7777" "udp 7778" "udp 7779" "udp 7780" "udp 19132" "udp 27015"; do set -- $r; sudo iptables -C INPUT -p $1 --dport $2 -j ACCEPT 2>/dev/null || sudo iptables -I INPUT 6 -p $1 --dport $2 -j ACCEPT; done; sudo DEBIAN_FRONTEND=noninteractive apt-get install -y netfilter-persistent >/dev/null 2>&1; sudo netfilter-persistent save >/dev/null 2>&1' 2>&1 | Out-Null

    Write-Step "  Writing frps config and starting frps..."
    "bindPort = $frpPort`nauth.method = `"token`"`nauth.token = `"$frpToken`"`n" | & $sshExe @sshArgs "mkdir -p ~/frp && cat > ~/frp/frps.toml"
    & $sshExe @sshArgs 'sudo docker rm -f frps >/dev/null 2>&1; sudo docker run -d --name frps --restart unless-stopped --network host -v $HOME/frp/frps.toml:/etc/frp/frps.toml snowdreamtech/frps' 2>&1 | Out-Null

    Start-Sleep -Seconds 3
    if ((& $sshExe @sshArgs "sudo docker ps --filter name=frps --format '{{.Names}}'" 2>$null) -match "frps") {
        Write-OK "frps is up on $frpServer."
    } else {
        Write-Host "frps did not start. Debug: ssh -i $sshKey $sshUser@$frpServer 'sudo docker logs frps'" -ForegroundColor Red
    }
}

Set-Location $PSScriptRoot
if (-not (Test-Path $dataDir)) { New-Item -ItemType Directory -Force $dataDir | Out-Null }

Import-Config "$PSScriptRoot\config.env"
if (-not $env:TUNNEL) { $env:TUNNEL = "playit" }
$tunnel = $env:TUNNEL.ToLower()
$env:TUNNEL = $tunnel

$frpServer = $env:FRP_SERVER_ADDR
$frpPort   = if ($env:FRP_SERVER_PORT) { $env:FRP_SERVER_PORT } else { "7000" }
$frpToken  = $env:FRP_TOKEN
$sshUser   = if ($env:FRP_SSH_USER) { $env:FRP_SSH_USER } else { "ubuntu" }
$sshKey    = if ($env:FRP_SSH_KEY)  { $env:FRP_SSH_KEY }  else { "vps/ssh-key" }
if ($sshKey -and -not [System.IO.Path]::IsPathRooted($sshKey)) { $sshKey = Join-Path $PSScriptRoot $sshKey }

$composeFiles = @("-f", "$PSScriptRoot\docker-compose.yml")
if (-not (Test-ChmodSupported)) {
    Write-Step "Data partition can't chmod; using volumes + sync mirror."
    $composeFiles += @("-f", "$PSScriptRoot\docker-compose.sync.yml")
}

$action = if ($Targets) { $Targets[0].ToLower() } else { "" }

switch ($action) {
    "vps"  { Ensure-Frps; break }
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

        if ($tunnel -eq "frp") { Ensure-Frps }

        Write-Step "Reserving ports from Hyper-V..."
        net stop winnat  | Out-Null
        netsh int ipv4 add excludedportrange protocol=tcp startport=25565 numberofports=1 | Out-Null
        net start winnat | Out-Null

        Write-Step "Creating game containers (stopped); starting $tunnel + sync..."
        docker compose $composeFiles --profile "*" create
        docker compose $composeFiles --profile $tunnel up -d

        if ($selected) {
            $profileArgs = @("--profile", $tunnel)
            foreach ($g in $selected) { $profileArgs += @("--profile", $g) }
            Write-Step "Starting: $($selected -join ', ')"
            docker compose $composeFiles $profileArgs up -d
        }

        Write-OK "$tunnel + sync running; games are in Docker Desktop ready to start."
        Write-Host "`nPress Enter to exit..."
        $null = Read-Host
    }
}
