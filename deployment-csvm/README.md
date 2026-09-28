# deployment-csvm

This deploys two services onto a single VM. cs-plane signs users in at CILogon, holds their credentials, SSH hosts
and sessions, and submits the Slurm job whose Linkspan serves each run. CyberShuttle Jupyter is the web workspace
that drives it. Everything these need is installed by `up.sh`, so the VM can start out bare.

## What it needs

- **A VM** running Ubuntu 24.04 on x86-64, reachable over ssh as `ubuntu` with passwordless sudo, which is how
  Ubuntu cloud images come. Ports 80 and 443 must be open to the internet; nothing else needs to be.
- **DNS records** pointing `jupyter.cybershuttle.org` and `jupyterapi.cybershuttle.org` at the VM.
- **On your machine:** Go 1.26, Bun, rsync, age, the age key at `~/.config/cybershuttle/sops.key`, and
  checkouts of `cs-plane` and `cs-jupyter` next to `cs-infra`.

## Up and down

```bash
./up.sh             # install or update everything, then check each public name
./down.sh           # stop everything; data, secrets and software stay
./down.sh --purge   # remove everything up.sh put on the VM, data included
```

`up.sh` builds cs-plane's `cs` binary and the Jupyter site on your machine and copies them to the VM. It then
decrypts each secret straight into its place on the VM, installs the packages, prepares the database, issues any
missing TLS certificates, and restarts cs-plane. Running it again redeploys whatever the checkouts hold. By default
it deploys to the ssh destination `cs-api`; set `CSVM_HOST` to deploy elsewhere.

`down.sh` keeps everything in place, so a later `up.sh` brings the deployment back as it was. With `--purge` it
also deletes the database, cs-plane's state, the certificates, the secrets and Postgres. nginx and certbot
remain installed because other sites on the VM may rely on them.

## What runs on the VM

Each name has its own nginx file in `root/etc/nginx/conf.d/`, named after it.

| Name | Serves | Behind it |
|---|---|---|
| `jupyter.cybershuttle.org` | the Jupyter site | static files nginx serves from `/var/www/jupyter.cybershuttle.org` |
| `jupyterapi.cybershuttle.org` | the cs-plane API, and the link each run's Linkspan dials back on | `cs-plane.service` on port 8045 |

nginx terminates TLS for both names and is the only thing reachable from outside. cs-plane and Postgres listen on
loopback.

The Jupyter site has no process of its own. `up.sh` builds it on your machine from the `cs-jupyter` checkout
with `bun run build`, points `cybershuttlePlaneApiUrl` in the built `jupyter-lite.json` at
`https://jupyterapi.cybershuttle.org/api/v1`, and copies the resulting `dist/` to
`/var/www/jupyter.cybershuttle.org` on the VM, replacing what was there.

cs-plane keeps its rows in the `cs_plane` schema of the Postgres database `cybershuttle`. It runs as `ubuntu` and
connects over Postgres's local socket, which authenticates it by its system user, so the database has no password.
It also keeps a few files, such as rendered SSH configs and uploaded keys, under `/home/ubuntu/.cybershuttle/control`.

cs-plane does not migrate its stored rows between releases. When a release's CHANGELOG gives upgrade steps, stop
cs-plane and follow them on the VM, running its SQL with `psql -d cybershuttle`, before `up.sh` installs that release.

To upgrade a VM that still runs Custos, after following cs-plane's CHANGELOG upgrade steps: `systemctl disable --now
custos custos-portal`, `rm /etc/systemd/system/custos{,-portal}.service /etc/default/custos
/etc/nginx/conf.d/{custos,jupyter,jupyterapi}.cybershuttle.org.conf`, `rm -r /opt/custos /opt/node
/usr/local/bin/custos-server`, `certbot delete --cert-name csvm`, `DROP SCHEMA custos CASCADE` in
`psql -d cybershuttle`, then `up.sh`, which reinstalls the nginx sites under a new certificate.

## Secrets

The secrets live in `secrets/`, one `NAME=value` per line, with each value encrypted with
[age](https://age-encryption.org) and base64-encoded, so the variable names stay readable. The files hold
nothing else. Each `up.sh` writes them to the VM, so this repository is where they are changed. Settings that
aren't secret sit in the service units instead.

| File | Installed to | Variables |
|---|---|---|
| `cs-plane.env` | `/etc/default/cs-plane` | `CS_OIDC_CLIENT_SECRET` |

To set a value, encrypt it and put the output after `NAME=` in the file, then run `up.sh`:

```bash
key=~/.config/cybershuttle/sops.key
printf %s 'the value' | age -r "$(age-keygen -y "$key")" | base64 | tr -d '\n'
```

The key exists only on your machine, and nothing about it is stored here: its public half is derived from it
when encrypting. Keep a copy in a password manager, because nothing can decrypt these values without it.

## Outside the VM

The running services depend on two things this repository does not create:

- The CILogon client cs-plane uses (`…/4738a93a9b45576c741063718d55143b`) must allow PKCE and the device flow,
  with `https://jupyter.cybershuttle.org/lab/index.html` as a redirect.
- Users connect a Dev Tunnels account (Microsoft or GitHub), and reach their own Slurm clusters over SSH.
