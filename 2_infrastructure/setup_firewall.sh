#!/usr/bin/env bash
# setup_firewall.sh — Rocklog host firewall (iptables + ip6tables), one script for every host type.
# Replaces ufw. Background: rocklog-vlic doc/security/host_firewall.md and
# doc/security/incident-2026-10-15-hub16.md (Docker-published ports bypass ufw).
#
# PROFILES
#   proxmox        Proxmox VE node. SSH/mosh and ADMIN_TCP (8006) from ADMIN_SOURCES, everything from
#                  CLUSTER_SOURCES, OPEN_TCP (80 443) public. FORWARD policy DROP (as before).
#   bastion        nginx gateway VM. OPEN_TCP (80 443 8080 8443) public, SSH from ADMIN_SOURCES.
#   app-vm         Docker app VM behind the bastion. SSH from ADMIN_SOURCES; containers reachable only
#                  from BASTION_SOURCES on APP_CONTAINER_PORTS (8080).
#   docker-public  Single public Docker host (nginx + containers on loopback, e.g. hub16).
#                  OPEN_TCP (80 443) public; no container port reachable from the internet.
#
# USAGE (as root)
#   setup_firewall.sh <profile> [options]   generate, apply, ask for confirmation, roll back after
#                                           CONFIRM_SECS (60) or when the SSH session drops
#   setup_firewall.sh apply                 re-apply the installed config (used by the systemd unit)
#   setup_firewall.sh status                show the active rules and counters
#
# OPTIONS
#   --dry-run        print the generated rulesets, change nothing (no root needed)
#   --yes            no confirmation/rollback (fresh VM with console access, automation)
#   --install        persist: /usr/local/sbin/rocklog-firewall, /etc/rocklog-firewall.conf,
#                    rocklog-firewall.service; disables netfilter-persistent and the legacy
#                    /etc/network/if-pre-up.d/iptables hook (they restore stale Docker rules at boot)
#   --disable-ufw    "ufw disable" before applying (re-enabled on rollback). Purge later: apt purge ufw
#   --config FILE    settings file (default /etc/rocklog-firewall.conf); environment overrides it
#
# SETTINGS (environment or config file; lists are space separated)
#   ADMIN_SOURCES           SSH (22) sources, IPv4/IPv6/CIDR. REQUIRED. "any" = everywhere (explicit)
#   MOSH_SOURCES            mosh 60000-61000/udp; default: proxmox = ADMIN_SOURCES, others = any
#   OPEN_TCP                public TCP ports (ranges as 8080:8090); default per profile
#   ADMIN_TCP               TCP ports for ADMIN_SOURCES only; default proxmox 8006
#   CLUSTER_SOURCES         proxmox: cluster peers, all traffic accepted (corosync, migration, ...)
#   BASTION_SOURCES         app-vm: hosts that may reach APP_CONTAINER_PORTS. REQUIRED for app-vm
#   APP_CONTAINER_PORTS     container ports (after DNAT) for BASTION_SOURCES; default 8080
#   PUBLIC_CONTAINER_PORTS  container ports reachable from anywhere; default none
#   PUBLIC_IF               uplink interface; default: interface of the default route
#   SCAN_PORTS              egress guard: outbound TCP ports logged + blocked; default 23,2323,5555
#   FORWARD_POLICY          DROP|ACCEPT|"" (unchanged); default proxmox DROP, others unchanged
#
# DESIGN
#   Only our own chains are (re)written: ROCKLOG-INPUT, ROCKLOG-OUTPUT and DOCKER-USER, via
#   iptables-restore --noflush. Docker's chains, the nat table and VM NAT are never touched.
#   INPUT/OUTPUT jump to our chains first; ROCKLOG-INPUT ends with DROP. Persistence is our own
#   systemd unit (before docker.service), not netfilter-persistent, which would also save and
#   restore Docker's dynamic rules.

set -euo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

