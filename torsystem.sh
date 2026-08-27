#!/usr/bin/env bash
#
# torsystem.sh — Transparently route all system traffic through the Tor network (VPN-like)
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
STATE_DIR="/var/lib/torsystem"
STATE_FILE="$STATE_DIR/state"

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
    echo -e "${C_RESET}${C_GRAY}         route all system traffic through Tor${C_RESET}"
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
    [[ -f "$STATE_FILE" ]] && [[ "$(cat "$STATE_FILE")" == "active" ]]
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

    wait "$pid"
    local status=$?

    if [[ $status -eq 0 ]]; then
        printf "\r  ${C_GREEN}✔${C_RESET} %s\n" "$msg"
    else
        printf "\r  ${C_RED}✘${C_RESET} %s\n" "$msg"
        echo -e "${C_GRAY}"
        sed 's/^/      /' "$logfile"
        echo -e "${C_RESET}"
    fi
    rm -f "$logfile"
    return $status
}

# wait_for_tor_bootstrap [timeout_seconds]
# Polls journalctl for "Bootstrapped 100%" instead of a fixed sleep.
# Applying iptables rules before Tor finishes bootstrapping is the #1
# cause of everything timing out right after 'start'.
wait_for_tor_bootstrap() {
    local timeout="${1:-60}"
    local waited=0
    local frames=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
    local i=0
    local pct=""

    while (( waited < timeout )); do
        pct=$(journalctl -u tor --no-pager -n 40 2>/dev/null | grep -oP 'Bootstrapped \K[0-9]+(?=%)' | tail -1)
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
    warn "Tor did not report 100% bootstrap within ${timeout}s — continuing, but this may cause timeouts."
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
    warn "TransPort (${TRANS_PORT}) or DNSPort (${DNS_PORT}) not detected as listening."
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
    echo "inactive" > "$STATE_FILE"

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

    systemctl enable tor >/dev/null 2>&1 || true
    echo ""
    ok "${C_BOLD}Installation complete.${C_RESET} Run '${C_CYAN}start${C_RESET}' to go live."
}

# ---------- Start ----------
cmd_start() {
    require_root
    require_cmds tor iptables curl
    print_banner

    if is_active; then
        warn "Already active. Use '${C_CYAN}restart${C_RESET}' to change identity."
        return 0
    fi

    spinner_run "Restarting Tor service" -- systemctl restart tor
    wait_for_tor_bootstrap 60
    wait_for_ports_listening

    ensure_state_dir
    log "Saving current iptables rules..."
    iptables-save > "$IPTABLES_SAVE_PATH"

    iptables -F
    iptables -t nat -F

    log "Applying routing rules to Tor..."
    iptables -t nat -A OUTPUT -m owner --uid-owner "$TOR_UID" -j RETURN
    iptables -t nat -A OUTPUT -p udp --dport 53 -j REDIRECT --to-ports "$DNS_PORT"
    iptables -t nat -A OUTPUT -p tcp --dport 53 -j REDIRECT --to-ports "$DNS_PORT"

    for net in "${NON_TOR_NETS[@]}"; do
        iptables -t nat -A OUTPUT -d "$net" -j RETURN
    done

    iptables -t nat -A OUTPUT -p tcp --syn -j REDIRECT --to-ports "$TRANS_PORT"

    iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    iptables -A OUTPUT -o lo -j ACCEPT
    for net in "${NON_TOR_NETS[@]}"; do
        iptables -A OUTPUT -d "$net" -j ACCEPT
    done
    iptables -A OUTPUT -m owner --uid-owner "$TOR_UID" -j ACCEPT
    iptables -A OUTPUT -p tcp --syn -j ACCEPT
    iptables -A OUTPUT -j DROP

    echo "active" > "$STATE_FILE"
    echo ""
    ok "${C_BOLD}${C_GREEN}Tor routing is now ACTIVE.${C_RESET} All TCP + DNS traffic is anonymized."
    echo ""
    cmd_status --no-banner
}

