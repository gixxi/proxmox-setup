# Running Planet Rocklog

## Overview

Running Planet Rocklog on a Proxmox VM that was provisioned in the previous step [(../3_vm_provissioning/README.md)](../3_vm_provissioning/README.md)
involves some additional steps to get the Docker container running.

## Prerequisites


### Create a directory for the container data

```bash
mkdir -p planetrocklog
```

### Pull the image

```bash
docker pull gixxi/vlic_runner:v12
```

### Setup the Makefile

The Makefile is used to start the container using supervisord. Do not copy it by hand — it is
generated from a single source, `../lib/vlic_runner_makefile.sh`:

```bash
# Proxmox app VM (from the provisioning host; app port on the VM IP for the bastion)
CIRCLECI_APIKEY=… ../3_vm_provissioning/create_makefile.sh <vm_ip>
# single public host (on the host itself; everything on 127.0.0.1)
CIRCLECI_APIKEY=… ../public_cloud_vm_provisioning/2_create_makefile.sh
```

The CircleCI key is stored in `vlic_runner/.circleci_apikey` (mode 600), not in the Makefile.
nREPL and CouchDB are published on 127.0.0.1 only — use an SSH tunnel for the REPL step below,
e.g. `ssh -L 18080:127.0.0.1:18080 root@<host>`.

### Create a supervisor config file

in /etc/supervisor/conf.d/

e.g. customer1.conf

```bash
[program:customer1]
; 2023-12-11 3883 <-- we use this for versioning
; 2025-03-13 4858
command=make 64bit BUILD=4858 CONT_NAME=customer1 VLIC_PORT=8080 IMAGE=hub5.planet-rocklog.com:5000/vlic/vlic_runner:v12 CORES=2 Xmx=5g
directory=/var/vlic/rocklog-vlic-docker/vlic_runner
user=lambdaroyal-anon
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
stdout_logfile=/home/lambdaroyal-anon/planetrocklog/customer1.log
stdout_logfile_maxbytes=10MB
stdout_logfile_backups=5
stdout_capture_maxbytes=10MB
stdout_events_enabled=false
stderr_logfile=/home/lambdaroyal-anon/planetrocklog/customer1.err
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
