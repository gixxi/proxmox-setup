- create a cron on the proxmox host that copies the SSL certificate to the bastian vm
- based on 3_vm_provisioning/provision_vm.sh we want to do the following in addition:

1. install nginx and ufw
2. setup ufw to support the following setup

```bash
Status: active

     To                         Action      From
     --                         ------      ----
[ 1] 22                         ALLOW IN    172.105.94.119            
[ 2] 22                         ALLOW IN    116.203.216.1             
[ 3] 22                         ALLOW IN    192.168.1.0/24            
[ 4] 22                         ALLOW IN    5.161.184.133             
[ 5] 22/tcp                     DENY IN     Anywhere                  
[ 6] 80/tcp                     ALLOW IN    Anywhere                  
[ 7] 443                        ALLOW IN    Anywhere                  
[ 8] 60000:61000/udp            ALLOW IN    Anywhere                  
[10] 22/tcp (v6)                DENY IN     Anywhere (v6)             
[11] 80/tcp (v6)                ALLOW IN    Anywhere (v6)             
[12] 443 (v6)                   ALLOW IN    Anywhere (v6)             
[13] 60000:61000/udp (v6)       ALLOW IN    Anywhere (v6)             
```

in addition we would like to allow TCP to 8080 as well 8443
