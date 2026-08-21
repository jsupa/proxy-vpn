#!/bin/sh
# Spúšťa tun2socks po vytvorení TUN zariadenia (--tun-post-up).
# tun2socks spúšťa príkaz BEZ shellu (shlex → exec), preto cesta k skriptu so shebangom.
# Idempotentné (del+add / replace) — pri reštarte tun2socksu sa tun1 znovuvytvorí
# a pravidlá sa obnovia nanovo.

# chyby presmerujeme na stderr PID 1 (docker logs) — tun2socks stderr zahadzuje
if [ -w /proc/1/fd/2 ]; then
  exec 2>/proc/1/fd/2
fi

WG_SUBNET="${WG_SUBNET:-10.8.0.0/24}"   # musí sedieť s WG_DEFAULT_ADDRESS (10.8.0.x)
TUN_DEV="${TUN_DEV:-tun1}"
TUN_TABLE="${TUN_TABLE:-100}"

ip link set "$TUN_DEV" up
ip rule del pref 50 >/dev/null 2>&1
ip rule add pref 50 to "$WG_SUBNET" lookup main
ip rule del pref 100 >/dev/null 2>&1
ip rule add pref 100 from "$WG_SUBNET" lookup "$TUN_TABLE"
ip route replace default dev "$TUN_DEV" table "$TUN_TABLE"