CONF=/etc/rocklog-firewall.conf
SELF_INSTALL=/usr/local/sbin/rocklog-firewall
UNIT=/etc/systemd/system/rocklog-firewall.service
BACKUP_DIR=${BACKUP_DIR:-/var/backups/rocklog-firewall}
LEGACY_HOOK=/etc/network/if-pre-up.d/iptables
CONFIRM_SECS=${CONFIRM_SECS:-60}
SETTINGS=(PROFILE ADMIN_SOURCES MOSH_SOURCES OPEN_TCP ADMIN_TCP CLUSTER_SOURCES BASTION_SOURCES
          APP_CONTAINER_PORTS PUBLIC_CONTAINER_PORTS PUBLIC_IF SCAN_PORTS FORWARD_POLICY)

info() { echo "[firewall] $*"; }
warn() { echo "[firewall] WARNING: $*" >&2; }
die()  { echo "[firewall] ERROR: $*" >&2; exit 1; }

usage() { sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

# ---------------------------------------------------------------- arguments
CMD=${1:-}; [ -n "$CMD" ] || usage 1; shift
DRY_RUN=no YES=no INSTALL=no DISABLE_UFW=no
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run)     DRY_RUN=yes ;;
        --yes)         YES=yes ;;
        --install)     INSTALL=yes ;;
        --disable-ufw) DISABLE_UFW=yes ;;
        --config)      CONF=${2:?--config needs a file}; shift ;;
        -h|--help)     usage 0 ;;
        *) die "unknown option $1" ;;
    esac
    shift
done

# ---------------------------------------------------------------- settings
# Environment wins over the config file.
load_settings() {
    local v; declare -gA ENV_SET=()
    for v in "${SETTINGS[@]}"; do [ -n "${!v+x}" ] && ENV_SET[$v]=${!v}; done
    if [ -f "$CONF" ]; then
        # shellcheck disable=SC1090
        . "$CONF"
    fi
    for v in "${!ENV_SET[@]}"; do printf -v "$v" '%s' "${ENV_SET[$v]}"; done
}

resolve_profile() {
    : "${ADMIN_SOURCES:?ADMIN_SOURCES must be set (use \"any\" to allow SSH from everywhere)}"
    case "$PROFILE" in
        proxmox)
            : "${OPEN_TCP=80 443}"; : "${ADMIN_TCP=8006}"; : "${MOSH_SOURCES=$ADMIN_SOURCES}"
            : "${FORWARD_POLICY=DROP}"; DOCKER=no ;;
        bastion)
            : "${OPEN_TCP=80 443 8080 8443}"; : "${ADMIN_TCP=}"; : "${MOSH_SOURCES=any}"; DOCKER=no ;;
        app-vm)
            : "${OPEN_TCP=}"; : "${ADMIN_TCP=}"; : "${MOSH_SOURCES=any}"; DOCKER=yes
            : "${BASTION_SOURCES:?BASTION_SOURCES must be set for app-vm (the bastion IP)}" ;;
        docker-public)
            : "${OPEN_TCP=80 443}"; : "${ADMIN_TCP=}"; : "${MOSH_SOURCES=any}"; DOCKER=yes ;;
        *) die "unknown profile '$PROFILE' (proxmox | bastion | app-vm | docker-public)" ;;
    esac
    : "${CLUSTER_SOURCES=}" "${BASTION_SOURCES=}" "${APP_CONTAINER_PORTS=8080}"
    : "${PUBLIC_CONTAINER_PORTS=}" "${SCAN_PORTS=23,2323,5555}" "${FORWARD_POLICY=}"
    if [ -z "${PUBLIC_IF:-}" ]; then
        PUBLIC_IF=$(ip -o route show default 2>/dev/null | awk '{print $5; exit}')
    fi
    [ "$DOCKER" = no ] || [ -n "$PUBLIC_IF" ] || die "PUBLIC_IF not detectable (no default route); set it explicitly"

    local s p
    for s in $ADMIN_SOURCES $MOSH_SOURCES $CLUSTER_SOURCES $BASTION_SOURCES; do
        [[ $s == any || $s =~ ^[0-9a-fA-F:.]+(/[0-9]{1,3})?$ ]] || die "invalid source '$s'"
    done
    for s in $CLUSTER_SOURCES $BASTION_SOURCES; do [ "$s" != any ] || die "'any' not allowed in CLUSTER_SOURCES/BASTION_SOURCES"; done
    for p in $OPEN_TCP $ADMIN_TCP $APP_CONTAINER_PORTS $PUBLIC_CONTAINER_PORTS ${SCAN_PORTS//,/ }; do
        [[ $p =~ ^[0-9]{1,5}(:[0-9]{1,5})?$ ]] || die "invalid port '$p'"
    done
    [[ ${FORWARD_POLICY} =~ ^(|DROP|ACCEPT)$ ]] || die "FORWARD_POLICY must be DROP, ACCEPT or empty"
    [[ ${PUBLIC_IF} =~ ^[A-Za-z0-9._@-]*$ ]] || die "invalid PUBLIC_IF '$PUBLIC_IF'"
    if [ "$ADMIN_SOURCES" = any ]; then warn "SSH open to the whole internet (ADMIN_SOURCES=any)"; fi
}

