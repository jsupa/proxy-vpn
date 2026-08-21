FROM ghcr.io/wg-easy/wg-easy:latest

# iproute2 = plnohodnotný `ip` (busybox v Alpine nevie `ip rule`/routovacie tabuľky),
# unzip + curl pre tun2socks
RUN apk add --no-cache iproute2 unzip curl

# tun2socks — tuneluje premávku WG klientov do SOCKS5 proxy
RUN curl -fL -o /tmp/tun2socks.zip \
      https://github.com/xjasonlyu/tun2socks/releases/download/v2.7.0/tun2socks-linux-amd64.zip \
    && unzip /tmp/tun2socks.zip -d /tmp/tun2socks \
    && mv /tmp/tun2socks/tun2socks-linux-amd64 /usr/local/bin/tun2socks \
    && chmod +x /usr/local/bin/tun2socks \
    && rm -rf /tmp/tun2socks.zip /tmp/tun2socks

COPY start-proxy.sh /start-proxy.sh
COPY tun-post-up.sh /tun-post-up.sh
RUN chmod +x /start-proxy.sh /tun-post-up.sh

# Štart cez náš skript (tun2socks + policy routing), wg-easy sa spustí na jeho konci
ENTRYPOINT ["/start-proxy.sh"]
