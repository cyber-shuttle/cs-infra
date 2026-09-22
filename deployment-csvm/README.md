# deployment-csvm

One Ubuntu 24.04 host (ssh alias `cs-api`, 3.142.234.94) serving CyberShuttle Jupyter, the csctl control plane it calls, and Apache Airavata Custos.
nginx terminates TLS for every name; the services listen on loopback only.

| Name | nginx routes to | Built from |
|---|---|---|
| `jupyter.cybershuttle.org` | static site in `/var/www/jupyter.cybershuttle.org` | `cs-jupyter` `dist/` |
| `jupyterapi.cybershuttle.org` | `csctl.service` on `127.0.0.1:8045` | `cs-control` |
| `custos.cybershuttle.org` | `custos-portal.service` on `127.0.0.1:3100`; `/me` to `custos.service` on `127.0.0.1:8100` | `airavata-custos` `web/` and `cmd/server` |

Custos core stores its data in Postgres 17, the `custos_db` container on `127.0.0.1:5433` with the
`custos_db_data` volume. csctl keeps its own state under `/home/ubuntu/.cybershuttle/control`.

## Up and down

```bash
./up.sh             # build, decrypt secrets onto the host, install, restart, check
./down.sh           # stop services, Postgres and both nginx sites; keep all data
./down.sh --purge   # remove every trace from the host, including the Custos database and csctl state
```

`up.sh` first decrypts every secret once, so a missing key stops it before anything changes. It then builds csctl,
`custos-server` and the Jupyter site on this machine and copies them, with the Custos portal source and `root/`, to
`/tmp/deployment-csvm` on the host. Each secret goes from `sops decrypt` over ssh straight into its path on the host
as `root:ubuntu 640`, and `install.sh` installs `root/` over `/`, enables both nginx sites, starts Postgres, builds
the portal with pnpm, restarts the three services and checks each public name. `down.sh` leaves secrets,
certificates, binaries, the database volume and csctl's state in place, so `up.sh` restores the deployment as it was.
`down.sh --purge` also deletes the units, binaries, nginx sites, certificates, secrets, portal, site, the
`custos_db` container and volume, and `/home/ubuntu/.cybershuttle`; the next `up.sh` reissues certificates and
Custos creates an empty database, with `CUSTOS_BOOTSTRAP_ADMIN_EMAIL` as its super-admin.

`cs-control` and `cs-jupyter` are taken from the checkouts beside this repository's main checkout, so a deploy
ships whatever they hold. Custos is cloned into `~/.cache/cs-infra/airavata-custos` at the commit pinned in `up.sh`.

| Variable | Default |
|---|---|
| `CSVM_HOST` | `cs-api`, an ssh alias with passwordless sudo |
| `CS_CONTROL`, `CS_JUPYTER` | sibling checkouts |
| `AIRAVATA_CUSTOS` | the pinned clone; set it to deploy another checkout |
| `SOPS_AGE_KEY_FILE` | `~/.config/cybershuttle/cs-infra-age.key` |

## Secrets

Every host secret is committed under `secrets/`, SOPS-encrypted to the age recipient in `/.sops.yaml`: variable
names stay readable and only their values are encrypted. The repository is the source of truth, and each `up.sh`
overwrites the host copy from it.

| Encrypted file | Installed to | Variables |
|---|---|---|
| `csctl.sops.env` | `/etc/default/csctl` | `CSCTL_OIDC_CLIENT_SECRET` |
| `custos.sops.env` | `/etc/default/custos` | `CONFIG_PATH`, `CUSTOS_BOOTSTRAP_ADMIN_EMAIL`, `CUSTOS_TRACING_MODE` |
| `custos.sops.yaml` | `/etc/custos/custos.yaml` | `core.database.url`, `core.api.port`, `core.log_level`, `core.auth.oidc.issuer`, `core.auth.oidc.audience`, `core.auth.cache_ttl` |
| `postgres.sops.env` | `/etc/custos/postgres.env` | `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD` |
| `custos-portal.sops.env` | `/opt/custos/web/.env.local` | `NODE_ENV`, `NEXTAUTH_URL`, `NEXTAUTH_SECRET`, `CUSTOS_CORE_API_BASE_URL`, `OIDC_ISSUER_URL`, `OIDC_CLIENT_ID`, `OIDC_CLIENT_SECRET`, `NEXT_PUBLIC_PORTAL_USE_MSW`, `NEXT_PUBLIC_PORTAL_BUILD_SHA` |

```bash
export SOPS_AGE_KEY_FILE=~/.config/cybershuttle/cs-infra-age.key
sops edit secrets/csctl.sops.env      # change a value, then ./up.sh
sops encrypt --filename-override secrets/new.sops.env new.env > secrets/new.sops.env   # add a file, then map it in up.sh
```

The private key exists only at `~/.config/cybershuttle/cs-infra-age.key`; keep a copy in a password manager, since
losing it leaves the encrypted files unreadable. To let someone else deploy, add their age public key to
`/.sops.yaml` and run `sops updatekeys` on each file.

## Prerequisites

- **This machine:** Go 1.26, Bun, rsync, sops and the age key, and checkouts of `cs-control` and `cs-jupyter`.
- **The host:** nginx, certbot with `python3-certbot-nginx`, Docker, Node 22 with pnpm 9.15.9, and rsync.
- **DNS:** A records for all three names pointing at the host.

## Outside this repository

| Where | Setting |
|---|---|
| CILogon client for csctl (`…/4738a93a9b45576c741063718d55143b`) | device flow and PKCE enabled; redirect `https://jupyter.cybershuttle.org/lab/index.html` |
| CILogon client for the Custos portal (`…/22de898fb3370485836d8e52f8e12103`) | redirect `https://custos.cybershuttle.org/api/auth/callback/oidc` |