# ---------- Stop ----------
cmd_stop() {
    require_root
    print_banner
    ensure_state_dir

    spinner_run "Flushing iptables rules" -- bash -c "iptables -F && iptables -t nat -F"

    if [[ -f "$IPTABLES_SAVE_PATH" ]]; then
        spinner_run "Restoring previous iptables rules" -- bash -c "iptables-restore < '$IPTABLES_SAVE_PATH'"
    fi

    echo "inactive" > "$STATE_FILE"
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
        local ip_info
        if ip_info=$(curl -s --max-time 10 https://check.torproject.org/api/ip); then
            echo -e "  ${C_DIM}$ip_info${C_RESET}"
        else
            err "Could not reach check.torproject.org."
        fi
    fi
}

# ---------- Leak check ----------
cmd_check() {
    print_banner
    require_cmds curl
    log "Verifying traffic is routed through Tor..."
    local resp
    resp=$(curl -s --max-time 10 https://check.torproject.org/api/ip || echo "")
    if [[ -z "$resp" ]]; then
        err "No response received. Check your connection or configuration."
        return 1
    fi
    echo -e "  ${C_DIM}$resp${C_RESET}"
    if echo "$resp" | grep -q '"IsTor":true'; then
        ok "${C_GREEN}${C_BOLD}Confirmed:${C_RESET} traffic is exiting through Tor."
    else
        err "${C_RED}${C_BOLD}Warning:${C_RESET} traffic is NOT exiting through Tor — possible leak."
        echo ""
        warn "Diagnostics to check:"
        echo -e "    ${C_DIM}journalctl -u tor -n 50${C_RESET}          (Tor bootstrap / errors)"
        echo -e "    ${C_DIM}ss -tlnp | grep -E '9040|5353'${C_RESET}   (TransPort / DNSPort listening?)"
        echo -e "    ${C_DIM}sudo iptables -t nat -L -n -v${C_RESET}    (rules actually applied?)"
    fi
}

# ---------- TUI (interactive menu) ----------
# Runs a cmd_* function in a subshell so an internal 'exit' (e.g. from die())
# only ends that subshell, not the whole TUI session; output is captured to
# a temp file and shown in a scrollable box.
_tui_run_and_show() {
    local backend="$1" title="$2"; shift 2
    local tmp
    tmp="$(mktemp)"

    ( "$@" ) > "$tmp" 2>&1
    local status=$?

    sed -ri 's/\x1B\[[0-9;]*[a-zA-Z]//g' "$tmp" 2>/dev/null || true
    "$backend" --title "$title" --textbox "$tmp" 25 90
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
        choice=$("$backend" --title "torsystem — Tor Network Control" \
            --menu "Choose an action:" 20 72 8 \
            "1" "Install prerequisites"                 \
            "2" "Start routing through Tor"              \
            "3" "Stop routing (restore normal network)"   \
            "4" "Restart / get new Tor identity"            \
            "5" "Show status"                                \
            "6" "Run leak check"                              \
            "7" "Exit" \
            3>&1 1>&2 2>&3)
        exitstatus=$?

        if [[ $exitstatus -ne 0 ]]; then
            break
        fi

        case "$choice" in
            1) _tui_run_and_show "$backend" "Installing prerequisites..." cmd_install ;;
            2) _tui_run_and_show "$backend" "Starting Tor routing..." cmd_start ;;
            3)
                if _tui_confirm "$backend" "Stop Tor routing and restore normal networking?"; then
                    _tui_run_and_show "$backend" "Stopping..." cmd_stop
                fi
                ;;
            4) _tui_run_and_show "$backend" "Getting new Tor identity..." cmd_restart ;;
            5) _tui_run_and_show "$backend" "Status" cmd_status ;;
            6) _tui_run_and_show "$backend" "Leak check" cmd_check ;;
            7) break ;;
        esac
    done
    clear
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
