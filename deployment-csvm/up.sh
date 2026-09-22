#!/usr/bin/env bash
# Builds deployment-csvm and installs it on the host over ssh. Each secret is decrypted with SOPS straight
# into its path on the host, so plaintext exists nowhere else. Certificates, the Postgres volume and csctl's state
# are left alone; everything else is rebuilt and reinstalled on each run.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
host=${CSVM_HOST:-cs-api}
export SOPS_AGE_KEY_FILE=${SOPS_AGE_KEY_FILE:-$HOME/.config/cybershuttle/cs-infra-age.key}
# Sibling checkouts of cs-infra's main checkout, which a worktree shares through its git directory.
workspace=$(dirname "$(dirname "$(git -C "$here" rev-parse --path-format=absolute --git-common-dir)")")
cs_control=${CS_CONTROL:-$workspace/cs-control}
cs_jupyter=${CS_JUPYTER:-$workspace/cs-jupyter}
custos=${AIRAVATA_CUSTOS:-${XDG_CACHE_HOME:-$HOME/.cache}/cs-infra/airavata-custos}
custos_ref=5d840613f48b8de29e30e16027633bdc3ee16b46
# Each encrypted file in secrets/ and the host path it is installed to.
secrets() {
    cat <<'MAP'
csctl.sops.env          /etc/default/csctl
custos.sops.env         /etc/default/custos
custos.sops.yaml        /etc/custos/custos.yaml
postgres.sops.env       /etc/custos/postgres.env
custos-portal.sops.env  /opt/custos/web/.env.local
MAP
}

# Decrypt everything once up front: a missing key must fail here, not after a secret on the host was truncated.
secrets | while read -r file _; do sops decrypt "$here/secrets/$file" >/dev/null; done
[ -n "${AIRAVATA_CUSTOS:-}" ] || {
    [ -d "$custos/.git" ] || git clone -q https://github.com/apache/airavata-custos "$custos"
    git -C "$custos" fetch -q origin && git -C "$custos" checkout -q --detach "$custos_ref"
}

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
cp -R "$here/root" "$here/install.sh" "$stage/"

rsync -az --delete "$stage/" "$host:/tmp/deployment-csvm/"
secrets | while read -r file target; do
    # shellcheck disable=SC2029 # the target path is meant to expand here
    sops decrypt "$here/secrets/$file" | ssh "$host" "sudo install -D -o root -g ubuntu -m 640 /dev/stdin '$target'"
done
ssh "$host" 'sudo bash /tmp/deployment-csvm/install.sh'
