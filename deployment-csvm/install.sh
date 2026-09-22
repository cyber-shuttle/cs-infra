#!/usr/bin/env bash
# Runs on the host as root from /tmp/deployment-csvm, after up.sh has decrypted the secrets into place. It installs
# everything the deployment needs onto a bare Ubuntu 24.04 VM and is safe to rerun; it never replaces a certificate,
# the database, or csctl's state that already exists.
set -euo pipefail
src=$(cd "$(dirname "$0")" && pwd)
node_version=v22.23.2

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends nginx certbot python3-certbot-nginx postgresql iptables rsync curl xz-utils >/dev/null
if [ "$(/opt/node/bin/node --version 2>/dev/null)" != "$node_version" ]; then
    rm -rf /opt/node && mkdir -p /opt/node
    curl -fsSL "https://nodejs.org/dist/$node_version/node-$node_version-linux-x64.tar.xz" | tar -xJ -C /opt/node --strip-components=1
fi

# One database with a schema per service. Both run as ubuntu and connect over the local socket, so Postgres
# authenticates them by their system user and no password exists.
systemctl enable --now --quiet postgresql
sudo -u postgres psql -q -v ON_ERROR_STOP=1 <<'SQL'
SELECT 'CREATE ROLE ubuntu LOGIN' WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'ubuntu') \gexec
SELECT 'CREATE DATABASE cybershuttle OWNER ubuntu' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'cybershuttle') \gexec
\connect cybershuttle
CREATE SCHEMA IF NOT EXISTS custos AUTHORIZATION ubuntu;
CREATE SCHEMA IF NOT EXISTS csctl AUTHORIZATION ubuntu;
SQL

certificate() {
    [ -e "/etc/letsencrypt/live/$1/fullchain.pem" ] && return
    local domains=()
    for domain in "$@"; do domains+=(-d "$domain"); done
    certbot certonly --nginx --non-interactive --agree-tos --register-unsafely-without-email \
        --cert-name "$1" "${domains[@]}"
}
certificate jupyter.cybershuttle.org jupyterapi.cybershuttle.org
certificate custos.cybershuttle.org

cp -r "$src/root/." /
for site in jupyter.cybershuttle.org custos.cybershuttle.org; do
    ln -sf "../sites-available/$site" "/etc/nginx/sites-enabled/$site"
done
nginx -t
systemctl reload nginx

install -m 755 "$src/csctl" "$src/custos-server" /usr/local/bin/
rsync -a --delete "$src/site/" /var/www/jupyter.cybershuttle.org/
chown -R www-data:www-data /var/www/jupyter.cybershuttle.org
rsync -a --delete --exclude node_modules --exclude .next --exclude .env.local "$src/web/" /opt/custos/web/
chown -R ubuntu:ubuntu /opt/custos
sudo -u ubuntu -H env PATH="/opt/node/bin:$PATH" COREPACK_ENABLE_DOWNLOAD_PROMPT=0 \
    bash -c 'cd /opt/custos/web && corepack pnpm install --frozen-lockfile && corepack pnpm build'

systemctl daemon-reload
systemctl enable --quiet custos custos-portal csctl
systemctl restart custos custos-portal csctl

check() { curl -fsS -o /dev/null --retry 15 --retry-delay 2 --retry-all-errors "$@" && echo "ok ${*: -1}"; }
check https://jupyter.cybershuttle.org/lab/index.html
check -H 'Origin: https://jupyter.cybershuttle.org' https://jupyterapi.cybershuttle.org/api/v1/oauth/config
check https://custos.cybershuttle.org/
