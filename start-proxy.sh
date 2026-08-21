#!/bin/sh

# WireGuard client traffic -> tun2socks -> SOCKS5/HTTP proxy (Egypt).
# Runs as the container ENTRYPOINT; at the end it starts the original wg-easy app.
#
# NOTE for tun2socks v2.7.0:
#  - long flags only with DOUBLE dashes (pflag parser)
#  - --tun-post-up runs the command WITHOUT a shell (shlex -> exec) — hence a script path

WG_SUBNET="${WG_SUBNET:-10.8.0.0/24}"   # must match WG_DEFAULT_ADDRESS (10.8.0.x)
TUN_DEV="${TUN_DEV:-tun1}"
TUN_TABLE="${TUN_TABLE:-100}"

# 1. tun2socks with a watchdog: if it dies (proxy unreachable...), it restarts.
#    During the outage client traffic stops (fail-closed) — never leaks outside the proxy.
#    Routing is set up by /tun-post-up.sh — tun2socks runs it on every TUN creation,
#    so after a tun2socks restart (recreated tun1) the rules come back automatically.
(
  while :; do
    tun2socks \
      --device "tun://$TUN_DEV" \
      --proxy "$PROXY_URL" \
      --loglevel info \
      --tun-post-up /tun-post-up.sh
    echo "tun2socks exited — restarting in 3 s..." >&2
    sleep 3
  done
) &

# 2. Wait until tun2socks creates the device and the post-up script adds the routing
#    (policy routing rule AND route in the table).
i=0
while [ "$i" -lt 30 ]; do
  if ip rule show | grep -q "from $WG_SUBNET" \
     && ip route show table "$TUN_TABLE" | grep -q default; then
    break
  fi
  sleep 1
  i=$((i + 1))
done
if ! ip rule show | grep -q "from $WG_SUBNET" \
   || ! ip route show table "$TUN_TABLE" | grep -q default; then
  echo "Error: routing was not set up — check PROXY_URL and tun2socks logs." >&2
  exit 1
fi

# 3. Original wg-easy app (dumb-init as PID 1, same CMD as the base image).
cd /app || exit 1
if [ -f server/index.mjs ]; then
  exec /usr/bin/dumb-init node server/index.mjs
else
  exec /usr/bin/dumb-init node server.js
fi
