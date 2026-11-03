#!/system/bin/sh
# Berry-FCM shared library — ported from OriginOS FCM Guardian privileged logic
# (io.github.originosfcmguardian, smali-analyzed 2026-11-03).
# All privileged operations here mirror the original's allowlist:
#   /system/bin/{am,cmd,getprop,id,settings} + dumpsys (read-only probes)
# Identity contract is identical: shell uid 2000 ONLY. Root is rejected on
# purpose (same as GuardianUserService "UserService requires shell UID 2000").

GMS="com.google.android.gms"
GCM_SERVICE_CMP="com.google.android.gms/.gcm.GcmService"
GCM_SENDER_PROXY_CMP="com.google.android.gms/.gcm.GcmSenderProxy"
ACT_MCS_HEARTBEAT="com.google.android.intent.action.MCS_HEARTBEAT"
ACT_HEARTBEAT_NOW="com.google.android.gms.gcm.ACTION_HEARTBEAT_NOW"
ACT_GCM_SEND="com.google.android.gcm.intent.SEND"

MODDIR="${MODDIR:-$(cd "$(dirname "$0")/.." && pwd)}"
TARGETS_FILE="$MODDIR/config/targets.txt"
STATE_DIR="$MODDIR/state"
FIX_BUDGET="${FIX_BUDGET:-10}"

# --- output helpers -------------------------------------------------------
b_log()  { printf '%s\n' "$*"; }
b_err()  { printf '\033[31m[x]\033[0m %s\n' "$*" >&2; }
b_ok()   { printf '\033[32m[+]\033[0m %s\n' "$*"; }
b_warn() { printf '\033[33m[!]\033[0m %s\n' "$*"; }
b_head() { printf '\033[1m== %s ==\033[0m\n' "$*"; }

# --- identity guard (parity: reject everything except uid 2000) -----------
b_identity_guard() {
    _uid="$(id -u 2>/dev/null)"
    if [ "$_uid" != "2000" ]; then
        b_err "uid=$_uid != 2000(shell)。Berry-FCM 只在 Shizuku(ADB)身份下运行,root 与其他身份一律拒绝(与原版一致)。"
        return 1
    fi
    return 0
}

# --- targets --------------------------------------------------------------
b_default_targets() { printf '%s\n' "$GMS"; }
b_load_targets() {
    if [ -s "$TARGETS_FILE" ]; then
        _list="$(grep -vE '^[[:space:]]*(#|$)' "$TARGETS_FILE" 2>/dev/null)"
        if [ -n "$_list" ]; then
            printf '%s\n' "$_list"
            return 0
        fi
        # pathological: file exists with bytes but zero valid package lines
        # (observed in the wild 2026-11-03: every probe reported nothing and
        # the loop silently no-op'd). GMS protection must never silently die
        # on a config glitch — fall back to defaults.
        b_default_targets
        return 0
    fi
    b_default_targets
}

# --- probes (read-only, all ported from the original's builders) ----------
# installed: cmd package path (original: e.smali probe) → pm path → dumpsys
# package dump. A transient cmd/binder hiccup (or a dead `cmd` service with a
# live dumpsys — observed in the wild 2026-11-03 on vivo/Android 17) must not
# read as "not installed".
b_pkg_installed() {
    _pkg="$1"
    [ -n "$(cmd package path --user 0 "$_pkg" 2>/dev/null)" ] && return 0
    [ -n "$(pm path --user 0 "$_pkg" 2>/dev/null)" ] && return 0
    dumpsys -t 3 package "$_pkg" 2>/dev/null | grep -q 'Package \[' && return 0
    return 1
}

# probe channel health: is dumpsys actually answering with a real dump?
# (error banners like "Unable to find service" print on stdout — non-empty
# output alone once counted as "probe ok", a false positive)
b_probe_ok() {
    _o="$(dumpsys -t 3 package "$GMS" 2>/dev/null | head -n 5)"
    [ -n "$_o" ] || return 1
    case "$_o" in
        *[Uu]nable*|*[Dd]enial*|*[Ee]xception*|*[Ee]rror*|*"not found"*|*"No service"*|*"can't find"*) return 1 ;;
    esac
    return 0
}

# stopped: dumpsys -t 3 package <pkg> -> "User 0: ... stopped=true"  (ie0.smali)
b_pkg_stopped() {
    _pkg="$1"
    dumpsys -t 3 package "$_pkg" 2>/dev/null | grep -q 'User 0:.*stopped=true'
}

