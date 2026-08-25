# Proton VPN for Omarchy

A bar widget for [Omarchy Quattro](https://omarchy.org) that puts Proton VPN in
your status bar: connection state at a glance, one-click connect and disconnect,
quick-connect by feature, and a country and city picker.

It drives the official `protonvpn` CLI. No API keys, no tokens, and no
credentials are stored by this plugin — sign-in happens in the CLI's own
interactive prompt, and Proton's client owns the session from there.

## Features

- **Live status in the bar** — the Proton mark takes your theme's foreground
  colour and reflects tunnel state, so it reads correctly in every Omarchy theme.
- **Click to toggle** — connect to the fastest server or disconnect.
- **Quick connect** — Fastest, Random, P2P, Secure Core, and Tor.
- **Country picker** — searchable list from `protonvpn countries list`.
- **City picker** — drill into a country for one row per city, showing that
  city's best server with its load and tier.
- **Detail panel** — server, location, account, plan, protocol, and load.
- **Interactive sign-in** — opens a floating terminal for username, password,
  and TOTP.

## Requirements

| Dependency | Where it comes from | Why |
| --- | --- | --- |
| Omarchy Quattro | — | Host shell (Quickshell) |
| `proton-vpn-cli` | Arch `extra` repo — `sudo pacman -S proton-vpn-cli` | Every VPN action |
| `python3` | Base system | Reads the client's cached server list |
| `nmcli` (NetworkManager) | Base system | Fast tunnel-state detection |
| `omarchy-launch-floating-terminal-with-presentation` | Omarchy | Interactive sign-in |

Install the CLI from the official repository, not the AUR:

```bash
sudo pacman -S proton-vpn-cli
```

## Install

```bash
omarchy plugin add https://github.com/grichard99/omarchy-protonvpn-plugin --enable
```

That clones the plugin into `~/.config/omarchy/plugins/` and enables it. If you
prefer to place it yourself, drop `--enable` and run:

```bash
omarchy plugin enable io.github.grichard99.protonvpn right
```

Then sign in — click the widget and follow the terminal prompt, or run:

```bash
protonvpn signin <YOUR_PROTON_USERNAME>
```

The CLI asks for your password and then a TOTP token. **The CLI supports TOTP
two-factor only**; if your account uses a FIDO2 security key, sign in once with
the Proton VPN GTK app instead — this widget reads the session the client
creates either way.

## Update

```bash
omarchy plugin update io.github.grichard99.protonvpn
```

## Remove

```bash
omarchy plugin remove io.github.grichard99.protonvpn
```

That disables the widget, removes it from your bar, and deletes the plugin
folder. It does not touch your Proton VPN session, settings, or any active
tunnel — disconnect and sign out from the widget or the CLI first if you want
those gone too:

```bash
protonvpn disconnect
protonvpn signout
```

## Settings

Configurable from Omarchy's widget settings:

| Setting | Default | Range |
| --- | --- | --- |
| Status refresh interval | 30s | 5–3600s |
| Link watch interval | 4s | 2–60s |

## Notes

**Choosing a protocol.** The protocol is not exposed by the CLI — `protonvpn
config set` doesn't offer it and `connect` has no `--protocol` flag. It lives in
`~/.config/Proton/VPN/settings.json`:

```json
{ "protocol": "wireguard" }
```

Valid values are `wireguard`, `openvpn-udp`, and `openvpn-tcp`. Reconnect after
changing it. `wireguard` is the fastest and the CLI warns about instability on
`openvpn-tcp`.

**How state is detected.** `protonvpn status` costs about a second of Python
start-up, which is far too slow to poll for a bar icon. The tunnel also appears
as an active NetworkManager connection named `ProtonVPN <server>` on device
`proton0`, which `nmcli` reports in around ten milliseconds. The widget polls
`nmcli` for the icon and only shells out to the CLI for the detail rows. Proton's
IPv6 leak guard (`pvpn-killswitch-ipv6`, on a dummy device) stays active
independently and is deliberately not counted as a live tunnel.

**Where the city list comes from.** The CLI has no server-list command
(`protonvpn servers` just prints a URL), but the Proton client caches the full
logical server list at `~/.cache/Proton/VPN/serverlist.json` and refreshes it on
every connect. `servers.py` reads that cache read-only and collapses it to one
row per city. If you've never connected, the cache won't exist yet and the city
list will be empty until you do.

## Security

This plugin runs unsandboxed inside the Omarchy shell process, like every
Omarchy plugin. It:

- stores no credentials, tokens, or account data
- makes no network requests of its own
- writes nothing outside its own folder, and reads Proton's cache read-only
- shells out only to `protonvpn`, `nmcli`, `python3`, and Omarchy's own
  terminal launcher
- never uses `sudo` and never downloads or executes remote code

Sign-in credentials go straight to the `protonvpn` CLI's own prompt in a
terminal; this plugin never sees them.

## Credits

The Proton VPN mark is drawn from the [Simple Icons](https://simpleicons.org)
path (CC0) and recoloured to the active theme, so it isn't a scaled bitmap.
Proton and Proton VPN are trademarks of Proton AG. This is an unofficial
community plugin and is not affiliated with or endorsed by Proton AG.

## License

[MIT](LICENSE)
