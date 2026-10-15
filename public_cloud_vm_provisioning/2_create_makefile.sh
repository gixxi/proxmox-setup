#!/usr/bin/env bash
# Create the vlic_runner Makefile locally (no remote IP / scp).
#
# Usage: ./2_create_makefile.sh [circleci_apikey]
#        CIRCLECI_APIKEY=… ./2_create_makefile.sh          (preferred: key stays out of ps and shell history)
#        VLIC_RUNNER_DIR=/path ./2_create_makefile.sh      (default: ~/vlic_runner)
#
# The Makefile content lives in ../lib/vlic_runner_makefile.sh (shared with
# 3_vm_provissioning/create_makefile.sh). On a single public host nginx runs locally and proxies to
# 127.0.0.1:<port>, so every container port is published on loopback only.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/vlic_runner_makefile.sh
. "$SCRIPT_DIR/../lib/vlic_runner_makefile.sh"

VLIC_RUNNER_DIR="${VLIC_RUNNER_DIR:-${HOME}/vlic_runner}"
CIRCLECI_APIKEY=${1:-${CIRCLECI_APIKEY:-}}

mkdir -p "$VLIC_RUNNER_DIR"
cd "$VLIC_RUNNER_DIR"

bash -c "$VLIC_RUNNER_KEY_MIGRATE_CMD"
render_vlic_runner_makefile CORES=8 SWAP_HEADROOM_GB=4 APP_BIND=127.0.0.1 > Makefile.new
mv Makefile.new Makefile

if [ -n "$CIRCLECI_APIKEY" ]; then
    printf '%s\n' "$CIRCLECI_APIKEY" | bash -c "$VLIC_RUNNER_KEY_WRITE_CMD"
    echo "CircleCI key stored in $VLIC_RUNNER_DIR/.circleci_apikey (mode 600)"
elif [ ! -s .circleci_apikey ]; then
    echo "NOTE: no CircleCI key — downloads need: CIRCLECI_APIKEY=… $0"
fi

echo "Makefile written to $VLIC_RUNNER_DIR/Makefile (all ports on 127.0.0.1)"
echo ""
echo "Usage examples:"
echo "  cd $VLIC_RUNNER_DIR && make 64bit Xmx=13g ENABLE_SWAP=true"
echo "  cd $VLIC_RUNNER_DIR && make 64bit BUILD=4858 CONT_NAME=mycontainer Xmx=8g"
echo "  nREPL from your machine: ssh -L 18080:127.0.0.1:18080 <host>, then connect to localhost:18080"
