#!/system/bin/sh
# Berry-FCM repair cycle: unstop every stopped target (verified), then GCM
# heartbeat (verified). Mirrors the original's guarded write path:
# read-only recheck after every write + per-run command budget.
. "$(dirname "$0")/berry.sh" || exit 1

b_identity_guard || exit 1

FIXED=0; FAILED=0; SPENT=0
b_head "Berry-FCM 修复 $(date '+%F %T')"

for pkg in $(b_load_targets); do
    if ! b_pkg_installed "$pkg"; then
        b_warn "$pkg 未安装,跳过"
        continue
    fi
    if ! b_pkg_stopped "$pkg"; then
        b_log "$pkg: 无 stopped 标记,无需修复"
        continue
    fi
    if [ "$SPENT" -ge "$FIX_BUDGET" ]; then
        b_err "修复预算($FIX_BUDGET 次)已用尽,中止(防刷屏防打架,与原版 command budget 同思路)"
        break
    fi
    SPENT=$((SPENT + 1))
    b_log "$pkg: 检出 stopped=true → cmd package unstop --user 0"
    if b_unstop "$pkg"; then
        # guarded recheck: read-only verify after write (原版只读复检)
        if b_pkg_stopped "$pkg"; then
            b_err "$pkg: unstop 后复检仍为 stopped,放弃本轮"
            FAILED=$((FAILED + 1))
        else
            b_ok "$pkg: stopped 已解除(复检通过)"
            FIXED=$((FIXED + 1))
        fi
    else
        FAILED=$((FAILED + 1))
    fi
done

# GCM heartbeat(只要 GMS 在目标里就发;原版 gms_manual_heartbeat_v1)
NEED_HB=0
for pkg in $(b_load_targets); do
    [ "$pkg" = "$GMS" ] && b_pkg_installed "$GMS" && NEED_HB=1
done
HB_RC=1; HB_SENT=0
if [ "$NEED_HB" = "1" ]; then
    b_log ""
    b_head "GCM 心跳(MCS_HEARTBEAT / HEARTBEAT_NOW / GcmSenderProxy)"
    if b_heartbeat; then HB_RC=0; HB_SENT=1; fi
else
    HB_RC=0
fi

b_log ""
b_head "结果"
if [ "$HB_SENT" = "1" ]; then _hb=已发
elif [ "$NEED_HB" = "1" ]; then _hb=部分未确认
else _hb='未发(GMS 未检出或目标列表为空)'; fi
b_log "解除 stopped: $FIXED 个 · 失败: $FAILED 个 · 心跳: $_hb"
# persist fix summary for the read-only WebUI (see check.sh note)
if mkdir -p "$STATE_DIR" 2>/dev/null && [ -w "$STATE_DIR" ]; then
    printf '{"ts":"%s","kind":"fix","fixed":%s,"failed":%s,"heartbeat":%s}\n' \
        "$(date '+%F %T')" "$FIXED" "$FAILED" "$HB_SENT" \
        > "$STATE_DIR/last-fix.json" 2>/dev/null
fi
if [ "$FAILED" = "0" ]; then
    exit 0
fi
exit 2
