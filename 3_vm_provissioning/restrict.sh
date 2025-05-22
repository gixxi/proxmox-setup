#!/bin/bash

# Check if the correct number of arguments are provided
if [ $# -ne 2 ]; then
    echo "Usage: $0 <ip_address> <app or bastian>"
    exit 1
fi

IP=$1
TYPE=$2

if [ "$TYPE" == "app" ]; then
    ssh root@$IP exec -c "systemctl disable nginx && systemctl disable nginx && ufw allow 8080:8090/tcp && ufw allow 18080:18090/tcp && ufw allow 28080:28090/tcp"
    # Add openjdk 17 jdk to the path and install leiningen as well as sshfs and rsync for the backup process
    ssh root@$IP exec -c "apt-get install -y openjdk-17-jdk sshfs rsync cron"
    ssh root@$IP exec -c "curl -o lein https://raw.githubusercontent.com/technomancy/leiningen/stable/bin/lein"
    ssh root@$IP exec -c "chmod +x lein"
    ssh root@$IP exec -c "mv lein /usr/local/bin/lein"
    

elif [ "$TYPE" == "bastian" ]; then
    ssh root@$IP exec -c "systemctl disable docker"
fi

