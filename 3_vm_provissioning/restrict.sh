#!/bin/bash
# Restrict a freshly provisioned VM to its role and install the host firewall.
#
# Usage: ADMIN_SOURCES="<ip/cidr …>" [BASTION_SOURCES="<bastion ip>"] \
#        [CIRCLECI_APIKEY=…] ./restrict.sh <ip_address> <app|bastian> [circleci_apikey]
#
#   ADMIN_SOURCES    SSH sources for the VM (required), e.g. "116.203.216.1 5.161.184.133 192.168.1.0/24"
#   BASTION_SOURCES  app only: the bastion that proxies to this VM (required for app)
#
# Firewall: ../2_infrastructure/setup_firewall.sh (iptables, replaces ufw). On app VMs the containers
# are reachable only from BASTION_SOURCES on the app port; nREPL/CouchDB are bound to 127.0.0.1 by the
# Makefile (../lib/vlic_runner_makefile.sh).

set -euo pipefail

if [ $# -lt 2 ] || [ $# -gt 3 ]; then
    echo "Usage: ADMIN_SOURCES=\"…\" [BASTION_SOURCES=\"…\"] $0 <ip_address> <app or bastian> [circleci_apikey]"
    exit 1
fi

IP=$1
TYPE=$2
CIRCLECI_APIKEY=${3:-${CIRCLECI_APIKEY:-}}
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FIREWALL="$SCRIPT_DIR/../2_infrastructure/setup_firewall.sh"

sources_ok() { [[ $1 =~ ^[0-9a-fA-F:./\ ]+$ || $1 == any ]]; }
: "${ADMIN_SOURCES:?set ADMIN_SOURCES (SSH sources), see header}"
sources_ok "$ADMIN_SOURCES" || { echo "invalid ADMIN_SOURCES"; exit 1; }

# install_firewall <profile> [VAR=value …] — copy the shared firewall script and apply it persistently.
# --yes: a fresh VM is still reachable via the Proxmox console if something goes wrong.
install_firewall() {
    local profile=$1; shift
    scp "$FIREWALL" "root@$IP:/root/setup_firewall.sh"
    ssh "root@$IP" "$* bash /root/setup_firewall.sh $profile --yes --install --disable-ufw"
}

if [ "$TYPE" == "app" ]; then
    : "${BASTION_SOURCES:?set BASTION_SOURCES (bastion IP) for app VMs}"
    sources_ok "$BASTION_SOURCES" || { echo "invalid BASTION_SOURCES"; exit 1; }

    ssh root@$IP exec -c "systemctl disable nginx"
    install_firewall app-vm "ADMIN_SOURCES='$ADMIN_SOURCES' BASTION_SOURCES='$BASTION_SOURCES'"

    # Add openjdk 17 jdk to the path and install leiningen as well as sshfs and rsync for the backup process
    ssh root@$IP exec -c "apt-get install -y openjdk-17-jdk sshfs rsync cron lftp"
    ssh root@$IP exec -c "curl -fsSL -o lein https://raw.githubusercontent.com/technomancy/leiningen/stable/bin/lein"
    ssh root@$IP exec -c "chmod +x lein"
    ssh root@$IP exec -c "mv lein /usr/local/bin/lein"

    # Create directory structure for rocklog-vlic-docker
    ssh root@$IP exec -c "mkdir -p /var/vlic/rocklog-vlic-docker/vlic_runner"
    # need to be created in the home directory
    ssh root@$IP "ln -sf /var/vlic/rocklog-vlic-docker/vlic_runner vlic_runner"

    # Create and deploy Makefile using the dedicated script (key via env, not argv)
    echo "Deploying Makefile with memory management features..."
    CIRCLECI_APIKEY="$CIRCLECI_APIKEY" "$SCRIPT_DIR/create_makefile.sh" "$IP"

    # Create supervisor template using a different approach
    cat > /tmp/supervisor_template << 'EOF'
[program:CUSTOMER_NAME]
; 2023-12-11 3883 <-- we use this for versioning
; 2025-03-13 4858
; Memory optimization: ENABLE_SWAP=true allows container to use swap when under pressure
; MEMORY_RESERVATION_GB auto-calculated as Xmx+2GB, SWAPPINESS=10 minimizes swap usage
command=make 64bit BUILD=4858 CONT_NAME=CUSTOMER_NAME VLIC_PORT=8080 IMAGE=hub5.planet-rocklog.com:5000/vlic/vlic_runner:v12 CORES=2 Xmx=5g ENABLE_SWAP=true SWAPPINESS=10
directory=/var/vlic/rocklog-vlic-docker/vlic_runner
user=root
autostart=true
autorestart=unexpected
startsecs=10
startretries=1
exitcodes=0,2
stopsignal=TERM
stopwaitsecs=10
stopasgroup=false
killasgroup=false
redirect_stderr=false
stdout_logfile=/var/vlic/rocklog-vlic-docker/vlic_runner/CUSTOMER_NAME.log
stdout_logfile_maxbytes=10MB
stdout_logfile_backups=5
stdout_capture_maxbytes=10MB
stdout_events_enabled=false
stderr_logfile=/var/vlic/rocklog-vlic-docker/vlic_runner/CUSTOMER_NAME.err
stderr_logfile_maxbytes=10MB
stderr_logfile_backups=5
stderr_capture_maxbytes=10MB
stderr_events_enabled=false
EOF

    scp /tmp/supervisor_template root@$IP:/etc/supervisor/conf.d/example.conf.template
    rm /tmp/supervisor_template

elif [ "$TYPE" == "bastian" ]; then
    ssh root@$IP exec -c "systemctl disable docker"
    install_firewall bastion "ADMIN_SOURCES='$ADMIN_SOURCES'"
else
    echo "Unknown type '$TYPE' (app | bastian)"; exit 1
fi
