#!/bin/bash
curl -k  -L https://${SATELLITE_URL}/pub/katello-server-ca.crt -o /etc/pki/ca-trust/source/anchors/${SATELLITE_URL}.ca.crt
update-ca-trust
rpm -Uhv https://${SATELLITE_URL}/pub/katello-ca-consumer-latest.noarch.rpm

subscription-manager register --org=${SATELLITE_ORG} --activationkey=${SATELLITE_ACTIVATIONKEY}

yum install yum-utils jq podman wget git ansible-core nano -y
setenforce 0
firewall-cmd --permanent --add-port=2000:2003/tcp
firewall-cmd --permanent --add-port=6030:6033/tcp
firewall-cmd --permanent --add-port=8065:8065/tcp
firewall-cmd --reload
# export RTPASS=ansible
# echo "ansible" | passwd root --stdin

# Grab sample switch config
rm -rf /tmp/setup ## Troubleshooting step

ansible-galaxy collection install community.general

mkdir /tmp/setup/

git clone https://github.com/nmartins0611/Instruqt_netops.git /tmp/setup/

### Configure containers

podman pull quay.io/nmartins/ceoslab-rh
#podman pull docker.io/nats
#podman run --name mattermost-preview -d --publish 8065:8065 mattermost/mattermost-preview

## Create Networks

podman network create net1
podman network create net2
podman network create net3
podman network create loop
podman network create management

# Create mattermost container
#podman run -d --network management --name=mattermost --privileged --publish 8065:8065 mattermost/mattermost-preview:7.8.6

##docker pull mattermost/platform:6.5.0

# podman create --name=ceos1 --privileged -v /tmp/setup/sw01/sw01:/mnt/flash/startup-config -e INTFTYPE=eth -e ETBA=1 -e SKIP_ZEROTOUCH_BARRIER_IN_SYSDBINIT=1 -e CEOS=1 -e EOS_PLATFORM=ceoslab -e container=docker -p 9092:9092 -p 6031:6030 -p 2001:22/tcp -i -t quay.io/nmartins/ceoslab-rh /sbin/init systemd.setenv=INTFTYPE=eth systemd.setenv=ETBA=1 systemd.setenv=SKIP_ZEROTOUCH_BARRIER_IN_SYSDBINIT=1 systemd.setenv=CEOS=1 systemd.setenv=EOS_PLATFORM=ceoslab systemd.setenv=container=podman
podman run -d --network management --memory=4g --name=ceos1 --privileged -v /tmp/setup/sw01/sw01:/mnt/flash/startup-config -e INTFTYPE=eth -e ETBA=1 -e SKIP_ZEROTOUCH_BARRIER_IN_SYSDBINIT=1 -e CEOS=1 -e EOS_PLATFORM=ceoslab -e container=podman -p 6031:6030 -p 2001:22/tcp quay.io/nmartins/ceoslab-rh /sbin/init systemd.setenv=INTFTYPE=eth systemd.setenv=ETBA=1 systemd.setenv=SKIP_ZEROTOUCH_BARRIER_IN_SYSDBINIT=1 systemd.setenv=CEOS=1 systemd.setenv=EOS_PLATFORM=ceoslab systemd.setenv=container=podman  ##
podman run -d --network management --memory=4g --name=ceos2 --privileged -v /tmp/setup/sw02/sw02:/mnt/flash/startup-config -e INTFTYPE=eth -e ETBA=1 -e SKIP_ZEROTOUCH_BARRIER_IN_SYSDBINIT=1 -e CEOS=1 -e EOS_PLATFORM=ceoslab -e container=podman -p 6032:6030 -p 2002:22/tcp quay.io/nmartins/ceoslab-rh /sbin/init systemd.setenv=INTFTYPE=eth systemd.setenv=ETBA=1 systemd.setenv=SKIP_ZEROTOUCH_BARRIER_IN_SYSDBINIT=1 systemd.setenv=CEOS=1 systemd.setenv=EOS_PLATFORM=ceoslab systemd.setenv=container=podman  ##systemd.setenv=MGMT_INTF=eth0
podman run -d --network management --memory=4g --name=ceos3 --privileged -v /tmp/setup/sw03/sw03:/mnt/flash/startup-config -e INTFTYPE=eth -e ETBA=1 -e SKIP_ZEROTOUCH_BARRIER_IN_SYSDBINIT=1 -e CEOS=1 -e EOS_PLATFORM=ceoslab -e container=podman -p 6033:6030 -p 2003:22/tcp quay.io/nmartins/ceoslab-rh /sbin/init systemd.setenv=INTFTYPE=eth systemd.setenv=ETBA=1 systemd.setenv=SKIP_ZEROTOUCH_BARRIER_IN_SYSDBINIT=1 systemd.setenv=CEOS=1 systemd.setenv=EOS_PLATFORM=ceoslab systemd.setenv=container=podman  ##systemd.setenv=MGMT_INTF=eth0
#podman run -d -it --network management --name=web01 --systemd=always --ip=10.0.0.10 -p 8080:80 quay.io/nmartins/httpd


