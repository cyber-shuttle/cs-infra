#!/usr/bin/env bash
# Takes the cs-api deployment offline. Secrets, certificates, binaries, the Postgres volume and csctl's state stay,
# so up.sh brings it back as it was.
set -euo pipefail
ssh "${CS_API_HOST:-cs-api}" 'sudo bash -s' <<'REMOTE'
set -euo pipefail
systemctl disable --now csctl custos-portal custos
docker stop custos_db >/dev/null
rm -f /etc/nginx/sites-enabled/jupyter.cybershuttle.org /etc/nginx/sites-enabled/custos.cybershuttle.org
nginx -t
systemctl reload nginx
REMOTE
