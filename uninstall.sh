#!/bin/sh
# mochawrt :: uninstall.sh — remove the uhttpd panel instance and files.
set -eu
G='\033[35;1m'; N='\033[0m'; log(){ printf "${G}%s${N}\n" "$*"; }
KEEP=0; [ "${1:-}" = "--keep-files" ] && KEEP=1

log "Removing uhttpd instance 'mochawrt'..."
uci -q delete uhttpd.mochawrt 2>/dev/null || true
uci commit uhttpd
[ -x /etc/init.d/uhttpd ] && /etc/init.d/uhttpd restart 2>/dev/null || true

if [ "$KEEP" = 0 ]; then
    for d in /opt/mochawrt /data/mochawrt /root/mochawrt; do
        [ -d "$d" ] && { rm -rf "$d"; log "removed $d"; }
    done
fi
log "mochawrt removed."
