# Synopsis

The bastion host is a host that is used to access the cluster nodes. It is used to access the cluster nodes from the outside world. It serves two main purposes:

- provide a single point of entry for the outside world to access the cluster nodes via http/https
- provide a single point of entry for the outside world to access the cluster nodes via ssh





# Prerequisites

install tofu

```bash
# Download the installer script:
curl --proto '=https' --tlsv1.2 -fsSL https://get.opentofu.org/install-opentofu.sh -o install-opentofu.sh
# Alternatively: wget --secure-protocol=TLSv1_2 --https-only https://get.opentofu.org/install-opentofu.sh -O install-opentofu.sh

# Give it execution permissions:
chmod +x install-opentofu.sh

# Please inspect the downloaded script

# Run the installer:
./install-opentofu.sh --install-method deb

# Remove the installer:
rm -f install-opentofu.sh
```

or on fedora

```bash
# Download the installer script
curl --proto '=https' --tlsv1.2 -fsSL https://get.opentofu.org/install-opentofu.sh -o install-opentofu.sh

# Make it executable
chmod +x install-opentofu.sh

# Run the installer with the rpm method (for Fedora)
./install-opentofu.sh --install-method rpm

# Remove the installer
rm -f install-opentofu.sh
```


