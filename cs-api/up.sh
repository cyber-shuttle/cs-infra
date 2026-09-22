#!/usr/bin/env bash
# Builds the cs-api deployment from source checkouts and installs it on the host over ssh. Everything is rebuilt
# and reinstalled on each run; host secrets, certificates, the Postgres volume and csctl's state are left alone.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
host=${CS_API_HOST:-cs-api}
cs_control=${CS_CONTROL:-$here/../../cs-control}
cs_jupyter=${CS_JUPYTER:-$here/../../cs-jupyter}
custos=${AIRAVATA_CUSTOS:-$here/../../airavata-custos}

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
(cd "$cs_control" && GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -o "$stage/csctl" .)
(cd "$custos" && GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -o "$stage/custos-server" ./cmd/server)
(cd "$cs_jupyter" && bun install --frozen-lockfile && bun run build)
cp -R "$cs_jupyter/dist" "$stage/site"
sed -i.orig 's#"cybershuttleControlApiUrl": *"[^"]*"#"cybershuttleControlApiUrl": "https://jupyterapi.cybershuttle.org/api/v1"#' "$stage/site/jupyter-lite.json"
rm "$stage/site/jupyter-lite.json.orig"
grep -q 'jupyterapi.cybershuttle.org' "$stage/site/jupyter-lite.json"
rsync -a --exclude node_modules --exclude .next --exclude .env.local "$custos/web/" "$stage/web/"
cp -R "$here/root" "$here/secrets" "$here/install.sh" "$stage/"

rsync -az --delete "$stage/" "$host:/tmp/cs-api-deploy/"
# shellcheck disable=SC2029 # the email is meant to expand here and travel to the host
ssh "$host" "sudo ${CERTBOT_EMAIL:+CERTBOT_EMAIL=$CERTBOT_EMAIL} bash /tmp/cs-api-deploy/install.sh"