# ## Attach Networks
podman network connect loop ceos1
podman network connect net1 ceos1
podman network connect net3 ceos1
#podman network connect management ceos1

podman network connect loop ceos2
podman network connect net1 ceos2
podman network connect net2 ceos2
#podman network connect management ceos2

podman network connect loop ceos3
podman network connect net2 ceos3
podman network connect net3 ceos3
#podman network connect management ceos3

# podman network connect management mattermost

## Wait for Switches to load conf
sleep 60

# ## Get management IP
var1=$(podman inspect ceos1 | jq -r '.[] | .NetworkSettings.Networks.management | .IPAddress')
var2=$(podman inspect ceos2 | jq -r '.[] | .NetworkSettings.Networks.management | .IPAddress')
var3=$(podman inspect ceos3 | jq -r '.[] | .NetworkSettings.Networks.management | .IPAddress')
var4=$(podman inspect mattermost | jq -r '.[] | .NetworkSettings.Networks.management | .IPAddress')

## Build local host etc/hosts
echo "$var1" ceos1 >> /etc/hosts
echo "$var2" ceos2 >> /etc/hosts
echo "$var3" ceos3 >> /etc/hosts
echo "$var4" mattermost >> /etc/hosts



## Install Gmnic
bash -c "$(curl -sL https://get-gnmic.kmrd.dev)"

## Test GMNIC
## gnmic -a localhost:6031 -u ansible -p ansible --insecure subscribe --path   "/interfaces/interface[name=Ethernet1]/state/admin-status"
## gnmic -addr ceos1:6031 -username ansible -password ansible   get '/network-instances/network-instance[name=default]/protocols/protocol[identifier=BGP][name=BGP]/bgp'
## gnmic -a localhost:6031 -u ansible -p ansible --insecure subscribe --path 'components/component/state/memory/'

# ## SSH Setup
# echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDdQebku7hz6otXEso48S0yjY0mQ5oa3VbFfOvEHeApfu9pNMG34OCzNpRadCDIYEfidyCXZqC91vuVM+6R7ULa/pZcgoeDopYA2wWSZEBIlF9DexAU4NEG4Zc0sHfrbK66lyVgdpvu1wmHT5MEhaCWQclo4B5ixuUVcSjfiM8Y7FL/qOp2FY8QcN10eExQo1CrGBHCwvATxdjgB+7yFhjVYVkYALINDoqbFaituKupqQyCj3FIoKctHG9tsaH/hBnhzRrLWUfuUTMMveDY24PzG5NR3rBFYI3DvKk5+nkpTcnLLD2cze6NIlKW5KygKQ4rO0tJTDOqoGvK5J5EM4Jb" >> /root/.ssh/authorized_keys 
# echo "Host *" >> /etc/ssh/ssh_config
# echo "StrictHostKeyChecking no" >> /etc/ssh/ssh_config
# echo "UserKnownHostsFile=/dev/null" >> /etc/ssh/ssh_config
# chmod 400 /etc/ssh/ssh_config
# systemctl restart sshd

