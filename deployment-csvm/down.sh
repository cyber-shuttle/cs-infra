#!/usr/bin/env bash
# Takes deployment-csvm offline. By default its data, secrets, certificates and software stay on the host, so up.sh
# brings it back as it was. --purge instead removes everything up.sh put there, including the database and csctl's
# state, so the next up.sh starts from a bare VM. nginx and certbot stay installed, since other sites may use them.
set -euo pipefail
purge=${1:-}
[ -z "$purge" ] || [ "$purge" = --purge ] || { echo "usage: $0 [--purge]" >&2; exit 2; }
# shellcheck disable=SC2029 # --purge is meant to expand here and travel to the host
ssh "${CSVM_HOST:-cs-api}" "sudo PURGE='$purge' bash -s" <<'REMOTE'
set -euo pipefail
sites=(jupyter.cybershuttle.org custos.cybershuttle.org)
systemctl disable --now csctl custos-portal custos postgresql 2>/dev/null || true
for site in "${sites[@]}"; do rm -f "/etc/nginx/sites-enabled/$site"; done
if [ -n "$PURGE" ]; then
    rm -f /etc/systemd/system/{csctl,custos,custos-portal}.service /usr/local/bin/{csctl,custos-server}
    systemctl daemon-reload
    for site in "${sites[@]}"; do
        rm -f "/etc/nginx/sites-available/$site"
        certbot delete --non-interactive --cert-name "$site" >/dev/null 2>&1 || true
    done
    rm -f /etc/nginx/conf.d/connection-upgrade.conf
    DEBIAN_FRONTEND=noninteractive apt-get purge -y -qq --auto-remove postgresql postgresql-common >/dev/null
    rm -rf /var/lib/postgresql /etc/postgresql /opt/node /home/ubuntu/.cache/node \
        /etc/default/csctl /etc/default/custos /etc/custos /opt/custos /var/www/jupyter.cybershuttle.org \
        /home/ubuntu/.cybershuttle /tmp/csctl-1000 /tmp/deployment-csvm
fi
nginx -t
systemctl reload nginx
REMOTE
