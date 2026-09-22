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

## Up and down

```bash
./up.sh     # build, decrypt secrets onto the host, install, restart, check
./down.sh   # stop services, Postgres and both nginx sites; keep all data
```

`up.sh` first decrypts every secret once, so a missing key stops it before anything changes. It then builds csctl,
`custos-server` and the Jupyter site on this machine and copies them, with the Custos portal source and `root/`, to
`/tmp/cs-api-deploy` on the host. Each secret goes from `sops decrypt` over ssh straight into its path on the host
as `root:ubuntu 640`, and `install.sh` installs `root/` over `/`, enables both nginx sites, starts Postgres, builds
the portal with pnpm, restarts the three services and checks each public name. `down.sh` leaves secrets,
certificates, binaries, the database volume and csctl's state in place, so `up.sh` restores the deployment as it was.

`cs-control` and `cs-jupyter` are taken from the checkouts beside this repository's main checkout, so a deploy
ships whatever they hold. Custos is cloned into `~/.cache/cs-infra/airavata-custos` at the commit pinned in `up.sh`.

| Variable | Default |
|---|---|
| `CS_API_HOST` | `cs-api`, an ssh alias with passwordless sudo |
| `CS_CONTROL`, `CS_JUPYTER` | sibling checkouts |
| `AIRAVATA_CUSTOS` | the pinned clone; set it to deploy another checkout |
| `SOPS_AGE_KEY_FILE` | `~/.config/cybershuttle/cs-infra-age.key` |

## Secrets

Every host secret is committed under `secrets/`, SOPS-encrypted to the age recipient in `/.sops.yaml`, at the
path it is installed to plus `.sops`. The repository is the source of truth: each `up.sh` overwrites the host copy.

| File | Holds |
|---|---|
| `/etc/default/csctl` | the CILogon client secret for csctl's client |
| `/etc/default/custos` | Custos config path and bootstrap super-admin email |
| `/etc/custos/custos.yaml` | Custos core config, including the Postgres password |
| `/etc/custos/postgres.env` | the Postgres credentials used when `custos_db` is first created |
| `/opt/custos/web/.env.local` | the portal's NextAuth secret and CILogon client secret |

```bash
export SOPS_AGE_KEY_FILE=~/.config/cybershuttle/cs-infra-age.key
sops edit secrets/etc/default/csctl.sops          # change a value, then ./up.sh
sops encrypt --filename-override secrets/etc/x.sops x > secrets/etc/x.sops   # add one
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
