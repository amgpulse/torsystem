#!/usr/bin/env bash
#
# torsystem.sh — Route TCP and DNS traffic through the Tor network
#
# Usage:
#   sudo ./torsystem.sh install     Install prerequisites and configure Tor
#   sudo ./torsystem.sh start       Enable transparent routing through Tor
#   sudo ./torsystem.sh stop        Restore normal networking
#   sudo ./torsystem.sh restart     Request a new Tor identity (new exit IP)
#   sudo ./torsystem.sh status      Show current status and exit IP
#   sudo ./torsystem.sh check       Test for DNS/IP leaks
#
set -euo pipefail

# ---------- Colors & style ----------
if [[ -t 1 ]]; then
    C_RESET=$'\033[0m'
    C_BOLD=$'\033[1m'
    C_DIM=$'\033[2m'
    C_GREEN=$'\033[38;5;42m'
    C_RED=$'\033[38;5;196m'
    C_YELLOW=$'\033[38;5;220m'
    C_PURPLE=$'\033[38;5;135m'
    C_CYAN=$'\033[38;5;51m'
    C_GRAY=$'\033[38;5;244m'
else
    C_RESET=""; C_BOLD=""; C_DIM=""; C_GREEN=""; C_RED=""; C_YELLOW=""; C_PURPLE=""; C_CYAN=""; C_GRAY=""
fi

# ---------- Config ----------
detect_tor_uid() {
    for u in debian-tor tor _tor toranon; do
        if id -u "$u" >/dev/null 2>&1; then
            id -u "$u"
            return 0
        fi
    done
    echo 100  # fallback
}
TOR_UID="$(detect_tor_uid)"
TRANS_PORT=9040
DNS_PORT=5353
VIRT_NET="10.192.0.0/10"
NON_TOR_NETS=("127.0.0.0/8" "10.0.0.0/8" "172.16.0.0/12" "192.168.0.0/16" "$VIRT_NET")

TORRC_PATH="/etc/tor/torrc"
TORRC_BACKUP="/etc/tor/torrc.torsystem.bak"
IPTABLES_SAVE_PATH="/var/lib/torsystem/iptables.rules.bak"
IP6TABLES_SAVE_PATH="/var/lib/torsystem/ip6tables.rules.bak"
STATE_DIR="/var/lib/torsystem"
STATE_FILE="$STATE_DIR/state"
BACKEND_FILE="$STATE_DIR/firewall-backend"
IPTABLES_CHAIN="TORSYSTEM_OUT"
NAT_CHAIN="TORSYSTEM_NAT"
IP6TABLES_CHAIN="TORSYSTEM6_OUT"

