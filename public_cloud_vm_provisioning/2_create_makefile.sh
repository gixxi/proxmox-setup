#!/usr/bin/env bash
# Create Makefile for vlic_runner locally (no remote IP / scp).
# Usage: ./2_create_makefile.sh [circleci_apikey]

set -euo pipefail

VLIC_RUNNER_DIR="${HOME}/vlic_runner"
MAKEFILE_PATH="${VLIC_RUNNER_DIR}/Makefile"

CIRCLECI_APIKEY=${1:-}

mkdir -p "$VLIC_RUNNER_DIR"

if [ -n "$CIRCLECI_APIKEY" ]; then
    cat > "$MAKEFILE_PATH" << EOF
CIRCLECI_APIKEY := $CIRCLECI_APIKEY
EOF
else
    cat > "$MAKEFILE_PATH" << 'EOF'
CIRCLECI_APIKEY := <circleci api key, ask the team for the key>
EOF
fi

cat >> "$MAKEFILE_PATH" << 'EOF'
VERSION := v12
current_dir := $(shell pwd)

ifndef VLIC_PORT
	VLIC_PORT := 8080
endif

ifndef COUCHDB_PORT
	COUCHDB_PORT := 5984
endif

ifndef CORES
	CORES := 4
endif

ifndef Xmx
	Xmx := 4g
endif

# Memory management parameters - will be calculated based on Xmx if not set
ifndef MEMORY_RESERVATION_GB
	MEMORY_RESERVATION_GB := 0
endif

ifndef ENABLE_SWAP
	ENABLE_SWAP := false
endif

ifndef SWAPPINESS
	SWAPPINESS := 10
endif

JAVA_HEAP=$(Xmx)
HEAP_NUM=$(JAVA_HEAP:g=)
DOCKER_MEMORY=$(shell echo $$(( $(HEAP_NUM) + 2 ))g)

# Validate and calculate memory reservation
MIN_RESERVATION_GB=$(shell echo $$(( $(HEAP_NUM) + 1 )))
# Auto-calculate reservation if not set (0) or too low
ifeq ($(MEMORY_RESERVATION_GB),0)
	MEMORY_RESERVATION_GB := $(shell echo $$(( $(HEAP_NUM) + 2 )))
endif
RESERVATION_CHECK=$(shell if [ $(MEMORY_RESERVATION_GB) -lt $(MIN_RESERVATION_GB) ]; then echo "ERROR"; fi)

# Calculate memory reservation (soft limit)
DOCKER_MEMORY_RESERVATION=$(MEMORY_RESERVATION_GB)g

# Set swap configuration
ifeq ($(ENABLE_SWAP),true)
	SWAP_CONFIG=--memory-swap=-1 --memory-swappiness=$(SWAPPINESS)
else
	SWAP_CONFIG=--memory-swap=$(DOCKER_MEMORY)
endif

ifndef IMAGE
	IMAGE := gixxi/vlic_runner:$(VERSION)
endif

# CouchDB/Erlang scales fd table with RLIMIT_NOFILE; Docker defaults are huge and can cause
# multi-GB fd_tab allocations. Override if needed: make DOCKER_ULIMIT_NOFILE=262144 …
ifndef DOCKER_ULIMIT_NOFILE
	DOCKER_ULIMIT_NOFILE := 65536
endif

ifndef CONT_NAME
	CONT_NAME := $(shell date +%s | sha256sum | base64 | head -c 32)
endif

persist:
	-mkdir $(CONT_NAME)
	-mkdir $(CONT_NAME)/data
	-mkdir $(CONT_NAME)/tmp
	-mkdir $(CONT_NAME)/tmp/vlic
	-mkdir $(CONT_NAME)/log
	-mkdir $(CONT_NAME)/log/evictor

extract: persist
	test -f rocklog-vlic-$(BUILD).tar.gz || curl -H "Circle-Token: $(CIRCLECI_APIKEY)" https://circleci.com/api/v1.1/project/github/lambdaroyal/rocklog-vlic/$(BUILD)/artifacts | grep -o 'https://[^"]*' | wget --verbose --header "Circle-Token: $(CIRCLECI_APIKEY)" --input-file -
	-cp rocklog-vlic.tar.gz rocklog-vlic-$(BUILD).tar.gz 
	-cp rocklog-vlic-$(BUILD).tar.gz $(CONT_NAME)/tmp/vlic/rocklog-vlic.tar.gz
	-rm rocklog-vlic.tar.gz

