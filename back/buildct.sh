pct create 100 local:vztmpl/debian-11-standard_11.6-1_amd64.tar.zst --cores 1 --cpuunits 1024 --memory 2048 --swap 128 --net0 name=eth0,ip=172.16.1.2/24,bridge=vmbr1,gw=172.16.1.1 --rootfs local:10 --onboot 1

