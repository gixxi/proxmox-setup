# Infrastructure

## Set root pw

> passwd ...

und unter [server root credentials]{https://docs.google.com/}

## SSH Hardening

In order to login to any Proxmox host using SSH the following requirements must be met:

- The host must be reachable from the IP address of the client
- The client IP address must be whitelisted in the Proxmox host hosts.allow file
- The username must be whitelisted in the **sshd_config** file
- The user must have a valid SSH key in the **authorized_keys** file
- The user is a non-root user

### Whitelisting the client IP address in the Proxmox host hosts.allow file

```bash
# Edit the hosts.allow file
nano /etc/hosts.allow

# Add the client IP address to the hosts.allow file
sshd: 192.168.1.100
sshd: 116.203.216.1
sshd: 192.168.1.0/24
sshd: 5.161.184.133

# Save and exit
```

### Deny all other SSH access

```bash
# Edit the hosts.deny file
nano /etc/hosts.deny

# Add the following line to the hosts.deny file
sshd:  all

# Save and exit
```

### Create a non-root user

```bash
USERN=lambdaroyal-anon && adduser $USERN -h /home/$USERN &&
mkdir /home/$USERN/.ssh && \\
chmod 700 /home/$USERN/.ssh && \\
touch /home/$USERN/.ssh/authorized_keys && \\
chmod 600 /home/$USERN/.ssh/authorized_keys && \\
chown -R $USERN:$USERN /home/$USERN
```

### Adding the username to the sshd_config file

The username must be added to the **sshd_config** file.

```bash
# Edit the sshd_config file
nano /etc/ssh/sshd_config

# Add the username to the sshd_config file
AllowUsers username

# Save and exit
```

### Adding the SSH key to the authorized_keys file

The SSH key must be added to the **authorized_keys** file of the root user and the extra user created above.

als user **root** ausführen

```bash
USERN=lambdaroyal-anon && chown -R $USERN:$USERN /home/$USERN/.ssh
chmod 700 /home/$USERN/.ssh
chmod 600 /home/$USERN/.ssh/authorized_keys
```

### Install requirements and the firewall

### Firewall (iptables, replaces ufw)

All hosts use `setup_firewall.sh` (in this folder) with a profile: `proxmox`, `bastion`, `app-vm`
or `docker-public`. ufw is no longer used — on Docker hosts it does not see published container
ports at all (rocklog-vlic `doc/security/incident-2026-10-15-hub16.md`). The script only manages its
own chains plus `DOCKER-USER`, never Docker's chains or NAT, covers IPv6, and rolls back
automatically unless you confirm from a second SSH session.

als **root**

```
# preview
ADMIN_SOURCES="116.203.216.1 5.161.184.133 192.168.1.0/24" ./setup_firewall.sh proxmox --dry-run
# apply, confirm within 60 s, persist (systemd unit rocklog-firewall.service), switch off ufw
ADMIN_SOURCES="116.203.216.1 5.161.184.133 192.168.1.0/24" ./setup_firewall.sh proxmox --install --disable-ufw
apt purge ufw          # once confirmed
./setup_firewall.sh status
```

Settings are stored in `/etc/rocklog-firewall.conf`; see the header of `setup_firewall.sh`.

All profiles also drop IPv4 TCP packets carrying IP options in `raw`/`PREROUTING` (chain
`ROCKLOG-RAW`, log prefix `FW-IPOPT-DROP`) — the trigger of CVE-2026-98432; switch off with
`TCP_IPOPT_GUARD=no`. Rules added by hand with `iptables …` are **not** persistent: the systemd unit
only rebuilds the script's own chains and `netfilter-persistent` is disabled on purpose. Put
permanent rules into `setup_firewall.sh`, then on each host re-run it with `--install` (or copy the
script to `/usr/local/sbin/rocklog-firewall` and run `rocklog-firewall apply`).

Worked example for a single public Docker host (several admin IPs, nginx → containers):
[`../public_cloud_vm_provisioning/README.md` → Firewall (`docker-public`)](../public_cloud_vm_provisioning/README.md#firewall-docker-public).

### Verify the firewall

> **⚠️ Do all three checks after every firewall change, on every host, and once more after the next
> reboot. A firewall that was only checked from the host itself is not verified** — ufw on hub16
> looked fine locally while CouchDB and nREPL were open to the internet.

#### Check 1 — on the host: loaded, current, persistent

```bash
rocklog-firewall status
cmp /usr/local/sbin/rocklog-firewall /path/to/proxmox-setup/2_infrastructure/setup_firewall.sh && echo "installed copy is current"
```

| Look for | Correct | If not |
|---|---|---|
| `-A PREROUTING -j ROCKLOG-RAW` | first rule after `-P PREROUTING ACCEPT` | `rocklog-firewall apply` |
| `Chain ROCKLOG-RAW` | 2 rules: `LOG … FW-IPOPT-DROP`, `DROP` | `rocklog-firewall apply` |
| `-P INPUT DROP` | exactly this | `rocklog-firewall apply` |
| `-A INPUT -j ROCKLOG-INPUT` | first rule after the policy | `rocklog-firewall apply` |
| `Chain ROCKLOG-INPUT`, last rule | `DROP` with no conditions | `rocklog-firewall apply` |
| `tcp dpt:22` rules in ROCKLOG-INPUT | one per `ADMIN_SOURCES` entry, with that source IP | fix `ADMIN_SOURCES` in `/etc/rocklog-firewall.conf`, `rocklog-firewall apply` |
| `Chain DOCKER-USER (1 references)` *(app-vm, docker-public)* | **1** reference; ends with `DROP … eth0 … ctstate NEW`, then `RETURN` | 0 references = Docker isn't jumping to it: is Docker running with `"iptables": true`? |
| `rocklog-firewall.service:` | `enabled` | rerun `setup_firewall.sh <profile> --install` |
| `netfilter-persistent:` | `disabled` or `not-found` | rerun with `--install` |
| `ufw:` | `inactive` or `not installed` | rerun with `--disable-ufw`, then `apt purge ufw` |
| `cmp` | `installed copy is current` | `install -m 700 setup_firewall.sh /usr/local/sbin/rocklog-firewall && rocklog-firewall apply` |

The systemd unit runs the **installed copy** at boot, not the repo checkout, so an outdated copy means
the next reboot silently loads old rules.

#### Check 2 — from outside: what the internet sees

Run from a machine that is **neither the host itself nor in `ADMIN_SOURCES`**, e.g. a laptop on a
phone hotspot or another cloud VM. From the host everything looks open (loopback is accepted); from
an admin IP, port 22 shows `open`, which is correct.

```bash
H=<public IPv4 or hostname>

# quick: the ports that matter (DB, nREPL, app/admin ports, Proxmox UI) — ~10 s
nmap -Pn -p 22,80,443,3000-3005,4050,5432,5984,5986,8006,8080-8085,8443,18080-18085,28080-28085 $H

# full sweep, IPv4 and IPv6 — 10–20 min each
nmap -Pn -p- $H
nmap -6 -Pn -p- <public IPv6>
```

| Profile | Must be `open` | Everything else |
|---|---|---|
| `docker-public` | 80, 443 | `filtered` |
| `bastion` | 80, 443, 8080, 8443 | `filtered` |
| `app-vm` | nothing (8080 only from the bastion) | `filtered` |
| `proxmox` | 80, 443 (22 and 8006 only from `ADMIN_SOURCES`) | `filtered` |

**Red flags — stop and investigate:**

- **4050, 5432, 5984, 18080–18085, 28080–28085 or 3000–3005 `open`**: nREPL, PostgreSQL or CouchDB on
  the internet — exactly the hub16 incident. Check `DOCKER-USER` (check 1) and bind the container to
  `127.0.0.1`.
- **`closed` instead of `filtered`**: the host answered with a TCP reset, so the packet reached it
  without being dropped. The `INPUT DROP` policy isn't active.
- **22 `open` from a non-admin network**: `ADMIN_SOURCES=any`, or a leftover ufw/iptables rule.
- **IPv6 shows ports that IPv4 doesn't**: ip6tables rules missing; rerun `rocklog-firewall apply`.

#### Check 3 — IP-options guard (CVE-2026-98432)

From outside, as root (`nping` comes with nmap), while you watch the counter on the host:

```bash
nping --tcp --flags syn -p 443 -c 3 $H                    # baseline: "RCVD … SA" (SYN-ACK) lines
nping --tcp --flags syn -p 443 -c 3 --ip-options R $H     # expected: no SA reply

# on the host, before and after:
iptables -t raw -L ROCKLOG-RAW -nv                        # DROP counter +3
```

- **No reply and counter +3:** guard works.
- **SYN-ACK to the probe with options:** guard is not active; go back to check 1.
- **No reply, counter unchanged:** the probe was dropped on the way (many networks filter IP options).
  The guard is untested, not broken; repeat from another network.

Probes in daily operation show up as `FW-IPOPT-DROP` in `journalctl -k`.

## Install necessary tools

> apt-get install emacs nano vim git xclip sudo ftp make supervisor lftp mosh nginx curl wget tmux openssh-server net-tools postgresql-client

## Set timezone to CET

> timedatectl set-timezone Europe/Berlin

### Bash als Standard-Shell setzen

> chsh -s /bin/bash lambdaroyal-anon

## Docker installieren

Docker installieren für Debian 13 incl. docker compose

```bash
for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do apt-get remove $pkg; done
# Offiziellen GPG-Schlüssel von Docker hinzufügen:
apt-get update
apt-get install ca-certificates curl
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

# Repository zu Apt-Quellen hinzufügen:
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update
apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```


## Add lambdaroyal-anon user to docker group
usermod -aG docker lambdaroyal-anon

## Update permissions in current session 
newgrp docker

## Docker socket

Do **not** `chmod 666 /var/run/docker.sock`: every local user and every process could then start a
privileged container, i.e. become root. Membership in the `docker` group (above) is root-equivalent
as well — grant it only to admin accounts. Log out and in again instead of loosening the socket.

# Einrichtung Nginx

```
apt-get install nginx
service nginx enable
```
Im Template ggf. Ports und Pfad zum Zertifikat anpassen!


## Anpassen der Konfiguration für das Einlesen von Subdomänenkonfigurationen

für Planet Rocklog besteht jede Konfiguration aus zwei Files:

1. Konfiguration eines virtuellen Servers 

- Eingelesen durch sites-enabled/*.conf

2. Konfiguration eines Locations Blocks

- Eingelesen durch sites-enabled/locations/*.conf

Für die Sicherstellung ist das File /etc/nginx/nginx.conf so zu konfigurieren, dass es die Files aus sites-enabled/*.conf und sites-enabled/locations/*.conf einliest.

```nginx
##
    # Virtual Host Configs
    ##
    include /etc/nginx/conf.d/*.conf;
    # Include individual .conf files from sites-enabled
    include /etc/nginx/sites-enabled/*.conf;
    # Explicitly include the standard default site if it exists
    include /etc/nginx/sites-enabled/default;
```


# Einrichtung Letsencrypt Certificat mit HTTP Challenge

> apt-get install snapd

Install certbot

> snap install --classic certbot

Create a link for convenience

> ln -s /snap/bin/certbot /usr/bin/certbot

Get the certificate

> certbot certonly --webroot

use info@rocklog.ch as email

Say yes to everything :)

enter subdomain, e.g.

> hub8.planet-rocklog.com

enter webroot

> /var/www/html

# Mail Relay Configuration

Keycloak versucht Emails über den Google Mailrelay. Dazu muss die IP des Servers in der GCP Adminconsole hinterlegt sein. Nach relay suchen.

# Devops

## Branch-Verwaltung

Die durch rocklogEDGE benötigen Docker Images werden durch den Docker Hub bereitgestellt. Für die Anmeldung des Hosts bei Docker Hub wird ein Authorisierungschlüssel benötigt.

(per github anmelden und Personal access token besorgen)
[https://app.docker.com/accounts/gixxi/settings/personal-access-tokens](https://app.docker.com/accounts/gixxi/settings/personal-access-tokens)

Dort einen Token für den spezifischen Host erzeugen.

Dann login mittels

```bash
docker login -u gixxi
```

