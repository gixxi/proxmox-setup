#!/usr/bin/env bash
#
# jvm-gc-watch.sh — live JVM GC watcher for a containerised JVM.
#
# Counterpart to the cgroup memory monitor: where that script watches the
# container's RAM against its cgroup limit, this one watches the JVM heap
# from the inside — old-gen occupancy trend and full-GC events — so you get
# early warning *before* the cgroup OOM killer is ever in play.
#
# Output : live console table (refreshes in place).
# Alerts : appended to a separate alert file on (a) any new full GC, or
#          (b) old-gen occupancy crossing a high-water threshold.
#
# Usage:
#   ./jvm-gc-watch.sh <container> [interval_sec] [old_gen_warn_pct]
#   ./jvm-gc-watch.sh greenenso              # 5s interval, warn at 90% old gen
#   ./jvm-gc-watch.sh greenenso 10 85        # 10s interval, warn at 85%
#   ./jvm-gc-watch.sh --help
#
# Notes:
#   - The JVM PID inside the container is auto-detected (first `java` process).
#     Override with JVM_PID=<pid> if you run more than one JVM in the container.
#   - jstat -gc emits values in KB. We convert to GiB for the heap columns.

set -u

ALERT_FILE="${ALERT_FILE:-/var/log/jvm-gc-alerts.log}"

print_help() {
    cat <<'EOF'
jvm-gc-watch.sh — live JVM GC watcher for a containerised JVM

USAGE
  jvm-gc-watch.sh <container> [interval_sec] [old_gen_warn_pct]
  jvm-gc-watch.sh --help

ARGUMENTS
  container          Name or ID of the running container.
  interval_sec       Refresh interval in seconds (default: 5). Use 0 for a
                     single snapshot.
  old_gen_warn_pct   Old-gen occupancy % that triggers an alert (default: 90).

ENVIRONMENT
  JVM_PID            Force a specific in-container JVM pid (skips auto-detect).
  ALERT_FILE         Path for the alert log (default: /var/log/jvm-gc-alerts.log).

COLUMNS
  EU/EC      Eden used / capacity (GiB) — short-lived allocations.
  OU/OC      Old-gen used / capacity (GiB) — long-lived objects. THE column
             to watch: steady creep here precedes full GCs and heap pressure.
  OldGen%    OU/OC as a percentage. Alerts fire when this crosses the threshold.
  MU         Metaspace used (MiB) — class metadata; should plateau, not climb.
  YGC/YGCT   Young GC count / cumulative time (s).
  FGC/FGCT   Full GC count / cumulative time (s). A rising FGC under load is
             the classic precursor to GC thrash and OOM. Any NEW full GC is
             alerted immediately.

ALERTS (appended to ALERT_FILE)
  - FULL_GC   : full-GC count increased since the previous sample.
  - OLD_GEN   : old-gen occupancy crossed old_gen_warn_pct.
EOF
}

case "${1:-}" in
    --help|-h) print_help; exit 0 ;;
esac

