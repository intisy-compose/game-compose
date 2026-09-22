# game-compose

A Docker stack for self-hosting several game servers (Minecraft, Hytale, ARK:
Survival Evolved, ARK: Survival Ascended) behind a single public tunnel, with each
server's data kept in its own **swappable data repo**.

## Servers

| slot | service | image |
| --- | --- | --- |
| `mc` | Minecraft (Java) | `itzg/minecraft-server` |
| `hytale` | Hytale (experimental) | `deinfreu/hytale-server` |
| `ark-ase` | ARK: Survival Evolved | `hermsi/ark-server` |
| `ark-asa` | ARK: Survival Ascended | `acekorneya/asa_server` |

All servers share one tunnel container so only the tunnel is exposed. Choose the
provider with `TUNNEL=playit` (default) or `TUNNEL=frp` in `config.env`.

## Quick start

Requires [Docker](https://docs.docker.com/get-docker/).

```bash
git clone --recursive https://github.com/intisy-compose/game-compose
cd game-compose
cp config.env.example config.env      # set TUNNEL + provider credentials

# start (Windows: docker-compose.ps1 / .bat, Linux/macOS: docker-compose.sh)
./docker-compose.sh
```

`--recursive` checks out the **public template** data for every slot, so the stack
runs immediately. Use `enter-console.sh` / `.bat` to attach to a server console.

## Data repos (swappable)

Each server's configuration lives in its own git repo mounted into the slot
directory (`mc_data`, `hytale_data`, `ark_ase_data`, `ark_asa_data`). The committed
default is a **public template** (`intisy-compose/<game>-server-data-template`) so a
fresh clone works and exposes nothing private. Keep your real servers in private
repos and switch on the go:

```bash
./data.sh list                                   # slots and their default source
./data.sh use mc intisy-compose/mc-server-data   # your private data
./data.sh use mc intisy-compose/mc-server-data@winter   # a specific branch
./data.sh use mc                                 # restore the public template
```

Maintain as many data repos or branches as you like and point a slot at whichever
you want to run. Worlds, saves and logs are gitignored in the data repos - commit
configuration, not runtime state. (`data.ps1` is the PowerShell equivalent.)

## Public exposure

`TUNNEL=frp` provisions an `frps` server on your VPS over SSH. Generate your own
SSH key into `vps/ssh-key` (gitignored) and set a matching `auth.token` in
`vps/frps.toml` and `FRP_TOKEN` in `config.env`. `TUNNEL=playit` uses a
[playit.gg](https://playit.gg/) agent instead (`PLAYIT_SECRET`).

## License

MIT - see [LICENSE](LICENSE).
