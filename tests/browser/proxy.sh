#!/bin/bash
# Fronts lab ports the way Killercoda's traffic proxy does: one HTTPS hostname per
# port, and a fresh X-Forwarded-For on every request. Usage: proxy.sh 8080 8025 ...
set -e
conf=/opt/kcproxy/Caddyfile
mkdir -p /opt/kcproxy
printf '{\n  http_port 18080\n  https_port 443\n  auto_https disable_redirects\n}\n' > $conf
for p in "$@"; do
  grep -q " lab-$p.kc.test" /etc/hosts || echo "127.0.0.1 lab-$p.kc.test" >> /etc/hosts
  cat >> $conf <<EOC
lab-$p.kc.test {
  tls internal
  reverse_proxy 127.0.0.1:$p {
    header_up X-Forwarded-For {http.request.uuid}
  }
}
EOC
done
docker rm -f kcproxy 2>/dev/null || true
docker run -d --name kcproxy --network host -v /opt/kcproxy:/etc/caddy caddy:2.8.4
for i in $(seq 1 30); do curl -sk -o /dev/null https://lab-$1.kc.test/ && exit 0; sleep 1; done
echo "proxy did not come up"; docker logs kcproxy; exit 1
