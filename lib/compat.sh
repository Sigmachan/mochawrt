# shellcheck shell=ash
# mochawrt :: lib/compat.sh
# Xiaomi (and generic OpenWrt) compatibility layer.
#
# Different Xiaomi routers — and the vendor "OpenWrt fork" firmwares — disagree
# about almost everything: where the thermal sensor lives, what the Wi-Fi netdev
# is called, whether `ubus`/`iwinfo` exist, which iface is WAN, etc. This file
# detects the device and exposes ONE stable API the CGI uses, so the UI behaves
# the same on an AX3000T, an AX9000, a BE7000 or an IPQ5424 RDP466 board.
#
# Public API (all echo a value, never fail hard):
#   compat_model            human model string
#   compat_board            board_name (sysinfo)
#   compat_soc              best-effort SoC family
#   compat_profile          matched profile id (e.g. xiaomi-ipq, xiaomi-filogic, generic)
#   compat_vendor           1 if vendor (immutable) fork, else 0
#   compat_have ubus|iwinfo|iw|ip|uci   1/0 capability probe
#   compat_temp_milli       CPU temperature in millidegrees (or "")
#   compat_wifi_ifaces      space-separated wifi netdevs (phy/vif)
#   compat_radios           space-separated ubus wifi device names (radio0 ...)
#   compat_wan_iface        L3 WAN interface name (uci/heuristic)
#   compat_lan_iface        L3 LAN interface name
#   compat_leases_file      dhcp leases path

# ---- capability probes ------------------------------------------------------
_has() { command -v "$1" >/dev/null 2>&1; }
compat_have() {
    case "$1" in
        ubus)   _has ubus   && echo 1 || echo 0 ;;
        iwinfo) _has iwinfo && echo 1 || echo 0 ;;
        iw)     _has iw     && echo 1 || echo 0 ;;
        ip)     _has ip     && echo 1 || echo 0 ;;
        uci)    _has uci    && echo 1 || echo 0 ;;
        *)      echo 0 ;;
    esac
}

# ---- identity ---------------------------------------------------------------
compat_model() {
    [ -r /tmp/sysinfo/model ] && { cat /tmp/sysinfo/model; return; }
    if _has ubus; then ubus call system board 2>/dev/null | sed -n 's/.*"model": *"\([^"]*\)".*/\1/p' | head -n1 && return; fi
    [ -r /proc/device-tree/model ] && tr -d '\000' < /proc/device-tree/model && return
    echo "Unknown router"
}
compat_board() {
    [ -r /tmp/sysinfo/board_name ] && { cat /tmp/sysinfo/board_name; return; }
    _has ubus && ubus call system board 2>/dev/null | sed -n 's/.*"board_name": *"\([^"]*\)".*/\1/p' | head -n1
}

# SoC family from board/model/cpuinfo
compat_soc() {
    _b="$(compat_board) $(compat_model)"
    case "$_b" in
        *ipq5424*|*rdp466*|*RDP466*) echo "Qualcomm IPQ5424 (WiFi-7)";;
        *ipq9554*|*be7000*|*BE7000*) echo "Qualcomm IPQ9554 (WiFi-7)";;
        *ipq807*|*ax9000*|*AX9000*)  echo "Qualcomm IPQ807x";;
        *ipq60*|*ax6*|*AX6*)         echo "Qualcomm IPQ60xx";;
        *filogic*|*mt7981*|*mt7986*|*be3600*|*be5000*|*7981*) echo "MediaTek Filogic";;
        *mt7621*)                    echo "MediaTek MT7621";;
        *)
            _cpu=""
            [ -r /proc/cpuinfo ] && _cpu="$(sed -n 's/.*[Mm]odel name[^:]*:[[:space:]]*\(.*\)/\1/p;s/.*Hardware[^:]*:[[:space:]]*\(.*\)/\1/p' /proc/cpuinfo | head -n1)"
            echo "${_cpu:-unknown SoC}" ;;
    esac
}

# profile id used to pick code paths
compat_profile() {
    _b="$(compat_board) $(compat_model)"
    case "$_b" in
        *ipq5424*|*rdp466*|*RDP466*|*ipq9554*|*be7000*|*BE7000*) echo "xiaomi-ipq-wifi7";;
        *ipq807*|*ax9000*|*AX9000*|*ipq60*|*ax6*|*AX6*)          echo "xiaomi-ipq";;
        *filogic*|*mt7981*|*mt7986*|*7981*|*be3600*|*be5000*)    echo "xiaomi-filogic";;
        *[Xx]iaomi*|*[Rr]edmi*|*[Mm]i\ *|*Routerich*)            echo "xiaomi-generic";;
        *) echo "generic";;
    esac
}

# vendor (immutable) fork? read-only root + Xiaomi profile
compat_vendor() {
    _p="$(compat_profile)"
    case "$_p" in xiaomi-*) ;; *) echo 0; return;; esac
    if ( : > /usr/lib/.mw 2>/dev/null ); then rm -f /usr/lib/.mw; echo 0; else echo 1; fi
}

# ---- thermal ----------------------------------------------------------------
compat_temp_milli() {
    # try the hottest cpu-ish thermal zone, then hwmon
    for z in /sys/class/thermal/thermal_zone*; do
        [ -r "$z/temp" ] || continue
        _t=$(cat "$z/temp" 2>/dev/null)
        case "$_t" in ''|*[!0-9]*) continue;; esac
        echo "$_t"; return
    done
    for h in /sys/class/hwmon/hwmon*/temp1_input; do
        [ -r "$h" ] && { cat "$h"; return; }
    done
    echo ""
}

# ---- wifi -------------------------------------------------------------------
compat_radios() {
    if _has ubus; then
        ubus call network.wireless status 2>/dev/null \
            | sed -n 's/^[[:space:]]*"\(radio[0-9]\)": {/\1/p' | tr '\n' ' '
    fi
}
compat_wifi_ifaces() {
    if _has iw; then iw dev 2>/dev/null | sed -n 's/.*Interface \(.*\)/\1/p' | tr '\n' ' '; return; fi
    # fallback: netdevs that look wireless
    for d in /sys/class/net/*; do
        n=$(basename "$d")
        [ -e "$d/phy80211" ] && printf '%s ' "$n"
        case "$n" in wlan*|ath*|ra*|wl*|phy*-ap*) printf '%s ' "$n";; esac
    done
}

# ---- L3 interfaces ----------------------------------------------------------
compat_wan_iface() {
    if _has uci; then
        for c in wan wan6 wwan; do uci -q get "network.$c" >/dev/null 2>&1 && { echo "$c"; return; }; done
    fi
    if _has ubus; then
        ubus call network.interface dump 2>/dev/null \
            | sed -n 's/.*"interface": *"\([^"]*\)".*/\1/p' | grep -m1 -E '^wan'
        return
    fi
    echo wan
}
compat_lan_iface() {
    if _has uci && uci -q get network.lan >/dev/null 2>&1; then echo lan; return; fi
    echo lan
}

compat_leases_file() {
    for f in /tmp/dhcp.leases /var/dhcp.leases /tmp/dnsmasq.leases; do
        [ -r "$f" ] && { echo "$f"; return; }
    done
    echo /tmp/dhcp.leases
}
