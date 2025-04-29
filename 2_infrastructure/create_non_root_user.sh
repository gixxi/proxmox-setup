#!/bin/bash

# parameters
username=$1
if [ -z "$username" ]; then
    echo "Usage: $0 <username>"
    exit 1
fi

# Create a non-root user
adduser $username -h /home/$username
mkdir /home/$username/.ssh
chmod 700 /home/$username/.ssh
touch /home/$username/.ssh/authorized_keys
chmod 600 /home/$username/.ssh/authorized_keys
chown -R $username:$username /home/$username
