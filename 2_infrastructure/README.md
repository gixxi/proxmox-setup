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

Worked example for a single public Docker host (several admin IPs, nginx → containers):
[`../public_cloud_vm_provisioning/README.md` → Firewall (`docker-public`)](../public_cloud_vm_provisioning/README.md#firewall-docker-public).

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

