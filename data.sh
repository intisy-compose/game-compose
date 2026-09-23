#!/usr/bin/env bash
# Swap a game-compose data slot to any data repo/branch, or restore the public default.
set -euo pipefail
cd "$(dirname "$0")"

declare -A SLOTS=( [mc]=mc_data [hytale]=hytale_data [ark-ase]=ark_ase_data [ark-asa]=ark_asa_data )

usage() {
  cat <<USAGE
Usage: ./data.sh <command>
  list                              show slots and their default (public template) source
  status                            show each slot's checked-out commit
  use <slot> [<owner/repo[@ref]>]   point a slot at a data repo and check it out
                                    (no source = restore the public template default)
Slots: ${!SLOTS[*]}
Examples:
  ./data.sh use mc intisy-compose/mc-server-data          # your private data
  ./data.sh use mc intisy-compose/mc-server-data@winter   # a specific branch
  ./data.sh use mc                                        # back to the public template
USAGE
}

case "${1:-}" in
  list)
    for s in "${!SLOTS[@]}"; do d=${SLOTS[$s]}
      printf '%-9s %-14s %s\n' "$s" "$d" "$(git config -f .gitmodules submodule."$d".url)"; done ;;
  status) git submodule status ;;
  use)
    s=${2:?slot required}; d=${SLOTS[$s]:?unknown slot}; src=${3:-}
    if [ -z "$src" ]; then url=$(git config -f .gitmodules submodule."$d".url); ref=main
    else repo=${src%@*}; ref=${src#*@}; [ "$ref" = "$src" ] && ref=main
      case "$repo" in *://*|git@*) url=$repo;; *) url="https://github.com/$repo.git";; esac; fi
    echo "Pointing '$s' ($d) at $url @ $ref"
    git config submodule."$d".url "$url"
    git submodule sync -- "$d" >/dev/null
    git submodule update --init -- "$d" >/dev/null 2>&1 || true
    git -C "$d" fetch -q origin "$ref"
    git -C "$d" checkout -q FETCH_HEAD
    echo "'$d' now at $(git -C "$d" rev-parse --short HEAD)" ;;
  *) usage ;;
esac
