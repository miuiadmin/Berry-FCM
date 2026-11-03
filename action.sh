#!/system/bin/sh
# Berry-FCM Action: full check → fix → post-verify, streaming report.
# Runs from the module card Action button (output dialog + logs/action-last.log).
export MODDIR="${MODDIR:-$(cd "$(dirname "$0")" && pwd)}"
. "$MODDIR/lib/berry.sh" || exit 1

printf '\033[1m\033[35m'
cat <<'EOF'
  ____                     __  ________
 / __ \_______  _________ _/  |/  _/ __ \
/ /_/ / ___/ / / / ___/ _ `/ /|// // / / /
\____/_/  / /_/ (__  )  _/ /|__/ // /_/ /
     /___/\__,_/____/_/ /_/|_/___/\____/  FCM Guardian
EOF
printf '\033[0m\n'
b_log "module=$SHIZUKU_MODULE_ID mode=$SHIZUKU_MODULE_MODE trusted=$SHIZUKU_MODULE_TRUSTED"
b_identity_guard || exit 1
b_log "uid=2000(shell) ✓ · boot_count=$(b_boot_count) · 目标数=$(b_load_targets | wc -l | tr -d ' ')"

echo ""
sh "$MODDIR/lib/check.sh" || exit 1

echo ""
sh "$MODDIR/lib/fix.sh"; rc=$?

echo ""
b_head "修复后复检"
sh "$MODDIR/lib/check.sh" | grep -E 'JSON:|stopped=|\[x\]|\[!\]' || true

exit $rc
