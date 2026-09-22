#!/usr/bin/env bash
# Runs on the host as root, from the directory up.sh staged. It never overwrites a secret, certificate, database
# volume or csctl state that already exists; a missing secret is created from its template and stops the run.
set -euo pipefail
src=$(cd "$(dirname "$0")" && pwd)

for tool in nginx certbot docker node pnpm rsync; do
    command -v "$tool" >/dev/null || { echo "missing $tool; see cs-api/README.md" >&2; exit 1; }
done

missing=()
while IFS= read -r template; do
    target=/${template#"$src/secrets/"}
    target=${target%.example}
    [ -e "$target" ] && continue
    install -D -o root -g ubuntu -m 640 "$template" "$target"
    missing+=("$target")
done < <(find "$src/secrets" -type f -name '*.example')
if ((${#missing[@]})); then
    printf 'fill in, then rerun up.sh: %s\n' "${missing[@]}" >&2
    exit 1
fi

certificate() {
    [ -e "/etc/letsencrypt/live/$1/fullchain.pem" ] && return
    local domains=()
    for domain in "$@"; do domains+=(-d "$domain"); done
    certbot certonly --nginx --non-interactive --agree-tos -m "${CERTBOT_EMAIL:?set CERTBOT_EMAIL to issue $1}" \
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

docker inspect custos_db >/dev/null 2>&1 || docker run -d --name custos_db --restart unless-stopped \
    -p 127.0.0.1:5433:5432 -v custos_db_data:/var/lib/postgresql/data -e TZ=UTC --env-file /etc/custos/postgres.env postgres:17
docker start custos_db >/dev/null

install -m 755 "$src/csctl" "$src/custos-server" /usr/local/bin/
rsync -a --delete "$src/site/" /var/www/jupyter.cybershuttle.org/
chown -R www-data:www-data /var/www/jupyter.cybershuttle.org
rsync -a --delete --exclude node_modules --exclude .next --exclude .env.local "$src/web/" /opt/custos/web/
chown -R ubuntu:ubuntu /opt/custos
sudo -u ubuntu -H bash -c 'cd /opt/custos/web && pnpm install --frozen-lockfile && pnpm build'

systemctl daemon-reload
systemctl enable --quiet custos custos-portal csctl
systemctl restart custos custos-portal csctl

check() { curl -fsS -o /dev/null --retry 15 --retry-delay 2 --retry-all-errors "$@" && echo "ok ${*: -1}"; }
check https://jupyter.cybershuttle.org/lab/index.html
check -H 'Origin: https://jupyter.cybershuttle.org' https://jupyterapi.cybershuttle.org/api/v1/oauth/config
check https://custos.cybershuttle.org/