#################################################################

cat <<EOF | tee /etc/yum.repos.d/influxdb.repo
[influxdb]
name = InfluxDB Repository - RHEL \$releasever
baseurl = https://repos.influxdata.com/rhel/\$releasever/\$basearch/stable
enabled = 1
gpgcheck = 1
gpgkey = https://repos.influxdata.com/influxdata-archive_compat.key

EOF

dnf install telegraf -y

cat <<EOF | tee /etc/telegraf/telegraf.conf


############################################## SWITCH 01  #############################################

[[inputs.gnmi]]
## Address and port of the GNMI GRPC server
 addresses = ["localhost:6031"] ## Container Switch
 name_override = "ceos1"
## credentials
 username = "ansible"
 password = "ansible"

## redial in case of failures after
# redial = "10s"

[[inputs.gnmi.subscription]]
  name = "Ethernet1"
  origin = "openconfig"
  subscription_mode = "on_change"
  path = "/interfaces/interface[name=Ethernet1]/state/admin-status"
  sample_interval = "2s"

[[inputs.gnmi.subscription]]
## Name of the measurement that will be emitted
  name = "bgp_neighbor_state_ceos1"
  origin = "openconfig"
  path = "/network-instances/network-instance/protocols/protocol/bgp/neighbors/neighbor/state/session-state"
  subscription_mode = "on_change"
  sample_interval = "2s"

############################################## SWITCH 02  #############################################


[[inputs.gnmi]]
## Address and port of the GNMI GRPC server
 addresses = ["localhost:6032"]
 name_override = "ceos2"
## credentials
 username = "ansible"
 password = "ansible"

## redial in case of failures after
# redial = "10s"

[[inputs.gnmi.subscription]]
  name = "Ethernet1"
  origin = "openconfig"
  subscription_mode = "on_change"
  path = "/interfaces/interface[name=Ethernet1]/state/admin-status"
  sample_interval = "2s"


############################################## SWITCH 03  #############################################


[[inputs.gnmi]]
## Address and port of the GNMI GRPC server
 addresses = ["localhost:6033"]
 name_override = "ceos3"
## credentials
 username = "ansible"
 password = "ansible"

## redial in case of failures after
# redial = "10s"

[[inputs.gnmi.subscription]]
  name = "Ethernet1"
  origin = "openconfig"
  subscription_mode = "on_change"
  path = "/interfaces/interface[name=Ethernet1]/state/admin-status"
  sample_interval = "1s"

############################################## OUTPUTS  ####################################################

[outputs.kafka]
# URLs of kafka brokers
  brokers = ["broker:9092"] # EDIT THIS LINE
# Kafka topic for producer messages
  topic = "network"
  data_format = "json"

EOF

systemctl start telegraf

sudo rpm --import https://artifacts.elastic.co/GPG-KEY-elasticsearch

cat <<EOF | tee /etc/yum.repos.d/elastic.repo
[elastic-8.x]
name=Elastic repository for 8.x packages
baseurl=https://artifacts.elastic.co/packages/8.x/yum
gpgcheck=1
gpgkey=https://artifacts.elastic.co/GPG-KEY-elasticsearch
enabled=1
autorefresh=1
type=rpm-md

EOF

sudo yum install filebeat -y

cat <<EOF | tee  /etc/filebeat/filebeat.yml 

filebeat.inputs:
- type: journald
  id: everything

output.kafka:
   # List of Kafka brokers
  hosts: ["broker:9092"]
  topic: 'network'
  partition.round_robin:
  reachable_only: false
  required_acks: 1
  compression: gzip

EOF

sleep 30

#systemctl enable filebeat
systemctl start filebeat

yum install httpd -y
yum install rsync -y

git clone https://github.com/nmartins0611/aap25-roadshow-content.git /tmp/lab-setup
sudo rsync -av /tmp/lab-setup/lab-resources/* /var/www/html/

systemctl start httpd

mkdir /var/www/html/chaos
chmod 777 /var/www/html/chaos

