#!/bin/sh
# mochawrt :: install.sh
# Installs the Catppuccin-Mocha web panel and wires it into uhttpd WITHOUT
# touching the read-only squashfs root. Files go to a writable dir; uhttpd is
# configured via UCI (persists on ubifs). Works on normal OpenWrt AND on Xiaomi
# vendor/immutable forks (IPQ5424/IPQ9554/AX9000/BE7000/...).
#
# Usage:
#   sh install.sh [--port 8090] [--dest /opt/mochawrt]
#   sh -c "$(wget -qO- https://raw.githubusercontent.com/Sigmachan/mochawrt/main/install.sh)"
set -eu

REPO_TARBALL="https://github.com/Sigmachan/mochawrt/archive/refs/heads/main.tar.gz"
G='\033[35;1m'; Y='\033[33;1m'; N='\033[0m'
log(){ printf "${G}%s${N}\n" "$*"; }
warn(){ printf "${Y}[warn]${N} %s\n" "$*" >&2; }
die(){ printf '\033[31;1m[err]\033[0m %s\n' "$*" >&2; exit 1; }
fetch(){ if command -v curl >/dev/null 2>&1; then curl -fsSL -o "$2" "$1"
  elif command -v uclient-fetch >/dev/null 2>&1; then uclient-fetch -qO "$2" "$1"
  else wget -qO "$2" "$1"; fi; }

PORT=8090; DEST=""
while [ $# -gt 0 ]; do case "$1" in
    --port) PORT="$2"; shift;; --dest) DEST="$2"; shift;;
    *) warn "unknown option: $1";; esac; shift; done

_self="$(cd "$(dirname -- "$0" 2>/dev/null)" 2>/dev/null && pwd || true)"

# pick writable home (never squashfs root)
if [ -z "$DEST" ]; then
    if [ -d /opt ] && ( : > /opt/.mw 2>/dev/null ); then rm -f /opt/.mw; DEST=/opt/mochawrt
    elif [ -d /data ] && ( : > /data/.mw 2>/dev/null ); then rm -f /data/.mw; DEST=/data/mochawrt
    else DEST=/root/mochawrt; fi
fi
log "Install dir: $DEST (writable)"
mkdir -p "$DEST"

if [ -n "$_self" ] && [ -f "$_self/www/index.html" ]; then
    log "Copying from local clone..."
    cp -rf "$_self/." "$DEST/"
else
    log "Downloading mochawrt..."
    fetch "$REPO_TARBALL" /tmp/mochawrt.tgz || die "download failed"
    ( cd /tmp && tar xzf mochawrt.tgz )
    cp -rf /tmp/mochawrt-main/. "$DEST/"
    rm -rf /tmp/mochawrt.tgz /tmp/mochawrt-main
fi
chmod +x "$DEST/www/cgi-bin/mochawrt" 2>/dev/null || true
[ -f "$DEST/www/index.html" ] || die "panel files missing"

log "Configuring uhttpd instance 'mochawrt' on port $PORT ..."
command -v uhttpd >/dev/null 2>&1 || warn "uhttpd not found — install it (opkg install uhttpd) or panel won't serve"
uci -q delete uhttpd.mochawrt 2>/dev/null || true
uci set uhttpd.mochawrt=uhttpd
uci add_list uhttpd.mochawrt.listen_http="0.0.0.0:$PORT"
uci set uhttpd.mochawrt.home="$DEST/www"
uci set uhttpd.mochawrt.cgi_prefix="/cgi-bin"
uci set uhttpd.mochawrt.script_timeout="60"
uci set uhttpd.mochawrt.max_requests="6"
uci set uhttpd.mochawrt.no_dirlists="1"
uci commit uhttpd
[ -x /etc/init.d/uhttpd ] && /etc/init.d/uhttpd restart 2>/dev/null || true

LANIP="$(uci -q get network.lan.ipaddr 2>/dev/null || echo 192.168.1.1)"
log "Done. Open:  http://$LANIP:$PORT/"
warn "CGI runs as root with no auth — keep it LAN-only (default firewall blocks WAN)."
log "Remove: sh $DEST/uninstall.sh"
