#!/bin/bash
# Christian Meichsner &  Frank Schneider
# Daily rsync Backup 

# This script consumes the subsequently listed parameters

while getopts :s:f:d:u:p: OPTION ; do
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
    *)   echo "Unknown parameter"
         exit 1
         ;;
  esac
done

umask 000
main_dir="/var/vlic/rocklog-vlic-docker/vlic_runner/"
mnt_dir="/tmp/backupmnt/"
day=`LC_ALL=C date +%A`

cd /tmp

mkdir -p /tmp/backupmnt/

chmod -R 4777 backupmnt/

echo 
echo ordner fuer $source mounten...

if mountpoint -q $mnt_dir ; then
    echo "It is already a mounted mountpoint"
else
    echo "Attempting to mount with SSHFS..."
    # Added error checking for mount command
    if echo $ftppass | sshfs -o reconnect,ServerAliveInterval=15,ServerAliveCountMax=3,noforget,allow_other,password_stdin $ftpuser@$ftpserver:$rsyncdir/ $mnt_dir ; then
        echo "Mount successful"
    else
        echo "Mount failed - aborting backup"
        exit 1
    fi
fi

# Only proceed with backup if mounting was successful
if mountpoint -q $mnt_dir ; then
    cd $main_dir/$source/

    echo sicherung startet fuer $source...

    mkdir -p $mnt_dir/sicherung_$source

    rsync -av --partial --no-perms --progress --inplace --no-group --no-owner --exclude={/log/,/logs/,/tmp/vlic/printing/tmp/,/tmp/vlic/dump.evictor/,/tmp/vlic/interfaces/} $main_dir/$source/ $mnt_dir/sicherung_$source/$source-$day/ >> /var/log/backup/log_backup_$source.log

    echo unmount ordner fuer $source...

    fusermount -zu $mnt_dir
    umount -l $mnt_dir
fi

rm -R /tmp/backupmnt/

echo 
