#!/system/bin/sh
# Berry-FCM bounded watch window: monitor + auto-fix inside the 120s budget.
#   usage: sh lib/watch.sh [duration_sec] [interval_sec] [hb_every_cycles]
# The manager kills scripts at 120s, so duration is capped at 105.
. "$(dirname "$0")/berry.sh" || exit 1

b_identity_guard || exit 1

DUR="${1:-90}"
INT="${2:-15}"
HB_EVERY="${3:-4}"
[ "$DUR" -gt 105 ] && DUR=105
[ "$INT" -lt 5 ] && INT=5

CYCLE=0; FIXES=0; SPENT=0
START="$(date +%s)"
b_head "Berry-FCM 监视窗口 ${DUR}s / 间隔 ${INT}s / 每 ${HB_EVERY} 轮心跳"

while :; do
    NOW="$(date +%s)"
    ELAPSED=$((NOW - START))
    [ "$ELAPSED" -ge "$DUR" ] && break
    CYCLE=$((CYCLE + 1))

    LINE="#$CYCLE +${ELAPSED}s"
    ACTED=0
    for pkg in $(b_load_targets); do
        b_pkg_installed "$pkg" || continue
        if b_pkg_stopped "$pkg"; then
            if [ "$SPENT" -ge "$FIX_BUDGET" ]; then
                LINE="$LINE $pkg=stopped(预算尽)"
                continue
            fi
            SPENT=$((SPENT + 1))
            if b_unstop "$pkg" && ! b_pkg_stopped "$pkg"; then
                FIXES=$((FIXES + 1)); ACTED=1
                LINE="$LINE $pkg=stopped→已解除"
            else
                LINE="$LINE $pkg=stopped→修复失败"
            fi
        fi
    done
    if [ "$ACTED" = "1" ]; then
        # 刚解除 stopped 的包立即补一发心跳最有效
        for pkg in $(b_load_targets); do
            [ "$pkg" = "$GMS" ] && b_heartbeat >/dev/null 2>&1 && break
        done
    elif [ $((CYCLE % HB_EVERY)) = "0" ]; then
        for pkg in $(b_load_targets); do
            [ "$pkg" = "$GMS" ] && b_pkg_installed "$GMS" && { b_heartbeat >/dev/null 2>&1; break; }
        done
        LINE="$LINE [心跳]"
    fi
    b_log "$LINE"
    sleep "$INT"
done

b_log ""
b_ok "窗口结束: $CYCLE 轮 · 自动解除 stopped $FIXES 次(预算 $SPENT/$FIX_BUDGET)"
