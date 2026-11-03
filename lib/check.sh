#!/system/bin/sh
# Berry-FCM read-only status check.
# Output: human report + one machine-readable line "JSON: {...}" for the WebUI.
. "$(dirname "$0")/berry.sh" || exit 1

b_identity_guard || exit 1

# ---- collect ----
GMS_OK=0; GMS_STOPPED=0; GCM_ALIVE=0; RECV=0
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
            TARGET_LINES="${TARGET_LINES}GMS=$pkg|installed|stopped=$STOP|enabled=$EN|gcm=$([ $GCM_ALIVE = 1 ] && echo yes || echo no)|recv=$RECV
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
printf '%s' "$TARGET_LINES" | while IFS='|' read -r name state extra1 extra2 extra3; do
    [ -z "$name" ] && continue
    if [ "$state" = "NOT-INSTALLED" ]; then
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
b_log "      GcmService=no 或 已注册接收器=0 = GCM 链路未建立,可发送心跳唤醒。"

# ---- machine line ----
printf 'JSON: {"gms_installed":%s,"gms_stopped":%s,"gcm_service":%s,"receivers":%s,"targets":[%s]}\n' \
    "$GMS_OK" "$GMS_STOPPED" "$GCM_ALIVE" "$RECV" "$(printf '%s' "$TARGET_JSON" | sed 's/,$//')"
