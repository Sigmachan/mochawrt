#!/bin/sh
# mochawrt :: restore-default.sh — revert make-default.sh (both modes).
set -eu
G='\033[35;1m'; N='\033[0m'; log(){ printf "${G}%s${N}\n" "$*"; }
D=/data/mochawrt
[ -d "$D" ] || D="$(cd "$(dirname "$0")" && pwd)"

# nginx mode revert
if [ -f "$D/nginx-80.conf.orig" ]; then
    # drop cron guard
    if [ -f /etc/crontabs/root ]; then
        grep -vF "nginx-default-guard.sh" /etc/crontabs/root > /etc/crontabs/root.t 2>/dev/null || true
        mv /etc/crontabs/root.t /etc/crontabs/root 2>/dev/null || true
        /etc/init.d/cron restart 2>/dev/null || true
    fi
    cp "$D/nginx-80.conf.orig" /etc/nginx/conf.d/80.conf
    nginx -s reload 2>/dev/null || /etc/init.d/nginx reload 2>/dev/null || /etc/init.d/nginx restart 2>/dev/null || true
    rm -f "$D/nginx-80.conf.orig" "$D/nginx-80.conf.mocha" "$D/nginx-default-guard.sh"
    LANIP="$(uci -q get network.lan.ipaddr 2>/dev/null || echo 192.168.31.1)"
    log "Reverted (nginx). Vendor UI back on http://$LANIP/  ; mochawrt on :8090"
    exit 0
fi

# uhttpd mode revert
MAIN_HTTP="0.0.0.0:80 [::]:80"; MAIN_HTTPS="0.0.0.0:443 [::]:443"; MOCHA_HTTP="0.0.0.0:8090"
[ -f "$D/.ports.orig" ] && . "$D/.ports.orig"
uci -q delete uhttpd.main.listen_http 2>/dev/null || true
for v in $MAIN_HTTP; do uci add_list uhttpd.main.listen_http="$v"; done
[ -n "${MAIN_HTTPS:-}" ] && { uci -q delete uhttpd.main.listen_https 2>/dev/null || true; for v in $MAIN_HTTPS; do uci add_list uhttpd.main.listen_https="$v"; done; }
uci -q delete uhttpd.mochawrt.listen_http 2>/dev/null || true
for v in $MOCHA_HTTP; do uci add_list uhttpd.mochawrt.listen_http="$v"; done
uci commit uhttpd; /etc/init.d/uhttpd restart 2>/dev/null || true; rm -f "$D/.ports.orig"
log "Reverted (uhttpd)."
