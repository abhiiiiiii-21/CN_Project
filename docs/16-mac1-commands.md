# Mac 1 — DNS Command Guide

## Easiest way: the control panel

Double-click **`Mac1.command`** in the project folder, or run:

```bash
./scripts/mac1.sh
```

Press one key. When asked, type your Mac password (nothing shows while you type).

| Key | Action | One-line command |
|---|---|---|
| `d` | **Demo mode on**: build configs, start DNS, set this Mac's DNS, flush, check | `./scripts/mac1.sh demo` |
| `n` | **Normal mode**: automatic DNS on this Mac, stop DNS, flush | `./scripts/mac1.sh normal` |
| `1` | Start DNS | `./scripts/mac1.sh start` |
| `2` | Stop DNS | `./scripts/mac1.sh stop` |
| `3` | Restart DNS | `./scripts/mac1.sh restart` |
| `i` | Status: IP, DNS setting, both resolvers | `./scripts/mac1.sh status` |
| `l` | Live DNS log; `Ctrl-C` also closes the panel | `./scripts/mac1.sh logs` |
| `e` | Point `app` to the standby edge (Mac 3) | `./scripts/mac1.sh standby` |
| `p` | Point `app` back to the primary edge (Mac 2) | `./scripts/mac1.sh primary` |
| `f` | Flush this Mac's DNS cache | `./scripts/mac1.sh flush` |
| `t` | Run all checks | `./scripts/mac1.sh test` |
| `q` | Quit; DNS keeps running | |

The panel changes **this Mac only**. It cannot start, stop or change anything on the other Macs.

## Demo day: order for the whole team

1. All four Macs join the same Wi-Fi.
2. Check that the four IPs still match `~/cn-team.env`. If any changed, update the file on every Mac and run `./scripts/render-configs.sh` on each.
3. Mac 1: press `d`.
4. Mac 3: `python3 backend/server.py A 3001`
5. Mac 4: `python3 backend/server.py B 3002`
6. Mac 4: `./scripts/dns-ctl.sh backup start`
7. Mac 2: `./scripts/edge-apply.sh primary`
8. Client Macs: `sudo networksetup -setdnsservers Wi-Fi <MAC1_IP> <MAC4_IP>`
9. Mac 1: press `i`, then `t`. Run `t` after steps 4 to 7 are done.

## Going back to normal

1. Every other Mac whose DNS was changed:
   ```bash
   sudo networksetup -setdnsservers Wi-Fi empty
   ```
2. Mac 1: press `n`.
3. Mac 4 stops its backup DNS (`./scripts/dns-ctl.sh backup stop`) and backend. Mac 3 stops its backend. Mac 2 runs `./scripts/edge-apply.sh stop`.

A Mac left pointing at the team DNS can lose name lookups, including websites, once those servers are stopped or it changes Wi-Fi.

## Which key for which demonstration

| Demonstration | On Mac 1 |
|---|---|
| Extension A: primary fails | `2`, then after the client check `1` |
| Extension B: TTL and record change | `e`, observe on a client, then `p` |
| Extension E: edge cutover | `e`, later `p`. Mac 3 must run the standby edge first |

For A the clients use both resolvers. For B they use **Mac 1 only**. For E, either clients use Mac 1 only, or Mac 4 changes the backup record too:

```bash
./scripts/dns-ctl.sh backup point-app <MAC3_IP>
```

and back with `<MAC2_IP>`.

## Manual commands, without the panel

```bash
source ~/cn-team.env
./scripts/render-configs.sh
./scripts/dns-ctl.sh primary start
./scripts/dns-ctl.sh primary stop
./scripts/dns-ctl.sh primary restart
./scripts/dns-ctl.sh primary status
./scripts/dns-ctl.sh primary logs
./scripts/dns-ctl.sh primary point-app "$MAC3_IP"
./scripts/dns-ctl.sh primary point-app "$MAC2_IP"
sudo networksetup -setdnsservers Wi-Fi "$MAC1_IP" "$MAC4_IP"
sudo networksetup -setdnsservers Wi-Fi empty
networksetup -getdnsservers Wi-Fi
sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
dig app.team1.test @"$MAC1_IP"
dig app.team1.test @"$MAC4_IP"
dscacheutil -q host -a name app.team1.test
sudo lsof -nP -i :53
```

`dig` asks a server directly and skips the macOS cache. `dscacheutil` shows what the Mac itself resolves.
