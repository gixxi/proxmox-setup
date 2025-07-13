# Workload User Creation System

This directory contains scripts for creating workload users with controlled access to system resources.

## Scripts

### `generate_password_hash.sh`

Generates secure password hashes for cloud-init configuration.

#### Usage

```bash
# Generate hash for a password
./generate_password_hash.sh mySecurePassword123

# Generate hash for password with spaces
./generate_password_hash.sh "Complex Password with Spaces"
```

#### Output

The script provides both plain text and hash versions for cloud-init:

```yaml
# Plain text version (less secure)
chpasswd:
  list: |
    root:mySecurePassword123
  expire: false

# Hash version (more secure)
chpasswd:
  list: |
    root:$6$xyz$hash...
  expire: false
```

### `create_workload_user.sh`

Creates a workload user with the following features:

- **Variable username**: Takes username as command line argument
- **Docker access**: User is automatically added to docker group
- **Data directory access**: Read/write access to `/data` and subdirectories
- **Limited sudo access**: Only specific commands for system monitoring
- **SSH setup**: Creates SSH directory structure
- **User profile**: Helpful aliases and environment setup

#### Usage

```bash
# Create a workload user named 'myapp'
sudo /usr/local/bin/create_workload_user.sh myapp

# Create a workload user named 'webapp'
sudo /usr/local/bin/create_workload_user.sh webapp

# Create a workload user named 'database'
sudo /usr/local/bin/create_workload_user.sh database
```

#### What the script does

1. **Creates user and group** with the specified username
2. **Adds user to docker group** for Docker access without sudo
3. **Sets up SSH directory** with proper permissions
4. **Configures data directory permissions**:
   - `/data` owned by `root:<username>`
   - Permissions: `775` (root read/write, user group read/write)
   - Subdirectories: `docker`, `apps`, `backup`, `logs`
5. **Creates user profile** with helpful aliases
6. **Sets up limited sudo access** for system monitoring
7. **Creates documentation** in user's home directory

#### Sudo Access (Limited)

The workload user gets sudo access to these commands only:

```bash
# System monitoring
sudo systemctl status *
sudo journalctl *

# Docker operations
sudo docker *
sudo docker-compose *

# ZFS operations
sudo zfs *
sudo zpool *

# Firewall status
sudo ufw status

# Supervisor operations
sudo supervisorctl status
sudo supervisorctl restart *
sudo supervisorctl stop *
sudo supervisorctl start *
```

#### Docker Access

The user is automatically added to the `docker` group, allowing:

```bash
# No sudo needed for Docker commands
docker ps
docker-compose up -d
docker run nginx
```

#### Data Directory Access

The user has full read/write access to:

- `/data/apps` - Application data and configurations
- `/data/logs` - Application and system logs  
- `/data/backup` - Backup files and archives
- `/data/docker` - Docker volumes and data

## Cloud-Init Integration

### Option 1: Manual Creation

After cloud-init deployment, manually create workload users:

```bash
# SSH as admin
ssh admin@server

# Create workload user
sudo /usr/local/bin/create_workload_user.sh myapp

# Add SSH key for the user
sudo mkdir -p /home/myapp/.ssh
sudo echo "ssh-rsa YOUR_PUBLIC_KEY" > /home/myapp/.ssh/authorized_keys
sudo chown -R myapp:myapp /home/myapp/.ssh
sudo chmod 700 /home/myapp/.ssh
sudo chmod 600 /home/myapp/.ssh/authorized_keys

# Update SSH config to allow the user
sudo sed -i "s/AllowUsers admin/AllowUsers admin myapp/" /etc/ssh/sshd_config
sudo systemctl reload ssh
```

### Option 2: Cloud-Init Template

Use the `workload_user_config.yml` template in your cloud-init configuration:

1. Copy `cloud_init_templates/workload_user_config.yml`
2. Modify the `WORKLOAD_USERNAME` variable
3. Add your SSH public key
4. Include in your cloud-init configuration

Example cloud-init configuration:

```yaml
#cloud-config
# Include base configuration
include:
  - base_config.yml
  - zfs_config.yml
  - network_config.yml
  - docker_config.yml
  - workload_user_config.yml

# Override workload username
WORKLOAD_USERNAME: myapp
```

## Security Benefits

1. **Principle of least privilege**: Users only have access to what they need
2. **Separation of concerns**: Admin for system management, workload users for applications
3. **Docker security**: Users can run Docker without sudo access
4. **Data protection**: Controlled access to `/data` directory
5. **Audit trail**: Limited sudo access makes tracking easier

## Example Workflow

```bash
# 1. Deploy server with cloud-init
# 2. SSH as admin
ssh admin@server

# 3. Create workload user
sudo /usr/local/bin/create_workload_user.sh myapp

# 4. Add SSH key
sudo mkdir -p /home/myapp/.ssh
sudo echo "ssh-rsa AAAAB3NzaC1yc2E..." > /home/myapp/.ssh/authorized_keys
sudo chown -R myapp:myapp /home/myapp/.ssh
sudo chmod 700 /home/myapp/.ssh
sudo chmod 600 /home/myapp/.ssh/authorized_keys

# 5. Update SSH config
sudo sed -i "s/AllowUsers admin/AllowUsers admin myapp/" /etc/ssh/sshd_config
sudo systemctl reload ssh

# 6. Test workload user access
ssh myapp@server
docker ps
cd /data/apps
ls -la
```

## Troubleshooting

### User not in docker group
```bash
sudo usermod -a -G docker <username>
# User needs to log out and back in for group changes to take effect
```

### Permission denied on /data
```bash
sudo chown root:<username> /data
sudo chmod 775 /data
```

### SSH access denied
```bash
# Check SSH config
sudo grep AllowUsers /etc/ssh/sshd_config

# Add user to AllowUsers
sudo sed -i "s/AllowUsers admin/AllowUsers admin <username>/" /etc/ssh/sshd_config
sudo systemctl reload ssh
``` 