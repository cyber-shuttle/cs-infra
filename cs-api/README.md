# cs-api deployment

One Ubuntu 24.04 host serving CyberShuttle Jupyter, the csctl control plane it calls, and Apache Airavata Custos.
nginx terminates TLS for every name; the services listen on loopback only.

| Name | nginx routes to | Built from |
|---|---|---|
| `jupyter.cybershuttle.org` | static site in `/var/www/jupyter.cybershuttle.org` | `cs-jupyter` `dist/` |
| `jupyterapi.cybershuttle.org` | `csctl.service` on `127.0.0.1:8045` | `cs-control` |
| `custos.cybershuttle.org` | `custos-portal.service` on `127.0.0.1:3100`; `/me` to `custos.service` on `127.0.0.1:8100` | `airavata-custos` `web/` and `cmd/server` |

Custos core stores its data in Postgres 17, the `custos_db` container on `127.0.0.1:5433` with the
`custos_db_data` volume. csctl keeps its own state under `/home/ubuntu/.cybershuttle/control`.

## Up

```bash
AIRAVATA_CUSTOS=../../worktree-custos-login/airavata-custos ./up.sh
```

`up.sh` builds csctl, `custos-server` and the Jupyter site on this machine, copies them with the Custos portal
source and this directory's configuration to `/tmp/cs-api-deploy` on the host, and runs `install.sh` there. That
installs `root/` over `/`, enables both nginx sites, starts Postgres, builds the portal with pnpm, restarts the
three services, and checks each public name. Rerunning it redeploys whatever the checkouts now hold.

| Variable | Default |
|---|---|
| `CS_API_HOST` | `cs-api` (an ssh alias with passwordless sudo) |
| `CS_CONTROL`, `CS_JUPYTER`, `AIRAVATA_CUSTOS` | sibling checkouts of this repository |
| `CERTBOT_EMAIL` | needed only when a certificate does not exist yet |

## Down

```bash
./down.sh
```

Stops and disables the three services, stops Postgres and disables both nginx sites. Secrets, certificates,
binaries, the database volume and csctl's state remain, so `up.sh` restores the deployment as it was.

## Prerequisites

- **This machine:** Go 1.26, Bun, rsync, and checkouts of `cs-control`, `cs-jupyter` and `apache/airavata-custos`.
- **The host:** nginx, certbot with `python3-certbot-nginx`, Docker, Node 22 with pnpm 9.15.9, and rsync.
- **DNS:** A records for all three names pointing at the host.
- **Secrets on the host**, created from `secrets/` on the first run, which then stops until they are filled in:

| File | Holds |
|---|---|
| `/etc/default/csctl` | the CILogon client secret for csctl's client |
| `/etc/default/custos` | Custos config path and bootstrap super-admin email |
| `/etc/custos/custos.yaml` | Custos core config, including the Postgres password |
| `/etc/custos/postgres.env` | the Postgres credentials used when `custos_db` is first created |
| `/opt/custos/web/.env.local` | the portal's NextAuth secret and CILogon client secret |

## Outside this repository

| Where | Setting |
|---|---|
| CILogon client for csctl (`…/4738a93a9b45576c741063718d55143b`) | device flow and PKCE enabled; redirect `https://jupyter.cybershuttle.org/lab/index.html` |
| CILogon client for the Custos portal (`…/22de898fb3370485836d8e52f8e12103`) | redirect `https://custos.cybershuttle.org/api/auth/callback/oidc` |
