# Public cloud / single-VM provisioning helpers

Small scripts to configure a **local machine** or **single public cloud VM** (Debian/Ubuntu-style) with the same Nginx layout used in `3_vm_provissioning/provision_vm.sh`, plus a Docker smoke test.

## Prerequisites

- Debian or Ubuntu (uses `apt-get`).
- Network access for `apt-get` (and Docker image pulls if you extend the scripts later).

## Scripts

| Script | Purpose |
|--------|---------|
| `1_setup_tools.sh` | Installs `nginx` and `docker.io`, applies the shared `nginx.conf`, restarts Nginx, enables Docker, runs a basic Docker check. |

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
