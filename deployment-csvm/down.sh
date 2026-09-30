#!/usr/bin/env bash
# Stops deployment-csvm, keeping everything on the VM so up.sh brings it back as it was. With --purge it removes
# everything up.sh added instead, data included, leaving nginx and certbot for any other sites on the VM.
set -euo pipefail
[ -z "${1:-}" ] || [ "$1" = --purge ] || { echo "usage: $0 [--purge]" >&2; exit 2; }
# shellcheck disable=SC2029 # --purge is meant to expand here and travel to the VM
ssh "${CSVM_HOST:-cs-api}" "sudo PURGE='${1:-}' bash -s" <<'REMOTE'
set -euo pipefail
systemctl disable --now cs-plane postgresql 2>/dev/null || true
rm -f /etc/nginx/conf.d/{jupyter,jupyterapi}.cybershuttle.org.conf
if [ -n "$PURGE" ]; then
    certbot delete --non-interactive --cert-name csvm >/dev/null 2>&1 || true
    DEBIAN_FRONTEND=noninteractive apt-get purge -y -qq --auto-remove postgresql postgresql-common >/dev/null
    rm -rf /etc/systemd/system/cs-plane.service \
        /usr/local/bin/cs /var/lib/postgresql /etc/postgresql \
        /etc/default/cs-plane /var/www/jupyter.cybershuttle.org \
        /home/ubuntu/.cybershuttle /tmp/cs-$(id -u ubuntu) /tmp/deployment-csvm
    systemctl daemon-reload
fi
systemctl reload nginx
REMOTE
