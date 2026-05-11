#!/usr/bin/env bash
# Restore from a remote path over SSHFS (same transport style as
# 4_running_planet_rocklog/backup-sshfs/do_backup_for_system.sh): mount with sshfs, rsync remote -> local.

set -euo pipefail

usage() {
    echo "Usage: $0 -f <host> -u <user> -p <password> -d <remote_base_dir> -s <remote_src_rel> -t <local_target_dir>" >&2
    echo "  -f  Remote host (SSH/SFTP server used with sshfs)" >&2
    echo "  -u  SSH user" >&2
    echo "  -p  SSH password (passed to sshfs via stdin)" >&2
    echo "  -d  Remote directory to mount (e.g. path on server after user@host:)" >&2
    echo "  -s  Source path relative to the mount (directory to pull from)" >&2
    echo "  -t  Local directory to restore into (created if missing)" >&2
    echo "  -m  Mount point (default: /tmp/restoremnt_sshfs)" >&2
    exit 1
}

ftpserver=""
ftpuser=""
ftppass=""
rsyncdir=""
remote_src=""
local_target=""
mnt_dir="/tmp/restoremnt_sshfs"

while getopts :f:u:p:d:s:t:m:h OPTION; do
    case "$OPTION" in
        f) ftpserver=$OPTARG ;;
        u) ftpuser=$OPTARG ;;
        p) ftppass=$OPTARG ;;
        d) rsyncdir=$OPTARG ;;
        s) remote_src=$OPTARG ;;
        t) local_target=$OPTARG ;;
        m) mnt_dir=$OPTARG ;;
        h) usage ;;
        *) usage ;;
    esac
done

if [ -z "$ftpserver" ] || [ -z "$ftpuser" ] || [ -z "$ftppass" ] || [ -z "$rsyncdir" ] || [ -z "$remote_src" ] || [ -z "$local_target" ]; then
    echo "ERROR: -f, -u, -p, -d, -s, and -t are required." >&2
    usage
fi

umask 000
mounted=0

cleanup() {
    if [ "$mounted" -eq 1 ] && mountpoint -q "$mnt_dir" 2>/dev/null; then
        echo "Unmounting $mnt_dir..."
        fusermount -zu "$mnt_dir" 2>/dev/null || true
        umount -l "$mnt_dir" 2>/dev/null || true
    fi
    mounted=0
    if ! mountpoint -q "$mnt_dir" 2>/dev/null; then
        rmdir "$mnt_dir" 2>/dev/null || true
    fi
}

trap cleanup EXIT

mkdir -p "$mnt_dir"
chmod -R 4777 "$mnt_dir" 2>/dev/null || chmod 1777 "$mnt_dir" 2>/dev/null || true

echo "Mounting ${ftpuser}@${ftpserver}:${rsyncdir}/ -> $mnt_dir ..."
if mountpoint -q "$mnt_dir"; then
    echo "ERROR: $mnt_dir is already a mountpoint; choose -m or unmount first." >&2
    exit 1
fi

if echo "$ftppass" | sshfs -o reconnect,ServerAliveInterval=15,ServerAliveCountMax=3,noforget,allow_other,password_stdin \
    "${ftpuser}@${ftpserver}:${rsyncdir}/" "$mnt_dir"; then
    echo "Mount successful."
    mounted=1
else
    echo "ERROR: sshfs mount failed." >&2
    exit 1
fi

src_path="${mnt_dir%/}/${remote_src#/}"
if [ ! -e "$src_path" ]; then
    echo "ERROR: Remote source path not found under mount: $src_path" >&2
    exit 1
fi

mkdir -p "$local_target"

echo "Rsync from $src_path -> $local_target ..."
if [ -d "$src_path" ]; then
    rsync -av --partial --progress --inplace \
        "$src_path/" "$local_target/"
else
    rsync -av --partial --progress --inplace \
        "$src_path" "$local_target/"
fi

echo "Restore finished."
