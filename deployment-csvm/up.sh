#!/usr/bin/env bash
# Builds deployment-csvm and installs it on the VM over ssh. Secrets are decrypted straight into place on the VM.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
host=${CSVM_HOST:-cs-api}
cs_plane=${CS_PLANE:-$here/../../cs-plane}
cs_jupyter=${CS_JUPYTER:-$here/../../cs-jupyter}
key=${CS_INFRA_KEY:-$HOME/.config/cybershuttle/sops.key}
secrets() {
    cat <<'MAP'
cs-plane.env  /etc/default/cs-plane
MAP
}
# Each line of a secrets file is NAME=value, with the value age-encrypted and base64-encoded.
decrypt() {
    while IFS= read -r line; do
        printf '%s=%s\n' "${line%%=*}" "$(printf '%s' "${line#*=}" | base64 -d | age -d -i "$key")"
    done < "$here/secrets/$1"
}

# A missing key must fail here, before a truncated secret could reach the VM.
secrets | while read -r file _; do decrypt "$file" >/dev/null; done

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
(cd "$cs_plane" && GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -o "$stage/cs" .)
(cd "$cs_jupyter" && bun install --frozen-lockfile && bun run build)
cp -R "$cs_jupyter/dist" "$stage/site"
perl -pi -e 's#("cybershuttlePlaneApiUrl": *)"[^"]*"#$1"https://jupyterapi.cybershuttle.org/api/v1"#' "$stage/site/jupyter-lite.json"
cp -R "$here/root" "$here/install.sh" "$stage/"

rsync -az --delete "$stage/" "$host:/tmp/deployment-csvm/"
secrets | while read -r file target; do
    # shellcheck disable=SC2029 # the target path is meant to expand here
    decrypt "$file" | ssh "$host" "sudo install -D -o root -g ubuntu -m 640 /dev/stdin '$target'"
done
ssh "$host" 'sudo bash /tmp/deployment-csvm/install.sh'
