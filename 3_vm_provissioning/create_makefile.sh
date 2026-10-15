#!/usr/bin/env bash
# Create and deploy the vlic_runner Makefile to a Proxmox app VM.
#
# Usage: ./create_makefile.sh <vm_ip> [circleci_apikey]
#        CIRCLECI_APIKEY=… ./create_makefile.sh <vm_ip>   (preferred: key stays out of ps and shell history)
#
# The Makefile content lives in ../lib/vlic_runner_makefile.sh (shared with
# public_cloud_vm_provisioning/2_create_makefile.sh). On an app VM the app port is published on
# <vm_ip>, because the bastion's nginx proxies to <vm_ip>:<port>; nREPL and CouchDB stay on 127.0.0.1.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/vlic_runner_makefile.sh
. "$SCRIPT_DIR/../lib/vlic_runner_makefile.sh"

if [ $# -lt 1 ] || [ $# -gt 2 ]; then
    echo "Usage: $0 <vm_ip> [circleci_apikey]"
    echo "  vm_ip            Target VM IP address (also the address the app port is published on)"
    echo "  circleci_apikey  Optional; better pass it as env CIRCLECI_APIKEY. Without a key an existing"
    echo "                   .circleci_apikey on the VM (or a key inlined in its old Makefile) is kept."
    exit 1
fi

IP=$1
CIRCLECI_APIKEY=${2:-${CIRCLECI_APIKEY:-}}
RUNNER_DIR=/var/vlic/rocklog-vlic-docker/vlic_runner

makefile=$(mktemp)
trap 'rm -f "$makefile"' EXIT
render_vlic_runner_makefile CORES=4 SWAP_HEADROOM_GB=8 APP_BIND="$IP" > "$makefile"

echo "Deploying Makefile to root@$IP:$RUNNER_DIR/Makefile"
ssh "root@$IP" "mkdir -p $RUNNER_DIR && cd $RUNNER_DIR && $VLIC_RUNNER_KEY_MIGRATE_CMD"
scp "$makefile" "root@$IP:$RUNNER_DIR/Makefile"

if [ -n "$CIRCLECI_APIKEY" ]; then
    printf '%s\n' "$CIRCLECI_APIKEY" | ssh "root@$IP" "cd $RUNNER_DIR && $VLIC_RUNNER_KEY_WRITE_CMD"
    echo "✓ CircleCI key stored in $RUNNER_DIR/.circleci_apikey (mode 600)"
elif ! ssh "root@$IP" "test -s $RUNNER_DIR/.circleci_apikey"; then
    echo "NOTE: no CircleCI key on $IP — downloads need: CIRCLECI_APIKEY=… $0 $IP"
fi

echo "✓ Makefile successfully deployed to $IP"
echo "  App port published on $IP (bastion target); nREPL/CouchDB on 127.0.0.1 only"
echo ""
echo "Usage examples:"
echo "  ssh root@$IP 'cd $RUNNER_DIR && make 64bit Xmx=13g ENABLE_SWAP=true'"
echo "  ssh root@$IP 'cd $RUNNER_DIR && make 64bit BUILD=4858 CONT_NAME=mycontainer Xmx=8g'"
echo "  nREPL from your machine: ssh -L 18080:127.0.0.1:18080 root@$IP, then connect to localhost:18080"
