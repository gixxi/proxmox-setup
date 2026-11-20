# proxmox-setup
Setting up proxmox on bare metal. Describes preliminary actions, setting up the cluster nodes and best practices right after

## Target audience and version

This guide is for setting up Proxmox VE 9 (Debian 13 "trixie") on bare metal. Nodes still on
Proxmox VE 8 are end of life — see [Upgrading a Proxmox VE 8 node](#3-upgrading-a-proxmox-ve-8-node).

# Preliminary actions

## 1. Download the ISO image and create a bootable USB

Head to the [Proxmox VE](https://www.proxmox.com/en/downloads/proxmox-virtual-environment/iso) website and download the latest ISO image.

Then, create a bootable USB using linux command line tools.

Check the device name of the USB drive using `lsblk` or `fdisk -l`.

e.g. 

> fdisk -l

yields

```sh
Disk /dev/sda: 14.53 GiB, 15597568000 bytes, 30464000 sectors
Disk model: Ultra           
Units: sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes
Disklabel type: dos
Disk identifier: 0x00000000
```
replace *sdX* with the device name of the USB drive.

```bash
sudo dd if=/path/to/proxmox-ve.iso of=/dev/sdX bs=4M status=progress && sync
```

## 2. Install Proxmox VE on the target machines

Make sure the target machines are booted from the bootable USB and boot from the USB drive.

Aim for graphical installation. 
Confirm the EULA.

### Choosing the volume

Choose the volume to install Proxmox VE. We will use the entire disk for the installation and opt for ZFS.

The ratio for ZFS is to be able to create a snapshot of the root volume.

Always use different storage devices for the installation and for the virtual machines. This allows us to redo the installation without losing the virtual machines.zu

### ZFS Options for the root volume

Make sure to use a ashift value of as per the block size of the storage device, otherwise we end up with write amplification and our disks will wear out faster.

### Addtional options

- use a network interface for the management network you are not using for the communication between the nodes nor between the nodes and the outside world.

# First steps on the Proxmox VE

## 1. Package repositories

Proxmox VE 9 uses the deb822 format (`/etc/apt/sources.list.d/*.sources`). Rules for every node:

- **Debian and Debian security over https.** CVE-2026-109518 (APT, 2026-11) lets an attacker in the
  network path swap a package during `apt-get update` and run code as root on an unpatched apt; https
  closes that path. `ftp.ch.debian.org` does not serve https — use `deb.debian.org`.
- **Proxmox enterprise repositories** (`enterprise.proxmox.com`) are https-only. Use them on nodes
  with a subscription.
- **Proxmox no-subscription repositories** (`download.proxmox.com`) have **no valid https**: IPv4
  presents a certificate for another name, IPv6 has no port 443. Keep them on `http://` — the
  packages are signed with the Proxmox key, which protects them once apt is patched (Debian 13: apt
  ≥ 3.0.4, Debian 12: apt ≥ 2.6.2).
- **Ceph** on PVE 9 is Squid (`ceph-squid`, suite `trixie`). PVE 9 ships the Ceph client
  (`ceph-common`, `ceph-fuse`) even without a Ceph cluster, so configure the matching repository
  anyway; a leftover `ceph-quincy bookworm` entry from PVE 8 must go.
- One entry per repository. Old `*.list` files next to the `*.sources` files produce
  "configured multiple times" warnings; move them out of `sources.list.d/`.

**Bash version** — run as root on a fresh node:

```bash
mkdir -p /root/apt-old && cp -a /etc/apt /root/apt-old/apt-$(date +%F)
# PVE 8 leftovers and old one-line Debian/Proxmox/Ceph entries (third-party lists such as Docker stay)
for f in pve-enterprise.list pve-no-subscription.list pve-install-repo.list ceph.list ceph.list.off ceph.list.bak; do
  [ -e "/etc/apt/sources.list.d/$f" ] && mv "/etc/apt/sources.list.d/$f" /root/apt-old/
done
: > /etc/apt/sources.list

cat > /etc/apt/sources.list.d/debian.sources <<'SRC'
Types: deb
URIs: https://deb.debian.org/debian
Suites: trixie trixie-updates
Components: main contrib non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: https://security.debian.org/debian-security
Suites: trixie-security
Components: main contrib non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
SRC
```

Then **either** — node **with** subscription (enterprise):

```bash
pvesubscription get | grep -i status     # must be "active", otherwise apt-get update fails with 401
cat > /etc/apt/sources.list.d/pve-enterprise.sources <<'SRC'
Types: deb
URIs: https://enterprise.proxmox.com/debian/pve
Suites: trixie
Components: pve-enterprise
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
SRC
cat > /etc/apt/sources.list.d/ceph.sources <<'SRC'
Types: deb
URIs: https://enterprise.proxmox.com/debian/ceph-squid
Suites: trixie
Components: enterprise
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
SRC
```

**or** — node **without** subscription (no-subscription):

```bash
cat > /etc/apt/sources.list.d/pve-enterprise.sources <<'SRC'
Types: deb
URIs: https://enterprise.proxmox.com/debian/pve
Suites: trixie
Components: pve-enterprise
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
Enabled: no
SRC
cat > /etc/apt/sources.list.d/proxmox.sources <<'SRC'
Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: trixie
Components: pve-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
SRC
cat > /etc/apt/sources.list.d/ceph.sources <<'SRC'
Types: deb
URIs: http://download.proxmox.com/debian/ceph-squid
Suites: trixie
Components: no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
SRC
```

Check and update — apt itself first:

```bash
chmod 644 /etc/apt/sources.list.d/*.sources
apt-get update 2>&1 | grep -E '^(Hit|Get|Err|W:|E:|Warning)'   # no Err, no "configured multiple times"
apt-get install --only-upgrade apt
apt policy apt | head -3                                         # Installed: >= 3.0.4
apt-get dist-upgrade                                             # on PVE never plain "apt upgrade"
```

## 2. Keeping a node patched

- Update with `apt-get dist-upgrade` (or *Node → Updates → Upgrade*). Kernel fixes only take effect
  after a **reboot**: migrate or shut down the guests (`qm list`, `pct list`), `reboot`, then check
  `uname -r`, `pveversion` and that the guests are back.
- PVE runs the Proxmox kernel (`proxmox-kernel-*`), not Debian's. Compare it with the Proxmox
  security advisories (PSA), not with Debian's DSA versions. Example: CVE-2026-98432 is fixed in
  `proxmox-kernel-7.0.14-25-pve` and later (PSA-2026-00080-1).
- Remove old kernels only after the new one has booted: `apt autoremove --purge`, then
  `proxmox-boot-tool kernel list` must still show the running kernel plus one fallback.
- Every node runs the Rocklog firewall, profile `proxmox`:
  `2_infrastructure/setup_firewall.sh proxmox --install` (see `2_infrastructure/README.md`).

## 3. Upgrading a Proxmox VE 8 node

Proxmox VE 8 (Debian 12) reached end of life on 2026-08-31 and gets no Proxmox kernel or QEMU fixes
any more. Upgrade in place following the official *Upgrade from 8 to 9* guide: run `pve8to9 --full`
until it reports no failures, upgrade an existing Ceph cluster to Squid **before** the PVE step, then
switch the repositories as in section 1 (suite `trixie`).

# 2. Hardening the Proxmox VE

## 2.1. Setup sshd to only pubkey authentication for non-root users

1. Become root
2. Create a new user on the proxmox 

```bash
USER=gix && useradd -d /home/$USER -c "$USER vlic anonymous" $USER && mkdir -p /home/$USER/.ssh && touch /home/$USER/.ssh/authorized_keys && chown -R $USER /home/$USER
```

3. Add the public key to the authorized_keys file

```bash
USER=gix && echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDJ+1234567890" >> /home/$USER/.ssh/authorized_keys
```

Repeat for all users you want to allow.

4. Setup sshd

run the following script

```bash
#!/bin/bash

# Define the SSH config file path
SSH_CONFIG="/etc/ssh/sshd_config"

# Create a timestamped backup
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="${SSH_CONFIG}.backup.${TIMESTAMP}"

echo "Creating backup of SSH config at ${BACKUP_FILE}"
cp "${SSH_CONFIG}" "${BACKUP_FILE}"

# Check if backup was successful
if [ ! -f "${BACKUP_FILE}" ]; then
  echo "Error: Failed to create backup file. Aborting."
  exit 1
fi

echo "Modifying SSH configuration..."

# Create a temporary file for the new configuration
TMP_FILE=$(mktemp)

# Get original permissions to preserve them
ORIGINAL_PERMS=$(stat -c "%a" "${SSH_CONFIG}")

# First, change PermitRootLogin from yes to no
sed 's/^PermitRootLogin yes/PermitRootLogin no/' "${SSH_CONFIG}" > "${TMP_FILE}"

# Now add or update all the security options
cat > "${TMP_FILE}" << EOF
# SSH Configuration modified on $(date)
# Original file backed up at ${BACKUP_FILE}

Port 22
Protocol 2
AllowUsers gix
LoginGraceTime 2m
PermitRootLogin no
StrictModes yes
MaxAuthTries 1
PubkeyAuthentication yes
AuthorizedKeysFile %h/.ssh/authorized_keys
RhostsRSAAuthentication no
PasswordAuthentication no
PermitEmptyPasswords no
UsePAM yes

# Preserving original configuration below
$(grep -v "^Port\|^Protocol\|^AllowUsers\|^LoginGraceTime\|^PermitRootLogin\|^StrictModes\|^MaxAuthTries\|^PubkeyAuthentication\|^AuthorizedKeysFile\|^RhostsRSAAuthentication\|^PasswordAuthentication\|^PermitEmptyPasswords\|^UsePAM" "${SSH_CONFIG}")
EOF

# Apply the changes
mv "${TMP_FILE}" "${SSH_CONFIG}"

# Restore original permissions
chmod "${ORIGINAL_PERMS}" "${SSH_CONFIG}"

echo "SSH configuration updated successfully."

# Validate the configuration
echo "Validating SSH configuration..."
sshd -t
if [ $? -ne 0 ]; then
  echo "Error: SSH configuration is invalid. Restoring backup..."
  cp "${BACKUP_FILE}" "${SSH_CONFIG}"
  chmod "${ORIGINAL_PERMS}" "${SSH_CONFIG}"
  echo "Backup restored. Please check your configuration manually."
  exit 1
fi

# Reload SSH daemon
echo "Reloading SSH daemon..."
/etc/init.d/ssh reload

echo "SSH configuration has been updated and service reloaded."
echo "IMPORTANT: Make sure you have another way to access the system before logging out!"
echo "After logging in, you can switch to root using: su -"
```

### Set bash as std shell

> chsh -s /bin/bash lambdaroyal-anon


2. Create a ZFS pool **data**

![alt text](image-2.png)

![alt text](image-1.png)
## 2. Create a virtual machine

## 3. Install the OS

## 4. Install proxmox

## 5. Install the cluster nodes


## 6. Deploy containerized services

### 6.1. Important configuration invariants

- set proper network bridge for the container
- set manual IP for the container
- set the gateway the host is using as well

#### Restrict ssh access to the container

using TCP Wrapper

```bash
apt-get install libnss-wrapper
```

/etc/hosts.allow

```bash
# /etc/hosts.allow: list of hosts that are allowed to access the system.
#                   See the manual pages hosts_access(5) and hosts_options(5).
#
# Example:    ALL: LOCAL @some_netgroup
#             ALL: .foobar.edu EXCEPT terminalserver.foobar.edu
#
# If you're going to protect the portmapper use the name "rpcbind" for the
# daemon name. See rpcbind(8) and rpc.mountd(8) for further information.
#
sshd: 192.168.1.100
sshd: 116.203.216.1
sshd: 192.168.1.0/24
sshd: 5.161.184.133
```

/etc/hosts.deny  

```bash
sshd: ALL
```





 Allow SSH access only from specific subnet

```bash
Match Address 192.168.1.0/24
    PermitRootLogin no
    PasswordAuthentication no
    PubkeyAuthentication yes
```


