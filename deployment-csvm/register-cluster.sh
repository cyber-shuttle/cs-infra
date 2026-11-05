#!/usr/bin/env bash
set -euo pipefail
[ $# -ge 2 ] || { echo "usage: $0 <name> <login-host> [ssh-port]" >&2; exit 2; }
# shellcheck disable=SC2029
ssh "${CSVM_HOST:-cs-api}" "sudo bash -s -- $(printf '%q ' "$@")" <<'REMOTE'
set -euo pipefail
. /etc/default/airavata-root
api() {
    curl -fsS -H "Authorization: Bearer $AIRAVATA_ROOT_ACCOUNT_TOKEN" -H 'Content-Type: application/json' \
        "http://127.0.0.1:8045/api/v1/$1" "${@:2}"
}
# Linkspan carries only the servers it started, so the run asks it for the Jupyter server, then holds the job.
run=$(cat <<'RUN'
curl -fsS -o /dev/null --retry 30 --retry-connrefused --retry-delay 1 -H 'Content-Type: application/json' -d @- \
  "http://127.0.0.1:$CS_CONTROL_PORT/api/v1/jupyter/sessions" <<EOF
{"addr": "127.0.0.1:$CS_APP_PORT", "token": "$CS_APP_TOKEN", "root_dir": "$PWD"}
EOF
sleep infinity
RUN
)
template=$(api application-templates | jq -r 'first(.[] | select(.templateName == "Jupyter") | .templateId) // empty')
[ -n "$template" ] || template=$(api application-templates -d '{"templateName": "Jupyter"}' | jq -r .templateId)
cluster=$(jq -n --arg name "$1" --arg host "$2" --argjson port "${3:-22}" \
    '{clusterName: $name, headnodeHost: $host, headnodePort: $port}' | api slurm-clusters -d @- | jq -r .slurmClusterId)
# The allocation is a placeholder the API requires; each run names its own.
jq -n --arg template "$template" --arg cluster "$cluster" --arg run "$run" \
    '{templateId: $template, slurmClusterId: $cluster, slurmRunSection: $run,
      defaultBatchJobConfig: {wallTimeMinutes: 60, allocation: "default", cpus: 2, mem: "4G"}}' |
    api slurm-deployments -d @- >/dev/null
echo "registered $1 as cluster $cluster"
REMOTE
