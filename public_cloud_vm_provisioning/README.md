# Public cloud / single-VM provisioning helpers

Small scripts to configure a **local machine** or **single public cloud VM** (Debian/Ubuntu-style) with the same Nginx layout used in `3_vm_provissioning/provision_vm.sh`, plus a Docker smoke test.

## Prerequisites

- Debian or Ubuntu (uses `apt-get`).
- **Docker** already installed and available on the machine (the script does not install it).
- Network access for `apt-get`.

## Scripts

| Script | Purpose |
|--------|---------|
| `1_setup_tools.sh` | Installs `nginx`, applies the shared `nginx.conf`, restarts Nginx, enables Docker, runs a basic Docker check. |
| `2_create_makefile.sh` | Same Makefile content as `3_vm_provissioning/create_makefile.sh`, written to `~/vlic_runner/Makefile` (creates `~/vlic_runner` if missing). No VM IP or `scp`—runs on the machine where you execute it. |
| `3_restore_from_ftp.sh` | Mounts a remote directory with **sshfs** (same style as `4_running_planet_rocklog/backup-sshfs/do_backup_for_system.sh`) and **rsync**s from a path under that mount into a local target directory. |
| `4_create_nginx_proxy_configuration.sh` | Nginx vhost for **service** `<subdomain>.<domain>`; TLS paths from cert issued for **`<server>.<domain>`** (`certbot certificates -d …`). Proxy to **127.0.0.1:port**. **Root only.** |
| `5_create_default_nginx_configuration.sh` | Writes **`/etc/nginx/sites-enabled/default`** as `default_server` for one FQDN; TLS via **`certbot certificates -d <fqdn>`**; backs up `sites-enabled` to **`sites-enabled.bak`** once; includes **`locations/*.conf`**. **Root only.** |

### `2_create_makefile.sh` (normal user)

Optional CircleCI token as the only argument (otherwise a placeholder line is written):

```bash
cd /path/to/proxmox-setup/public_cloud_vm_provisioning
chmod +x 2_create_makefile.sh   # if needed
./2_create_makefile.sh
# or: ./2_create_makefile.sh "$CIRCLECI_TOKEN"
```

Then use Make from `~/vlic_runner` (see the script’s printed examples).

### `3_restore_from_ftp.sh`

Requires `sshfs`, FUSE, and `rsync` on the machine (e.g. `apt-get install -y sshfs rsync`).

The “FTP” name matches the backup scripts: the transport is **SSH/SFTP via sshfs**, not classic FTP.

```bash
./3_restore_from_ftp.sh -f backup.example.com -u myuser -p 'secret' \
  -d /path/on/server -s sicherung_vm1/vm1-Monday -t /var/vlic/rocklog-vlic-docker/vlic_runner/vm1
```

- **`-d`** — Remote path passed to sshfs (`user@host:…` after the colon), same idea as `-d` in `do_backup_for_system.sh`.
- **`-s`** — Path under the mount to restore from (use `-s .` for the mount root).
- **`-t`** — Local directory to receive files (created if missing).
- **`-m`** — Optional custom mount point (default `/tmp/restoremnt_sshfs`).

The script unmounts on exit and tries to remove the empty mount-point directory. Passing the password on the command line is convenient but not secret-safe; prefer SSH keys if you can configure them for sshfs.

### `4_create_nginx_proxy_configuration.sh` (root)

Runs on the host where Nginx and Certbot live. Proxies to the app on **localhost** (Docker).

Two names matter:

1. **Service domain** — what Nginx serves (`server_name`, config filenames): `<subdomain>.<domain>` (e.g. `customer-xy.rocklog.ch`).
2. **Certificate domain** — the FQDN the existing Let’s Encrypt cert was issued for: `<server>.<domain>` (e.g. `hub-zh-01.rocklog.ch`). The script runs `certbot certificates -d <server>.<domain>` and uses the listed `fullchain.pem` / `privkey.pem`.

Arguments: `domain`, `subdomain`, `server`, `app_http_port`.

```bash
sudo ./4_create_nginx_proxy_configuration.sh rocklog.ch customer-xy hub-zh-01 8080
```

Requires `certbot` and a certificate already issued for `<server>.<domain>`. If the cert does not cover the service hostname, add a matching SAN or use a cert that includes both names; otherwise browsers may warn.

### `5_create_default_nginx_configuration.sh` (root)

One argument: **full hostname** (same value for `server_name` and for `certbot certificates -d`), e.g. `hub-zh-01.planet-rocklog.com`.

1. Requires root.  
2. On first run, copies `/etc/nginx/sites-enabled` → `/etc/nginx/sites-enabled.bak` if `.bak` does not exist.  
3. Resolves `fullchain.pem` / `privkey.pem` with certbot for that FQDN.  
4. Writes `default`, ensures `locations/` exists (adds a tiny placeholder `*.conf` only if the directory has no `.conf` files yet, so `include` works).  
5. Runs `nginx -t` and `systemctl reload nginx`.

```bash
sudo ./5_create_default_nginx_configuration.sh hub-zh-01.planet-rocklog.com
```

`listen 443` uses `ssl` (required for HTTPS). The `/werner/status` location serves from `/tmp` (see script comments).

## How to apply

### As root (recommended)

Log in as root or use a root shell, then:

```bash
cd /path/to/proxmox-setup/public_cloud_vm_provisioning
chmod +x 1_setup_tools.sh   # if needed
./1_setup_tools.sh
```

### As a normal user (with sudo)

You must use `sudo` so the script can install packages, write `/etc/nginx/nginx.conf`, and manage systemd:

```bash
cd /path/to/proxmox-setup/public_cloud_vm_provisioning
chmod +x 1_setup_tools.sh   # if needed
sudo ./1_setup_tools.sh
```

The script exits with an error if it is not run with root privileges (directly or via `sudo`).

### Copying to the target VM

From your workstation you can copy the directory and run there:

```bash
scp -r public_cloud_vm_provisioning user@your-vm:/tmp/
ssh user@your-vm
sudo /tmp/public_cloud_vm_provisioning/1_setup_tools.sh
```

## After running

- Nginx: `systemctl status nginx`, `curl -sI http://127.0.0.1/`
- Docker: `docker ps`, `docker info`

If Nginx fails its config test, the script restores `nginx.conf` from `nginx.conf.bak` when a backup exists.
