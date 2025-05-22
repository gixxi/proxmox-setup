# Running Planet Rocklog

## Overview

Running Planet Rocklog on a Proxmox VM that was provisioned in the previous step [(../3_vm_provissioning/README.md)](../3_vm_provissioning/README.md)
involves some additional steps to get the Docker container running.

## Prerequisites


### Create a directory for the container data

```bash
mkdir -p /var/vlic/rocklog-vlic-docker/vlic_runner
ln -s /var/vlic/rocklog-vlic-docker/vlic_runner vlic_runner
```

### Login to the rocklog Docker repository

```bash
docker login hub5.planet-rocklog.com:5000
```

Username: rocklog
Password: Ask the team for the password

### Pull the image

```bash
docker pull hub5.planet-rocklog.com:5000/vlic/vlic_runner:v12
```

### Setup the Makefile

The Makefile is used to start the container using supervisord. Create the makefile in the vlic_runner directory.

```bash
CIRCLECI_APIKEY := <circleci api key, ask the team for the key>
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


JAVA_HEAP=$(Xmx)
HEAP_NUM=$(JAVA_HEAP:g=)
DOCKER_MEMORY=$(shell echo $$(( $(HEAP_NUM) + 2 ))g)

ifndef IMAGE
        IMAGE := hub5.planet-rocklog.com:5000/vlic/vlic_runner:$(VERSION)
endif


ifndef CONT_NAME
        CONT_NAME := $(shell date +%s | sha256sum | base64 | head -c 32)
endif

build:
        docker build -t vlic/vlic_runner:${VERSION} .
        docker tag vlic/vlic_runner:${VERSION} hub5.planet-rocklog.com:5000/vlic/vlic_runner:${VERSION}
deploy:
        sudo docker push hub5.planet-rocklog.com:5000/vlic/vlic_runner:${VERSION}

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
        sudo docker run -e LANG=C.UTF-8 -e LC_ALL=C.UTF-8 --name=$(CONT_NAME) -it --restart='always' -p $(COUCHDB_PORT):5984 -p 5987:5986 -p $(VLIC_PORT):8080 -v $(current_dir)/$(CONT_NAME)/data:/data -v $(current_dir)/$(CONT_NAME)/tmp/vlic:/tmp/vlic -v $(current_dir)/$(CONT_NAME)/log ${IMAGE} bash

couchdb: persist
        echo "Starting bash in new container"
        sudo docker run -e LANG=C.UTF-8 -e LC_ALL=C.UTF-8 --name=$(CONT_NAME) -it -p $(COUCHDB_PORT):5984 -p $(VLIC_PORT):8080 -v $(current_dir)/$(CONT_NAME)/data:/data -v $(current_dir)/$(CONT_NAME)/tmp/vlic:/tmp/vlic -v $(current_dir)/$(CONT_NAME)/log ${IMAGE} couchdb bash

64bit: extract
        echo "Building container with unique data dir $(CONT_NAME) with archive $(ARCHIVE) for customer data, image=$(IMAGE) -Xmx=$(Xmx) cores=$(CORES)"
        -sudo docker rm -f $(CONT_NAME)
        sudo docker run -e LANG=C.UTF-8 -e LC_ALL=C.UTF-8 --rm --name=$(CONT_NAME) -p $(VLIC_PORT):8080 -p 1$(VLIC_PORT):4050 -p 2$(VLIC_PORT):5984 -v $(current_dir)/$(CONT_NAME)/.ssh:/.ssh -v $(current_dir)/$(CONT_NAME)/data:/data -v $(current_dir)/$(CONT_NAME)/tmp/vlic:/tmp/vlic -v $(current_dir)/$(CONT_NAME)/log:/usr/local/var/log/couchdb/ -v $(current_dir)/$(CONT_NAME)/log/evictor:/log -v /etc/localtime:/etc/localtime:ro --cpus="$(CORES)" --log-driver=local --memory=$(DOCKER_MEMORY) $(IMAGE) couchdb 64bit $(Xmx)

```

### Create a supervisor config file

in /etc/supervisor/conf.d/

e.g. customer1.conf

```bash
[program:customer1]
; 2023-12-11 3883 <-- we use this for versioning
; 2025-03-13 4858
command=make 64bit BUILD=4858 CONT_NAME=customer1 VLIC_PORT=8080 IMAGE=hub5.planet-rocklog.com:5000/vlic/vlic_runner:v12 CORES=2 Xmx=5g
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
stdout_logfile=/var/vlic/rocklog-vlic-docker/vlic_runner/customer1.log
stdout_logfile_maxbytes=10MB
stdout_logfile_backups=5
stdout_capture_maxbytes=10MB
stdout_events_enabled=false
stderr_logfile=/var/vlic/rocklog-vlic-docker/vlic_runner/customer1.err
stderr_logfile_maxbytes=10MB
stderr_logfile_backups=5
stderr_capture_maxbytes=10MB
stderr_events_enabled=false
```

#### Important: Set proper websocket endpoind using clojure REPL

connect to the container:

> lein repl :connect <REPL_PORT>

in the repl, run the following code to set the websocket endpoint and url-prefix. Change the following variables:

- <SUBDOMAIN> e.g. customer1
- <DOMAIN> e.g. rocklog.ch
- <GATEWAY_HOST> e.g. datacenter1.rocklog.ch
- <LOCATION_NAME> e.g. customer1

```clojure
(require '[lambdaroyal.memory.abstraction.search :as search]
         '[lambdaroyal.vlic.crosscutting.tx-decorator :as tx']
         '[lambdaroyal.memory.core.tx :refer :all]
         '[lambdaroyal.vlic.domain.printing-numberranges :refer :all]
         '[lambdaroyal.vlic.ioc :refer :all]
         '[lambdaroyal.vlic.crosscutting.user :as u]
         '[lambdaroyal.vlic.crosscutting.datastructures :refer :all]
         '[lambdaroyal.vlic.crosscutting.cardmeta :as cm]
         '[lambdaroyal.vlic.crosscutting.plansearch :as ps])
(def tx (create-tx (:ctx @lambdaroyal.vlic.main/system)))

(let [config (select-first tx :config "system")
      url-prefix "https://<SUBDOMAIN>.<DOMAIN>"
      wss-endpoint "wss://<GATEWAY_HOST>/<LOCATION_NAME>/autobahn"]
  (dosync (alter-document tx :config config assoc :general (assoc (-> config last :general) :wss-endpoint wss-endpoint :url-prefix url-prefix))))
```


### Create a nginx proxy config file

on the proxmox server, create a nginx config file in /etc/nginx/conf.d/ using the script as per [Running Bastian VM](../5_running_bastian_vm/README.md)

if not otherwise stated in the supervisor config file, the following ports are used:

- 8080: application, to be used as <PORT>
- 18080: repl
- 28080: couchdb

```bash
./create_nginx_proxy_configuration.sh <BASIAN_VM_IP> <DOMAIN> <SUBDOMAIN> <CUSTOMER_VM_IP> <PORT>
```

e.g.

```bash
./create_nginx_proxy_configuration.sh 192.168.1.103 customer1 rocklog.ch customer1 8080
```

### Setup DNS records on the domain registrar

- A record for the application
