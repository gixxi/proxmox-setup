#!/bin/bash
# Christian Meichsner &  Frank Schneider
# Daily rsync Backup 

# This script consumes the subsequently listed parameters
#   -s source  -f server  -d remote dir  -u user
#   -P file    password file (mode 600) — preferred; -p password shows up in ps and crontab

while getopts :s:f:d:u:p:P: OPTION ; do
  case "$OPTION" in
    s)   
         source=$OPTARG
         echo "Using $OPTARG as source for archiving"
         ;;
    d)   
         rsyncdir=$OPTARG
         echo "Using $OPTARG as ftp upload dir"
         ;;
    f)   
         ftpserver=$OPTARG
         echo "Using $OPTARG as ftp server"
         ;;
    u)   
         ftpuser=$OPTARG
         echo "Using $OPTARG as ftp user"
         ;;
    p)   ftppass=$OPTARG;;
    P)   ftppass=$(cat "$OPTARG");;
    *)   echo "Unknown parameter"
         exit 1
         ;;
  esac
done

# backups must not be readable or writable by other local users
umask 077
mnt_dir="/tmp/backupmnt/"
day=`LC_ALL=C date +%A`

cd /tmp

mkdir -p /tmp/backupmnt/

chmod 700 backupmnt/

echo 
echo ordner fuer $source mounten...

if mountpoint -q $mnt_dir ; then
    echo "It is already a mounted mountpoint"
else
    echo "Attempting to mount with SSHFS..."
    # Added error checking for mount command
    if printf '%s\n' "$ftppass" | sshfs -o reconnect,ServerAliveInterval=15,ServerAliveCountMax=3,noforget,password_stdin $ftpuser@$ftpserver:$rsyncdir/ $mnt_dir ; then
        echo "Mount successful"
    else
        echo "Mount failed - aborting backup"
        exit 1
    fi
fi

# Only proceed with backup if mounting was successful
if mountpoint -q $mnt_dir ; then
    cd $source/

    echo sicherung startet fuer $source...

    mkdir -p $mnt_dir/sicherung_$source

    rsync -av --partial --no-perms --progress --inplace --no-group --no-owner --exclude={/log/,/logs/,/tmp/vlic/printing/tmp/,/tmp/vlic/dump.evictor/,/tmp/vlic/interfaces/} $source/ $mnt_dir/sicherung_$source/$source-$day/ >> /var/log/backup/log_backup_$source.log

    echo unmount ordner fuer $source...

    fusermount -zu $mnt_dir
    umount -l $mnt_dir
fi

# rmdir only: rm -R on a still-mounted sshfs would delete the remote backups
rmdir /tmp/backupmnt/ 2>/dev/null || echo "WARNING: /tmp/backupmnt not removed (not empty or still mounted)"

echo 
