# cs-infra

Reproducible deployments of CyberShuttle services. Each directory is one host, with its configuration mirrored
under `root/`, its encrypted secrets under `secrets/`, and `up.sh` / `down.sh` to bring it up and take it down.

| Deployment | Host | Serves |
|---|---|---|
| [deployment-csvm](deployment-csvm/README.md) | `cs-api` (3.142.234.94) | cs-plane, CyberShuttle Jupyter and Custos |

Secret values are committed only age-encrypted; see each deployment's README.