bash: persist
	echo "Starting bash in new container"
	docker run --ulimit nofile=$(DOCKER_ULIMIT_NOFILE):$(DOCKER_ULIMIT_NOFILE) -e LANG=C.UTF-8 -e LC_ALL=C.UTF-8 --name=$(CONT_NAME) -it --restart='always' -p $(COUCHDB_PORT):5984 -p 5987:5986 -p $(VLIC_PORT):8080 -v $(current_dir)/$(CONT_NAME)/data:/data -v $(current_dir)/$(CONT_NAME)/tmp/vlic:/tmp/vlic -v $(current_dir)/$(CONT_NAME)/log ${IMAGE} bash

couchdb: persist
	echo "Starting bash in new container"
	docker run --ulimit nofile=$(DOCKER_ULIMIT_NOFILE):$(DOCKER_ULIMIT_NOFILE) -e LANG=C.UTF-8 -e LC_ALL=C.UTF-8 --name=$(CONT_NAME) -it -p $(COUCHDB_PORT):5984 -p $(VLIC_PORT):8080 -v $(current_dir)/$(CONT_NAME)/data:/data -v $(current_dir)/$(CONT_NAME)/tmp/vlic:/tmp/vlic -v $(current_dir)/$(CONT_NAME)/log ${IMAGE} couchdb bash

64bit: extract
	echo "Building container with unique data dir $(CONT_NAME) with archive $(ARCHIVE) for customer data, image=$(IMAGE) -Xmx=$(Xmx) cores=$(CORES)"
	echo "Memory config: limit=$(DOCKER_MEMORY), reservation=$(DOCKER_MEMORY_RESERVATION), swap=$(ENABLE_SWAP)"
	@if [ "$(RESERVATION_CHECK)" = "ERROR" ]; then \
		echo "ERROR: MEMORY_RESERVATION_GB ($(MEMORY_RESERVATION_GB)GB) must be at least Xmx + 1GB ($(MIN_RESERVATION_GB)GB)"; \
		echo "Current Java heap: $(HEAP_NUM)GB, minimum reservation required: $(MIN_RESERVATION_GB)GB"; \
		echo "Please set MEMORY_RESERVATION_GB=$(MIN_RESERVATION_GB) or higher"; \
		exit 1; \
	fi
	-docker rm -f $(CONT_NAME)
	docker run --ulimit nofile=$(DOCKER_ULIMIT_NOFILE):$(DOCKER_ULIMIT_NOFILE) -e LANG=C.UTF-8 -e LC_ALL=C.UTF-8 --rm --name=$(CONT_NAME) \
		-p $(VLIC_PORT):8080 -p 1$(VLIC_PORT):4050 -p 2$(VLIC_PORT):5984 \
		-v $(current_dir)/$(CONT_NAME)/.ssh:/.ssh \
		-v $(current_dir)/$(CONT_NAME)/data:/data \
		-v $(current_dir)/$(CONT_NAME)/tmp/vlic:/tmp/vlic \
		-v $(current_dir)/$(CONT_NAME)/log:/usr/local/var/log/couchdb/ \
		-v $(current_dir)/$(CONT_NAME)/log/evictor:/log \
		-v /etc/localtime:/etc/localtime:ro \
		--cpus="$(CORES)" --log-driver=local \
		--memory=$(DOCKER_MEMORY) --memory-reservation=$(DOCKER_MEMORY_RESERVATION) \
		$(SWAP_CONFIG) \
		$(IMAGE) couchdb 64bit $(Xmx)
EOF

echo "Makefile written to $MAKEFILE_PATH"
echo ""
echo "Usage examples:"
echo "  cd $VLIC_RUNNER_DIR && make 64bit Xmx=13g ENABLE_SWAP=true"
echo "  cd $VLIC_RUNNER_DIR && make 64bit BUILD=4858 CONT_NAME=mycontainer Xmx=8g"
