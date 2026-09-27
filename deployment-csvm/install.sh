#!/usr/bin/env bash
# Runs as root on the VM from /tmp/deployment-csvm, after up.sh has put the secrets in place. Safe to rerun: the
# certificate, the database and cs-plane's state are kept.
set -euo pipefail
cd "$(dirname "$0")"

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends nginx certbot python3-certbot-nginx postgresql rsync curl >/dev/null

# cs-plane runs as ubuntu over the local socket, so no password exists.
systemctl enable --now --quiet postgresql
sudo -u postgres psql -q -v ON_ERROR_STOP=1 <<'SQL'
SELECT 'CREATE ROLE ubuntu LOGIN' WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'ubuntu') \gexec
SELECT 'CREATE DATABASE cybershuttle OWNER ubuntu' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'cybershuttle') \gexec
\connect cybershuttle
CREATE SCHEMA IF NOT EXISTS cs_plane AUTHORIZATION ubuntu;
SQL

[ -e /etc/letsencrypt/live/csvm ] || certbot certonly --nginx --non-interactive --agree-tos --register-unsafely-without-email \
    --cert-name csvm -d jupyter.cybershuttle.org -d jupyterapi.cybershuttle.org
cp -r root/. /
nginx -t
systemctl reload nginx

install -m 755 cs /usr/local/bin/
rsync -a --delete site/ /var/www/jupyter.cybershuttle.org/

systemctl daemon-reload
systemctl enable --quiet cs-plane
systemctl restart cs-plane

for url in https://jupyter.cybershuttle.org/lab/index.html https://jupyterapi.cybershuttle.org/api/v1/oauth/config; do
    curl -fsS -o /dev/null --retry 15 --retry-delay 2 --retry-all-errors -H 'Origin: https://jupyter.cybershuttle.org' "$url" && echo "ok $url"
done
