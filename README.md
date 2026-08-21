# wg-easy + tun2socks — WireGuard klienti cez SOCKS5 proxy

Docker stack pre VPS: **wg-easy** (WireGuard server + web admin) doplnený o **tun2socks**,
ktorý presmeruje všetku premávku WG klientov (napr. Cudy WR300) cez SOCKS5 proxy v Egypte.

```
router ──WireGuard (UDP 51820)──▶ VPS kontajner ──policy routing──▶ tun2socks ──SOCKS5──▶ Egypt proxy ──▶ internet
```

## Požiadavky

- VPS s Docker + Docker Compose (v2)
- Firewall: povolený **UDP 51820** (TCP 51821 len ak vystavíš web admin verejne)
- SOCKS5 proxy v Egypte (adresa, port, meno, heslo)
- Prístup do interného registry `reg.kubov.link`

## Build a publish (na vývojovom stroji)

```bash
# bumpni "version" v package.json, potom:
pnpm docker:release    # build (linux/amd64) + push :verzia + :latest
```

Pri prvom použití sa prihlás do registry: `docker login reg.kubov.link`

## Nasadenie na VPS

```bash
# 1. Skopíruj na VPS: docker-compose.yml + .env (z .env.example)
# 2. Na VPS:
docker compose pull
docker compose up -d
docker compose logs -f
```

## Web admin (51821)

Z bezpečnostných dôvodov je UI naviazané len na `127.0.0.1` — pripoj sa cez SSH tunel:

```bash
ssh -L 51821:localhost:51821 root@TVOJA_VPS_IP
# prehliadač: http://localhost:51821
```

Ak chceš verejný prístup, zmeň v `docker-compose.yml` port na `"51821:51821/tcp"`
(maj silné heslo — UI bude dostupné komukoľvek na internete).

## Profil pre router

1. Web admin → **New Client** (napr. `Cudy-WR300`) → stiahni `.conf`
2. Importuj profil v administrácii Cudy (WireGuard klient)

## Verifikácia (zo zariadenia za routerom)

```bash
# verejná IP = Egypt proxy
curl -s https://ipinfo.io/json

# Cloudflare exit node (colo by malo byť v regióne Egypta)
curl -s https://www.cloudflare.com/cdn-cgi/trace | grep -E 'ip|colo'

# DNS leak test: https://dnsleaktest.com — mali by sa objaviť len egyptské resolvery
```

## Kontrola krajiny proxy

`check-proxies.mjs` zistí krajinu každého proxy zo zoznamu — geo-IP dotaz ide **cez**
samotný proxy, takže výsledok je krajina exit uzla.

```bash
# 1. Ulož proxy do proxies.txt (jeden na riadok: ip:port:user:pass)
# 2. Spusti:
pnpm proxies:check proxies.txt                 # auto-detect: najprv HTTP, potom SOCKS5
pnpm proxies:check proxies.txt --proto http    # vynútený protokol (http|socks5)
pnpm proxies:check proxies.txt --csv vysledky.csv
```

Výstup: tabuľka (proxy, krajina, exit IP, protokol, čas odozvy) + zhrnutie podľa krajín.
Geo API: primárne ip-api.com, fallback ipinfo.io. `proxies.txt` je v `.gitignore` —
credentialy necommitovať.

## Ako to funguje

- `start-proxy.sh` spustí tun2socks (rozhranie `tun1`) + watchdog a pridá policy routing:
  premávka zo `10.8.0.0/24` (WG klienti) ide do tabuľky 100 → `tun1` → SOCKS5 proxy.
- Prichádzajúci WireGuard (UDP 51820) zostáva mimo týchto pravidiel — tunel sa nepreruší.
- Ak proxy spadne, tun2socks sa reštartuje; medzitým premávka klientov stojí
  (fail-closed — žiadny leak mimo proxy).

## Troubleshooting

```bash
docker compose exec wg-easy-proxy ip rule show
docker compose exec wg-easy-proxy ip route show table 100
```

- Klient nemá internet → skontroluj `PROXY_URL` v `.env`, logy kontajnera.
- `WG_SUBNET` (10.8.0.0/24) musí sedieť s `WG_DEFAULT_ADDRESS` wg-easy (10.8.0.x).
- Rollback: `docker compose down` — profily zostávajú vo `wg-data/`.

## Štruktúra

| Súbor | Účel |
|---|---|
| `docker-compose.yml` | služba, porty, env (obraz z registry) |
| `Dockerfile` | wg-easy + iproute2 + tun2socks |
| `start-proxy.sh` | tun2socks + policy routing + štart wg-easy |
| `package.json` | verzia + build/push/release skripty do registry |
| `check-proxies.mjs` | zistí krajinu proxy zo zoznamu (HTTP/SOCKS5) |
| `proxies.txt.example` | šablóna zoznamu proxy (`.txt` je v .gitignore) |
| `.env.example` | šablóna tajomstiev (`.env` je v .gitignore) |
