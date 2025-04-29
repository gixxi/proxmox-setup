#!/bin/bash

# Check if the correct number of arguments are provided
if [ $# -ne 2 ]; then
    echo "Usage: $0 <ip_address> <app or bastian>"

IP=$1
TYPE=$2

if [ "$TYPE" == "app" ]; then
    ssh root@$IP exec -c "systemctl disable nginx && systemctl disable nginx && ufw allow 8080:8090/tcp && ufw allow 18080:18090/tcp && ufw allow 28080:28090/tcp"
elif [ "$TYPE" == "bastian" ]; then
    ssh root@$IP exec -c "systemctl disable docker"
fi

