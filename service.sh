#!/system/bin/sh
# Berry-FCM Service: guarded one-shot recovery per Shizuku binder session,
# with a per-boot ledger (ported from the original's boot_count guard —
# "guarded one-shot recovery", one auto-recovery per package per boot).
# Gate note: only runs in Full access + Allow background actions
# (or Full Trust); Safe mode blocks it by design.
export MODDIR="${MODDIR:-$(cd "$(dirname "$0")" && pwd)}"
. "$MODDIR/lib/berry.sh" || exit 0   # service 必须安静,失败不抛错

b_identity_guard || exit 0

mkdir -p "$STATE_DIR"
BC="$(b_boot_count)"
[ -z "$BC" ] && BC=0
if [ ! -f "$STATE_DIR/boot_count" ] || [ "$(cat "$STATE_DIR/boot_count" 2>/dev/null)" != "$BC" ]; then
    printf '%s' "$BC" > "$STATE_DIR/boot_count"
    rm -f "$STATE_DIR"/recovered_* 2>/dev/null
    echo "[$(date '+%F %T')] new boot_count=$BC, ledger reset"
fi

FIXED=0
for pkg in $(b_load_targets); do
    [ -f "$STATE_DIR/recovered_$pkg" ] && continue
    b_pkg_installed "$pkg" || continue
    if b_pkg_stopped "$pkg"; then
        echo "[$(date '+%F %T')] $pkg stopped=true → one-shot unstop"
        if b_unstop "$pkg" && ! b_pkg_stopped "$pkg"; then
            FIXED=$((FIXED + 1))
            echo "[$(date '+%F %T')] $pkg unstopped (verified)"
        else
            echo "[$(date '+%F %T')] $pkg unstop failed/未确认,本轮放弃"
        fi
    fi
    # 无论是否修复都记账:每包每 boot 只自动干预一次,避免与系统互相打架
    : > "$STATE_DIR/recovered_$pkg"
done

if [ "$FIXED" -gt "0" ]; then
    for pkg in $(b_load_targets); do
        [ "$pkg" = "$GMS" ] && b_heartbeat >/dev/null 2>&1 && break
    done
    echo "[$(date '+%F %T')] heartbeat sent after recovery"
fi
echo "[$(date '+%F %T')] service done: fixed=$FIXED"

# refresh persisted report so the read-only WebUI (dead-bridge managers)
# reflects post-recovery state; read-only probes, quiet by design
sh "$MODDIR/lib/check.sh" >/dev/null 2>&1 || true
