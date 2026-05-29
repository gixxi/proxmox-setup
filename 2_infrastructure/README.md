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

### Install requirements and install UFW

#### UFW only necessary for non-proxmox servers

### Setup UFW (Ubuntu Firewall)

als **root**

Install

> apt-get install ufw

Setup rules

```
/sbin/ufw allow ssh &&
/sbin/ufw allow http &&
/sbin/ufw allow https &&
/sbin/ufw allow 60000:61000/udp &&
/sbin/ufw enable &&
/sbin/ufw status verbose
```

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

### Benutzer lambdaroyal-anon zur Gruppe docker hinzufügen
# Add lambdaroyal-anon user to docker group
usermod -aG docker lambdaroyal-anon

# Update permissions in current session 
newgrp docker

# Allow access to docker socket
chmod 666 /var/run/docker.sock

