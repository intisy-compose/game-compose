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
    Write-Host "Usage: .\docker-compose.ps1 [<game>...|down|logs|vps|console|data]"
    Write-Host "  (no args)        create all containers (stopped) for Docker Desktop"
    Write-Host "  <game>...        run server(s) now: $($games -join ', ')"
    Write-Host "  down             stop and remove everything"
    Write-Host "  logs             follow logs"
    Write-Host "  vps              set up / verify the frp server on the VPS (TUNNEL=frp)"
    Write-Host "  console [name]   attach to a console: $($consoles.Keys -join ', ')"
    Write-Host "  data list        show data slots and their default (public template) source"
    Write-Host "  data status      show each slot's checked-out commit"
    Write-Host "  data use <slot> [owner/repo[@ref]]"
    Write-Host "                   point a slot at a data repo (no source = public template)"
    Write-Host "Data slots: $($dataSlots.Keys -join ', ')"
}

$dataSlots = [ordered]@{ mc = "mc_data"; hytale = "hytale_data"; "ark-ase" = "ark_ase_data"; "ark-asa" = "ark_asa_data" }
$consoles  = [ordered]@{
    minecraft = "minecraft_server"; hytale = "hytale_server"; playit = "playit_agent"
    "ark-ase" = "ark_ase_server"; "ark-asa" = "ark_asa_server"
}

function Resolve-DataSource([string]$Path, [string]$Source) {
    if ([string]::IsNullOrEmpty($Source)) {
        return @{ Url = (git config -f .gitmodules "submodule.$Path.url"); Ref = "main" }
    }
    $parts = $Source.Split("@", 2)
    $url = if ($parts[0] -match "://|^git@") { $parts[0] } else { "https://github.com/$($parts[0]).git" }
    return @{ Url = $url; Ref = $(if ($parts.Count -eq 2) { $parts[1] } else { "main" }) }
}

function Set-DataSource([string]$Path, [string]$Source) {
    $resolved = Resolve-DataSource $Path $Source
    Write-Step "Pointing $Path at $($resolved.Url) @ $($resolved.Ref)"
    if (-not (Test-Path "$Path\.git")) { git submodule update --init -- $Path 2>$null | Out-Null }
    git config "submodule.$Path.url" $resolved.Url
    git -C $Path remote set-url origin $resolved.Url
    git -C $Path fetch -q origin $resolved.Ref
    git -C $Path checkout -q FETCH_HEAD
    Write-OK "$Path now at $(git -C $Path rev-parse --short HEAD)"
}

function Invoke-Data([string[]]$Arguments) {
    $subcommand = if ($Arguments) { $Arguments[0].ToLower() } else { "list" }
    switch ($subcommand) {
        "list" {
            foreach ($slot in $dataSlots.Keys) {
                "{0,-9} {1,-14} {2}" -f $slot, $dataSlots[$slot], (git config -f .gitmodules "submodule.$($dataSlots[$slot]).url")
            }
        }
        "status" { git submodule status }
        "use" {
            $slot = if ($Arguments.Count -ge 2) { $Arguments[1].ToLower() } else { "" }
            if (-not $dataSlots.Contains($slot)) { Write-Host "Unknown data slot '$slot'" -ForegroundColor Red; Show-Usage; exit 1 }
            Set-DataSource $dataSlots[$slot] $(if ($Arguments.Count -ge 3) { $Arguments[2] } else { "" })
        }
        default { Show-Usage; exit 1 }
    }
}

function Enter-Console([string]$Name) {
    if (-not $Name) {
        $names = @($consoles.Keys)
        for ($index = 0; $index -lt $names.Count; $index++) { Write-Host "$($index + 1)) $($names[$index])" }
        $choice = Read-Host "Enter choice [1-$($names.Count)]"
        if ($choice -notmatch '^\d+$' -or [int]$choice -lt 1 -or [int]$choice -gt $names.Count) {
            Write-Host "Invalid choice." -ForegroundColor Red; exit 1
        }
        $Name = $names[[int]$choice - 1]
    }
    if (-not $consoles.Contains($Name.ToLower())) { Write-Host "Unknown console '$Name'" -ForegroundColor Red; Show-Usage; exit 1 }
    Write-Step "Attaching to $Name... (Ctrl+P, Ctrl+Q to detach)"
    docker attach $consoles[$Name.ToLower()]
}

