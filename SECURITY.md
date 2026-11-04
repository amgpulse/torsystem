# Security Policy

## Supported Versions

We take the security and anonymity of our users extremely seriously. Because `torsystem` operates at the root level and controls the entire system's network stack, any vulnerability could lead to catastrophic IP leaks.

Currently, the following versions are actively supported with security updates:

| Version | Supported          |
| ------- | ------------------ |
| 1.8.x   | :white_check_mark: |
| 1.7.x   | :white_check_mark: |
| < 1.7   | :x:                |

## Threat Model & Security Architecture

`torsystem` is designed with a strict **fail-closed** philosophy: *if the system cannot guarantee traffic is routed through Tor, it drops the traffic.* We specifically focus on preventing the following threat vectors:

1. **Dual-Backend Integrity (`nftables` & `iptables`):** We natively support `nftables` (prioritized) and legacy `iptables`. Both backends use isolated tables/chains with strict ownership checks to prevent conflicts with other system firewalls.
2. **Boot Kill-Switch (Fail-Closed):** A dedicated systemd unit restores firewall rules before networking starts. If the full rule set cannot be restored on boot, a minimal loopback-only `DROP` policy is applied to prevent unencrypted fallback.
3. **IPv6 & DNS Leaks:** Tor in this setup only routes IPv4. We implement strict `ip6tables`/`nftables` rules to drop all outbound IPv6 traffic. DNS requests are forcefully redirected to Tor's `DNSPort`.
4. **Race Conditions:** Applying firewall rules before Tor is fully bootstrapped is a critical flaw. We poll `journalctl` and wait for `Bootstrapped 100%` before touching the firewall.
5. **Local Control Security:** Tor's control port is restricted to `127.0.0.1` and uses cookie authentication to prevent unauthorized identity rotation or local hijacking.
6. **State & Snapshot Atomicity:** Firewall snapshots and routing states use atomic temp files with restrictive permissions to prevent tampering or corruption during interrupted operations.

## Reporting a Vulnerability

**Please do not report security vulnerabilities through public GitHub issues.**

If you discover a potential security flaw (e.g., a leak scenario, a fail-open state in the kill-switch, or a logic error in the Bash script), please report it privately:

*   **Contact:** Open a [Private Security Advisory](https://github.com/amgpulse/torsystem/security/advisories/new) on GitHub.
*   **What to include:** A detailed description of the vulnerability, steps to reproduce, and your system environment (Distro, Kernel version, Tor version, and Firewall backend).

I will acknowledge your report within **48 hours** and work with you to patch the issue. Once resolved, we will publish a security advisory and credit you for the discovery (unless you prefer to remain anonymous).

## Automated Security Audits & Codex

As the maintainer, I believe in continuous verification. This project is actively seeking integration with automated security review tools (such as OpenAI's Codex Security) to:
*   Statically analyze the complex `nftables` and `iptables` rule generation logic.
*   Audit Bash edge-cases, variable expansions, and `pipefail` interactions for potential logic errors.
*   Verify the atomicity of the boot kill-switch and snapshot restore functions.

## Disclaimer

This tool is provided for legitimate privacy purposes. The maintainer is not responsible for misuse, nor can they guarantee absolute anonymity against a global, active adversary (e.g., targeted traffic correlation attacks by nation-states). Always verify your traffic with the built-in `check` command.
