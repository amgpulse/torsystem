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

</div>


---

**torsystem** is a single-file CLI tool that transparently redirects **all** outgoing TCP and DNS traffic on your machine through the [Tor network](https://www.torproject.org/), the same way a VPN would — no per-app configuration, no `torify`, no `proxychains`. Just `start` and every connection on the system goes through Tor.

## ✨ Features

- 🧅 **System-wide routing** — all TCP + DNS traffic transparently redirected through Tor via `iptables`
- 🛡️ **Leak-proof by default** — a final `DROP` rule blocks anything that isn't routed through Tor instead of silently leaking it, and all IPv6 traffic is blocked outright (Tor only carries IPv4 here)
- ⏳ **Bootstrap-aware** — checks Tor's authenticated ControlPort for bootstrap progress, with `journalctl` as a fallback, before enabling routing
- 🔄 **One-command identity rotation** — get a fresh exit IP with `restart`
- 🔍 **Built-in leak check** — verifies against `check.torproject.org` that you're really exiting through Tor
- 🐧 **Multi-distro** — auto-detects `pacman`, `apt`, or `dnf`
- ↩️ **Fully reversible** — `stop` restores your previous `iptables` rules exactly as they were
- 🎨 **Nice terminal UI** — ASCII banner, colors, spinners, and progress bars
- 🖥️ **Optional menu-driven TUI** — `torsystem.sh tui` gives you a `whiptail`-based point-and-click menu, no flags to remember
- 🌍 **Exit node country selection** — pick a preferred exit country from a quick list or enter a custom code, right from the TUI's Advanced Settings

## 📦 Requirements

- Linux with `sudo` and `systemd`
- One of: `pacman` (Arch), `apt` (Debian/Ubuntu/Kali/Parrot), `dnf` (Fedora)

> **Arch users:** if `nftables.service` is active and conflicts with the legacy `iptables` rules this script uses, stop it first:
> ```bash
> sudo systemctl stop nftables.service
> ```

## 🚀 Installation

```bash
git clone https://github.com/amgpulse/torsystem.git
cd torsystem
chmod +x torsystem.sh
sudo ./torsystem.sh install
```

This installs `tor`, `iptables`, `curl`, and `iproute2`, and appends the required config to `/etc/tor/torrc` (your original `torrc` is backed up first, automatically).

## 🕹️ Usage

```bash
sudo ./torsystem.sh start     # enable system-wide routing through Tor
sudo ./torsystem.sh status    # show current status + exit IP
sudo ./torsystem.sh check     # verify traffic is really exiting through Tor
sudo ./torsystem.sh restart   # rotate to a new Tor identity / exit IP
sudo ./torsystem.sh stop      # restore normal networking
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

## 🖥️ Interactive TUI (optional)

Prefer menus over remembering flags? Run the built-in terminal UI instead — no extra files, it's the same script:

```bash
sudo ./torsystem.sh tui
```

This launches a `whiptail`/`dialog`-based menu (works over SSH too, no GUI needed) with the same actions — Install, Start, Stop, Restart, Status, Check — presented as a simple list you navigate with arrow keys.

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
2. On `start`, the script waits for Tor to report `Bootstrapped 100%` and confirms `TransPort`/`DNSPort` are listening — *before* touching `iptables`.
3. `iptables` then redirects all outgoing DNS to `DNSPort` and all new TCP connections to `TransPort`.
4. Local/private networks (loopback, LAN ranges) are exempted so your local network keeps working.
5. A final `DROP` rule blocks anything that didn't match a Tor rule — this is what prevents leaks.
6. `stop` restores the exact `iptables` ruleset that existed right before `start` ran.

## ⚠️ Limitations

- **`check.torproject.org` may be blocked** on some networks/ISPs (it's a known Tor-related domain). `status` and `check` now retry with a longer timeout and fall back to a plain IP lookup if it's unreachable — but that fallback can't confirm you're actually exiting through Tor, only that traffic is going out. If you're on such a network, treat a fallback result with caution and check `journalctl -u tor` for real bootstrap status.

- **UDP** (other than DNS) isn't routed — Tor only carries TCP. UDP-only apps (some games, VoIP) will be **blocked**, not leaked.
- **IPv6 is blocked outright** while routing is active, since Tor only carries IPv4 traffic here. This is intentional and fail-safe: rather than risk an IPv6 leak, any IPv6 traffic is dropped. If an app absolutely needs IPv6, it won't work while routing is on — that's by design.
- Tor is great for browsing, not for torrenting/streaming/heavy downloads — it's slower than a regular VPN, and misusing it burdens the whole Tor network.
- Backups live in `/var/lib/torsystem` (`iptables` + `ip6tables`) and `/etc/tor/torrc.torsystem.bak` (original `torrc`).

## 🧩 Roadmap / extending this

All logic lives in isolated functions (`cmd_install`, `cmd_start`, `cmd_stop`, `cmd_restart`, `cmd_status`, `cmd_check`), so it's straightforward to:
- Wrap it in a GUI (Python/PyQt, GTK, etc.) via `subprocess` + `pkexec`
- Add per-app exclusion rules
- Add Tor bridge support for censored networks

Contributions and PRs are welcome.

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