# enabled= raw value on the User 0 line (0=default 1=enabled 2/3=disabled)
b_pkg_enabled_state() {
    _pkg="$1"
    _line="$(dumpsys -t 3 package "$_pkg" 2>/dev/null | grep 'User 0:' | head -n 1)"
    _val="$(printf '%s\n' "$_line" | sed -n 's/.*enabled=\([0-9]*\).*/\1/p')"
    [ -n "$_val" ] && printf '%s' "$_val" || printf 'unknown'
}

# GcmService liveness (tc2.smali: dumpsys -t 2 activity service <cmp>)
b_gcm_service_alive() {
    dumpsys -t 2 activity service "$GCM_SERVICE_CMP" 2>/dev/null | grep -q 'Service record'
}

# GMS persistent process (com.google.android.gms.persistent) is the real push
# backbone — it hosts the MCS long connection to mtalk.google.com:5228.
# GcmService itself is on-demand: "not running" is normal on an idle device
# and was a misleading health signal (original Guardian's rough edge).
b_gms_persistent_alive() {
    [ -n "$(pidof com.google.android.gms.persistent 2>/dev/null)" ] && return 0
    ps -A 2>/dev/null | grep -q '[c]om\.google\.android\.gms\.persistent'
}

# MCS long-connection ground truth (v1.0.10): is there an ESTABLISHED TCP
# connection to remote port 5228 (0x1484) — the GCM endpoint mtalk.google.com?
# More decisive than the process-name probe: if the connection is up, push
# works no matter which process holds it; if it is down behind the GFW, no
# amount of heartbeats will raise it (GMS traffic must be proxied).
# Echoes 1 = connected, 0 = none found, -1 = /proc/net unreadable (unknown).
# /proc/net/tcp fields: "sl: local rem st ..." — rem ends ":1484", st 01 = ESTABLISHED.
b_mcs_state() {
    _seen=0
    for _f in /proc/net/tcp /proc/net/tcp6; do
        if [ -r "$_f" ]; then
            _seen=1
            grep -qi ':1484 01 ' "$_f" 2>/dev/null && { echo 1; return; }
        fi
    done
    [ "$_seen" = "1" ] && echo 0 || echo -1
}

# GMS registered receiver count (fe0.smali ReceiverList regex on
# dumpsys -t 2 activity broadcasts — receiver alive = push stack alive)
b_gms_receiver_count() {
    dumpsys -t 2 activity broadcasts 2>/dev/null | grep -c 'ReceiverList{.*com\.google\.android\.gms/'
}

# boot ledger (rr2.smali: settings get global boot_count)
b_boot_count() { settings get global boot_count 2>/dev/null | tr -d ' \r\n'; }

# --- repairs (write path) --------------------------------------------------
# capability probe (e.smali): does this Android have "cmd package unstop"?
b_unstop_supported() {
    cmd package unstop 2>&1 | grep -qF 'unstop [--user USER_ID] PACKAGE'
}

# unstop (y11.smali modern path): cmd package unstop --user 0 <pkg>
b_unstop() {
    _pkg="$1"
    if ! b_unstop_supported; then
        b_err "此 Android 无 cmd package unstop(需 13+);legacy app_process 通道不可移植,跳过"
        return 1
    fi
    cmd package unstop --user 0 "$_pkg" >/dev/null 2>&1
}

# heartbeat (sp0/bg0/fe0.smali): three broadcasts, verified against
# "Broadcast completed: result=0" exactly like the original validators.
b_heartbeat() {
    _rc=0
    for _spec in "-a $ACT_MCS_HEARTBEAT -p $GMS" \
                 "-a $ACT_HEARTBEAT_NOW -p $GMS" \
                 "-a $ACT_GCM_SEND -n $GCM_SENDER_PROXY_CMP"; do
        # shellcheck disable=SC2086
        _out="$(am broadcast --user 0 $_spec 2>&1)"
        if printf '%s' "$_out" | grep -q 'Broadcast completed: result=0'; then
            b_ok "heartbeat ok: $_spec"
        else
            b_warn "heartbeat 未确认: $_spec"
            printf '%s\n' "$_out" | sed 's/^/    /' | head -n 6
            _rc=1
        fi
    done
    return $_rc
}
