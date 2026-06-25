#!/bin/sh
# mochawrt :: make-default.sh
# Make mochawrt the DEFAULT web UI on :80, keeping the vendor (Xiaomi/MiWiFi) UI
# reachable on :8080. Fully reversible (restore-default.sh). SSH stays up regardless.
#
# Two modes, auto-detected:
#   * nginx vendor front (Xiaomi IPQ): rewrites /etc/nginx/conf.d/80.conf to proxy
#     :80 -> mochawrt uhttpd (127.0.0.1:<port>). /etc is ramfs, so a cron guard in
#     /etc/crontabs (ubifs, persistent) re-applies it after every reboot.
#   * plain uhttpd: swaps listen ports (mochawrt->:80, vendor->:8080).
set -eu
G='\033[35;1m'; Y='\033[33;1m'; N='\033[0m'
log(){ printf "${G}%s${N}\n" "$*"; }; warn(){ printf "${Y}%s${N}\n" "$*"; }
D=/data/mochawrt
[ -d "$D" ] || D="$(cd "$(dirname "$0")" && pwd)"

PORT="$(uci -q get uhttpd.mochawrt.listen_http 2>/dev/null | tr ' ' '\n' | sed -n 's/.*:\([0-9]*\)$/\1/p' | head -n1)"
PORT="${PORT:-8090}"

if command -v nginx >/dev/null 2>&1 && [ -f /etc/nginx/conf.d/80.conf ]; then
    log "nginx vendor front detected — proxying :80 -> mochawrt (127.0.0.1:$PORT)"
    [ -f "$D/nginx-80.conf.orig" ] || cp /etc/nginx/conf.d/80.conf "$D/nginx-80.conf.orig"
    cat > "$D/nginx-80.conf.mocha" <<EOF
	# mochawrt default UI (managed by make-default.sh; revert: restore-default.sh)
	server {
		listen       80;
		listen       [::]:80;
		server_name  _;
		client_max_body_size 64M;
		location / {
			proxy_pass http://127.0.0.1:$PORT;
			proxy_http_version 1.1;
			proxy_set_header Host \$host;
			proxy_set_header X-Real-IP \$remote_addr;
			proxy_read_timeout 120s;
		}
	}
EOF
    cp "$D/nginx-80.conf.mocha" /etc/nginx/conf.d/80.conf
    nginx -s reload 2>/dev/null || /etc/init.d/nginx reload 2>/dev/null || /etc/init.d/nginx restart 2>/dev/null || true

    # persistence guard (ramfs /etc resets on boot; /etc/crontabs is ubifs)
    cat > "$D/nginx-default-guard.sh" <<EOF
#!/bin/sh
# re-assert mochawrt as default :80 after vendor regenerates nginx on boot
M="$D/nginx-80.conf.mocha"; T=/etc/nginx/conf.d/80.conf
[ -f "\$M" ] || exit 0
uci -q get uhttpd.mochawrt >/dev/null 2>&1 && { netstat -ln 2>/dev/null | grep -q ":$PORT " || /etc/init.d/uhttpd start >/dev/null 2>&1; }
if ! cmp -s "\$M" "\$T" 2>/dev/null; then cp "\$M" "\$T" && (nginx -s reload 2>/dev/null || /etc/init.d/nginx reload 2>/dev/null); fi
EOF
    chmod +x "$D/nginx-default-guard.sh"
    touch /etc/crontabs/root
    grep -vF "nginx-default-guard.sh" /etc/crontabs/root > /etc/crontabs/root.t 2>/dev/null || true
    mv /etc/crontabs/root.t /etc/crontabs/root 2>/dev/null || true
    echo "* * * * * sh $D/nginx-default-guard.sh" >> /etc/crontabs/root
    /etc/init.d/cron enable 2>/dev/null || true; /etc/init.d/cron restart 2>/dev/null || true

    LANIP="$(uci -q get network.lan.ipaddr 2>/dev/null || echo 192.168.31.1)"
    log "mochawrt is now DEFAULT:  http://$LANIP/"
    log "vendor (MiWiFi) UI:       http://$LANIP:8080/"
    warn "Revert:  sh $D/restore-default.sh"
else
    # plain uhttpd port swap
    uci -q get uhttpd.mochawrt >/dev/null 2>&1 || { echo "run install.sh first" >&2; exit 1; }
    [ -f "$D/.ports.orig" ] || {
        { echo "MAIN_HTTP=\"$(uci -q get uhttpd.main.listen_http)\""; echo "MAIN_HTTPS=\"$(uci -q get uhttpd.main.listen_https)\""; echo "MOCHA_HTTP=\"$(uci -q get uhttpd.mochawrt.listen_http)\""; } > "$D/.ports.orig"; }
    uci -q delete uhttpd.main.listen_http 2>/dev/null || true
    uci add_list uhttpd.main.listen_http="0.0.0.0:8080"; uci add_list uhttpd.main.listen_http="[::]:8080"
    uci -q delete uhttpd.mochawrt.listen_http 2>/dev/null || true
    uci add_list uhttpd.mochawrt.listen_http="0.0.0.0:80"; uci add_list uhttpd.mochawrt.listen_http="[::]:80"
    uci commit uhttpd; /etc/init.d/uhttpd restart 2>/dev/null || true
    log "mochawrt default on :80 (uhttpd); vendor on :8080. Revert: sh $D/restore-default.sh"
fi
