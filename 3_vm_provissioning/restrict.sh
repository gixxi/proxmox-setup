#!/bin/bash

# Check if the correct number of arguments are provided
if [ $# -lt 2 ] || [ $# -gt 3 ]; then
    echo "Usage: $0 <ip_address> <app or bastian> [circleci_apikey]"
    exit 1
fi

IP=$1
TYPE=$2
CIRCLECI_APIKEY=$3

if [ "$TYPE" == "app" ]; then
    ssh root@$IP exec -c "systemctl disable nginx && systemctl disable nginx && ufw allow 8080:8090/tcp && ufw allow 18080:18090/tcp && ufw allow 28080:28090/tcp"
    # Add openjdk 17 jdk to the path and install leiningen as well as sshfs and rsync for the backup process
    ssh root@$IP exec -c "apt-get install -y openjdk-17-jdk sshfs rsync cron lftp"
    ssh root@$IP exec -c "curl -o lein https://raw.githubusercontent.com/technomancy/leiningen/stable/bin/lein"
    ssh root@$IP exec -c "chmod +x lein"
    ssh root@$IP exec -c "mv lein /usr/local/bin/lein"
    
    # Create directory structure for rocklog-vlic-docker
    ssh root@$IP exec -c "mkdir -p /var/vlic/rocklog-vlic-docker/vlic_runner"
    # need to be created in the home directory
    ssh root@$IP "ln -sf /var/vlic/rocklog-vlic-docker/vlic_runner vlic_runner"
    
    # Create and deploy Makefile using the dedicated script
    echo "Deploying Makefile with memory management features..."
    SCRIPT_DIR="$(dirname "$0")"
    if [ -f "$SCRIPT_DIR/create_makefile.sh" ]; then
        "$SCRIPT_DIR/create_makefile.sh" "$IP" "$CIRCLECI_APIKEY"
    else
        echo "ERROR: create_makefile.sh not found in $SCRIPT_DIR"
        echo "Please ensure create_makefile.sh is in the same directory as restrict.sh"
        exit 1
    fi
    
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
fi

