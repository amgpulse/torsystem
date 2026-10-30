<div align="center">

```
████████╗ ██████╗ ██████╗ ███████╗██╗   ██╗███████╗████████╗███████╗███╗   ███╗
╚══██╔══╝██╔═══██╗██╔══██╗██╔════╝╚██╗ ██╔╝██╔════╝╚══██╔══╝██╔════╝████╗ ████║
   ██║   ██║   ██║██████╔╝███████╗ ╚████╔╝ ███████╗   ██║   █████╗  ██╔████╔██║
   ██║   ██║   ██║██╔══██╗╚════██║  ╚██╔╝  ╚════██║   ██║   ██╔══╝  ██║╚██╔╝██║
   ██║   ╚██████╔╝██║  ██║███████║   ██║   ███████║   ██║   ███████╗██║ ╚═╝ ██║
   ╚═╝    ╚═════╝ ╚═╝  ╚═╝╚══════╝   ╚═╝   ╚══════╝   ╚═╝   ╚══════╝╚═╝     ╚═╝
```

### Route your entire Linux system through Tor — transparently, like a VPN.

[![Shell](https://img.shields.io/badge/shell-bash-1f425f.svg)](https://www.gnu.org/software/bash/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Linux-blue)](#requirements)
[![Made with Tor](https://img.shields.io/badge/powered%20by-Tor-7D4698?logo=torproject&logoColor=white)](https://www.torproject.org/)
[![Changelog](https://img.shields.io/github/v/release/amgpulse/torsystem?label=changelog&sort=semver&color=blue)](CHANGELOG.md)

</div>


---

**torsystem** is a single-file CLI tool that transparently redirects **all** outgoing TCP and DNS traffic on your machine through the [Tor network](https://www.torproject.org/), the same way a VPN would — no per-app configuration, no `torify`, no `proxychains`. Just `start` and every connection on the system goes through Tor.

## ✨ Features

- 🧅 **System-wide routing** — all TCP + DNS traffic transparently redirected through Tor via `nftables` or `iptables`
- 🛡️ **Leak-proof by default** — a final `DROP` rule blocks anything that isn't routed through Tor instead of silently leaking it, and all IPv6 traffic is blocked outright (Tor only carries IPv4 here)
- 🔒 **Persistent kill switch** — the firewall is restored before networking on boot and stays fail-closed if Tor stops; only `stop` removes it
- ⏳ **Bootstrap-aware** — checks Tor's authenticated ControlPort for bootstrap progress, with `journalctl` as a fallback, before enabling routing
- 🔄 **One-command identity rotation** — get a fresh exit IP with `restart`
- 🔍 **Built-in leak check** — verifies against `check.torproject.org` that you're really exiting through Tor
- 🐧 **Multi-distro** — auto-detects `pacman`, `apt`, or `dnf`
- ↩️ **Reversible** — `stop` removes torsystem's rules and restores normal networking
- 🎨 **Nice terminal UI** — ASCII banner, colors, spinners, and progress bars
- 🖥️ **Optional menu-driven TUI** — `torsystem.sh tui` gives you a `whiptail`-based point-and-click menu, no flags to remember
- 🌍 **Exit node country selection** — pick a preferred exit country from a quick list or enter a custom code, right from the TUI's Advanced Settings

## 📦 Requirements

- Linux with `sudo` and `systemd`
- One of: `pacman` (Arch), `apt` (Debian/Ubuntu/Kali/Parrot), `dnf` (Fedora)
- `python3` (used for Tor ControlPort communication)

> **Firewall compatibility:** `torsystem` natively supports both modern `nftables` and legacy `iptables`. When `nft` is present, it creates an isolated `inet torsystem` table that works cleanly alongside existing firewall setups (including `nftables.service` on Arch/Fedora) without conflicts.

## 🚀 Installation

```bash
git clone https://github.com/amgpulse/torsystem.git
cd torsystem
chmod +x torsystem.sh
sudo ./torsystem.sh install
```

This installs `tor`, `nftables`, `iptables`, `curl`, `iproute2`, and `python3`, and appends the required config to `/etc/tor/torrc` (your original `torrc` is backed up first, automatically). It also configures the local ControlPort at `127.0.0.1:9051` with cookie authentication.
It also installs `torsystem` under `/usr/local/sbin` and enables a systemd unit that restores the kill switch before the network starts. Re-run `install` after replacing the script to update that boot-time copy.

## 🕹️ Usage

```bash
sudo ./torsystem.sh start     # enable system-wide routing through Tor
sudo ./torsystem.sh status    # show current status + exit IP
sudo ./torsystem.sh check     # verify traffic is really exiting through Tor
sudo ./torsystem.sh restart   # rotate to a new Tor identity / exit IP
sudo ./torsystem.sh stop      # restore normal networking
sudo ./torsystem.sh about     # show torsystem version
sudo ./torsystem.sh update    # check for a newer version (does not install it)
```

| Command   | Description                                              |
|-----------|-----------------------------------------------------------|
| `install` | Install prerequisites and configure `torrc`                |
| `start`   | Enable transparent routing through Tor                     |
| `stop`    | Restore normal networking                                   |
| `restart` | Request a new Tor identity (new exit IP)                    |
| `status`  | Show current status and exit IP                             |
| `tui`     | Launch an interactive menu (whiptail/dialog)                 |
| `check`   | Verify traffic is really passing through Tor                |
| `about`   | Show the installed torsystem version                         |
| `update`  | Check whether a newer version is available; does not install it |

## 🖥️ Interactive TUI (optional)

Prefer menus over remembering flags? Run the built-in terminal UI instead — no extra files, it's the same script:

```bash
sudo ./torsystem.sh tui
```

This launches a `whiptail`/`dialog`-based menu (works over SSH too, no GUI needed) with six main actions — Install, Start, Stop, Restart, Status, Check — plus **Advanced settings** and **About / version**, presented as a simple list you navigate with arrow keys.

> Requires `whiptail` (preinstalled on most Debian/Ubuntu systems) or `dialog` (Arch/Fedora):
> ```bash
> sudo apt install whiptail     # Debian/Ubuntu
> sudo pacman -S dialog         # Arch
> sudo dnf install dialog       # Fedora
> ```

### Advanced Settings — exit node country

From the TUI's main menu, choose **Advanced settings** to pick a preferred exit country:

- Quick list: Germany, Netherlands, United States, United Kingdom, France, Sweden, Switzerland
- **Custom code**: enter any 2-letter ISO country code (e.g. `JP`, `CA`)
- **Any country**: clears the restriction and goes back to the default (any exit relay)

Picking a country updates `torrc` (`ExitNodes {XX}` + `StrictNodes 1`), restarts Tor, and waits for it to re-bootstrap before returning you to the menu. Note: restricting to one country means fewer available relays, so circuits may take a little longer to build.

## ⚙️ How it works

1. `torrc` is configured with a `TransPort` (TCP) and `DNSPort` (DNS).
2. On `start`, the script waits for Tor to report `Bootstrapped 100%` and confirms `TransPort`/`DNSPort` are listening — *before* touching the firewall.
3. By default, `nftables` is used when available, with an isolated `inet torsystem` table. Otherwise, `iptables` is used with `TORSYSTEM_*` chains. Set `TORSYSTEM_BACKEND` to override the backend.
4. Local/private networks (loopback, LAN ranges) are exempted so your local network keeps working. DNS is always redirected to Tor, even when the configured resolver is on the local network.
5. A final `DROP` rule blocks traffic that did not match a Tor rule. Traffic owned by the `tor` user is exempt so Tor can make its outbound connections (including to bridges).
6. The enabled `torsystem-killswitch.service` reapplies these rules before networking on boot whenever routing was active. Existing connections are not exempted, so they cannot continue outside Tor. If the full rule set cannot be restored, it falls back to a fail-closed `DROP` (loopback only) instead of letting traffic leak; run `stop` to recover.
7. `stop` removes torsystem's firewall rules and explicitly unlocks normal networking. Private/LAN IPv4 ranges remain exempt while routing is active.

## ⚠️ Limitations

- **`check.torproject.org` may be blocked** on some networks/ISPs (it's a known Tor-related domain). `status` and `check` now retry with a longer timeout and fall back to a plain IP lookup if it's unreachable — but that fallback can't confirm you're actually exiting through Tor, only that traffic is going out. If you're on such a network, treat a fallback result with caution and check `journalctl -u tor` for real bootstrap status.

- **UDP** (other than DNS) isn't routed — Tor only carries TCP. UDP-only apps (some games, VoIP) will be **blocked**, not leaked.
- **IPv6 is blocked outright** while routing is active, since Tor only carries IPv4 traffic here. This is intentional and fail-safe: rather than risk an IPv6 leak, any IPv6 traffic is dropped. If an app absolutely needs IPv6, it won't work while routing is on — that's by design.
- Tor is great for browsing, not for torrenting/streaming/heavy downloads — it's slower than a regular VPN, and misusing it burdens the whole Tor network.
- Firewall snapshots for `iptables`, `ip6tables`, and `nftables` live in `/var/lib/torsystem`; they are only used to recover setups from older versions. `stop` removes only torsystem's own rules. The original `torrc` backup is at `/etc/tor/torrc.torsystem.bak`.

## 🧩 Roadmap / extending this

All logic lives in isolated functions (`cmd_install`, `cmd_start`, `cmd_stop`, `cmd_restart`, `cmd_status`, `cmd_check`, `cmd_boot_lock`, `cmd_update`, `cmd_tui`), so it's straightforward to:
- Wrap it in a GUI (Python/PyQt, GTK, etc.) via `subprocess` + `pkexec`
- Add per-app exclusion rules
- Add Tor bridge support for censored networks

Contributions and PRs are welcome.

## 📝 Changelog

See [CHANGELOG.md](CHANGELOG.md) for the full release history.

## 🤝 Contributing

1. Fork the repo
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Commit your changes
4. Open a PR

## 📜 License

MIT — see [LICENSE](LICENSE).

## ⚖️ Disclaimer

This tool is provided for legitimate privacy and anonymity purposes. You are responsible for complying with the laws and terms of service applicable in your jurisdiction and network. The authors are not responsible for misuse.
---

<div align="center">

**Made it because I wanted it to exist.**

If it saves you the same headaches it saved me, that's enough.

Feedback, issues, and PRs are genuinely welcome.

</div>