# Provisions frps on the VPS over SSH if it isn't already running: installs
# Docker, opens the firewall, writes the token config, and starts the container.
# Idempotent - safe to call on every frp start.
function Ensure-Frps {
    if (-not $frpServer) { Write-Host "FRP_SERVER_ADDR not set in config.env" -ForegroundColor Red; exit 1 }
    if (-not (Test-Path $sshKey)) { Write-Host "SSH key not found: $sshKey" -ForegroundColor Red; exit 1 }
    # Git's ssh tolerates the key's file permissions; Windows' ssh.exe rejects
    # them on this drive. Prefer Git's, fall back to whatever ssh is on PATH.
    $sshExe = "ssh"; $scpExe = "scp"
    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($git) {
        $bin = Join-Path (Split-Path (Split-Path $git.Source)) "usr\bin"
        if (Test-Path "$bin\ssh.exe") { $sshExe = "$bin\ssh.exe" }
        if (Test-Path "$bin\scp.exe") { $scpExe = "$bin\scp.exe" }
    }
    $sshArgs = @("-i", $sshKey, "-o", "StrictHostKeyChecking=accept-new", "-o", "ConnectTimeout=20", "$sshUser@$frpServer")
    $scpArgs = @("-i", $sshKey, "-o", "StrictHostKeyChecking=accept-new", "-o", "ConnectTimeout=20")

    Write-Step "Checking frps on $frpServer ..."
    if ((& $sshExe @sshArgs "sudo ss -tln 2>/dev/null | grep -q ':$frpPort ' && echo UP" 2>$null) -match "UP") {
        Write-OK "frps already listening on :$frpPort."; return
    }

    Write-Step "  Installing Docker if missing..."
    & $sshExe @sshArgs "command -v docker >/dev/null 2>&1 || (curl -fsSL https://get.docker.com | sudo sh)" 2>&1 | Out-Null

    Write-Step "  Opening firewall ports..."
    # No quotes in the remote command: PowerShell mangles embedded double-quotes
    # when passing to ssh.exe, which silently breaks the loop.
    & $sshExe @sshArgs 'for p in 7000 25565; do sudo iptables -C INPUT -p tcp --dport $p -j ACCEPT 2>/dev/null || sudo iptables -I INPUT 1 -p tcp --dport $p -j ACCEPT; done; for p in 5520 7777 7778 7779 7780 19132 27015; do sudo iptables -C INPUT -p udp --dport $p -j ACCEPT 2>/dev/null || sudo iptables -I INPUT 1 -p udp --dport $p -j ACCEPT; done; sudo DEBIAN_FRONTEND=noninteractive apt-get install -y netfilter-persistent >/dev/null 2>&1; sudo netfilter-persistent save >/dev/null 2>&1' 2>&1 | Out-Null

    Write-Step "  Writing frps config and starting frps..."
    $tmpToml = Join-Path $env:TEMP "games-frps.toml"
    [System.IO.File]::WriteAllText($tmpToml, "bindPort = $frpPort`nauth.method = `"token`"`nauth.token = `"$frpToken`"`n", (New-Object System.Text.UTF8Encoding($false)))
    & $sshExe @sshArgs "mkdir -p ~/frp" 2>&1 | Out-Null
    & $scpExe @scpArgs $tmpToml "${sshUser}@${frpServer}:frp/frps.toml" 2>&1 | Out-Null
    Remove-Item $tmpToml -Force -ErrorAction SilentlyContinue
    & $sshExe @sshArgs 'sudo docker rm -f frps >/dev/null 2>&1; sudo docker run -d --name frps --restart unless-stopped --network host -v $HOME/frp/frps.toml:/etc/frp/frps.toml snowdreamtech/frps' 2>&1 | Out-Null

    Start-Sleep -Seconds 4
    if ((& $sshExe @sshArgs "sudo ss -tln 2>/dev/null | grep -q ':$frpPort ' && echo UP" 2>$null) -match "UP") {
        Write-OK "frps is up and listening on ${frpServer}:$frpPort."
    } else {
        Write-Host "frps not listening. Debug: ssh -i $sshKey $sshUser@$frpServer 'sudo docker logs frps'" -ForegroundColor Red
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

$action = if ($Targets) { $Targets[0].ToLower() } else { "" }
$rest   = @(if ($Targets -and $Targets.Count -gt 1) { $Targets[1..($Targets.Count - 1)] })

switch ($action) {
    "help"    { Show-Usage; break }
    "data"    { Invoke-Data $rest; break }
    "console" { Enter-Console $(if ($rest) { $rest[0] } else { "" }); break }
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
