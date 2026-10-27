# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.7.1] - 2026-10-28

### Fixed

- Resolved conflicting intervals error in `nftables` by removing `VIRT_NET` (`10.192.0.0/10`) from `non_tor_nets` (as it is a subset of `10.0.0.0/8`).
- Added explicit TCP redirection for `VIRT_NET` before non-Tor network exemptions, ensuring `.onion` addresses route properly through Tor.

## [1.7.0] - 2026-10-26

### Added

- Native `nftables` support with dual-backend auto-detection, prioritizing `nftables` and falling back to legacy `iptables`.
- Dedicated `inet torsystem` table providing unified IPv4 and IPv6 leak protection, fail-closed kill switch, and clean atomic rule teardown.
- Persistent boot kill switch support for `nftables` via `torsystem-killswitch.service`.
- Manual firewall backend override via `TORSYSTEM_BACKEND` environment variable (`nftables` or `iptables`).

### Changed

- `status` and `check` commands now detect and display the active firewall backend, providing tailored diagnostics (`nft` or `iptables`).
- Prerequisites installation now includes `nftables` across `pacman`, `apt`, and `dnf`.
- Updated documentation and removed requirement for Arch Linux users to disable `nftables.service`.

## [1.6.1] - 2026-10-22

### Fixed

- Legacy firewall restore now actually reads the saved ruleset. Background jobs
  get `/dev/null` on stdin, so the old redirect made `iptables-restore` a
  silent no-op and left old rules behind after `stop`.
- Boot kill switch now fails closed: if the full IPv4 rule set cannot be
  restored, a minimal loopback-only `DROP` policy is applied instead. An IPv6
  failure no longer skips IPv4 protection.
- `status` without `sudo` reports `ACTIVE (unverified)` from the state file
  instead of a misleading `INACTIVE`.
- `wait_for_ports_listening` no longer produces a false negative from a
  `pipefail`/SIGPIPE interaction.

## [1.6.0] - 2026-10-19

### Added

- Persistent Tor kill switch: a systemd unit restores the firewall rules before
  networking starts on boot whenever routing was active.

### Changed

- Routing state and firewall backend are tracked on disk so the kill switch can
  recover after a reboot or an interrupted `start`.

## [1.5.1] - 2026-10-07

### Added

- `update` command to check GitHub for a newer release.

### Changed

- Improved Tor bootstrap detection and handling.

## [1.4.0] - 2026-10-05

### Added

- `about` command and a TUI About menu showing the installed version, with an
  update check.

## [1.3.2] - 2026-10-04

### Security

- Tor's control port now uses cookie authentication and listens only on
  `127.0.0.1`.

### Fixed

- Safer firewall snapshot handling: atomic temp files and restrictive
  permissions.

## [1.3.1] - 2026-10-04

### Changed

- Reworked firewall handling around dedicated `TORSYSTEM_OUT`, `TORSYSTEM_NAT`
  and `TORSYSTEM6_OUT` chains instead of restoring full firewall snapshots.
- Added ownership checks so the script refuses to touch conflicting chains.

## [1.3.0] - 2026-09-03

### Added

- IPv6 leak protection: all outbound IPv6 traffic is blocked while routing is
  active, with loopback exempted.

## [1.2.0] - 2026-08-29

### Added

- Advanced settings menu with exit-node country selection: a quick list, a
  custom two-letter country code, or any country.

### Fixed

- Reliability improvements and a fix for stray carriage returns (`^M`).

## [1.1.0] - 2026-08-27

### Added

- Interactive TUI built on `whiptail`/`dialog`.

## [1.0.0] - 2026-08-26

### Added

- Initial release: transparent system-wide TCP and DNS routing through Tor via
  `iptables`, with `install`, `start`, `stop`, `restart`, `status` and `check`
  commands, multi-distro package detection, and a built-in leak check.

[Unreleased]: https://github.com/amgpulse/torsystem/compare/v1.7.1...HEAD
[1.7.1]: https://github.com/amgpulse/torsystem/compare/v1.7.0...v1.7.1
[1.7.0]: https://github.com/amgpulse/torsystem/compare/v1.6.1...v1.7.0
[1.6.1]: https://github.com/amgpulse/torsystem/compare/v1.6.0...v1.6.1
[1.6.0]: https://github.com/amgpulse/torsystem/compare/v1.5.1...v1.6.0
[1.5.1]: https://github.com/amgpulse/torsystem/compare/v1.4.0...v1.5.1
[1.4.0]: https://github.com/amgpulse/torsystem/compare/v1.3.2...v1.4.0
[1.3.2]: https://github.com/amgpulse/torsystem/compare/v1.3.1...v1.3.2
[1.3.1]: https://github.com/amgpulse/torsystem/compare/v1.3.0...v1.3.1
[1.3.0]: https://github.com/amgpulse/torsystem/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/amgpulse/torsystem/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/amgpulse/torsystem/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/amgpulse/torsystem/releases/tag/v1.0.0
