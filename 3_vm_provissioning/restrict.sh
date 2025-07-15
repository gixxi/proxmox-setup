#!/bin/bash

# Check if the correct number of arguments are provided
if [ $# -ne 2 ]; then
    echo "Usage: $0 <ip_address> <app or bastian>"
    exit 1
fi

IP=$1
TYPE=$2

if [ "$TYPE" == "app" ]; then
    ssh root@$IP exec -c "systemctl disable nginx && systemctl disable nginx && ufw allow 8080:8090/tcp && ufw allow 18080:18090/tcp && ufw allow 28080:28090/tcp"
    # Add openjdk 17 jdk to the path and install leiningen as well as sshfs and rsync for the backup process
    ssh root@$IP exec -c "apt-get install -y openjdk-17-jdk sshfs rsync cron lftp"
    ssh root@$IP exec -c "curl -o lein https://raw.githubusercontent.com/technomancy/leiningen/stable/bin/lein"
    ssh root@$IP exec -c "chmod +x lein"
    ssh root@$IP exec -c "mv lein /usr/local/bin/lein"
    
    # Create directory structure for rocklog-vlic-docker
    ssh root@$IP exec -c "mkdir -p /var/vlic/rocklog-vlic-docker/vlic_runner"
    # need to be created in the home directory
    ssh root@$IP "ln -sf /var/vlic/rocklog-vlic-docker/vlic_runner vlic_runner"
    
    # Create Makefile using a different approach
    cat > /tmp/makefile_content << 'EOF'
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
EOF

    scp /tmp/makefile_content root@$IP:/var/vlic/rocklog-vlic-docker/vlic_runner/Makefile
    rm /tmp/makefile_content
    
    # Create supervisor template using a different approach
    cat > /tmp/supervisor_template << 'EOF'
[program:CUSTOMER_NAME]
; 2023-12-11 3883 <-- we use this for versioning
; 2025-03-13 4858
command=make 64bit BUILD=4858 CONT_NAME=CUSTOMER_NAME VLIC_PORT=8080 IMAGE=hub5.planet-rocklog.com:5000/vlic/vlic_runner:v12 CORES=2 Xmx=5g
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
stdout_logfile=/var/vlic/rocklog-vlic-docker/vlic_runner/CUSTOMER_NAME.log
stdout_logfile_maxbytes=10MB
stdout_logfile_backups=5
stdout_capture_maxbytes=10MB
stdout_events_enabled=false
stderr_logfile=/var/vlic/rocklog-vlic-docker/vlic_runner/CUSTOMER_NAME.err
stderr_logfile_maxbytes=10MB
stderr_logfile_backups=5
stderr_capture_maxbytes=10MB
stderr_events_enabled=false
EOF

    scp /tmp/supervisor_template root@$IP:/etc/supervisor/conf.d/example.conf.template
    rm /tmp/supervisor_template

elif [ "$TYPE" == "bastian" ]; then
    ssh root@$IP exec -c "systemctl disable docker"
fi

