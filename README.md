# wg-easy + tun2socks — WireGuard clients via SOCKS5/HTTP proxy

Docker stack for a VPS: **wg-easy** (WireGuard server + web admin) extended with
**tun2socks**, which routes all WireGuard client traffic (e.g. Cudy WR300) through an
Egypt proxy.

```
router ──WireGuard (UDP 51820)──▶ VPS container ──policy routing──▶ tun2socks ──proxy──▶ Egypt proxy ──▶ internet
```

## Requirements

- VPS with Docker + Docker Compose (v2)
- Firewall: allow **UDP 51820** (TCP 51821 only if you expose the web admin publicly)
- An Egyptian proxy (address, port, username, password) — HTTP or SOCKS5
- Access to the internal registry `reg.kubov.link`

## Build & publish (on your dev machine)

```bash
# bump "version" in package.json, then:
pnpm docker:release    # build (linux/amd64) + push :version + :latest
```

Log in to the registry first: `docker login reg.kubov.link`

## Deploy on the VPS

```bash
# 1. Copy to the VPS: docker-compose.yml + .env (based on .env.example)
# 2. On the VPS:
docker compose pull
docker compose up -d
docker compose logs -f
```

## Web admin (51821)

For security the UI is bound to `127.0.0.1` only — connect via an SSH tunnel:

```bash
ssh -L 51821:localhost:51821 root@VPS_IP
# browser: http://localhost:51821
```

For public access, change the port mapping in `docker-compose.yml` to
`"51821:51821/tcp"` (use a strong password — the UI will be reachable by anyone).

## Router profile

1. Web admin → **New Client** (e.g. `Cudy-WR300`) → download the `.conf` file
2. Import the profile in the Cudy admin (WireGuard client)

## Verification (from a device behind the router)

```bash
# public IP = proxy exit
curl -s https://ipinfo.io/json

# Cloudflare exit node (colo should be in the Egypt region)
curl -s https://www.cloudflare.com/cdn-cgi/trace | grep -E 'ip|colo'

# DNS leak test: https://dnsleaktest.com — only Egyptian resolvers should appear
```

## Proxy country checker

`check-proxies.mjs` detects the country of each proxy in a list — the geo-IP request
goes **through** the proxy itself, so the result is the exit node's country.

```bash
# 1. Put proxies into proxies.txt (one per line: ip:port:user:pass)
# 2. Run:
pnpm proxies:check proxies.txt                     # auto-detect: HTTP first, then SOCKS5
pnpm proxies:check proxies.txt --proto http        # force protocol (http|socks5)
pnpm proxies:check proxies.txt --geo ip2location   # ip2location.io database (default: ip-api)
pnpm proxies:check proxies.txt --csv results.csv
```

Output: table (proxy, country, exit IP, protocol, latency) + summary by country.
Geo API: default **ip-api.com** (more accurate exit for hosting IPs — for some
providers ip2location only returns the IP's registration address); switch to
api.ip2location.io with `--geo ip2location` (1,000 queries/day without a key; free key
50K/month via env `IP2LOCATION_KEY=...`). `proxies.txt` is in `.gitignore` — never
commit credentials.

## How it works

- `start-proxy.sh` starts tun2socks (interface `tun1`) with a watchdog and adds policy
  routing: traffic from `10.8.0.0/24` (WG clients) goes to table 100 → `tun1` → proxy.
- Incoming WireGuard (UDP 51820) stays outside these rules — the tunnel is never broken.
- If the proxy dies, tun2socks restarts; meanwhile client traffic stops
  (fail-closed — no traffic ever leaks outside the proxy).

## Troubleshooting

```bash
docker exec wg-easy-proxy ip rule show
docker exec wg-easy-proxy ip route show table 100
```

- Client has no internet → check `PROXY_URL` in `.env`, container logs.
- `WG_SUBNET` (10.8.0.0/24) must match wg-easy's `WG_DEFAULT_ADDRESS` (10.8.0.x).
- Rollback: `docker compose down` — profiles persist in `wg-data/`.

## Structure

| File | Purpose |
|---|---|
| `docker-compose.yml` | service, ports, env (image from registry) |
| `Dockerfile` | wg-easy + iproute2 + tun2socks |
| `start-proxy.sh` | tun2socks + policy routing + wg-easy startup |
| `tun-post-up.sh` | idempotent routing, run by tun2socks on every TUN create |
| `package.json` | version + build/push/release scripts for the registry |
| `check-proxies.mjs` | proxy country checker (HTTP/SOCKS5) |
| `proxies.txt.example` | proxy list template (`.txt` is in .gitignore) |
| `.env.example` | secrets template (`.env` is in .gitignore) |
