#!/system/bin/sh
# Berry-FCM target list manager (config/targets.txt).
#   usage: sh lib/targets.sh list|add <pkg>|remove <pkg>|reset
. "$(dirname "$0")/berry.sh" || exit 1

mkdir -p "$MODDIR/config"
[ -f "$TARGETS_FILE" ] || b_default_targets > "$TARGETS_FILE"

valid_pkg() {
    printf '%s' "$1" | grep -qE '^[A-Za-z][A-Za-z0-9._]+$'
}

case "$1" in
    list)
        echo "--- config/targets.txt ---"
        cat "$TARGETS_FILE"
        ;;
    add)
        pkg="$2"
        if ! valid_pkg "$pkg"; then
            echo "非法包名: $pkg"; exit 1
        fi
        grep -qxF "$pkg" "$TARGETS_FILE" && { echo "已在列表: $pkg"; exit 0; }
        echo "$pkg" >> "$TARGETS_FILE"
        echo "已添加: $pkg"
        cat "$TARGETS_FILE"
        ;;
    remove)
        pkg="$2"
        if ! valid_pkg "$pkg"; then echo "非法包名"; exit 1; fi
        if [ "$pkg" = "$GMS" ]; then
            echo "GMS 是核心目标,不可移除(心跳依赖它)"; exit 1
        fi
        tmp="$TARGETS_FILE.tmp"
        grep -vxF "$pkg" "$TARGETS_FILE" > "$tmp" && mv "$tmp" "$TARGETS_FILE"
        echo "已移除: $pkg"
        cat "$TARGETS_FILE"
        ;;
    reset)
        b_default_targets > "$TARGETS_FILE"
        echo "已重置为默认(仅 GMS)"
        ;;
    *)
        echo "usage: sh lib/targets.sh list|add <pkg>|remove <pkg>|reset"
        exit 1
        ;;
esac