if [ $# -lt 1 ]; then
    echo "Usage: $0 <container> [interval_sec] [old_gen_warn_pct]" >&2
    echo "       $0 --help" >&2
    exit 1
fi

CONTAINER="$1"
INTERVAL="${2:-5}"
OLD_GEN_WARN_PCT="${3:-90}"

# --- resolve container id, anchored match (no substring false positives) ---
CONTAINER_ID=$(docker ps --filter "name=^${CONTAINER}$" --format '{{.ID}}' | head -n1)
if [ -z "$CONTAINER_ID" ]; then
    # maybe an ID was passed directly
    CONTAINER_ID=$(docker ps --filter "id=${CONTAINER}" --format '{{.ID}}' | head -n1)
fi
if [ -z "$CONTAINER_ID" ]; then
    echo "ERROR: container '${CONTAINER}' not found or not running" >&2
    exit 1
fi

# --- locate the JVM pid inside the container ---
detect_jvm_pid() {
    if [ -n "${JVM_PID:-}" ]; then
        echo "$JVM_PID"
        return 0
    fi
    # pgrep inside the container's namespace; fall back to ps parsing.
    docker exec "$CONTAINER_ID" sh -c '
        if command -v pgrep >/dev/null 2>&1; then
            pgrep -n java
        else
            ps -eo pid,comm 2>/dev/null | awk "\$2==\"java\"{print \$1; exit}"
        fi
    ' 2>/dev/null | head -n1
}

# --- alert file: ensure writable, warn (non-fatal) if not ---
ensure_alert_file() {
    if ! touch "$ALERT_FILE" 2>/dev/null; then
        echo "WARNING: cannot write alert file '$ALERT_FILE' — alerts go to stderr only." >&2
        ALERT_FILE=""
    fi
}

log_alert() {
    # $1 = type, $2 = message
    local line
    line="$(date '+%Y-%m-%d %H:%M:%S %Z')  [$1]  container=${CONTAINER}  $2"
    if [ -n "$ALERT_FILE" ]; then
        echo "$line" >> "$ALERT_FILE"
    fi
    # also surface on stderr so it shows even in live mode
    echo "$line" >&2
}

# integer KB -> GiB with 2 decimals (awk; avoids bash float pain)
kb_to_gib() { awk -v k="${1:-0}" 'BEGIN{printf "%.2f", k/1048576}'; }
kb_to_mib() { awk -v k="${1:-0}" 'BEGIN{printf "%.1f", k/1024}'; }

PREV_FGC=""

sample_once() {
    local pid
    pid=$(detect_jvm_pid)
    if [ -z "$pid" ]; then
        echo "ERROR: no java process found in container ${CONTAINER}" >&2
        return 1
    fi

    # jstat -gc <pid> : header line + data line
    local raw
    raw=$(docker exec "$CONTAINER_ID" jstat -gc "$pid" 2>/dev/null)
    if [ -z "$raw" ]; then
        echo "ERROR: jstat returned nothing (is it a JDK image? pid=$pid)" >&2
        return 1
    fi

    # data is the last line; columns (jstat -gc order):
    # S0C S1C S0U S1U EC EU OC OU MC MU CCSC CCSU YGC YGCT FGC FGCT GCT
    local data
    data=$(echo "$raw" | tail -n1)
    # shellcheck disable=SC2086
    set -- $data
    local EC="$5" EU="$6" OC="$7" OU="$8" MU="${10}" YGC="${13}" YGCT="${14}" FGC="${15}" FGCT="${16}"

    local old_pct
    old_pct=$(awk -v u="$OU" -v c="$OC" 'BEGIN{ if(c>0) printf "%.1f", (u/c)*100; else print "0.0" }')

    # ---- render console table ----
    clear
    echo "=== JVM GC Watch: ${CONTAINER} (ID: ${CONTAINER_ID}, pid ${pid}) ==="
    echo "Timestamp: $(date)"
    echo "Alert file: ${ALERT_FILE:-<stderr only>}   Old-gen warn: ${OLD_GEN_WARN_PCT}%"
    echo ""
    printf "%-10s %-10s %-10s %-10s %-9s %-9s %-8s %-10s %-6s %-10s\n" \
        "EU(GiB)" "EC(GiB)" "OU(GiB)" "OC(GiB)" "OldGen%" "MU(MiB)" "YGC" "YGCT(s)" "FGC" "FGCT(s)"
    printf "%-10s %-10s %-10s %-10s %-9s %-9s %-8s %-10s %-6s %-10s\n" \
        "$(kb_to_gib "$EU")" "$(kb_to_gib "$EC")" \
        "$(kb_to_gib "$OU")" "$(kb_to_gib "$OC")" \
        "$old_pct" "$(kb_to_mib "$MU")" \
        "$YGC" "$YGCT" "$FGC" "$FGCT"
    echo ""

    # ---- detection ----
    # (a) new full GC since last sample
    if [ -n "$PREV_FGC" ] && [ "$FGC" -gt "$PREV_FGC" ] 2>/dev/null; then
        log_alert "FULL_GC" "full GC count rose ${PREV_FGC} -> ${FGC} (FGCT=${FGCT}s, oldgen=${old_pct}%)"
        echo "⚠️  FULL GC detected (count ${PREV_FGC} -> ${FGC})"
    fi
    PREV_FGC="$FGC"

    # (b) old-gen occupancy over threshold
    if awk -v p="$old_pct" -v t="$OLD_GEN_WARN_PCT" 'BEGIN{exit !(p>=t)}'; then
        log_alert "OLD_GEN" "old-gen occupancy ${old_pct}% >= ${OLD_GEN_WARN_PCT}% (OU=$(kb_to_gib "$OU")GiB / OC=$(kb_to_gib "$OC")GiB)"
        echo "⚠️  OLD GEN high: ${old_pct}% (>= ${OLD_GEN_WARN_PCT}%)"
    else
        echo "✅ old-gen ${old_pct}% under ${OLD_GEN_WARN_PCT}% threshold"
    fi
}

ensure_alert_file

if [ "$INTERVAL" = "0" ]; then
    sample_once
    exit $?
fi

while true; do
    sample_once || { sleep "$INTERVAL"; continue; }
    echo ""
    echo "Refreshing every ${INTERVAL}s... (Ctrl+C to stop)"
    sleep "$INTERVAL"
done