# ---------- Banner ----------
print_banner() {
    echo -e "${C_PURPLE}${C_BOLD}"
    cat <<'EOF'
  _______            _____           _
 |__   __|          / ____|         | |
    | | ___  _ __  | (___  _   _ ___| |_ ___ _ __ ___
    | |/ _ \| '__|  \___ \| | | / __| __/ _ \ '_ ` _ \
    | | (_) | |      ____) | |_| \__ \ ||  __/ | | | | |
    |_|\___/|_|     |_____/ \__, |___/\__\___|_| |_| |_|
                              __/ |
                             |___/
EOF
    echo -e "${C_RESET}${C_GRAY}         route TCP and DNS traffic through Tor${C_RESET}"
    echo ""
}

# ---------- Helpers ----------
log()   { echo -e "  ${C_CYAN}●${C_RESET} $*"; }
ok()    { echo -e "  ${C_GREEN}✔${C_RESET} $*"; }
warn()  { echo -e "  ${C_YELLOW}⚠${C_RESET} $*"; }
err()   { echo -e "  ${C_RED}✘${C_RESET} $*" >&2; }
die()   { err "$*"; exit 1; }

require_root() {
    [[ $EUID -eq 0 ]] || die "This script must be run with sudo/root."
}

require_cmds() {
    local missing=()
    for c in "$@"; do
        command -v "$c" >/dev/null 2>&1 || missing+=("$c")
    done
    if (( ${#missing[@]} > 0 )); then
        die "Missing tools: ${missing[*]} — run 'install' first."
    fi
}

ensure_state_dir() {
    mkdir -p "$STATE_DIR"
}

is_active() {
    [[ -f "$STATE_FILE" ]] &&
        [[ "$(cat "$STATE_FILE")" == "active" ]] || return 1
    if [[ -f "$BACKEND_FILE" ]] && [[ "$(cat "$BACKEND_FILE")" == "chains" ]]; then
        command -v iptables >/dev/null 2>&1 || return 1
        iptables -C OUTPUT -j "$IPTABLES_CHAIN" >/dev/null 2>&1 || return 1
        iptables -t nat -C OUTPUT -j "$NAT_CHAIN" >/dev/null 2>&1 || return 1
        if command -v ip6tables >/dev/null 2>&1; then
            ip6tables -C OUTPUT -j "$IP6TABLES_CHAIN" >/dev/null 2>&1 || return 1
        fi
        return 0
    else
        return 0
    fi
}

detect_pkg_manager() {
    if command -v pacman >/dev/null 2>&1; then
        echo "pacman"
    elif command -v apt-get >/dev/null 2>&1; then
        echo "apt"
    elif command -v dnf >/dev/null 2>&1; then
        echo "dnf"
    else
        die "No supported package manager found (pacman/apt/dnf)."
    fi
}

# ---------- Spinner animation ----------
# spinner_run "Message" -- command args...
spinner_run() {
    local msg="$1"; shift
    if [[ "$1" == "--" ]]; then shift; fi

    local frames=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
    local logfile
    logfile="$(mktemp)"

    ("$@" >"$logfile" 2>&1) &
    local pid=$!

    local i=0
    if [[ -t 1 ]]; then
        while kill -0 "$pid" 2>/dev/null; do
            printf "\r  ${C_CYAN}%s${C_RESET} %s" "${frames[$((i % ${#frames[@]}))]}" "$msg"
            i=$((i + 1))
            sleep 0.08
        done
    fi

    local status=0
    if wait "$pid"; then
        status=0
    else
        status=$?
    fi

    local cr=""
    [[ -t 1 ]] && cr="\r"

    if [[ $status -eq 0 ]]; then
        printf "${cr}  ${C_GREEN}✔${C_RESET} %s\n" "$msg"
    else
        printf "${cr}  ${C_RED}✘${C_RESET} %s\n" "$msg"
        echo -e "${C_GRAY}"
        sed 's/^/      /' "$logfile"
        echo -e "${C_RESET}"
    fi
    rm -f "$logfile"
    return $status
}

# wait_for_tor_bootstrap [timeout_seconds]
# Polls journalctl for "Bootstrapped 100%" instead of a fixed sleep.
# Routing is not enabled unless Tor finishes bootstrapping.
wait_for_tor_bootstrap() {
    local timeout="${1:-60}"
    local waited=0
    local frames=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
    local i=0
    local pct=""

    while (( waited < timeout )); do
        pct=$(journalctl -u tor --no-pager -n 40 2>/dev/null |
            grep -oP 'Bootstrapped \K[0-9]+(?=%)' | tail -1 || true)
        if [[ "$pct" == "100" ]]; then
            if [[ -t 1 ]]; then printf "\r  ${C_GREEN}✔${C_RESET} Tor bootstrap complete (100%%)               \n"; fi
            return 0
        fi
        if [[ -t 1 ]]; then
            printf "\r  ${C_CYAN}%s${C_RESET} Waiting for Tor to bootstrap%s   " \
                "${frames[$((i % ${#frames[@]}))]}" "${pct:+ ($pct%)}"
        fi
        i=$((i + 1))
        sleep 1
        waited=$((waited + 1))
    done

    echo ""
    warn "Tor did not report 100% bootstrap within ${timeout}s."
    warn "Check: ${C_DIM}journalctl -u tor -n 50${C_RESET}"
    return 1
}

# wait_for_ports_listening — make sure TransPort/DNSPort are actually up
# before we redirect all system traffic into them.
wait_for_ports_listening() {
    local retries=10
    while (( retries > 0 )); do
        if ss -tln 2>/dev/null | grep -q ":${TRANS_PORT} " \
           && ss -uln 2>/dev/null | grep -q ":${DNS_PORT} "; then
            return 0
        fi
        sleep 1
        retries=$((retries - 1))
    done
    warn "TransPort (${TRANS_PORT}) or DNSPort (${DNS_PORT}) not detected as listening; routing cannot be enabled."
    warn "Routing may fail. Check: ${C_DIM}ss -tlnp | grep -E '${TRANS_PORT}|${DNS_PORT}'${C_RESET}"
    return 1
}

# progress_bar "Message" seconds
progress_bar() {
    local msg="$1"
    local duration="${2:-2}"
    local width=28
    local steps=30
    local sleep_time
    sleep_time=$(awk -v d="$duration" -v s="$steps" 'BEGIN { print d / s }')

    if [[ ! -t 1 ]]; then
        sleep "$duration"
        return
    fi

    for ((i = 0; i <= steps; i++)); do
        local filled=$((i * width / steps))
        local empty=$((width - filled))
        local bar
        bar="$(printf "%${filled}s" | tr ' ' '#')$(printf "%${empty}s" | tr ' ' '-')"
        printf "\r  ${C_PURPLE}%s${C_RESET} [${C_CYAN}%s${C_RESET}] %d%%" "$msg" "$bar" $((i * 100 / steps))
        sleep "$sleep_time"
    done
    echo ""
}

# ---------- Install ----------
cmd_install() {
    require_root
    print_banner
    local pm
    pm="$(detect_pkg_manager)"
    log "Detected package manager: ${C_BOLD}$pm${C_RESET}"

    case "$pm" in
        pacman)
            spinner_run "Syncing package databases" -- pacman -Sy --noconfirm
            spinner_run "Installing tor, iptables, curl, iproute2" -- pacman -S --noconfirm --needed tor iptables curl iproute2
            ;;
        apt)
            spinner_run "Updating package lists" -- apt-get update -qq
            spinner_run "Installing tor, iptables, curl, iproute2" -- apt-get install -y tor iptables curl iproute2
            ;;
        dnf)
            spinner_run "Installing tor, iptables, curl, iproute" -- dnf install -y tor iptables curl iproute
            ;;
    esac

    ensure_state_dir

    if [[ ! -f "$TORRC_BACKUP" ]]; then
        cp "$TORRC_PATH" "$TORRC_BACKUP"
        ok "Backed up original torrc to ${C_DIM}$TORRC_BACKUP${C_RESET}"
    fi

    if ! grep -q "## torsystem-managed" "$TORRC_PATH" 2>/dev/null; then
        cat >> "$TORRC_PATH" <<EOF

## torsystem-managed — added by torsystem.sh
VirtualAddrNetwork $VIRT_NET
AutomapHostsOnResolve 1
TransPort $TRANS_PORT
DNSPort $DNS_PORT
SocksPort 9050
EOF
        ok "Applied required settings to $TORRC_PATH"
    else
        log "torrc settings already present, skipping."
    fi

    if ! systemctl enable tor >/dev/null 2>&1; then
        warn "Could not enable Tor at boot; you may need to enable the tor service manually."
    fi
    echo ""
    ok "${C_BOLD}Installation complete.${C_RESET} Run '${C_CYAN}start${C_RESET}' to go live."
}

# ---------- IPv6 leak protection ----------
# Tor only routes IPv4 in this setup; if IPv6 is enabled on the system it
# could bypass Tor entirely. Fail-safe approach: block ALL outbound IPv6
# traffic while routing is active, rather than trying to route it (which
# Tor doesn't support here). No IPv6 = no IPv6 leak.
block_ipv6_leaks() {
    if ! command -v ip6tables >/dev/null 2>&1; then
        warn "ip6tables not found — cannot block IPv6. If this system has IPv6 enabled, it may bypass Tor."
        return 0
    fi

    log "Blocking outbound IPv6 traffic (Tor routing here supports IPv4 only)..."
    ip6tables -N "$IP6TABLES_CHAIN" || return 1
    ip6tables -A "$IP6TABLES_CHAIN" -o lo -j ACCEPT || return 1
    ip6tables -A "$IP6TABLES_CHAIN" -j DROP || return 1
    ip6tables -C OUTPUT -j "$IP6TABLES_CHAIN" 2>/dev/null ||
        ip6tables -I OUTPUT 1 -j "$IP6TABLES_CHAIN" || return 1
}

restore_ipv6() {
    if ! command -v ip6tables >/dev/null 2>&1; then
        return 0
    fi

    while ip6tables -C OUTPUT -j "$IP6TABLES_CHAIN" >/dev/null 2>&1; do
        ip6tables -D OUTPUT -j "$IP6TABLES_CHAIN" || return 1
    done
    if ip6tables -S "$IP6TABLES_CHAIN" >/dev/null 2>&1; then
        ip6tables -F "$IP6TABLES_CHAIN" || return 1
        ip6tables -X "$IP6TABLES_CHAIN" || return 1
    fi
}

apply_iptables_rules() {
    iptables -t nat -N "$NAT_CHAIN" || return 1
    iptables -N "$IPTABLES_CHAIN" || return 1

    iptables -t nat -A "$NAT_CHAIN" -m owner --uid-owner "$TOR_UID" -j RETURN || return 1
    iptables -t nat -A "$NAT_CHAIN" -p udp --dport 53 -j REDIRECT --to-ports "$DNS_PORT" || return 1
    iptables -t nat -A "$NAT_CHAIN" -p tcp --dport 53 -j REDIRECT --to-ports "$DNS_PORT" || return 1
    for net in "${NON_TOR_NETS[@]}"; do
        iptables -t nat -A "$NAT_CHAIN" -d "$net" -j RETURN || return 1
    done
    iptables -t nat -A "$NAT_CHAIN" -p tcp --syn -j REDIRECT --to-ports "$TRANS_PORT" || return 1

    iptables -A "$IPTABLES_CHAIN" -m state --state ESTABLISHED,RELATED -j ACCEPT || return 1
    iptables -A "$IPTABLES_CHAIN" -o lo -j ACCEPT || return 1
    for net in "${NON_TOR_NETS[@]}"; do
        iptables -A "$IPTABLES_CHAIN" -d "$net" -j ACCEPT || return 1
    done
    iptables -A "$IPTABLES_CHAIN" -m owner --uid-owner "$TOR_UID" -j ACCEPT || return 1
    iptables -A "$IPTABLES_CHAIN" -p tcp --syn -j ACCEPT || return 1
    iptables -A "$IPTABLES_CHAIN" -j DROP || return 1

    iptables -t nat -C OUTPUT -j "$NAT_CHAIN" 2>/dev/null ||
        iptables -t nat -I OUTPUT 1 -j "$NAT_CHAIN" || return 1
    iptables -C OUTPUT -j "$IPTABLES_CHAIN" 2>/dev/null ||
        iptables -I OUTPUT 1 -j "$IPTABLES_CHAIN" || return 1
}

remove_iptables_rules() {
    local failed=0
    local chain table
    while iptables -C OUTPUT -j "$IPTABLES_CHAIN" >/dev/null 2>&1; do
        iptables -D OUTPUT -j "$IPTABLES_CHAIN" || return 1
    done
    while iptables -t nat -C OUTPUT -j "$NAT_CHAIN" >/dev/null 2>&1; do
        iptables -t nat -D OUTPUT -j "$NAT_CHAIN" || return 1
    done
    for chain in "$IPTABLES_CHAIN" "$NAT_CHAIN"; do
        table="filter"
        [[ "$chain" == "$NAT_CHAIN" ]] && table="nat"
        if iptables -t "$table" -S "$chain" >/dev/null 2>&1; then
            iptables -t "$table" -F "$chain" || failed=1
            iptables -t "$table" -X "$chain" || failed=1
        fi
    done
    return "$failed"
}

# ---------- Start ----------
cmd_start() {
    require_root
    require_cmds tor iptables curl ss systemctl
    print_banner

    if is_active; then
        if [[ ! -f "$BACKEND_FILE" ]] || [[ "$(cat "$BACKEND_FILE")" != "chains" ]]; then
            die "Legacy Tor routing is marked active. Run 'stop' to restore its saved firewall rules before starting again."
        fi
        warn "Already active. Use '${C_CYAN}restart${C_RESET}' to change identity."
        return 0
    fi

    ensure_state_dir
    if [[ -f "$BACKEND_FILE" ]] && [[ "$(cat "$BACKEND_FILE")" == "chains" ]]; then
        remove_iptables_rules || die "Could not remove stale torsystem IPv4 chains; run 'stop' before retrying."
        restore_ipv6 || die "Could not remove stale torsystem IPv6 rules; run 'stop' before retrying."
    else
        if iptables -t nat -S "$NAT_CHAIN" >/dev/null 2>&1 ||
            iptables -S "$IPTABLES_CHAIN" >/dev/null 2>&1; then
            die "A reserved torsystem firewall chain already exists without an ownership marker; refusing to modify it."
        fi
        if command -v ip6tables >/dev/null 2>&1 &&
            ip6tables -S "$IP6TABLES_CHAIN" >/dev/null 2>&1; then
            die "A reserved torsystem IPv6 chain already exists without an ownership marker; refusing to modify it."
        fi
    fi

    spinner_run "Restarting Tor service" -- systemctl restart tor
    wait_for_tor_bootstrap 60 || die "Tor did not finish bootstrapping; routing was not enabled."
    wait_for_ports_listening || die "Tor's transparent proxy ports are not listening; routing was not enabled."

    printf '%s\n' "chains" > "$BACKEND_FILE"
    printf '%s\n' "starting" > "$STATE_FILE"
    if ! apply_iptables_rules || ! block_ipv6_leaks; then
        warn "Firewall setup failed; removing torsystem-owned rules."
        if remove_iptables_rules && restore_ipv6; then
            printf '%s\n' "inactive" > "$STATE_FILE"
            rm -f "$BACKEND_FILE"
        else
            warn "Cleanup was incomplete; run 'stop' to remove remaining torsystem rules."
        fi
        die "Tor routing was not enabled because firewall setup failed."
    fi

    echo "active" > "$STATE_FILE"
    echo ""
    ok "${C_BOLD}${C_GREEN}Tor routing is now ACTIVE.${C_RESET} External IPv4 TCP and DNS go through Tor; private networks are exempt and other UDP is blocked."
    echo ""
    cmd_status --no-banner
}

# ---------- Stop ----------
cmd_stop() {
    require_root
    print_banner
    ensure_state_dir

    local current_state=""
    [[ -f "$STATE_FILE" ]] && current_state="$(cat "$STATE_FILE")"
    if [[ "$current_state" != "active" ]] &&
        { [[ ! -f "$BACKEND_FILE" ]] || [[ "$(cat "$BACKEND_FILE")" != "chains" ]]; }; then
        log "Tor routing is not marked active; leaving firewall rules unchanged."
        return 0
    fi

    if [[ -f "$BACKEND_FILE" ]] && [[ "$(cat "$BACKEND_FILE")" == "chains" ]]; then
        if ! remove_iptables_rules || ! restore_ipv6; then
            die "Could not remove all torsystem firewall rules; state was retained for recovery."
        fi
    else
        warn "Legacy firewall setup detected; restoring its saved firewall snapshots."
        if [[ -f "$IPTABLES_SAVE_PATH" ]]; then
            spinner_run "Restoring previous IPv4 firewall rules" -- \
                iptables-restore < "$IPTABLES_SAVE_PATH"
        else
            die "Legacy IPv4 firewall backup is missing; refusing to flush firewall rules."
        fi
        if command -v ip6tables-restore >/dev/null 2>&1 &&
            [[ -f "$IP6TABLES_SAVE_PATH" ]]; then
            spinner_run "Restoring previous IPv6 firewall rules" -- \
                ip6tables-restore < "$IP6TABLES_SAVE_PATH"
        fi
    fi

    echo "inactive" > "$STATE_FILE"
    rm -f "$BACKEND_FILE"
    echo ""
    ok "${C_BOLD}Back to normal networking.${C_RESET}"
}

# ---------- Restart / new identity ----------
cmd_restart() {
    require_root
    print_banner
    if ! is_active; then
        die "Not currently active. Run '${C_CYAN}start${C_RESET}' first."
    fi

    if command -v nc >/dev/null 2>&1; then
        printf 'AUTHENTICATE ""\r\nSIGNAL NEWNYM\r\nQUIT\r\n' | nc -q 1 127.0.0.1 9051 2>/dev/null || true
    fi
    spinner_run "Restarting Tor for a new identity" -- systemctl restart tor
    wait_for_tor_bootstrap 60
    wait_for_ports_listening

    echo ""
    ok "${C_BOLD}New Tor identity acquired.${C_RESET}"
    echo ""
    cmd_status --no-banner
}

# ---------- Status ----------
cmd_status() {
    [[ "${1:-}" == "--no-banner" ]] || print_banner

    if is_active; then
        echo -e "  Status: ${C_GREEN}${C_BOLD}ACTIVE${C_RESET} ✅"
    else
        echo -e "  Status: ${C_GRAY}${C_BOLD}INACTIVE${C_RESET} ⭕"
    fi

    if command -v curl >/dev/null 2>&1; then
        local ip_info exit_ip
        if ip_info=$(_tor_check_fetch); then
            exit_ip=$(echo "$ip_info" | grep -oE '"IP":"[^"]+"' | cut -d'"' -f4)
            if [[ -n "$exit_ip" ]]; then
                echo -e "  Exit IP: ${C_BOLD}${exit_ip}${C_RESET}"
            fi
            echo -e "  ${C_DIM}$ip_info${C_RESET}"
        else
            _tor_check_diagnose "$?"
        fi
    fi
}

# _tor_check_fetch — try check.torproject.org, then a fallback endpoint.
# Prints the JSON response on success; returns curl's exit code on failure.
_tor_check_fetch() {
    local resp curl_status
    if resp=$(curl -fsS --max-time 20 --retry 2 --retry-delay 2 \
        https://check.torproject.org/api/ip 2>/dev/null); then
        curl_status=0
    else
        curl_status=$?
    fi
    if [[ $curl_status -eq 0 && -n "$resp" ]]; then
        echo "$resp"
        return 0
    fi

    # Fallback: check.torproject.org itself may be blocked/filtered by some
    # ISPs/networks even when Tor routing works fine. Confirm at least that
    # traffic is going out somewhere, and note the fallback was used.
    local ip
    if ip=$(curl -fsS --max-time 20 --retry 2 --retry-delay 2 https://api.ipify.org 2>/dev/null) &&
        [[ -n "$ip" ]]; then
        echo "{\"IsTor\":\"unknown (check.torproject.org unreachable, used fallback)\",\"IP\":\"$ip\"}"
        return 0
    fi

    return "$curl_status"
}

# _tor_check_diagnose <curl-exit-code> — print a specific reason instead of
# a generic "could not reach" message.
_tor_check_diagnose() {
    local code="$1"
    case "$code" in
        6)  err "DNS resolution failed. If Tor just restarted, wait a few seconds and try again — otherwise DNS routing (DNSPort) may not be active." ;;
        7)  err "Connection refused. Is Tor actually running? Check: ${C_DIM}systemctl status tor${C_RESET}" ;;
        28) err "Connection timed out. check.torproject.org may be blocked/filtered on your network, or the Tor circuit is slow/still building." ;;
        35|60) err "TLS/certificate error while connecting." ;;
        *)  err "Could not reach check.torproject.org (curl exit code: $code)." ;;
    esac
    warn "This can also happen if check.torproject.org is blocked on your network."
    warn "Try again in a few seconds, or run: ${C_DIM}curl -v https://check.torproject.org/api/ip${C_RESET} manually to see more detail."
}

# ---------- Leak check ----------
cmd_check() {
    print_banner
    require_cmds curl
    log "Verifying traffic is routed through Tor..."
    local resp curl_status
    if resp=$(_tor_check_fetch); then
        curl_status=0
    else
        curl_status=$?
    fi
    if [[ $curl_status -ne 0 || -z "$resp" ]]; then
        _tor_check_diagnose "$curl_status"
        echo ""
        warn "Further diagnostics:"
        echo -e "    ${C_DIM}journalctl -u tor -n 50${C_RESET}          (Tor bootstrap / errors)"
        echo -e "    ${C_DIM}ss -tlnp | grep -E '9040|5353'${C_RESET}   (TransPort / DNSPort listening?)"
        echo -e "    ${C_DIM}sudo iptables -t nat -L -n -v${C_RESET}    (rules actually applied?)"
        return 1
    fi
    echo -e "  ${C_DIM}$resp${C_RESET}"
    if echo "$resp" | grep -q '"IsTor":true'; then
        ok "${C_GREEN}${C_BOLD}Confirmed:${C_RESET} traffic is exiting through Tor."
    elif echo "$resp" | grep -q '"IsTor":"unknown'; then
        warn "check.torproject.org was unreachable, so Tor exit status could not be confirmed directly."
        warn "A fallback IP lookup succeeded, meaning routing works, but this does NOT confirm it's via Tor."
        echo -e "    ${C_DIM}journalctl -u tor -n 50${C_RESET}          (Tor bootstrap / errors)"
        return 2
    else
        err "${C_RED}${C_BOLD}Warning:${C_RESET} traffic is NOT exiting through Tor — possible leak."
        echo ""
        warn "Diagnostics to check:"
        echo -e "    ${C_DIM}journalctl -u tor -n 50${C_RESET}          (Tor bootstrap / errors)"
        echo -e "    ${C_DIM}ss -tlnp | grep -E '9040|5353'${C_RESET}   (TransPort / DNSPort listening?)"
        echo -e "    ${C_DIM}sudo iptables -t nat -L -n -v${C_RESET}    (rules actually applied?)"
        return 1
    fi
    return 0
}


# ---------- Exit node preference ----------
# set_torrc_exit_node <CC|""> — set or clear a preferred exit country.
# Passing an empty string clears the restriction (any exit node, default).
set_torrc_exit_node() {
    local code="${1:-}"
    require_root
    require_cmds tor

    if [[ -n "$code" && ! "$code" =~ ^[A-Z]{2}$ ]]; then
        die "Exit country must be a two-letter uppercase country code."
    fi

    sed -i '/^# torsystem-exit-node-begin$/,/^# torsystem-exit-node-end$/d' "$TORRC_PATH"

    if [[ -n "$code" ]]; then
        log "Setting preferred exit country to: ${C_BOLD}$code${C_RESET}"
        cat >> "$TORRC_PATH" <<EOF
# torsystem-exit-node-begin
ExitNodes {$code}
StrictNodes 1
# torsystem-exit-node-end
EOF
    else
        log "Clearing exit node preference (any country)."
    fi

    spinner_run "Restarting Tor to apply the change" -- systemctl restart tor
    wait_for_tor_bootstrap 60
    wait_for_ports_listening
    echo ""
    ok "${C_BOLD}Exit node preference updated.${C_RESET}"
    echo ""
    cmd_status --no-banner
}

# ---------- TUI (interactive menu) ----------
# Runs a cmd_* function in a subshell so an internal 'exit' (e.g. from die())
# only ends that subshell, not the whole TUI session; output is captured to
# a temp file and shown in a scrollable box.
_tui_run_and_show() {
    local backend="$1" title="$2"; shift 2
    local tmp
    tmp="$(mktemp)"

    local status=0
    if ( "$@" ) > "$tmp" 2>&1; then
        status=0
    else
        status=$?
    fi

    sed -ri 's/\x1B\[[0-9;]*[a-zA-Z]//g; s/\r//g' "$tmp" 2>/dev/null || true
    "$backend" --title "$title" --textbox "$tmp" 25 90 || true
    rm -f "$tmp"
    return $status
}

_tui_confirm() {
    local backend="$1" msg="$2"
    "$backend" --title "Confirm" --yesno "$msg" 10 60
}

cmd_tui() {
    local backend=""
    if command -v whiptail >/dev/null 2>&1; then
        backend="whiptail"
    elif command -v dialog >/dev/null 2>&1; then
        backend="dialog"
    else
        die "Neither 'whiptail' nor 'dialog' is installed.
  Debian/Ubuntu: sudo apt install whiptail
  Arch:          sudo pacman -S dialog
  Fedora:        sudo dnf install dialog"
    fi

    require_root

    while true; do
        local choice exitstatus
        if choice=$("$backend" --title "torsystem — Tor Network Control" \
            --menu "Choose an action:" 21 72 9 \
            "1" "Install prerequisites"                 \
            "2" "Start routing through Tor"              \
            "3" "Stop routing (restore normal network)"   \
            "4" "Restart / get new Tor identity"            \
            "5" "Show status"                                \
            "6" "Run leak check"                              \
            "7" "Advanced settings"                            \
            "8" "Exit" \
            3>&1 1>&2 2>&3); then
            exitstatus=0
        else
            exitstatus=$?
        fi

        if [[ $exitstatus -ne 0 ]]; then
            break
        fi

        case "$choice" in
            1) _tui_run_and_show "$backend" "Installing prerequisites..." cmd_install || true ;;
            2) _tui_run_and_show "$backend" "Starting Tor routing..." cmd_start || true ;;
            3)
                if _tui_confirm "$backend" "Stop Tor routing and restore normal networking?"; then
                    _tui_run_and_show "$backend" "Stopping..." cmd_stop || true
                fi
                ;;
            4) _tui_run_and_show "$backend" "Getting new Tor identity..." cmd_restart || true ;;
            5) _tui_run_and_show "$backend" "Status" cmd_status || true ;;
            6) _tui_run_and_show "$backend" "Leak check" cmd_check || true ;;
            7) cmd_tui_advanced "$backend" ;;
            8) break ;;
        esac
    done
    clear
}

# ---------- TUI: Advanced Settings submenu ----------
cmd_tui_advanced() {
    local backend="$1"
    while true; do
        local choice exitstatus
        if choice=$("$backend" --title "Advanced Settings" \
            --menu "Preferred exit node country:" 22 68 11 \
            "DE" "Germany"                     \
            "NL" "Netherlands"                  \
            "US" "United States"                 \
            "GB" "United Kingdom"                 \
            "FR" "France"                           \
            "SE" "Sweden"                             \
            "CH" "Switzerland"                         \
            "CUSTOM" "Enter a custom country code..."   \
            "ANY"    "Any country (clear preference)"    \
            "BACK"   "Back to main menu" \
            3>&1 1>&2 2>&3); then
            exitstatus=0
        else
            exitstatus=$?
        fi

        if [[ $exitstatus -ne 0 ]] || [[ "$choice" == "BACK" ]]; then
            break
        fi

        case "$choice" in
            ANY)
                _tui_run_and_show "$backend" "Clearing exit node preference..." set_torrc_exit_node "" || true
                ;;
            CUSTOM)
                local code custom_status
                if code=$("$backend" --title "Custom Exit Node" \
                    --inputbox "Enter a 2-letter country code (e.g. DE, NL, JP):" 10 60 \
                    3>&1 1>&2 2>&3); then
                    custom_status=0
                else
                    custom_status=$?
                fi
                if [[ $custom_status -eq 0 && -n "$code" ]]; then
                    code="$(printf '%s' "$code" | tr '[:lower:]' '[:upper:]')"
                    if [[ "$code" =~ ^[A-Z]{2}$ ]]; then
                        _tui_run_and_show "$backend" "Setting exit node to $code..." set_torrc_exit_node "$code" || true
                    else
                        "$backend" --title "Invalid input" --msgbox "Please enter exactly 2 letters (ISO country code), e.g. DE or JP." 9 60
                    fi
                fi
                ;;
            *)
                _tui_run_and_show "$backend" "Setting exit node to $choice..." set_torrc_exit_node "$choice" || true
                ;;
        esac
    done
}

# ---------- Usage ----------
usage() {
    print_banner
    cat <<EOF
  ${C_BOLD}Usage:${C_RESET} sudo $0 <command>

  ${C_BOLD}Commands:${C_RESET}
    ${C_CYAN}install${C_RESET}     Install prerequisites and configure torrc
    ${C_CYAN}start${C_RESET}       Enable transparent routing through Tor
    ${C_CYAN}stop${C_RESET}        Restore normal networking
    ${C_CYAN}restart${C_RESET}     Request a new Tor identity
    ${C_CYAN}status${C_RESET}      Show current status and exit IP
    ${C_CYAN}check${C_RESET}       Verify traffic is really passing through Tor
    ${C_CYAN}tui${C_RESET}         Launch an interactive menu (whiptail/dialog)

EOF
}

# ---------- Entry point ----------
main() {
    local cmd="${1:-}"
    case "$cmd" in
        install)  cmd_install ;;
        start)    cmd_start ;;
        stop)     cmd_stop ;;
        restart)  cmd_restart ;;
        status)   cmd_status ;;
        check)    cmd_check ;;
        tui)      cmd_tui ;;
        *)        usage; exit 1 ;;
    esac
}

main "$@"
