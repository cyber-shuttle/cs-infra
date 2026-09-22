# cs-infra

Reproducible deployments of CyberShuttle services. Each directory is one host, with its configuration mirrored
under `root/`, its SOPS-encrypted secrets under `secrets/`, and `up.sh` / `down.sh` to bring it up and take it down.

| Deployment | Host | Serves |
|---|---|---|
| [deployment-csvm](deployment-csvm/README.md) | `cs-api` (3.142.234.94) | cs-plane, CyberShuttle Jupyter and Custos |

Secrets are committed only SOPS-encrypted to the age recipient in `.sops.yaml`; see each deployment's README.