# ---------------------------------------------------------------- rule generation
csv() { echo "$*" | tr -s ' ' ','; }

# sources_for <4|6> <list> — the entries of <list> that belong to the address family
sources_for() {
    local s
    for s in $2; do
        if [ "$s" = any ]; then echo any
        elif [[ $s == *:* ]]; then [ "$1" = 6 ] && echo "$s"
        else [ "$1" = 4 ] && echo "$s"
        fi
    done
    return 0
}
src() { [ "$1" = any ] || echo "-s $1 "; }

# gen_rules <4|6> — iptables-restore input for one address family
gen_rules() {
    local f=$1 s I=-A\ ROCKLOG-INPUT O=-A\ ROCKLOG-OUTPUT D=-A\ DOCKER-USER
    echo "*filter"
    echo ":ROCKLOG-INPUT - [0:0]"
    echo ":ROCKLOG-OUTPUT - [0:0]"
    [ "$DOCKER" = yes ] && echo ":DOCKER-USER - [0:0]"

    echo "$I -i lo -j ACCEPT"
    echo "$I -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT"
    echo "$I -m conntrack --ctstate INVALID -j DROP"
    if [ "$f" = 4 ]; then
        echo "$I -p icmp --icmp-type echo-request -m limit --limit 20/second -j ACCEPT"
        echo "$I -p udp --sport 67 --dport 68 -j ACCEPT"
    else
        echo "$I -p ipv6-icmp -j ACCEPT"
        echo "$I -s fe80::/10 -p udp --dport 546 -j ACCEPT"
    fi
    for s in $(sources_for "$f" "$ADMIN_SOURCES"); do
        echo "$I $(src "$s")-p tcp --dport 22 -j ACCEPT"
        [ -z "$ADMIN_TCP" ] || echo "$I $(src "$s")-p tcp -m multiport --dports $(csv "$ADMIN_TCP") -j ACCEPT"
    done
    for s in $(sources_for "$f" "$MOSH_SOURCES"); do
        echo "$I $(src "$s")-p udp --dport 60000:61000 -j ACCEPT"
    done
    [ -z "$OPEN_TCP" ] || echo "$I -p tcp -m multiport --dports $(csv "$OPEN_TCP") -j ACCEPT"
    for s in $(sources_for "$f" "$CLUSTER_SOURCES"); do
        echo "$I -s $s -j ACCEPT"
    done
    echo "$I -m limit --limit 6/minute -j LOG --log-prefix \"FW-IN-DROP \""
    echo "$I -j DROP"

    # Egress guard for host processes (botnet scan targets)
    echo "$O -p tcp -m multiport --dports $SCAN_PORTS -m conntrack --ctstate NEW -j LOG --log-prefix \"EGRESS-SCAN \" --log-uid"
    echo "$O -p tcp -m multiport --dports $SCAN_PORTS -j REJECT"

    if [ "$DOCKER" = yes ]; then
        # FORWARD path of containers. Ports here are container ports (after DNAT).
        echo "$D -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN"
        echo "$D -p tcp -m multiport --dports $SCAN_PORTS -m conntrack --ctstate NEW -j LOG --log-prefix \"EGRESS-SCAN-CT \""
        echo "$D -p tcp -m multiport --dports $SCAN_PORTS -j DROP"
        for s in $(sources_for "$f" "$BASTION_SOURCES"); do
            echo "$D -i $PUBLIC_IF -s $s -p tcp -m multiport --dports $(csv "$APP_CONTAINER_PORTS") -j RETURN"
        done
        [ -z "$PUBLIC_CONTAINER_PORTS" ] || echo "$D -i $PUBLIC_IF -p tcp -m multiport --dports $(csv "$PUBLIC_CONTAINER_PORTS") -j RETURN"
        echo "$D -i $PUBLIC_IF -m conntrack --ctstate NEW -m limit --limit 6/minute -j LOG --log-prefix \"FW-CT-DROP \""
        echo "$D -i $PUBLIC_IF -m conntrack --ctstate NEW -j DROP"
        echo "$D -j RETURN"
    fi
    echo "COMMIT"
}

