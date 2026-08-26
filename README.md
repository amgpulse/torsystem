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
- 🛡️ **Leak-proof by default** — a final `DROP` rule blocks anything that isn't routed through Tor instead of silently leaking it
- ⏳ **Bootstrap-aware** — waits for Tor to actually finish bootstrapping (polls `journalctl`) before flipping traffic over, instead of a blind sleep
- 🔄 **One-command identity rotation** — get a fresh exit IP with `restart`
- 🔍 **Built-in leak check** — verifies against `check.torproject.org` that you're really exiting through Tor
- 🐧 **Multi-distro** — auto-detects `pacman`, `apt`, or `dnf`
- ↩️ **Fully reversible** — `stop` restores your previous `iptables` rules exactly as they were
- 🎨 **Nice terminal UI** — ASCII banner, colors, spinners, and progress bars

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
| `check`   | Verify traffic is really passing through Tor                |

## ⚙️ How it works

1. `torrc` is configured with a `TransPort` (TCP) and `DNSPort` (DNS).
2. On `start`, the script waits for Tor to report `Bootstrapped 100%` and confirms `TransPort`/`DNSPort` are listening — *before* touching `iptables`.
3. `iptables` then redirects all outgoing DNS to `DNSPort` and all new TCP connections to `TransPort`.
4. Local/private networks (loopback, LAN ranges) are exempted so your local network keeps working.
5. A final `DROP` rule blocks anything that didn't match a Tor rule — this is what prevents leaks.
6. `stop` restores the exact `iptables` ruleset that existed right before `start` ran.

## ⚠️ Limitations

- **UDP** (other than DNS) isn't routed — Tor only carries TCP. UDP-only apps (some games, VoIP) will be **blocked**, not leaked.
- **IPv6** isn't handled in this version — disable it system-wide if it's active, or extend the script.
- Tor is great for browsing, not for torrenting/streaming/heavy downloads — it's slower than a regular VPN, and misusing it burdens the whole Tor network.
- Backups live in `/var/lib/torsystem` (`iptables`) and `/etc/tor/torrc.torsystem.bak` (original `torrc`).

## 🧩 Roadmap / extending this

All logic lives in isolated functions (`cmd_install`, `cmd_start`, `cmd_stop`, `cmd_restart`, `cmd_status`, `cmd_check`), so it's straightforward to:
- Wrap it in a GUI (Python/PyQt, GTK, etc.) via `subprocess` + `pkexec`
- Add IPv6 support
- Add per-app exclusion rules

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
