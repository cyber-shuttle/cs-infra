# cs-infra

Reproducible deployments of CyberShuttle services. Each directory is one host, with its configuration mirrored
under `root/`, secret templates under `secrets/`, and `up.sh` / `down.sh` to bring it up and take it down.

| Deployment | Host | Serves |
|---|---|---|
| [cs-api](cs-api/README.md) | `cs-api` (3.142.234.94) | CyberShuttle Jupyter, its csctl control API, and Custos |

No secret is committed: a deployment reads them from files on its host and only creates a template when one is
missing.
