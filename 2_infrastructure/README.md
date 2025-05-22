# Infrastructure

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
adduser username -h /home/username
mkdir /home/username/.ssh
chmod 700 /home/username/.ssh
touch /home/username/.ssh/authorized_keys
chmod 600 /home/username/.ssh/authorized_keys
chown -R username:username /home/username
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

The SSH key must be added to the **authorized_keys** file of the root user.

