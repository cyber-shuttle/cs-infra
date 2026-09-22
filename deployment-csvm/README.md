# deployment-csvm

This deploys CyberShuttle Jupyter, the csctl control plane it talks to, and Apache Airavata Custos onto a single
VM. Everything the services need is installed by `up.sh`, so the VM can start out bare.

## What it needs

- **A VM** running Ubuntu 24.04 on x86-64, reachable over ssh as `ubuntu` with passwordless sudo, which is how
  Ubuntu cloud images come. Ports 80 and 443 must be open to the internet; nothing else needs to be.
- **DNS records** pointing `jupyter.cybershuttle.org`, `jupyterapi.cybershuttle.org` and
  `custos.cybershuttle.org` at the VM.
- **On your machine:** Go 1.26, Bun, rsync, sops, the age key at `~/.config/cybershuttle/cs-infra-age.key`, and
  checkouts of `cs-control` and `cs-jupyter` next to `cs-infra`.

## Up and down

```bash
./up.sh             # install or update everything, then check each public name
./down.sh           # stop everything; data, secrets and software stay
./down.sh --purge   # remove everything up.sh put on the VM, data included
```

`up.sh` builds csctl, the Custos server and the Jupyter site on your machine and copies them to the VM. It then
decrypts each secret straight into its place on the VM, installs the packages and Node, prepares the database,
issues any missing TLS certificates, and restarts the services. Running it again redeploys whatever the
checkouts hold. Custos is built from the commit pinned in `up.sh`. By default it deploys to the ssh destination
`cs-api`; set `CSVM_HOST` to deploy elsewhere.

`down.sh` keeps everything in place, so a later `up.sh` brings the deployment back as it was. With `--purge` it
also deletes the database, csctl's state, the certificates, the secrets, Postgres and Node. nginx and certbot
remain installed because other sites on the VM may rely on them.

## What runs on the VM

| Name | Serves | Behind it |
|---|---|---|
| `jupyter.cybershuttle.org` | the Jupyter site | files in `/var/www/jupyter.cybershuttle.org` |
| `jupyterapi.cybershuttle.org` | the control API | `csctl.service` on port 8045 |
| `custos.cybershuttle.org` | the Custos portal, and Custos's `/me` for csctl | `custos-portal.service` on 3100, `custos.service` on 8100 |

nginx terminates TLS for all three names and is the only thing reachable from outside. csctl and Postgres listen
on loopback. The two Custos services can't be limited to loopback, so their units drop outside traffic to their
ports instead.

Custos and csctl share one Postgres database, `cybershuttle`, each in its own schema. Both run as `ubuntu` and
connect over Postgres's local socket, which authenticates them by their system user, so the database has no
password. csctl also keeps a few files, such as rendered SSH configs and uploaded keys, under
`/home/ubuntu/.cybershuttle/control`.

## Secrets

The secrets live in `secrets/`, encrypted with SOPS. The variable names are readable and only their values are
encrypted. Each `up.sh` writes them to the VM, so this repository is where they are changed.

| File | Installed to | Variables |
|---|---|---|
| `csctl.sops.env` | `/etc/default/csctl` | `CSCTL_OIDC_CLIENT_SECRET` |
| `custos.sops.env` | `/etc/default/custos` | `CONFIG_PATH`, `CUSTOS_BOOTSTRAP_ADMIN_EMAIL`, `CUSTOS_TRACING_MODE` |
| `custos-portal.sops.env` | `/opt/custos/web/.env.local` | `NODE_ENV`, `NEXTAUTH_URL`, `NEXTAUTH_SECRET`, `CUSTOS_CORE_API_BASE_URL`, `OIDC_ISSUER_URL`, `OIDC_CLIENT_ID`, `OIDC_CLIENT_SECRET`, `NEXT_PUBLIC_PORTAL_USE_MSW`, `NEXT_PUBLIC_PORTAL_BUILD_SHA` |

To change a value, edit the file with sops and run `up.sh`:

```bash
SOPS_AGE_KEY_FILE=~/.config/cybershuttle/cs-infra-age.key sops edit secrets/csctl.sops.env
```

The age key exists only on your machine. Keep a copy in a password manager, because nothing can decrypt these
files without it. To let someone else deploy, add their age public key to `/.sops.yaml` and run
`sops updatekeys` on each file.

## Outside the VM

The running services depend on three things this repository does not create:

- The CILogon client csctl uses (`…/4738a93a9b45576c741063718d55143b`) must allow PKCE and the device flow, with
  `https://jupyter.cybershuttle.org/lab/index.html` as a redirect.
- The CILogon client the Custos portal uses (`…/22de898fb3370485836d8e52f8e12103`) must list
  `https://custos.cybershuttle.org/api/auth/callback/oidc` as a redirect.
- Users link a Microsoft or GitHub account for Dev Tunnels, and reach their own Slurm clusters over SSH.
