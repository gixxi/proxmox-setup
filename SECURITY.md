# Security review — proxmox-setup

Review of 2026-10-15, triggered by the hub16 incident (rocklog-vlic
`doc/security/incident-2026-10-15-hub16.md`): CouchDB 1.6.1 without admin and an nREPL bound to
`0.0.0.0` were published on the internet by `docker run -p …`; ufw did not filter them, an attacker
executed code in a tenant container and used it for port scans.

## Principles

1. **Containers publish on loopback** (or, on a Proxmox app VM, on the VM IP for the bastion only).
   Admin ports — nREPL 4050, CouchDB 5984/5986 — are bound to `127.0.0.1` everywhere; use an SSH tunnel.
   Single source: `lib/vlic_runner_makefile.sh`.
2. **One firewall, iptables, for every host type**: `2_infrastructure/setup_firewall.sh`
   (profiles `proxmox`, `bastion`, `app-vm`, `docker-public`). ufw is gone — it does not see
   Docker-published ports. The script manages `DOCKER-USER`, covers IPv6, applies with automatic
   rollback and persists via `rocklog-firewall.service` instead of `netfilter-persistent`.
3. **Secrets never on the command line, in world-readable files or in logs.**

## Findings

| # | Sev. | Finding | Where | Status |
|---|------|---------|-------|--------|
| 1 | critical | nREPL (4050) and CouchDB (5984) published on all interfaces; README told to `ufw allow 18080:18090` / `28080:28090` | `create_makefile.sh`, `2_create_makefile.sh`, `restrict.sh`, `3_vm_provissioning/README.md` | **fixed** — `ADMIN_BIND=127.0.0.1` in the shared generator; firewall drops the rest |
| 2 | critical | `chmod 666 /var/run/docker.sock` — every local user/process becomes root | `2_infrastructure/README.md` | **fixed** — removed, warning added |
| 3 | high | `setup_firewall.sh` flushed all tables incl. `nat` (kills Docker port mappings and VM NAT), no IPv6 rules (IPv6 wide open), 8006 open to the world, lockout-prone sequential apply, `netfilter-persistent` restores stale Docker rules | `2_infrastructure/setup_firewall.sh` | **fixed** — rewritten (see principle 2); 8006 only from `ADMIN_SOURCES` |
| 4 | high | Backups: `umask 000`, mount dir `chmod 4777`, sshfs `allow_other` — any local user can read/alter the off-site backups; `rm -R` on the mount dir after a possibly failed unmount deletes remote backups | `backup-sshfs/do_backup_for_system.sh`, `backup_restore/restore_from_ftp_using_rsync.sh` | **fixed** — `umask 077`/`022`, mount dir 700, no `allow_other`, `rmdir` only |
| 5 | high | Backup storage password passed as `-p` (visible in `ps`, crontab) | same | **partly** — `-P <file>` added; switch crontabs to `-P` or, better, SSH keys for the storage box |
| 6 | high | CircleCI key inlined in the Makefile (world-readable), printed by make into the supervisor log (`curl -H "Circle-Token: …"`), passed as argv, temp file in `/tmp` | Makefile generators | **fixed** — `.circleci_apikey` (600), recipe silenced (`@`), key via env/stdin, `mktemp`; existing inline keys are migrated |
| 7 | medium | Cloud-init snippet with the root password in clear text, world-readable in `/var/lib/vz/snippets`; password echoed at the end of provisioning | `provision_vm.sh`, `recreate_cloudinit_script.sh` | **fixed** — `chmod 600`, not printed. Still on argv (`--password`) |
| 8 | medium | Proxmox node TLS private key copied to the internet-facing bastion | `copy_ssl_to_bastian.sh` | open — use a separate certificate for the bastion |
| 9 | medium | Docker daemon default bind `0.0.0.0` | `docker-only/5_storage_setup/configure_docker_storage.sh` | **fixed** — `"ip": "127.0.0.1"` in `daemon.json` |
| 10 | medium | `NOPASSWD` sudo for `docker` and membership in `docker` group = passwordless root | `docker-only/1_host_setup/create_non_root_user.sh`, `deb_cloud_init/cloudinit_postinstall.sh` (`NOPASSWD: ALL`) | open — decide deliberately; restrict to admin accounts |
| 11 | medium | Terraform sample: `root@pam` password auth, `pm_tls_insecure = true` | `main.tf` | open — use an API token (`pm_api_token_id`/`_secret` from variables) and the node's CA |
| 12 | low | `StrictHostKeyChecking=no` + `UserKnownHostsFile=/dev/null` (MITM possible) | `fix_vm_dns.sh` | open |
| 13 | low | `lein` and OpenTofu installer downloaded without checksum verification | `restrict.sh`, `setup_bastion_host.md` | open |
| 14 | low | Image registry `hub5.planet-rocklog.com:5000` — verify TLS + authentication | supervisor template in `restrict.sh` | open — verify |
| 15 | info | `provision_vm.sh` and `recreate_cloudinit_script.sh` share ~300 lines of cloud-init script | | open — extract into `lib/` like the Makefile |

## Rolling out on existing hosts

Per host, as root (the firewall rolls back by itself if the confirmation from a second SSH session
does not come within 60 s):

```bash
# 1. Regenerate the Makefile (keeps the CircleCI key), then restart the containers via supervisor
CIRCLECI_APIKEY=… 3_vm_provissioning/create_makefile.sh <vm_ip>          # Proxmox app VM
public_cloud_vm_provisioning/2_create_makefile.sh                         # public host, on the host
# 2. Firewall, replacing ufw / the old iptables script
ADMIN_SOURCES="…" [BASTION_SOURCES="…"] 2_infrastructure/setup_firewall.sh <profile> --install --disable-ufw
apt purge ufw
# 3. Verify from outside: only 22 (admin sources), 80/443 (+ profile ports) reachable
nmap -Pn -p 1-65535 <ipv4>;  nmap -6 -Pn -p 1-65535 <ipv6>
```

Hosts that run an existing Makefile in a different directory (e.g. hub16 in
`/home/lambdaroyal-anon/planetrocklog`) use `VLIC_RUNNER_DIR=<dir> 2_create_makefile.sh`.
