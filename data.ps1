# Swap a game-compose data slot to any data repo/branch, or restore the public default.
param([string]$Command = "list", [string]$Slot, [string]$Source)
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot
$Slots = @{ mc = "mc_data"; hytale = "hytale_data"; "ark-ase" = "ark_ase_data"; "ark-asa" = "ark_asa_data" }

function Show-Usage {
  Write-Host "Usage: .\data.ps1 <list|status|use> [slot] [owner/repo[@ref]]"
  Write-Host "  use <slot> [owner/repo[@ref]]  point a slot at a data repo (no source = public template)"
  Write-Host "Slots: $($Slots.Keys -join ', ')"
}

switch ($Command.ToLower()) {
  "list"   { foreach ($k in $Slots.Keys) { "{0,-9} {1,-14} {2}" -f $k, $Slots[$k], (git config -f .gitmodules "submodule.$($Slots[$k]).url") } }
  "status" { git submodule status }
  "use" {
    if (-not $Slots.ContainsKey($Slot)) { throw "unknown slot '$Slot'" }
    $d = $Slots[$Slot]
    if ([string]::IsNullOrEmpty($Source)) { $url = git config -f .gitmodules "submodule.$d.url"; $ref = "main" }
    else {
      $parts = $Source.Split("@", 2); $repo = $parts[0]; $ref = if ($parts.Count -eq 2) { $parts[1] } else { "main" }
      $url = if ($repo -match "://|^git@") { $repo } else { "https://github.com/$repo.git" }
    }
    Write-Host "Pointing '$Slot' ($d) at $url @ $ref"
    git config "submodule.$d.url" $url
    git submodule sync -- $d | Out-Null
    git submodule update --init -- $d 2>$null | Out-Null
    git -C $d fetch -q origin $ref
    git -C $d checkout -q FETCH_HEAD
    Write-Host "'$d' now at $(git -C $d rev-parse --short HEAD)"
  }
  default { Show-Usage }
}