# ---------------------------------------------------------------- apply
have_v6() { [ -f /proc/net/if_inet6 ] && command -v ip6tables-restore >/dev/null; }
families() { echo 4; if have_v6; then echo 6; fi; }
ipt() { if [ "$1" = 4 ]; then echo iptables; else echo ip6tables; fi; }

# ensure_first <cmd> <builtin-chain> <target> — exactly one jump, at position 1
ensure_first() {
    if [ "$("$1" -S "$2" | sed -n 2p)" != "-A $2 -j $3" ]; then
        while "$1" -D "$2" -j "$3" 2>/dev/null; do :; done
        "$1" -I "$2" 1 -j "$3"
    fi
}

apply_rules() {
    local f t
    for f in $(families); do
        t=$(ipt "$f")
        gen_rules "$f" | "$t-restore" --noflush
        ensure_first "$t" INPUT ROCKLOG-INPUT
        ensure_first "$t" OUTPUT ROCKLOG-OUTPUT
        "$t" -P INPUT DROP
        [ -z "$FORWARD_POLICY" ] || "$t" -P FORWARD "$FORWARD_POLICY"
    done
}

ROLLBACK_FILES=() UFW_WAS_ACTIVE=no
rollback() {
    trap - HUP INT TERM
    warn "rolling back to the previous ruleset"
    local f i=0
    for f in $(families); do "$(ipt "$f")-restore" < "${ROLLBACK_FILES[$i]}"; i=$((i + 1)); done
    if [ "$UFW_WAS_ACTIVE" = yes ]; then ufw --force enable >/dev/null && info "ufw re-enabled"; fi
    die "not confirmed — previous ruleset restored"
}

confirm_or_rollback() {
    trap rollback HUP INT TERM
    [ -t 0 ] || { rollback; }
    echo
    info "Rules are active. Open a NEW SSH session now and check that it works."
    printf '[firewall] Type "yes" within %ss to keep them (anything else / timeout / lost session = rollback): ' "$CONFIRM_SECS"
    local answer=""
    read -r -t "$CONFIRM_SECS" answer || true
    [ "$answer" = yes ] || rollback
    trap - HUP INT TERM
    info "confirmed"
}

install_persistent() {
    local v
    [ "$(readlink -f "$0")" = "$SELF_INSTALL" ] || install -m 700 "$0" "$SELF_INSTALL"
    ( umask 077
      { echo "# rocklog-firewall settings — written by setup_firewall.sh --install on $(date -Is)"
        for v in "${SETTINGS[@]}"; do printf '%s=%q\n' "$v" "${!v}"; done
      } > "$CONF" )
    cat > "$UNIT" <<EOF
[Unit]
Description=Rocklog host firewall (iptables/ip6tables)
Documentation=man:iptables(8)
DefaultDependencies=no
Wants=network-pre.target
After=local-fs.target systemd-modules-load.service
Before=network-pre.target docker.service shutdown.target
Conflicts=shutdown.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=$SELF_INSTALL apply --yes --config $CONF

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable rocklog-firewall.service >/dev/null
    info "installed: $SELF_INSTALL, $CONF, $UNIT (enabled)"

    if systemctl is-enabled netfilter-persistent >/dev/null 2>&1; then
        systemctl disable netfilter-persistent >/dev/null
        info "disabled netfilter-persistent (would restore stale Docker rules at boot)"
    fi
    if [ -f "$LEGACY_HOOK" ]; then
        mv "$LEGACY_HOOK" "$LEGACY_HOOK.disabled-by-rocklog-firewall"   # run-parts skips names with dots
        info "disabled legacy hook $LEGACY_HOOK"
    fi
    if command -v ufw >/dev/null && ufw status 2>/dev/null | grep -q 'Status: active'; then
        warn "ufw is still active and will reload its rules at boot — rerun with --disable-ufw"
    fi
}

