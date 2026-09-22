#!/usr/bin/env bash
# Runs as root on the VM from /tmp/deployment-csvm, after up.sh has put the secrets in place. Safe to rerun: the
# certificate, the database and csctl's state are kept.
set -euo pipefail
cd "$(dirname "$0")"
node=v22.23.2

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends nginx certbot python3-certbot-nginx postgresql iptables rsync curl xz-utils >/dev/null
if [ "$(/opt/node/bin/node --version 2>/dev/null)" != "$node" ]; then
    rm -rf /opt/node && mkdir /opt/node
    curl -fsSL "https://nodejs.org/dist/$node/node-$node-linux-x64.tar.xz" | tar -xJ -C /opt/node --strip-components=1
fi

# One database with a schema per service. Both services run as ubuntu over the local socket, so no password exists.
systemctl enable --now --quiet postgresql
sudo -u postgres psql -q -v ON_ERROR_STOP=1 <<'SQL'
SELECT 'CREATE ROLE ubuntu LOGIN' WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'ubuntu') \gexec
SELECT 'CREATE DATABASE cybershuttle OWNER ubuntu' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'cybershuttle') \gexec
\connect cybershuttle
CREATE SCHEMA IF NOT EXISTS custos AUTHORIZATION ubuntu;
CREATE SCHEMA IF NOT EXISTS csctl AUTHORIZATION ubuntu;
SQL

[ -e /etc/letsencrypt/live/csvm ] || certbot certonly --nginx --non-interactive --agree-tos --register-unsafely-without-email \
    --cert-name csvm -d jupyter.cybershuttle.org -d jupyterapi.cybershuttle.org -d custos.cybershuttle.org
cp -r root/. /
nginx -t
systemctl reload nginx

install -m 755 csctl custos-server /usr/local/bin/
rsync -a --delete site/ /var/www/jupyter.cybershuttle.org/
rsync -a --delete --exclude node_modules --exclude .next --exclude .env.local web/ /opt/custos/web/
chown -R ubuntu:ubuntu /opt/custos
sudo -u ubuntu -H env PATH="/opt/node/bin:$PATH" COREPACK_ENABLE_DOWNLOAD_PROMPT=0 \
    bash -c 'cd /opt/custos/web && corepack pnpm install --frozen-lockfile && corepack pnpm build'

systemctl daemon-reload
systemctl enable --quiet custos custos-portal csctl
systemctl restart custos custos-portal csctl

for url in https://jupyter.cybershuttle.org/lab/index.html https://jupyterapi.cybershuttle.org/api/v1/oauth/config https://custos.cybershuttle.org/; do
    curl -fsS -o /dev/null --retry 15 --retry-delay 2 --retry-all-errors -H 'Origin: https://jupyter.cybershuttle.org' "$url" && echo "ok $url"
done
