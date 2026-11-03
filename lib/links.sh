#!/system/bin/sh
# Berry-FCM vivo/OriginOS quick deep links (ported from wp.smali):
#   autostart  → vivo 后台自启动管理(BgStartUpManagerActivity / com.iqoo.secure.BGSTARTUPMANAGER)
#   gmsnotif   → GMS 应用通知设置(OriginOS 常悄悄关掉 GMS 通知渠道)
#   bootid     → 打印当前 boot_count + 模块账本(调试用)
. "$(dirname "$0")/berry.sh" || exit 1

b_identity_guard || exit 1

case "$1" in
    autostart)
        if am start -n "com.vivo.permissionmanager/.activity.BgStartUpManagerActivity" >/dev/null 2>&1; then
            b_ok "已打开 vivo 后台自启动管理;若空白请手动到 设置→搜索「自启动」"
        elif am start -a "com.iqoo.secure.BGSTARTUPMANAGER" >/dev/null 2>&1; then
            b_ok "已打开 iQOO 后台启动管理"
        else
            b_warn "无法打开设置,请在系统设置中手动搜索「自启动」。"
            exit 1
        fi
        ;;
    gmsnotif)
        if am start -a "android.settings.APP_NOTIFICATION_SETTINGS" \
             --es "android.provider.extra.APP_PACKAGE" "$GMS" >/dev/null 2>&1; then
            b_ok "已打开 GMS 通知设置,请检查各渠道开关(尤其 GCM/Miscellaneous)"
        else
            b_warn "无法打开 GMS 通知设置"
            exit 1
        fi
        ;;
    bootid)
        echo "boot_count=$(b_boot_count)"
        [ -f "$STATE_DIR/boot_count" ] && echo "ledger=$(cat "$STATE_DIR/boot_count")" || echo "ledger=none"
        ls "$STATE_DIR" 2>/dev/null | grep '^recovered_' | sed 's/^recovered_/recovered: /'
        ;;
    *)
        echo "usage: sh lib/links.sh autostart|gmsnotif|bootid"
        exit 1
        ;;
esac