# ---------------------------------------------------------------- commands
need_root() { [ "$(id -u)" -eq 0 ] || die "must run as root"; }

cmd_status() {
    local f t
    for f in $(families); do
        t=$(ipt "$f")
        echo "===== $t"
        "$t" -S INPUT | head -3; "$t" -S OUTPUT | head -2
        "$t" -L ROCKLOG-INPUT -nv --line-numbers 2>/dev/null || echo "(ROCKLOG-INPUT missing)"
        "$t" -L ROCKLOG-OUTPUT -nv --line-numbers 2>/dev/null || true
        "$t" -L DOCKER-USER -nv --line-numbers 2>/dev/null || true
    done
    echo "===== persistence"
    echo "rocklog-firewall.service: $(systemctl is-enabled rocklog-firewall 2>/dev/null || echo not-installed)"
    echo "netfilter-persistent:     $(systemctl is-enabled netfilter-persistent 2>/dev/null || echo not-installed)"
    if command -v ufw >/dev/null; then echo "ufw: $(ufw status 2>/dev/null | head -1)"; fi
}

cmd_apply() {   # boot / re-apply: settings from config, no confirmation
    need_root
    [ -n "${PROFILE:-}" ] || die "no PROFILE in $CONF — run setup_firewall.sh <profile> --install first"
    resolve_profile
    apply_rules
    info "applied profile $PROFILE"
}

cmd_profile() {
    PROFILE=$CMD
    resolve_profile
    if [ "$DRY_RUN" = yes ]; then
        local f
        for f in 4 6; do
            echo "### $(ipt "$f")-restore --noflush"; gen_rules "$f"
            echo "### then: INPUT/OUTPUT jump to ROCKLOG-INPUT/ROCKLOG-OUTPUT at position 1, INPUT policy DROP${FORWARD_POLICY:+, FORWARD policy $FORWARD_POLICY}"
        done
        return
    fi
    need_root
    if [ "$PROFILE" = proxmox ] && command -v pve-firewall >/dev/null \
       && pve-firewall status 2>/dev/null | grep -q 'enabled'; then
        die "pve-firewall is enabled — it manages INPUT itself. Use the Proxmox firewall (Datacenter > Firewall) or disable it first."
    fi
    if [ "$YES" = no ] && [ ! -t 0 ]; then die "no terminal for the confirmation — run interactively or pass --yes"; fi

    local ts f
    ts=$(date +%Y%m%dT%H%M%S)
    mkdir -p -m 700 "$BACKUP_DIR"
    for f in $(families); do
        "$(ipt "$f")-save" > "$BACKUP_DIR/$ts.v$f"
        ROLLBACK_FILES+=("$BACKUP_DIR/$ts.v$f")
    done
    info "previous ruleset saved to $BACKUP_DIR/$ts.v*"

    if [ "$DISABLE_UFW" = yes ] && command -v ufw >/dev/null && ufw status | grep -q 'Status: active'; then
        UFW_WAS_ACTIVE=yes
        ufw disable >/dev/null
        info "ufw disabled"
    fi

    apply_rules
    info "applied profile $PROFILE (public interface: ${PUBLIC_IF:-n/a})"
    [ "$YES" = yes ] || confirm_or_rollback
    [ "$INSTALL" = no ] || install_persistent
    if [ "$UFW_WAS_ACTIVE" = yes ]; then info "ufw is disabled; remove it with: apt purge ufw"; fi
    [ "$INSTALL" = yes ] || warn "not persistent — rerun with --install to survive a reboot"
}

case "$CMD" in
    status) need_root; load_settings; DOCKER=no; cmd_status ;;
    apply)  load_settings; cmd_apply ;;
    proxmox|bastion|app-vm|docker-public) load_settings; cmd_profile ;;
    -h|--help|help) usage 0 ;;
    *) die "unknown command '$CMD'" ;;
esac
