#!/system/bin/sh
# Berry-FCM read-only status check.
# Output: human report + one machine-readable line "JSON: {...}" for the WebUI.
. "$(dirname "$0")/berry.sh" || exit 1

b_identity_guard || exit 1

# ---- [diag] device-truth lines (always on, keep compact) ----
# These exist because a 2026-11-03 field report showed the target loop
# silently no-op'ing (empty b_load_targets) while probe=1 — raw states here
# turn the next copied report into a definitive answer.
_ftn=0
if [ -s "$TARGETS_FILE" ]; then
    _ftn="$(grep -vE '^[[:space:]]*(#|$)' "$TARGETS_FILE" 2>/dev/null | grep -c .)"
    [ -z "$_ftn" ] && _ftn=0
fi
_fsz=none
[ -f "$TARGETS_FILE" ] && _fsz="$(wc -c < "$TARGETS_FILE" 2>/dev/null | tr -d ' ')"
b_log "[diag] moddir=$MODDIR"
b_log "[diag] targets_file 有效行=$_ftn/字节数=$_fsz · 生效目标=$(b_load_targets 2>/dev/null | grep -c .) 个"
b_log "[diag] cmd_path=$(cmd package path --user 0 "$GMS" 2>&1 | head -c 70 | tr '\n\r' '  ')"
b_log "[diag] pm_path=$(pm path --user 0 "$GMS" 2>&1 | head -c 70 | tr '\n\r' '  ')"
[ "$_ftn" = "0" ] && b_log "[diag] targets.txt 头部=$(head -c 60 "$TARGETS_FILE" 2>&1 | tr '\n\r\t' '   ')"

# ---- collect ----
GMS_OK=0; GMS_STOPPED=0; GCM_ALIVE=0; PERSIST=0; RECV=0; PROBE_OK=0
b_probe_ok && PROBE_OK=1
TARGET_JSON=""
TARGET_LINES=""
for pkg in $(b_load_targets); do
    if b_pkg_installed "$pkg"; then
        STOP=0; b_pkg_stopped "$pkg" && STOP=1
        if [ "$pkg" = "$GMS" ]; then
            GMS_OK=1; GMS_STOPPED=$STOP
            EN="$(b_pkg_enabled_state "$pkg")"
            RECV="$(b_gms_receiver_count)"
            b_gcm_service_alive && GCM_ALIVE=1
            b_gms_persistent_alive && PERSIST=1
            TARGET_LINES="${TARGET_LINES}GMS=$pkg|installed|stopped=$STOP|enabled=$EN|gcm=$([ $GCM_ALIVE = 1 ] && echo yes || echo on-demand)|persist=$([ $PERSIST = 1 ] && echo yes || echo no)|recv=$RECV
"
        else
            TARGET_JSON="${TARGET_JSON}{\"pkg\":\"$pkg\",\"installed\":1,\"stopped\":$STOP},"
            TARGET_LINES="${TARGET_LINES}APP=$pkg|installed|stopped=$STOP
"
        fi
    else
        if [ "$pkg" = "$GMS" ]; then
            TARGET_LINES="${TARGET_LINES}GMS=$pkg|NOT-INSTALLED
"
        else
            TARGET_JSON="${TARGET_JSON}{\"pkg\":\"$pkg\",\"installed\":0,\"stopped\":0},"
            TARGET_LINES="${TARGET_LINES}APP=$pkg|NOT-INSTALLED
"
        fi
    fi
done

# ---- human report ----
b_head "Berry-FCM 状态检测 $(date '+%F %T')"
if [ "$PROBE_OK" = "1" ]; then
    b_ok "探测通道: dumpsys 正常"
else
    b_warn "探测通道异常: dumpsys 未返回数据(系统繁忙或权限临时受限),以下「未安装」结论不可信,请稍后重测"
fi
printf '%s' "$TARGET_LINES" | while IFS='|' read -r name state extra1 extra2 extra3; do
    [ -z "$name" ] && continue
    if [ "$state" = "NOT-INSTALLED" ] && [ "$PROBE_OK" = "0" ]; then
        b_warn "$name 探测失败(命令无返回,非「未安装」)"
    elif [ "$state" = "NOT-INSTALLED" ]; then
        b_warn "$name 未安装"
    else
        if printf '%s' "$extra1" | grep -q 'stopped=1'; then
            b_warn "$name $state $extra1 $extra2 $extra3  ← stopped,待修复"
        else
            b_ok "$name $state $extra1 $extra2 $extra3"
        fi
    fi
done
b_log ""
b_log "说明: stopped=true = 被「强制停止」,该状态下 FCM/广播一律收不到;"
b_log "      GcmService 为按需服务,'on-demand' 属正常;推送主干看 persistent 进程"
b_log "      (persist=no) 与接收器数(recv=0)= 链路未建立,可发心跳唤醒。"

# ---- machine line + persisted report (read-only WebUI fallback) ----
# state/last-report.json is what the WebUI reads when the manager's JS bridge
# is dead (rushiranpise/Shizuku-Next release builds strip @JavascriptInterface
# via R8) — the page then renders this file over file:// XHR instead.
J="$(printf '{"probe":%s,"gms_installed":%s,"gms_stopped":%s,"gcm_service":%s,"gcm_persistent":%s,"receivers":%s,"targets":[%s]}' \
    "$PROBE_OK" "$GMS_OK" "$GMS_STOPPED" "$GCM_ALIVE" "$PERSIST" "$RECV" "$(printf '%s' "$TARGET_JSON" | sed 's/,$//')")"
if mkdir -p "$STATE_DIR" 2>/dev/null && [ -w "$STATE_DIR" ]; then
    printf '{"ts":"%s","kind":"check","json":%s}\n' \
        "$(date '+%F %T')" "$J" > "$STATE_DIR/last-report.json" 2>/dev/null
fi
printf 'JSON: %s\n' "$J"
