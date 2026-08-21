#!/bin/sh
# Runs after tun2socks creates the TUN device (--tun-post-up).
# tun2socks executes the command WITHOUT a shell (shlex -> exec), hence a script path with shebang.
# Idempotent (del+add / replace) — when tun2socks restarts, tun1 is recreated
# and the rules are restored from scratch.

# forward errors to PID 1's stderr (docker logs) — tun2socks discards its own stderr
if [ -w /proc/1/fd/2 ]; then
  exec 2>/proc/1/fd/2
fi

WG_SUBNET="${WG_SUBNET:-10.8.0.0/24}"   # must match WG_DEFAULT_ADDRESS (10.8.0.x)
TUN_DEV="${TUN_DEV:-tun1}"
TUN_TABLE="${TUN_TABLE:-100}"

ip link set "$TUN_DEV" up
ip rule del pref 50 >/dev/null 2>&1
ip rule add pref 50 to "$WG_SUBNET" lookup main
ip rule del pref 100 >/dev/null 2>&1
ip rule add pref 100 from "$WG_SUBNET" lookup "$TUN_TABLE"
ip route replace default dev "$TUN_DEV" table "$TUN_TABLE"
