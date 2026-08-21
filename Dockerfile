FROM ghcr.io/wg-easy/wg-easy:latest

# iproute2 = full-featured `ip` (Alpine's busybox lacks `ip rule`/routing tables),
# unzip + curl for tun2socks
RUN apk add --no-cache iproute2 unzip curl

# tun2socks — tunnels WG client traffic into the proxy
RUN curl -fL -o /tmp/tun2socks.zip \
      https://github.com/xjasonlyu/tun2socks/releases/download/v2.7.0/tun2socks-linux-amd64.zip \
    && unzip /tmp/tun2socks.zip -d /tmp/tun2socks \
    && mv /tmp/tun2socks/tun2socks-linux-amd64 /usr/local/bin/tun2socks \
    && chmod +x /usr/local/bin/tun2socks \
    && rm -rf /tmp/tun2socks.zip /tmp/tun2socks

COPY start-proxy.sh /start-proxy.sh
COPY tun-post-up.sh /tun-post-up.sh
RUN chmod +x /start-proxy.sh /tun-post-up.sh

# Start via our script (tun2socks + policy routing); wg-easy starts at its end
ENTRYPOINT ["/start-proxy.sh"]
