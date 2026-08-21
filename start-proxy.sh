#!/bin/sh

# Premávka z WireGuard klientov -> tun2socks -> SOCKS5/HTTP proxy (Egypt).
# Beží ako ENTRYPOINT kontajnera; na konci spustí pôvodnú wg-easy aplikáciu.
#
# POZOR na tun2socks v2.7.0:
#  - dlhé flagy len s DVOJITOU pomlčkou (pflag parser)
#  - --tun-post-up spúšťa príkaz BEZ shellu (shlex → exec) — preto cesta k skriptu

WG_SUBNET="${WG_SUBNET:-10.8.0.0/24}"   # musí sedieť s WG_DEFAULT_ADDRESS (10.8.0.x)
TUN_DEV="${TUN_DEV:-tun1}"
TUN_TABLE="${TUN_TABLE:-100}"

# 1. tun2socks s watchdogom: ak spadne (proxy nedostupná...), reštartuje sa.
#    Počas výpadku premávka klientov stojí (fail-closed) — nikdy neunikne mimo proxy.
#    Routing nastavuje /tun-post-up.sh — tun2socks ho spúšťa pri každom vytvorení tun,
#    takže po reštarte tun2socksu (znovuvytvorený tun1) sa pravidlá obnovia samé.
(
  while :; do
    tun2socks \
      --device "tun://$TUN_DEV" \
      --proxy "$PROXY_URL" \
      --loglevel info \
      --tun-post-up /tun-post-up.sh
    echo "tun2socks skončil — reštart o 3 s..." >&2
    sleep 3
  done
) &

# 2. Počkáme, kým tun2socks vytvorí zariadenie a post-up skript pridá routing
#    (pravidlo v policy routing A route v tabuľke).
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
  echo "Chyba: routovanie nevzniklo — skontroluj PROXY_URL a logy tun2socks." >&2
  exit 1
fi

# 3. Pôvodná wg-easy aplikácia (dumb-init ako PID 1, rovnaký CMD ako base obraz).
cd /app || exit 1
if [ -f server/index.mjs ]; then
  exec /usr/bin/dumb-init node server/index.mjs
else
  exec /usr/bin/dumb-init node server.js
fi
